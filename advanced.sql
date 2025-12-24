
SELECT
    n.npu_serial AS `物理显卡序列号`,
    n.queue_type AS `队列类型`,
    n.cores AS `物理总核数`,
    -- 统计已分配的虚拟核
    COALESCE(SUM(vcpu.virtual_cores), 0) AS `已分配核数`,
    -- 计算利用率百分比
    CONCAT(
        ROUND(
            COALESCE(SUM(vcpu.virtual_cores), 0) / n.cores * 100,
            1
        ),
        '%'
    ) AS `核心利用率`,
    -- 统计运行中的虚拟机数量
    COUNT(vm.node_id) AS `运行实例数`,
    -- 统计当前每小时收益
    COALESCE(SUM(vm.hourly_price), 0) AS `当前每小时产出(¥)`
FROM
    npus n
    -- 连接虚拟CPU表 (只看已分配的)
    LEFT JOIN virtualcpu vcpu ON n.NPU_id = vcpu.NPU_id
    AND vcpu.status = 'allocated'
    -- 连接虚拟机实例表 (只看运行中的，因为只有运行中才产生收益)
    LEFT JOIN virtualcomputers vm ON vcpu.vir_NPU_id = vm.vir_NPU_id
    AND vm.status = 'running'
GROUP BY
    n.NPU_id,
    n.npu_serial,
    n.queue_type,
    n.cores
ORDER BY `已分配核数` DESC;




这个 SQL 查询语句是一份物理硬件资源利用率与收益报表。

它的核心目的是：站在数据中心管理员的角度，查看每一块物理显卡（NPU）到底有多忙，以及它正在为你赚多少钱。

以下是详细的逐层解读：

1. 查询的主体 (FROM npus n)
查询的基础是 npus 表，也就是物理硬件表。
这意味着即使某块显卡完全空闲（没有分配任何虚拟机），它也会出现在结果中（因为使用了 LEFT JOIN），方便管理员看到闲置资源。
2. 数据的来源 (JOINs)
这个查询通过两次“左连接”把三层数据串了起来：

物理层 (npus)：真实的硬件。
虚拟层 (virtualcpu)：从物理硬件上切分出来的虚拟 CPU 核心。
实例层 (virtualcomputers)：最终卖给用户的虚拟机实例。
LEFT JOIN virtualcpu ... AND vc.status = 'allocated'：只统计那些已经被切分出去的虚拟核。
LEFT JOIN virtualcomputers ... AND vm.status = 'running'：只统计那些正在运行的实例（关机的机器不占用算力，也不产生收益）。
3. 统计指标 (SELECT & Aggregates)
每一行代表一块物理 NPU 卡，包含以下关键数据：

物理总核数: 这块卡原本有多强（比如 64 核）。
已分配核数: SUM(vc.virtual_cores)。这块卡上目前切分出去了多少个虚拟核。
核心利用率: (已分配 / 总数) %。这是最关键的指标。
如果接近 100%，说明这块卡满载了，可能需要扩容。
如果是 0%，说明这块卡在“吃灰”。
运行实例数: COUNT(vm.node_id)。这块卡上目前跑着几个虚拟机。
当前每小时产出(¥): SUM(vm.hourly_price)。这块卡当前每小时能产生多少营收。
4. 排序 (ORDER BY)
ORDER BY 已分配核数 DESC: 把负载最重（分配出去核心最多）的显卡排在最前面，方便管理员优先关注热点资源。
总结
这句话是在问数据库：

“把所有物理显卡列出来，告诉我每块卡上有多少个虚拟核正在被使用，占了总核数的百分之多少，上面跑了几个虚拟机，以及这块卡现在每小时能给我赚多少钱？”
 

SELECT 
    u.user_name AS `用户名`,
    u.balance AS `当前余额`,
    SUM(vc.hourly_price) AS `烧钱速度(元/时)`,
    ROUND(
        CASE 
            WHEN u.balance <= 0 THEN 0
            ELSE u.balance / SUM(vc.hourly_price)
        END, 1
    ) AS `预计剩余时长(h)`,
    GROUP_CONCAT(DISTINCT n.npu_serial SEPARATOR ', ') AS `占用物理NPU`
