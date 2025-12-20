/*
 Navicat Premium Dump SQL
 Source Schema         : cloud
 Target Server Type    : MySQL
 Target Server Version : 80000+ (MySQL 8.0+)
 
 Date: 2025-12-20
 Description: Cloud Resource Management (Optimized with Queues & Transactions)
 Status: Verified & Corrected
*/

CREATE DATABASE IF NOT EXISTS `cloud`;
USE `cloud`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =======================================================
-- 1. 清理旧对象 (Drop Tables & Procedures)
-- =======================================================
DROP PROCEDURE IF EXISTS `sp_create_instance`;
DROP TABLE IF EXISTS `use_log`;
DROP TABLE IF EXISTS `bills`;
DROP TABLE IF EXISTS `requests`;
DROP TABLE IF EXISTS `virtualcomputers`;
DROP TABLE IF EXISTS `virtualvolume`;
DROP TABLE IF EXISTS `virtualmemory`;
DROP TABLE IF EXISTS `virtualcpu`;
DROP TABLE IF EXISTS `storagevolume`;
DROP TABLE IF EXISTS `memory`;
DROP TABLE IF EXISTS `npus`;
DROP TABLE IF EXISTS `users`;

-- =======================================================
-- 2. 基础用户表 (Users)
-- =======================================================
CREATE TABLE `users` (
  `user_id` int NOT NULL AUTO_INCREMENT,
  `user_name` varchar(255) NOT NULL,
  `user_password` varchar(255) NOT NULL,
  `create_time` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  `email` varchar(255) NOT NULL,
  `role` varchar(50) NOT NULL DEFAULT 'user' COMMENT 'admin/user',
  `balance` decimal(10, 2) NULL DEFAULT 0.00,
  `status` varchar(50) NULL DEFAULT 'active',
  PRIMARY KEY (`user_id`),
  UNIQUE INDEX `user_name`(`user_name`),
  UNIQUE INDEX `email`(`email`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 3. 物理资源池 (Physical Resource Pools)
-- =======================================================

-- 3.1 物理计算节点 (原 npus 表)
CREATE TABLE `npus` (
  `NPU_id` int NOT NULL AUTO_INCREMENT,
  `npu_serial` varchar(255) NOT NULL COMMENT '物理节点主机名/序列号',
  `queue_type` varchar(100) NOT NULL COMMENT '所属资源队列: gpu_v100, cpu_6126',
  `cores` int NOT NULL DEFAULT 0 COMMENT '物理CPU总核数',
  `available_cores` int NOT NULL DEFAULT 0 COMMENT '【核心】剩余可用CPU核数',
  `NPU_memory` int NOT NULL COMMENT '物理总显存(GB), 纯CPU节点此项为0',
  `available_memory` int NOT NULL COMMENT '【核心】剩余可用显存(GB)',
  `hourly_rate` decimal(10, 2) NOT NULL DEFAULT 0.00 COMMENT '节点基础费率',
  `status` varchar(50) NULL DEFAULT 'online',
  PRIMARY KEY (`NPU_id`),
  UNIQUE INDEX `npu_serial`(`npu_serial`),
  INDEX `idx_npu_queue`(`queue_type`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 3.2 物理内存条
CREATE TABLE `memory` (
  `memory_id` int NOT NULL AUTO_INCREMENT,
  `memory_name` varchar(255) NULL,
  `queue_type` varchar(100) NULL COMMENT '需与计算节点队列匹配',
  `memory_size` int NOT NULL COMMENT '物理总内存(GB)',
  `available_size` int NOT NULL COMMENT '【核心】剩余可用内存(GB)',
  `memory_type` varchar(50) NOT NULL DEFAULT 'DDR4',
  `status` varchar(50) NULL DEFAULT 'online',
  PRIMARY KEY (`memory_id`),
  INDEX `idx_mem_queue`(`queue_type`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- 3.3 物理存储卷
CREATE TABLE `storagevolume` (
  `volume_id` int NOT NULL AUTO_INCREMENT,
  `volume_name` varchar(255) NOT NULL,
  `size_gb` int NOT NULL COMMENT '物理总容量(GB)',
  `available_size` int NOT NULL COMMENT '【核心】剩余可用容量(GB)',
  `volume_type` varchar(50) NOT NULL COMMENT 'SSD/HDD/NVMe',
  `status` varchar(50) NULL DEFAULT 'online',
  PRIMARY KEY (`volume_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 4. 请求表 (Requests)
-- =======================================================
CREATE TABLE `requests` (
  `request_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `request_type` varchar(50) NOT NULL COMMENT 'create_vm/start/stop',
  `status` varchar(50) NOT NULL DEFAULT 'pending',
  `node_id` int NULL DEFAULT NULL COMMENT '关联的虚拟节点ID',
  `submit_time` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  `complete_time` datetime NULL DEFAULT NULL,
  `parameters` json NULL COMMENT '请求参数快照',
  `error_message` text NULL,
  PRIMARY KEY (`request_id`),
  INDEX `idx_req_user`(`user_id`),
  INDEX `idx_req_node`(`node_id`),
  CONSTRAINT `requests_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 5. 虚拟资源映射表 (Virtualization Layer)
-- =======================================================
CREATE TABLE `virtualcpu` (
  `vir_NPU_id` int NOT NULL AUTO_INCREMENT,
  `NPU_id` int NOT NULL COMMENT '指向物理计算节点',
  `virtual_cores` int NOT NULL DEFAULT 1 COMMENT '占用核数',
  `virtual_memory` int NOT NULL DEFAULT 0 COMMENT '占用显存',
  `status` varchar(50) NOT NULL DEFAULT 'allocated',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`vir_NPU_id`),
  CONSTRAINT `virtualcpu_ibfk_1` FOREIGN KEY (`NPU_id`) REFERENCES `npus` (`NPU_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `virtualmemory` (
  `vir_memory_id` int NOT NULL AUTO_INCREMENT,
  `memory_id` int NOT NULL COMMENT '指向物理内存',
  `virtual_size` int NOT NULL COMMENT '占用内存大小',
  `status` varchar(50) NOT NULL DEFAULT 'allocated',
  PRIMARY KEY (`vir_memory_id`),
  CONSTRAINT `virtualmemory_ibfk_1` FOREIGN KEY (`memory_id`) REFERENCES `memory` (`memory_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `virtualvolume` (
  `vir_volume_id` int NOT NULL AUTO_INCREMENT,
  `volume_id` int NOT NULL COMMENT '指向物理卷',
  `virtual_size` int NOT NULL COMMENT '占用存储大小',
  `status` varchar(50) NOT NULL DEFAULT 'allocated',
  PRIMARY KEY (`vir_volume_id`),
  CONSTRAINT `virtualvolume_ibfk_1` FOREIGN KEY (`volume_id`) REFERENCES `storagevolume` (`volume_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 6. 虚拟机实例表 (Virtual Computers)
-- =======================================================
CREATE TABLE `virtualcomputers` (
  `node_id` int NOT NULL AUTO_INCREMENT,
  `request_id` int NOT NULL,
  `node_name` int NOT NULL COMMENT '数字编号',
  `queue_name` varchar(100) NULL COMMENT '所属队列',
  `vir_NPU_id` int NOT NULL,
  `vir_memory_id` int NOT NULL,
  `vir_volume_id` int NOT NULL,
  `hourly_price` decimal(10, 2) NOT NULL COMMENT '创建时锁定的单价',
  `status` varchar(50) NOT NULL DEFAULT 'idle' COMMENT 'running/stopped/error',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`node_id`),
  UNIQUE INDEX `node_name`(`node_name`),
  INDEX `idx_vc_request`(`request_id`),
  CONSTRAINT `virtualcomputers_ibfk_1` FOREIGN KEY (`request_id`) REFERENCES `requests` (`request_id`),
  CONSTRAINT `virtualcomputers_ibfk_2` FOREIGN KEY (`vir_NPU_id`) REFERENCES `virtualcpu` (`vir_NPU_id`),
  CONSTRAINT `virtualcomputers_ibfk_3` FOREIGN KEY (`vir_memory_id`) REFERENCES `virtualmemory` (`vir_memory_id`),
  CONSTRAINT `virtualcomputers_ibfk_4` FOREIGN KEY (`vir_volume_id`) REFERENCES `virtualvolume` (`vir_volume_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

ALTER TABLE `requests` 
ADD CONSTRAINT `requests_ibfk_node` 
FOREIGN KEY (`node_id`) REFERENCES `virtualcomputers` (`node_id`) 
ON DELETE SET NULL;

-- =======================================================
-- 7. 账单与日志 (Bills & Logs)
-- =======================================================
CREATE TABLE `bills` (
  `bill_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `request_id` int NOT NULL,
  `node_id` int NOT NULL,
  `start_time` datetime NOT NULL,
  `end_time` datetime NOT NULL,
  `usage_hours` decimal(10, 2) GENERATED ALWAYS AS ((timestampdiff(SECOND,`start_time`,`end_time`) / 3600.0)) STORED NULL,
  `hourly_rate` decimal(10, 2) NOT NULL,
  `cost_amount` decimal(10, 2) NOT NULL,
  `payment_status` varchar(20) NOT NULL DEFAULT 'unpaid',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`bill_id`),
  INDEX `idx_bill_user`(`user_id`),
  INDEX `idx_bill_req`(`request_id`), -- [修复] 补全索引
  CONSTRAINT `bills_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE,
  CONSTRAINT `bills_ibfk_2` FOREIGN KEY (`request_id`) REFERENCES `requests` (`request_id`), -- [修复] 补全外键
  CONSTRAINT `bills_ibfk_3` FOREIGN KEY (`node_id`) REFERENCES `virtualcomputers` (`node_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `use_log` (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `action` varchar(50) NOT NULL,
  `details` text NULL,
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`log_id`),
  CONSTRAINT `use_log_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 8. 存储过程:直接建立一个事务
-- =======================================================
DELIMITER //

DROP PROCEDURE IF EXISTS `sp_create_instance` //

CREATE PROCEDURE `sp_create_instance`(
    IN p_user_id INT,
    IN p_queue_name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, 
    IN p_req_cores INT,
    IN p_req_gpu_mem INT,
    IN p_req_ram INT,
    IN p_req_disk INT,
    OUT p_node_id INT
)
BEGIN
    DECLARE v_npu_id INT DEFAULT NULL;
    DECLARE v_mem_id INT DEFAULT NULL;
    DECLARE v_vol_id INT DEFAULT NULL;
    DECLARE v_req_id INT;
    DECLARE v_vir_npu INT;
    DECLARE v_vir_mem INT;
    DECLARE v_vir_vol INT;
    DECLARE v_price DECIMAL(10,2);
    
    -- 开启事务
    START TRANSACTION;
    -- 下面是一个简单的调度算法，使用sql语言


    -- 1. 查找满足条件的计算节点 (CPU + GPU) 并锁定
    SELECT NPU_id, hourly_rate INTO v_npu_id, v_price
    FROM npus 
    WHERE queue_type = p_queue_name 
      AND available_cores >= p_req_cores 
      AND available_memory >= p_req_gpu_mem 
      AND status = 'online'
    LIMIT 1 FOR UPDATE;
    
    -- 2. 查找满足条件的物理内存 并锁定
    SELECT memory_id INTO v_mem_id 
    FROM memory 
    WHERE queue_type = p_queue_name 
      AND available_size >= p_req_ram 
      AND status = 'online'
    LIMIT 1 FOR UPDATE;
    
    -- 3. 查找满足条件的存储 并锁定
    SELECT volume_id INTO v_vol_id 
    FROM storagevolume 
    WHERE available_size >= p_req_disk 
      AND status = 'online'
    LIMIT 1 FOR UPDATE;
    
    -- 4. 资源校验
    IF v_npu_id IS NULL OR v_mem_id IS NULL OR v_vol_id IS NULL THEN
        ROLLBACK;
        SET p_node_id = -1; 
    ELSE
        -- 5. 扣除物理资源
        UPDATE npus 
        SET available_cores = available_cores - p_req_cores, 
            available_memory = available_memory - p_req_gpu_mem 
        WHERE NPU_id = v_npu_id;
        
        UPDATE memory SET available_size = available_size - p_req_ram WHERE memory_id = v_mem_id;
        UPDATE storagevolume SET available_size = available_size - p_req_disk WHERE volume_id = v_vol_id;
        
        -- 6. 创建请求记录
        INSERT INTO requests (user_id, request_type, status, parameters, complete_time) 
        VALUES (p_user_id, 'create_vm', 'completed', JSON_OBJECT('queue', p_queue_name, 'cores', p_req_cores, 'ram', p_req_ram), NOW());
        SET v_req_id = LAST_INSERT_ID();
        
        -- 7. 创建虚拟资源映射
        INSERT INTO virtualcpu (NPU_id, virtual_cores, virtual_memory) VALUES (v_npu_id, p_req_cores, p_req_gpu_mem);
        SET v_vir_npu = LAST_INSERT_ID();
        
        INSERT INTO virtualmemory (memory_id, virtual_size) VALUES (v_mem_id, p_req_ram);
        SET v_vir_mem = LAST_INSERT_ID();
        
        INSERT INTO virtualvolume (volume_id, virtual_size) VALUES (v_vol_id, p_req_disk);
        SET v_vir_vol = LAST_INSERT_ID();
        
        -- 8. 创建虚拟机实例
        INSERT INTO virtualcomputers (request_id, node_name, queue_name, vir_NPU_id, vir_memory_id, vir_volume_id, hourly_price, status)
        VALUES (v_req_id, FLOOR(RAND() * 900000 + 100000), p_queue_name, v_vir_npu, v_vir_mem, v_vir_vol, v_price, 'running');
        SET p_node_id = LAST_INSERT_ID();
        
        -- 9. 回填请求表的外键
        UPDATE requests SET node_id = p_node_id WHERE request_id = v_req_id;
        
        -- 10. 记录成功日志
        INSERT INTO use_log (user_id, action, details) 
        VALUES (p_user_id, 'create_success', CONCAT('NodeID:', p_node_id, ' Created'));
        
        COMMIT;
    END IF;
END //

DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;

-- =======================================================
-- 9. 初始化仿真数据 (Data Initialization)
-- =======================================================

-- 9.1 初始化 GPU 队列 (gpu_v100)
INSERT INTO `npus` (npu_serial, queue_type, cores, available_cores, NPU_memory, available_memory, hourly_rate, status)
WITH RECURSIVE seq AS (SELECT 5 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 17)
SELECT CONCAT('gpu_v100_node_', LPAD(n, 2, '0')), 'gpu_v100', 24, 24, 128, 128, 15.00, 'online' FROM seq;

INSERT INTO `memory` (memory_name, queue_type, memory_size, available_size, memory_type, status)
WITH RECURSIVE seq AS (SELECT 5 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 17)
SELECT CONCAT('RAM_gpu_v100_', LPAD(n, 2, '0')), 'gpu_v100', 512, 512, 'DDR4', 'online' FROM seq;

-- 9.2 初始化 高性能计算节点 (gpuB)
INSERT INTO `npus` (npu_serial, queue_type, cores, available_cores, NPU_memory, available_memory, hourly_rate, status)
VALUES ('gpuB_node_01', 'gpuB', 96, 96, 640, 640, 50.00, 'online');

INSERT INTO `memory` (memory_name, queue_type, memory_size, available_size, memory_type, status)
VALUES ('RAM_gpuB_01', 'gpuB', 1024, 1024, 'DDR5', 'online');

-- 9.3 初始化 CPU 队列 (cpu_6126)
INSERT INTO `npus` (npu_serial, queue_type, cores, available_cores, NPU_memory, available_memory, hourly_rate, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 10)
SELECT CONCAT('cpu_6126_', LPAD(n, 2, '0')), 'cpu_6126', 24, 24, 0, 0, 3.00, 'online' FROM seq;

INSERT INTO `memory` (memory_name, queue_type, memory_size, available_size, memory_type, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 10)
SELECT CONCAT('RAM_6126_', LPAD(n, 2, '0')), 'cpu_6126', 192, 192, 'DDR4', 'online' FROM seq;

-- 9.4 初始化 共享存储池
INSERT INTO `storagevolume` (volume_name, size_gb, available_size, volume_type, status) 
VALUES 
  ('Ceph Shared Pool', 100000, 100000, 'HDD', 'online'),
  ('NVMe Fast Pool', 20000, 20000, 'SSD', 'online');

-- 9.5 初始化 用户
INSERT INTO `users` (user_id, user_name, user_password, email, role, balance, status) 
VALUES 
  (1, 'Admin', 'admin123', 'admin@cloud.com', 'admin', 99999.00, 'active'),
  (2, 'Student', '123456', 'stu@edu.cn', 'user', 1000.00, 'active')
ON DUPLICATE KEY UPDATE user_name=VALUES(user_name);

-- 验证
SELECT 'Database Optimized & Initialized. Ready for calls to sp_create_instance.' as status;

