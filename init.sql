/*
 Navicat Premium Dump SQL
 Source Schema         : cloud
 Target Server Type    : MySQL
 Target Server Version : 80000+ (MySQL 8.0+)
 File Encoding         : 65001
 
 Description: Cloud Resource Management - Large Scale Simulation Data
*/

CREATE DATABASE IF NOT EXISTS `cloud`;
USE `cloud`;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =======================================================
-- 1. 清理旧对象 (Drop Tables & Procedures)
-- =======================================================
DROP PROCEDURE IF EXISTS `sp_create_instance`;
DROP PROCEDURE IF EXISTS `sp_release_resource`;
DROP PROCEDURE IF EXISTS `sp_init_mock_load`; -- 清理临时初始化过程
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
  `role` varchar(50) NOT NULL DEFAULT 'user',
  `balance` decimal(10, 2) NULL DEFAULT 0.00,
  `status` varchar(50) NULL DEFAULT 'active',
  PRIMARY KEY (`user_id`),
  UNIQUE INDEX `user_name`(`user_name`),
  UNIQUE INDEX `email`(`email`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 3. 物理资源池 (Physical Resource Pools)
-- =======================================================
CREATE TABLE `npus` (
  `NPU_id` int NOT NULL AUTO_INCREMENT,
  `npu_serial` varchar(255) NOT NULL,
  `queue_type` varchar(100) NOT NULL,
  `cores` int NOT NULL DEFAULT 0,
  `available_cores` int NOT NULL DEFAULT 0,
  `NPU_memory` int NOT NULL,
  `available_memory` int NOT NULL,
  `hourly_rate` decimal(10, 2) NOT NULL DEFAULT 0.00,
  `status` varchar(50) NULL DEFAULT 'online',
  PRIMARY KEY (`NPU_id`),
  UNIQUE INDEX `npu_serial`(`npu_serial`),
  INDEX `idx_npu_queue`(`queue_type`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `memory` (
  `memory_id` int NOT NULL AUTO_INCREMENT,
  `memory_name` varchar(255) NULL,
  `queue_type` varchar(100) NULL,
  `memory_size` int NOT NULL,
  `available_size` int NOT NULL,
  `memory_type` varchar(50) NOT NULL DEFAULT 'DDR4',
  `status` varchar(50) NULL DEFAULT 'online',
  PRIMARY KEY (`memory_id`),
  INDEX `idx_mem_queue`(`queue_type`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `storagevolume` (
  `volume_id` int NOT NULL AUTO_INCREMENT,
  `volume_name` varchar(255) NOT NULL,
  `size_gb` int NOT NULL,
  `available_size` int NOT NULL,
  `volume_type` varchar(50) NOT NULL,
  `status` varchar(50) NULL DEFAULT 'online',
  PRIMARY KEY (`volume_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

-- =======================================================
-- 4. 请求表 (Requests)
-- =======================================================
CREATE TABLE `requests` (
  `request_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `request_type` varchar(50) NOT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'pending',
  `node_id` int NULL DEFAULT NULL,
  `submit_time` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  `complete_time` datetime NULL DEFAULT NULL,
  `parameters` json NULL,
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
  `NPU_id` int NOT NULL,
  `virtual_cores` int NOT NULL DEFAULT 1,
  `virtual_memory` int NOT NULL DEFAULT 0,
  `status` varchar(50) NOT NULL DEFAULT 'allocated',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`vir_NPU_id`),
  CONSTRAINT `virtualcpu_ibfk_1` FOREIGN KEY (`NPU_id`) REFERENCES `npus` (`NPU_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `virtualmemory` (
  `vir_memory_id` int NOT NULL AUTO_INCREMENT,
  `memory_id` int NOT NULL,
  `virtual_size` int NOT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'allocated',
  PRIMARY KEY (`vir_memory_id`),
  CONSTRAINT `virtualmemory_ibfk_1` FOREIGN KEY (`memory_id`) REFERENCES `memory` (`memory_id`)
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

CREATE TABLE `virtualvolume` (
  `vir_volume_id` int NOT NULL AUTO_INCREMENT,
  `volume_id` int NOT NULL,
  `virtual_size` int NOT NULL,
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
  `node_name` int NOT NULL,
  `queue_name` varchar(100) NULL,
  `vir_NPU_id` int NOT NULL,
  `vir_memory_id` int NOT NULL,
  `vir_volume_id` int NOT NULL,
  `hourly_price` decimal(10, 2) NOT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'idle',
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
  INDEX `idx_bill_req`(`request_id`),
  CONSTRAINT `bills_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE,
  CONSTRAINT `bills_ibfk_2` FOREIGN KEY (`request_id`) REFERENCES `requests` (`request_id`),
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
-- 8. 存储过程
-- =======================================================
DELIMITER //

CREATE PROCEDURE `sp_create_instance`(
    IN p_existing_req_id INT, 
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
    DECLARE v_vir_npu INT;
    DECLARE v_vir_mem INT;
    DECLARE v_vir_vol INT;
    DECLARE v_price DECIMAL(10,2);
    
    START TRANSACTION;
    
    SELECT NPU_id, hourly_rate INTO v_npu_id, v_price FROM npus 
    WHERE queue_type = p_queue_name AND available_cores >= p_req_cores AND available_memory >= p_req_gpu_mem AND status = 'online' LIMIT 1 FOR UPDATE;
    
    SELECT memory_id INTO v_mem_id FROM memory 
    WHERE queue_type = p_queue_name AND available_size >= p_req_ram AND status = 'online' LIMIT 1 FOR UPDATE;
    
    SELECT volume_id INTO v_vol_id FROM storagevolume 
    WHERE available_size >= p_req_disk AND status = 'online' LIMIT 1 FOR UPDATE;
    
    IF v_npu_id IS NULL OR v_mem_id IS NULL OR v_vol_id IS NULL THEN
        ROLLBACK;
        SET p_node_id = -1; 
    ELSE
        UPDATE npus SET available_cores = available_cores - p_req_cores, available_memory = available_memory - p_req_gpu_mem WHERE NPU_id = v_npu_id;
        UPDATE memory SET available_size = available_size - p_req_ram WHERE memory_id = v_mem_id;
        UPDATE storagevolume SET available_size = available_size - p_req_disk WHERE volume_id = v_vol_id;
        
        INSERT INTO virtualcpu (NPU_id, virtual_cores, virtual_memory) VALUES (v_npu_id, p_req_cores, p_req_gpu_mem);
        SET v_vir_npu = LAST_INSERT_ID();
        
        INSERT INTO virtualmemory (memory_id, virtual_size) VALUES (v_mem_id, p_req_ram);
        SET v_vir_mem = LAST_INSERT_ID();
        
        INSERT INTO virtualvolume (volume_id, virtual_size) VALUES (v_vol_id, p_req_disk);
        SET v_vir_vol = LAST_INSERT_ID();
        
        INSERT INTO virtualcomputers (request_id, node_name, queue_name, vir_NPU_id, vir_memory_id, vir_volume_id, hourly_price, status)
        VALUES (p_existing_req_id, FLOOR(RAND() * 900000 + 100000), p_queue_name, v_vir_npu, v_vir_mem, v_vir_vol, v_price, 'running');
        SET p_node_id = LAST_INSERT_ID();
        
        INSERT INTO use_log (user_id, action, details) 
        VALUES ((SELECT user_id FROM requests WHERE request_id = p_existing_req_id), 'create_success', CONCAT('NodeID:', p_node_id, ' Created'));
        
        COMMIT;
    END IF;
END //

CREATE PROCEDURE `sp_release_resource`(
    IN p_node_id INT,
    OUT p_result_status VARCHAR(50)
)
BEGIN
    DECLARE v_req_id INT;
    DECLARE v_user_id INT;
    DECLARE v_vir_npu_id INT;
    DECLARE v_vir_mem_id INT;
    DECLARE v_vir_vol_id INT;
    DECLARE v_phy_npu_id INT;
    DECLARE v_phy_mem_id INT;
    DECLARE v_phy_vol_id INT;
    DECLARE v_cores_used INT;
    DECLARE v_gpu_mem_used INT;
    DECLARE v_ram_used INT;
    DECLARE v_disk_used INT;
    DECLARE v_start_time DATETIME;
    DECLARE v_hourly_price DECIMAL(10, 2);
    DECLARE v_current_status VARCHAR(50);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_result_status = 'SQL_ERROR';
    END;

    START TRANSACTION;

    SELECT request_id, vir_NPU_id, vir_memory_id, vir_volume_id, created_at, hourly_price, status
    INTO v_req_id, v_vir_npu_id, v_vir_mem_id, v_vir_vol_id, v_start_time, v_hourly_price, v_current_status
    FROM virtualcomputers WHERE node_id = p_node_id FOR UPDATE;

    IF v_current_status IS NULL THEN
        SET p_result_status = 'NOT_FOUND';
        ROLLBACK;
    ELSEIF v_current_status != 'running' THEN
        SET p_result_status = 'ALREADY_STOPPED';
        ROLLBACK;
    ELSE
        SELECT user_id INTO v_user_id FROM requests WHERE request_id = v_req_id;

        SELECT NPU_id, virtual_cores, virtual_memory INTO v_phy_npu_id, v_cores_used, v_gpu_mem_used
        FROM virtualcpu WHERE vir_NPU_id = v_vir_npu_id;
        
        SELECT memory_id, virtual_size INTO v_phy_mem_id, v_ram_used
        FROM virtualmemory WHERE vir_memory_id = v_vir_mem_id;
        
        SELECT volume_id, virtual_size INTO v_phy_vol_id, v_disk_used
        FROM virtualvolume WHERE vir_volume_id = v_vir_vol_id;

        UPDATE npus SET available_cores = available_cores + v_cores_used, available_memory = available_memory + v_gpu_mem_used WHERE NPU_id = v_phy_npu_id;
        UPDATE memory SET available_size = available_size + v_ram_used WHERE memory_id = v_phy_mem_id;
        UPDATE storagevolume SET available_size = available_size + v_disk_used WHERE volume_id = v_phy_vol_id;

        UPDATE virtualcpu SET status = 'released' WHERE vir_NPU_id = v_vir_npu_id;
        UPDATE virtualmemory SET status = 'released' WHERE vir_memory_id = v_vir_mem_id;
        UPDATE virtualvolume SET status = 'released' WHERE vir_volume_id = v_vir_vol_id;
        UPDATE virtualcomputers SET status = 'terminated' WHERE node_id = p_node_id;
        UPDATE requests SET status = 'completed', complete_time = NOW() WHERE request_id = v_req_id;

        INSERT INTO bills (user_id, request_id, node_id, start_time, end_time, hourly_rate, cost_amount, payment_status)
        VALUES (v_user_id, v_req_id, p_node_id, v_start_time, NOW(), v_hourly_price, (TIMESTAMPDIFF(SECOND, v_start_time, NOW()) / 3600.0) * v_hourly_price, 'unpaid');

        INSERT INTO use_log (user_id, action, details) 
        VALUES (v_user_id, 'release_resource', CONCAT('NodeID:', p_node_id, ' resources released. Bill generated.'));

        SET p_result_status = 'SUCCESS';
        COMMIT;
    END IF;
END //
DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;

-- =======================================================
-- 9. 大规模数据初始化 (Large Scale Data Initialization)
-- =======================================================

-- 9.1 初始化 用户 (1 Admin, 1 Student, 50 Researchers)
INSERT INTO `users` (user_id, user_name, user_password, email, role, balance, status) 
VALUES 
  (1, 'Admin', 'admin123', 'admin@cloud.com', 'admin', 9999999.00, 'active'),
  (2, 'Student', '123456', 'stu@edu.cn', 'user', 50000.00, 'active');

-- 批量插入背景用户
INSERT INTO `users` (user_name, user_password, email, role, balance, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 50)
SELECT CONCAT('Researcher_', LPAD(n, 3, '0')), 'pass123', CONCAT('res', n, '@lab.com'), 'user', 100000.00, 'active' FROM seq;

-- 9.2 初始化 大规模物理资源
-- A. GPU V100 集群 (50个节点)
INSERT INTO `npus` (npu_serial, queue_type, cores, available_cores, NPU_memory, available_memory, hourly_rate, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 51)
SELECT CONCAT('gpu_v100_node_', LPAD(n, 3, '0')), 'gpu_v100', 24, 24, 128, 128, 15.00, 'online' FROM seq;

INSERT INTO `memory` (memory_name, queue_type, memory_size, available_size, memory_type, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 51)
SELECT CONCAT('RAM_v100_', LPAD(n, 3, '0')), 'gpu_v100', 512, 512, 'DDR4', 'online' FROM seq;

-- B. GPU A100 高性能集群 (10个节点)
INSERT INTO `npus` (npu_serial, queue_type, cores, available_cores, NPU_memory, available_memory, hourly_rate, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 11)
SELECT CONCAT('gpuB_node_', LPAD(n, 2, '0')), 'gpuB', 96, 96, 640, 640, 50.00, 'online' FROM seq;

INSERT INTO `memory` (memory_name, queue_type, memory_size, available_size, memory_type, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 11)
SELECT CONCAT('RAM_gpuB_', LPAD(n, 2, '0')), 'gpuB', 1024, 1024, 'DDR5', 'online' FROM seq;

-- C. CPU 通用计算池 (100个节点)
INSERT INTO `npus` (npu_serial, queue_type, cores, available_cores, NPU_memory, available_memory, hourly_rate, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 101)
SELECT CONCAT('cpu_6126_', LPAD(n, 3, '0')), 'cpu_6126', 24, 24, 0, 0, 3.00, 'online' FROM seq;

INSERT INTO `memory` (memory_name, queue_type, memory_size, available_size, memory_type, status)
WITH RECURSIVE seq AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM seq WHERE n < 101)
SELECT CONCAT('RAM_6126_', LPAD(n, 3, '0')), 'cpu_6126', 192, 192, 'DDR4', 'online' FROM seq;

-- D. 存储池 (PB级别)
INSERT INTO `storagevolume` (volume_name, size_gb, available_size, volume_type, status) 
VALUES 
  ('Ceph HDD Pool', 1000000, 1000000, 'HDD', 'online'), -- 1PB
  ('NetApp SSD Pool', 100000, 100000, 'SSD', 'online'); -- 100TB

-- 9.3 模拟背景负载 (Simulate Background Traffic)
-- 创建一个临时过程来生成随机负载
DELIMITER //
CREATE PROCEDURE `sp_init_mock_load`()
BEGIN
    DECLARE v_i INT DEFAULT 3; -- 从第3个用户开始 (避开Admin和Student)
    DECLARE v_max_user INT DEFAULT 52;
    DECLARE v_req_id INT;
    DECLARE v_node_id INT;
    DECLARE v_rand_queue INT;
    
    -- 循环遍历背景用户
    WHILE v_i <= v_max_user DO
        -- 每个用户随机创建 1-3 个实例
        SET v_rand_queue = FLOOR(RAND() * 3); -- 0, 1, 2
        
        -- 插入请求记录
        INSERT INTO requests (user_id, request_type, status, parameters) 
        VALUES (v_i, 'create_vm', 'processing', '{"mock": true}');
        SET v_req_id = LAST_INSERT_ID();
        
        -- 随机选择队列并调用创建过程
        -- 30% 概率创建 GPU V100, 10% A100, 60% CPU
        IF v_rand_queue = 0 THEN
             -- 申请 V100 (4核, 16G显存, 32G内存)
             CALL sp_create_instance(v_req_id, 'gpu_v100', 4, 16, 32, 100, v_node_id);
        ELSEIF v_rand_queue = 1 AND (v_i % 5 = 0) THEN 
             -- 只有少量用户申请 A100 (12核, 80G显存)
             CALL sp_create_instance(v_req_id, 'gpuB', 12, 80, 128, 500, v_node_id);
        ELSE
             -- 大部分申请 CPU (2核, 0显存, 4G内存)
             CALL sp_create_instance(v_req_id, 'cpu_6126', 2, 0, 4, 50, v_node_id);
        END IF;
        
        -- 更新请求状态
        IF v_node_id > 0 THEN
            UPDATE requests SET status = 'completed', node_id = v_node_id WHERE request_id = v_req_id;
        ELSE
            UPDATE requests SET status = 'failed', error_message = 'Init Resource Full' WHERE request_id = v_req_id;
        END IF;

        SET v_i = v_i + 1;
    END WHILE;
END //
DELIMITER ;

-- 执行负载模拟
CALL sp_init_mock_load();

-- 清理临时过程
DROP PROCEDURE `sp_init_mock_load`;

-- 验证结果
SELECT 
    (SELECT COUNT(*) FROM npus) as total_physical_nodes,
    (SELECT COUNT(*) FROM users) as total_users,
    (SELECT COUNT(*) FROM virtualcomputers WHERE status='running') as active_vms,
    (SELECT SUM(available_cores) FROM npus) as remaining_cpu_cores;
    
