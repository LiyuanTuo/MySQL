import streamlit as st
import pandas as pd
import mysql.connector
import json
from datetime import datetime

# ================= 数据库连接辅助 =================

def get_connection(db_config):
    """获取数据库连接"""
    return mysql.connector.connect(**db_config)

# ================= 核心逻辑函数 =================

def approve_request(db_config, req_id, user_id, params):
    """
    批准请求：调用存储过程 sp_create_instance 分配物理资源
    """
    conn = get_connection(db_config)
    cursor = conn.cursor()
    
    try:
        db_p = params.get('db_params', {})
        p_queue = params.get('queue')
        
        # 参数列表：第一个参数改为 req_id (用户提交的那个ID)
        args = [
            req_id,  # <--- 传入现有的 Request ID
            p_queue, 
            db_p.get('req_cores', 1),
            db_p.get('req_gpu_mem', 0),
            db_p.get('req_ram', 1),
            db_p.get('req_disk', 10),
            0 
        ]
        
        # 调用存储过程
        result_args = cursor.callproc('sp_create_instance', args)
        new_node_id = result_args[-1] 
        
        if new_node_id and new_node_id > 0:
            # 更新状态为 approved
            cursor.execute(
                "UPDATE requests SET status='approved', node_id=%s WHERE request_id=%s", 
                (new_node_id, req_id)
            )
            conn.commit()
            st.toast(f" 审批成功！资源已分配，节点 ID: {new_node_id}")
            return True
        else:
            st.toast(" 资源池不足 (CPU/GPU/内存/磁盘)，分配失败。", icon="⚠️")
            return False
            
    except mysql.connector.Error as err:
        st.error(f"数据库错误: {err}")
        return False
    finally:
        cursor.close()
        conn.close()

def reject_request(db_config, req_id):
    """
    拒绝请求：不占用资源，直接标记为 rejected
    """
    conn = get_connection(db_config)
    cursor = conn.cursor()
    try:
        cursor.execute("UPDATE requests SET status='rejected' WHERE request_id=%s", (req_id,))
        conn.commit()
        st.toast(f"已拒绝请求 {req_id}")
    except mysql.connector.Error as err:
        st.error(f"操作失败: {err}")
    finally:
        cursor.close()
        conn.close()

def stop_instance(db_config, node_id, req_id, action_type):
    """
    停止实例：
    action_type='complete': 正常完成 (状态 completed)
    action_type='terminate': 强制终止 (状态 terminated)
    两者都需要调用 sp_release_resource 释放物理硬件
    """
    conn = get_connection(db_config)
    cursor = conn.cursor()
    try:
        # 1. 调用存储过程释放物理资源 (归还核数、内存等)
        try:
            # 这里传入两个参数 [node_id, '']
            # 第二个参数是 OUT p_result_status 的占位符
            cursor.callproc('sp_release_resource', [node_id, ''])
            
        except mysql.connector.Error as e:
            if e.errno == 1305: # PROCEDURE does not exist
                st.error("错误：数据库中缺少存储过程 `sp_release_resource`，无法自动释放物理资源。请联系DBA。")
                return False
            else:
                raise e
        
        # 2. 根据操作类型更新 requests 和 virtualcomputers 的状态
        final_status = 'completed' if action_type == 'complete' else 'terminated'
        
        # 更新请求状态
        cursor.execute("UPDATE requests SET status=%s, complete_time=NOW() WHERE request_id=%s", (final_status, req_id))
        
        # 更新虚拟机状态 (通常释放后虚拟机记录标记为 terminated 或 stopped)
        # 注意：sp_release_resource 内部其实已经把 virtualcomputers 设为 terminated 了，
        # 但为了双重保险或处理 action_type 差异，这里保留更新逻辑，但建议统一为 terminated
        cursor.execute("UPDATE virtualcomputers SET status='terminated' WHERE node_id=%s", (node_id,))
        
        conn.commit()
        
        msg = "任务正常结束 (Completed)" if action_type == 'complete' else "任务已强制终止 (Terminated)"
        st.toast(f"{msg} - 节点 {node_id} 资源已释放")
        return True
        
    except mysql.connector.Error as err:
        st.error(f"释放资源失败: {err}")
        return False
    finally:
        cursor.close()
        conn.close()

# ================= 界面渲染主函数 =================