FROM users u
JOIN requests r ON u.user_id = r.user_id
JOIN virtualcomputers vc ON r.request_id = vc.request_id
JOIN virtualcpu vcpu ON vc.vir_NPU_id = vcpu.vir_NPU_id
JOIN npus n ON vcpu.NPU_id = n.NPU_id
WHERE vc.status = 'running' 
GROUP BY u.user_id, u.user_name, u.balance
HAVING `当前余额` < 50000 OR `预计剩余时长(h)` < 5
ORDER BY `预计剩余时长(h)` ASC, `当前余额` ASC; 

 
这条 SQL 语句的主要目的是生成一份 “高风险用户预警报告”。

它旨在找出那些正在运行高消耗任务，但账户余额不足或即将耗尽的用户。管理员可以使用这份报告来决定是否需要通知用户充值，或者强制停止任务以避免欠费。

具体解读如下：

1. 查询的核心逻辑
它查询了所有 正在运行 (status = 'running') 的虚拟机实例，并按 用户 进行分组统计。

2. 统计的关键指标 (SELECT 部分)
烧钱速度(元/时): SUM(vc.hourly_price)
计算该用户所有正在运行的实例每小时总共消耗多少钱。
预计剩余时长(h): balance / SUM(vc.hourly_price)
用“当前余额”除以“烧钱速度”，估算出用户的钱还能支撑几个小时。
使用了 CASE WHEN 处理余额小于等于0的情况，防止计算出负数或除零错误。
占用物理NPU: GROUP_CONCAT(...)
列出该用户占用了哪些物理显卡（NPU），方便管理员查看资源占用情况。
3. 筛选高风险用户 (HAVING 部分)
它只显示满足以下 任一 条件的用户：

当前余额 < 50000: 余额已经很低了（绝对值低）。
OR
预计剩余时长(h) < 5: 按照当前的消耗速度，5小时内就会欠费（相对值低，即使余额有1000，如果每小时消耗300，也会被筛选出来）。
4. 排序优先级 (ORDER BY 部分)
最紧急的排在最前面：优先显示 预计剩余时长 最短的用户（即最快会欠费的用户）。
一句话总结：
这条语句是在问数据库

：“告诉我哪些用户正在跑任务，而且钱快不够用了（余额少于50000元或只能撑不到5小时），并把最危险的用户排在最前面。”





SELECT
    queue_type AS `资源池`,
    COUNT(*) AS `物理节点总数`,
    -- 1. 完全空闲: 一点资源都没被用
    SUM(
        CASE
            WHEN available_cores = cores THEN 1
            ELSE 0
        END
    ) AS `完全空闲节点`,
    -- 2. 完全满载: 一滴资源都不剩了
    SUM(
        CASE
            WHEN available_cores = 0 THEN 1
            ELSE 0
        END
    ) AS `完全满载节点`,
    -- 3. 碎片状态: 用了一部分，还剩一部分
    SUM(
        CASE
            WHEN available_cores > 0
            AND available_cores < cores THEN 1
            ELSE 0
        END
    ) AS `碎片化节点`,
    -- 4. 整体利用率指标
    CONCAT(
        ROUND(
            (
                1 - SUM(available_cores) / SUM(cores)
            ) * 100,
            1
        ),
        '%'
    ) AS `CPU整体利用率`,
    CONCAT(
        ROUND(
            (
                1 - SUM(available_memory) / SUM(NPU_memory)
            ) * 100,
            1
        ),
        '%'
    ) AS `显存整体利用率`
FROM npus
GROUP BY
    queue_type;

-- =======================================================
-- 复杂查询示例 4: 资源池健康度与碎片化分析 (Resource Health & Fragmentation)
-- =======================================================
-- 作用: 运维人员专用。查看物理机是被“吃干抹净”了，还是有很多“碎片”资源（有空闲但不够开新机）。
-- 技巧: 使用 CASE WHEN 进行分段统计 (Binning)。
--
-- 详细解释:
-- 1. 核心数据源: npus 表，代表物理节点。
-- 2. 数据分箱 (Binning) 统计:
--    使用 SUM(CASE WHEN ... THEN 1 ELSE 0 END) 这种模式，可以把节点分为三类：
--    - 完全空闲: available_cores = cores (一点没动，随时待命)。
--    - 完全满载: available_cores = 0 (榨干了，物尽其用)。
--    - 碎片化: 0 < available < cores (用了一部分，剩下的可能因为太小而无法分配，即“碎片”)。
--    运维重点关注“碎片化节点”，如果碎片太多，说明调度算法可能需要优化（如进行碎片整理或迁移）。
-- 3. 整体利用率:
--    - 公式: (1 - 剩余总量 / 物理总量) * 100%
--    - 这是一个宏观指标，反映了整个集群的繁忙程度。