def render_admin_dashboard(db_config):
    """
    管理员控制台主视图 - 由 fore.py 调用
    """
    st.title("HPC 集群调度控制台")
    
    # 使用 Tabs 分隔功能区，界面更整洁
    tab1, tab2, tab3 = st.tabs(["资源池监控", "调度管理 (排队/运行)", "全部请求监控"])

    conn = get_connection(db_config)
    if not conn:
        st.stop()
    cursor = conn.cursor(dictionary=True)

    # --- Tab 1: 资源池监控 ---
    with tab1:
        st.subheader("物理资源池状态 (Physical Infrastructure)")
        st.caption("实时监控 `npus` 和 `memory` 表的剩余容量")
        
        col1, col2 = st.columns(2)
        
        with col1:
            st.markdown("### 计算节点 (NPU/CPU)")
            cursor.execute("""
                SELECT queue_type, 
                       COUNT(*) as total_nodes, 
                       SUM(available_cores) as free_cores, 
                       SUM(available_memory) as free_gpu_mem 
                FROM npus GROUP BY queue_type
            """)
            npu_stats = pd.DataFrame(cursor.fetchall())
            st.dataframe(npu_stats, use_container_width=True, hide_index=True)
            
        with col2:
            st.markdown("### 内存池 (RAM)")
            cursor.execute("""
                SELECT queue_type, 
                       SUM(available_size) as free_ram_gb 
                FROM memory GROUP BY queue_type
            """)
            mem_stats = pd.DataFrame(cursor.fetchall())
            st.dataframe(mem_stats, use_container_width=True, hide_index=True)

    # --- Tab 2: 调度管理 (核心功能) ---
    with tab2:
        # 2.1 待审批队列
        st.subheader("1. 等待队列 (Pending)")
        cursor.execute("SELECT * FROM requests WHERE status='pending' ORDER BY submit_time ASC")
        pending_reqs = pd.DataFrame(cursor.fetchall())
        
        if pending_reqs.empty:
            st.info("暂无排队作业。")
        else:
            for _, req in pending_reqs.iterrows():
                with st.container(border=True):
                    c1, c2, c3 = st.columns([5, 1, 1])
                    
                    # 解析参数用于显示
                    try:
                        params = json.loads(req['parameters'])
                        spec_name = params.get('name', 'Unknown')
                        queue_name = params.get('queue', 'Unknown')
                        db_p = params.get('db_params', {})
                        req_desc = f"CPU: {db_p.get('req_cores')}C | GPU: {db_p.get('req_gpu_mem')}G | RAM: {db_p.get('req_ram')}G"
                    except:
                        params = {}
                        spec_name = "解析错误"
                        queue_name = "-"
                        req_desc = "-"

                    with c1:
                        st.markdown(f"**Req #{req['request_id']}** | 用户ID: `{req['user_id']}` | 提交时间: {req['submit_time']}")
                        st.text(f"申请: {spec_name} ({queue_name})")
                        st.caption(f"规格需求: {req_desc}")
                    
                    with c2:
                        if st.button("通过", key=f"ok_{req['request_id']}", use_container_width=True):
                            if approve_request(db_config, req['request_id'], req['user_id'], params):
                                st.rerun()
                    with c3:
                        if st.button("拒绝", key=f"no_{req['request_id']}", use_container_width=True):
                            reject_request(db_config, req['request_id'])
                            st.rerun()

        st.divider()

        # 2.2 运行中实例管理
        st.subheader("2. 运行中实例 (Active Instances)")
        # 关联 requests 和 virtualcomputers 表，获取正在运行的任务
        # 逻辑：状态为 approved 且在 virtualcomputers 表中有对应记录
        sql_active = """
            SELECT r.request_id, u.user_name, r.submit_time, 
                   vc.node_id, vc.node_name, vc.queue_name, vc.hourly_price
            FROM requests r
            JOIN users u ON r.user_id = u.user_id
            JOIN virtualcomputers vc ON r.request_id = vc.request_id
            WHERE r.status = 'approved'
            ORDER BY r.submit_time DESC
        """
        cursor.execute(sql_active)
        active_reqs = pd.DataFrame(cursor.fetchall())

        if active_reqs.empty:
            st.info("当前无运行中的实例。")
        else:
            # 表头
            h1, h2, h3, h4 = st.columns([1, 2, 2, 2])
            h1.markdown("**ReqID**")
            h2.markdown("**节点信息**")
            h3.markdown("**用户/时间**")
            h4.markdown("**操作**")
            
            for _, row in active_reqs.iterrows():
                with st.container(border=True):
                    c1, c2, c3, c4 = st.columns([1, 2, 2, 2])
                    c1.text(f"#{row['request_id']}")
                    c2.text(f"Node: {row['node_name']}\nID: {row['node_id']}")
                    c3.text(f"User: {row['user_name']}\n{row['submit_time']}")
                    
                    with c4:
                        b_col1, b_col2 = st.columns(2)
                        with b_col1:
                            # 正常完成：模拟用户作业结束
                            if st.button("完成", key=f"fin_{row['request_id']}", help="释放资源，标记为 Completed"):
                                if stop_instance(db_config, row['node_id'], row['request_id'], 'complete'):
                                    st.rerun()
                        with b_col2:
                            # 强制终止：管理员强行回收
                            if st.button("终止", key=f"kill_{row['request_id']}", type="primary", help="释放资源，标记为 Terminated"):
                                if stop_instance(db_config, row['node_id'], row['request_id'], 'terminate'):
                                    st.rerun()

    # --- Tab 3: 全量请求监视 ---
    with tab3:
        st.subheader("全部请求监控 (All History)")
        
        # 筛选器
        filter_status = st.selectbox("按状态筛选", ["All", "pending", "approved", "completed", "terminated", "rejected"])
        
        base_sql = """
            SELECT r.request_id, u.user_name, r.status, r.submit_time, r.complete_time, r.node_id
            FROM requests r
            LEFT JOIN users u ON r.user_id = u.user_id
        """
        
        if filter_status != "All":
            base_sql += f" WHERE r.status = '{filter_status}'"
        
        base_sql += " ORDER BY r.request_id DESC LIMIT 50"
        
        cursor.execute(base_sql)
        history_df = pd.DataFrame(cursor.fetchall())
        
        if not history_df.empty:
            st.dataframe(
                history_df, 
                use_container_width=True,
                column_config={
                    "request_id": "ID",
                    "user_name": "用户",
                    "status": st.column_config.TextColumn("状态", help="当前作业状态"),
                    "node_id": "节点ID",
                    "submit_time": st.column_config.DatetimeColumn("提交时间", format="D MMM, HH:mm"),
                    "complete_time": st.column_config.DatetimeColumn("结束时间", format="D MMM, HH:mm"),
                }
            )
        else:
            st.info("没有找到符合条件的记录。")

                with c1:
                    st.markdown(f"**作业ID: {req['request_id']}** | 用户ID: {req['user_id']}")
                    st.caption(f"申请资源: {params['name']} (队列: {params['queue']})")
                    # 显示具体硬件需求
                    db_p = params.get('db_params', {})
                    st.code(f"需求: CPU={db_p.get('req_cores')}C, GPU={db_p.get('req_gpu_mem')}G, RAM={db_p.get('req_ram')}G", language="text")
                
                with c2:
                    if st.button("调度/通过", key=f"app_{req['request_id']}", type="primary"):
                        if approve_request(db_config, req['request_id'], req['user_id'], params):
                            st.rerun()
                with c3:
                    if st.button("拒绝", key=f"rej_{req['request_id']}"):
                        reject_request(db_config, req['request_id'])
                        st.rerun()
    
    # 3. 查看所有运行实例
    st.markdown("---")
    st.subheader("全系统运行实例 (Virtual Computers)")
    
    # 关联查询以显示更多信息
    sql_all = """
    SELECT vc.node_id, vc.node_name, vc.queue_name, vc.status, vc.hourly_price, 
           u.user_name, np.npu_serial
    FROM virtualcomputers vc
    JOIN requests r ON vc.request_id = r.request_id
    JOIN users u ON r.user_id = u.user_id
    JOIN virtualcpu vcpu ON vc.vir_NPU_id = vcpu.vir_NPU_id
    JOIN npus np ON vcpu.NPU_id = np.NPU_id
    WHERE vc.status='running'
    """
    cursor.execute(sql_all)
    all_instances = pd.DataFrame(cursor.fetchall())
    
    if not all_instances.empty:
        st.dataframe(all_instances, use_container_width=True)
    else:
        st.text("全系统无运行实例")

    # 4. 高级查询 (SQL)
    st.markdown("---")
    st.subheader("高级查询 (SQL)")
    
    sql_query = st.text_area("输入 SQL 语句", height=150, placeholder="SELECT * FROM users WHERE ...")
    
    if st.button("执行查询", type="primary"):
        if sql_query.strip():
            try:
                cursor.execute(sql_query)
                
                if cursor.with_rows:
                    result = cursor.fetchall()
                    if result:
                        df_result = pd.DataFrame(result)
                        st.dataframe(df_result, use_container_width=True)
                        st.success(f"查询成功，返回 {len(result)} 行。")
                    else:
                        st.info("查询成功，但未返回任何结果。")
                else:
                    conn.commit()
                    st.success(f"执行成功，影响行数: {cursor.rowcount}")
                    
            except mysql.connector.Error as err:
                st.error(f"SQL 执行错误: {err}")
        else:
            st.warning("请输入 SQL 语句")
        
    cursor.close()
    conn.close()
