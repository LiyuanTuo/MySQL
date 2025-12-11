/*
 Navicat Premium Dump SQL

 Source Server         : test
 Source Server Type    : MySQL
 Source Server Version : 90500 (9.5.0)
 Source Host           : localhost:3306
 Source Schema         : cloud

 Target Server Type    : MySQL
 Target Server Version : 90500 (9.5.0)
 File Encoding         : 65001

 Date: 09/12/2025 16:59:08
*/
CREATE DATABASE IF NOT EXISTS `cloud`;
USE `cloud`;
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for bills
-- ----------------------------
DROP TABLE IF EXISTS `bills`;
CREATE TABLE `bills`  (
  `bill_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL COMMENT '用户ID',
  `request_id` int NOT NULL COMMENT '请求编号',
  `node_id` int NOT NULL COMMENT '使用节点编号',
  `start_time` datetime NOT NULL COMMENT '节点实际开始使用时间',
  `end_time` datetime NOT NULL COMMENT '节点实际结束使用时间',
  `usage_hours` decimal(10, 2) GENERATED ALWAYS AS ((timestampdiff(SECOND,`start_time`,`end_time`) / 3600.0)) STORED COMMENT '使用时长(小时)' NULL,
  `hourly_rate` decimal(10, 2) NOT NULL COMMENT '小时费率',
  `cost_amount` decimal(10, 2) NOT NULL COMMENT '总花费',
  `payment_status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'unpaid' COMMENT '支付状态: unpaid/paid/refunded',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  `paid_at` datetime NULL DEFAULT NULL COMMENT '支付时间',
  PRIMARY KEY (`bill_id`) USING BTREE,
  INDEX `request_id`(`request_id` ASC) USING BTREE,
  INDEX `node_id`(`node_id` ASC) USING BTREE,
  INDEX `idx_bill_user`(`user_id` ASC) USING BTREE,
  INDEX `idx_bill_time`(`start_time` ASC, `end_time` ASC) USING BTREE,
  INDEX `idx_bill_payment_status`(`payment_status` ASC) USING BTREE,
  CONSTRAINT `bills_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `bills_ibfk_2` FOREIGN KEY (`request_id`) REFERENCES `requests` (`request_id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `bills_ibfk_3` FOREIGN KEY (`node_id`) REFERENCES `virtualcomputers` (`node_id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB AUTO_INCREMENT = 1 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for memory
-- ----------------------------
DROP TABLE IF EXISTS `memory`;
CREATE TABLE `memory`  (
  `memory_id` int NOT NULL AUTO_INCREMENT,
  `memory_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT NULL COMMENT '内存条名称',
  `memory_size` int NOT NULL COMMENT '内存大小(GB)',
  `memory_type` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL COMMENT '内存条类型DDR4/DDR5',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT 'available' COMMENT '状态: available/in_use',
  PRIMARY KEY (`memory_id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

SELECT * FROM `memory` LIMIT 200;
-- ----------------------------
-- Table structure for npus
-- ----------------------------
DROP TABLE IF EXISTS `npus`;
CREATE TABLE `npus`  (
  `NPU_id` int NOT NULL AUTO_INCREMENT,
  `npu_serial` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL COMMENT 'NPU序列号/物理标识',
  `NPU_memory` int NOT NULL COMMENT '内存大小(GB)',
  `hourly_rate` decimal(10, 2) NOT NULL DEFAULT 0.00 COMMENT '每小时费率',
  `fluency` int NOT NULL COMMENT 'NPU的频率(MHz)',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT 'available' COMMENT '状态: available/in_use/maintenance',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`NPU_id`) USING BTREE,
  UNIQUE INDEX `npu_serial`(`npu_serial` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for requests
-- ----------------------------
DROP TABLE IF EXISTS `requests`;
CREATE TABLE `requests`  (
  `request_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL COMMENT '提交用户',
  `request_type` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL COMMENT '请求类型: create/start/stop/delete/scale',
  `priority` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'normal' COMMENT '请求优先级: high/medium/low',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'pending' COMMENT '请求状态: pending/queued/running/completed/failed/rejected',
  `node_id` int NULL DEFAULT NULL COMMENT '请求节点（计算机编号）',
  `submit_time` datetime NULL DEFAULT CURRENT_TIMESTAMP COMMENT '提交时间',
  `start_time` datetime NULL DEFAULT NULL COMMENT '开始处理时间',
  `complete_time` datetime NULL DEFAULT NULL COMMENT '完成时间',
  `parameters` json NULL COMMENT '请求参数(JSON格式)',
  `error_message` text CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL COMMENT '错误信息',
  PRIMARY KEY (`request_id`) USING BTREE,
  INDEX `idx_req_user`(`user_id` ASC) USING BTREE,
  INDEX `idx_req_status`(`status` ASC) USING BTREE,
  INDEX `idx_req_submit_time`(`submit_time` ASC) USING BTREE,
  INDEX `requests_ibfk_2`(`node_id` ASC) USING BTREE,
  CONSTRAINT `requests_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `requests_ibfk_2` FOREIGN KEY (`node_id`) REFERENCES `virtualcomputers` (`node_id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE = InnoDB AUTO_INCREMENT = 1 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for storagevolume
-- ----------------------------
DROP TABLE IF EXISTS `storagevolume`;
CREATE TABLE `storagevolume`  (
  `volume_id` int NOT NULL AUTO_INCREMENT,
  `volume_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL COMMENT '卷的名称',
  `size_gb` int NOT NULL COMMENT '大小（GB)',
  `volume_type` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL COMMENT '类型(SSD/HDD)',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT 'available' COMMENT '状态: available/attached',
  PRIMARY KEY (`volume_id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;
SELECT * FROM `storagevolume` LIMIT 50;
-- ----------------------------
-- Table structure for use_log
-- ----------------------------
DROP TABLE IF EXISTS `use_log`;
CREATE TABLE `use_log`  (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `user_id` int NOT NULL,
  `request_id` int NULL DEFAULT NULL,
  `bill_id` int NULL DEFAULT NULL,
  `action` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL COMMENT '操作类型',
  `details` text CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL COMMENT '操作详情',
  `ip_address` varchar(45) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT NULL COMMENT '操作IP地址',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`log_id`) USING BTREE,
  INDEX `request_id`(`request_id` ASC) USING BTREE,
  INDEX `bill_id`(`bill_id` ASC) USING BTREE,
  INDEX `idx_log_user_time`(`user_id` ASC, `created_at` ASC) USING BTREE,
  INDEX `idx_log_action`(`action` ASC) USING BTREE,
  CONSTRAINT `use_log_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE RESTRICT,
  CONSTRAINT `use_log_ibfk_2` FOREIGN KEY (`request_id`) REFERENCES `requests` (`request_id`) ON DELETE SET NULL ON UPDATE RESTRICT,
  CONSTRAINT `use_log_ibfk_3` FOREIGN KEY (`bill_id`) REFERENCES `bills` (`bill_id`) ON DELETE SET NULL ON UPDATE RESTRICT
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for users
-- ----------------------------
DROP TABLE IF EXISTS `users`;
CREATE TABLE `users`  (
  `user_id` int NOT NULL AUTO_INCREMENT,
  `user_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `user_password` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `create_time` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  `email` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
  `role` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'user' COMMENT '角色: admin/user',
  `balance` decimal(10, 2) NULL DEFAULT 0.00 COMMENT '账户余额',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT 'active' COMMENT '状态: active/suspended',
  PRIMARY KEY (`user_id`) USING BTREE,
  UNIQUE INDEX `user_name`(`user_name` ASC) USING BTREE,
  UNIQUE INDEX `email`(`email` ASC) USING BTREE
) ENGINE = InnoDB AUTO_INCREMENT = 1 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

SELECT * FROM `users` LIMIT 10;
-- ----------------------------
-- Table structure for virtualcomputers
-- ----------------------------
DROP TABLE IF EXISTS `virtualcomputers`;
CREATE TABLE `virtualcomputers`  (
  `node_id` int NOT NULL AUTO_INCREMENT,
  `request_id` int NOT NULL COMMENT '请求id',
  `node_name` int NOT NULL COMMENT '节点名称/编号',
  `node_display_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL DEFAULT NULL COMMENT '节点显示名称',
  `vir_NPU_id` int NOT NULL COMMENT '虚拟NPU id',
  `vir_memory_id` int NOT NULL COMMENT '虚拟内存id',
  `vir_volume_id` int NOT NULL COMMENT '虚拟磁盘id',
  `hourly_price` decimal(10, 2) NOT NULL COMMENT '每小时单价',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'idle' COMMENT '节点状态: idle/busy/stopped/error',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`node_id`) USING BTREE,
  UNIQUE INDEX `node_name`(`node_name` ASC) USING BTREE,
  INDEX `vir_NPU_id`(`vir_NPU_id` ASC) USING BTREE,
  INDEX `vir_memory_id`(`vir_memory_id` ASC) USING BTREE,
  INDEX `vir_volume_id`(`vir_volume_id` ASC) USING BTREE,
  INDEX `idx_vc_status`(`status` ASC) USING BTREE,
  INDEX `virtualcomputers_ibfk_1`(`request_id` ASC) USING BTREE,
  CONSTRAINT `virtualcomputers_ibfk_2` FOREIGN KEY (`vir_NPU_id`) REFERENCES `virtualcpu` (`vir_NPU_id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `virtualcomputers_ibfk_3` FOREIGN KEY (`vir_memory_id`) REFERENCES `virtualmemory` (`vir_memory_id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `virtualcomputers_ibfk_4` FOREIGN KEY (`vir_volume_id`) REFERENCES `virtualvolume` (`vir_volume_id`) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `virtualcomputers_ibfk_1` FOREIGN KEY (`request_id`) REFERENCES `requests` (`request_id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB AUTO_INCREMENT = 1 CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for virtualcpu
-- ----------------------------
DROP TABLE IF EXISTS `virtualcpu`;
CREATE TABLE `virtualcpu`  (
  `vir_NPU_id` int NOT NULL AUTO_INCREMENT,
  `NPU_id` int NOT NULL COMMENT '物理NPU ID',
  `virtual_cores` int NOT NULL DEFAULT 1 COMMENT '虚拟核心数',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'available' COMMENT '状态: available/in_use',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`vir_NPU_id`) USING BTREE,
  INDEX `NPU_id`(`NPU_id` ASC) USING BTREE,
  CONSTRAINT `virtualcpu_ibfk_1` FOREIGN KEY (`NPU_id`) REFERENCES `npus` (`NPU_id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Table structure for virtualmemory
-- ----------------------------
DROP TABLE IF EXISTS `virtualmemory`;
CREATE TABLE `virtualmemory`  (
  `vir_memory_id` int NOT NULL AUTO_INCREMENT,
  `memory_id` int NOT NULL COMMENT '物理内存ID',
  `virtual_size` int NOT NULL COMMENT '虚拟内存大小(GB)',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'available' COMMENT '状态: available/in_use',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`vir_memory_id`) USING BTREE,
  INDEX `memory_id`(`memory_id` ASC) USING BTREE,
  CONSTRAINT `virtualmemory_ibfk_1` FOREIGN KEY (`memory_id`) REFERENCES `memory` (`memory_id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;

SELECT * FROM `virtualmemory` LIMIT 30;
-- ----------------------------
-- Table structure for virtualvolume
-- ----------------------------
DROP TABLE IF EXISTS `virtualvolume`;
CREATE TABLE `virtualvolume`  (
  `vir_volume_id` int NOT NULL AUTO_INCREMENT,
  `volume_id` int NOT NULL COMMENT '物理卷ID',
  `virtual_size` int NOT NULL COMMENT '虚拟卷大小(GB)',
  `status` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'available' COMMENT '状态: available/attached',
  `created_at` datetime NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`vir_volume_id`) USING BTREE,
  INDEX `volume_id`(`volume_id` ASC) USING BTREE,
  CONSTRAINT `virtualvolume_ibfk_1` FOREIGN KEY (`volume_id`) REFERENCES `storagevolume` (`volume_id`) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci ROW_FORMAT = Dynamic;
SELECT * FROM `virtualvolume` LIMIT 30;
-- ----------------------------
-- View structure for user_usage_stats
-- ----------------------------
DROP VIEW IF EXISTS `user_usage_stats`;
CREATE ALGORITHM = UNDEFINED SQL SECURITY DEFINER VIEW `user_usage_stats` AS 
SELECT 
  `u`.`user_id` AS `user_id`,
  `u`.`user_name` AS `user_name`,
  `u`.`email` AS `email`,
  `u`.`balance` AS `balance`,
  COUNT(DISTINCT `vc`.`node_id`) AS `total_nodes`,
  COUNT(DISTINCT `r`.`request_id`) AS `total_requests`,
  SUM(CASE WHEN (`b`.`payment_status` = 'paid') THEN `b`.`cost_amount` ELSE 0 END) AS `total_spent`,
  MAX(`r`.`submit_time`) AS `last_request_time` 
FROM `users` `u`
LEFT JOIN `requests` `r` ON `u`.`user_id` = `r`.`user_id`
LEFT JOIN `virtualcomputers` `vc` ON `r`.`request_id` = `vc`.`request_id`
LEFT JOIN `bills` `b` ON `u`.`user_id` = `b`.`user_id`
GROUP BY `u`.`user_id`, `u`.`user_name`, `u`.`email`, `u`.`balance`;

-- ----------------------------
-- Triggers structure for table bills
-- ----------------------------
DROP TRIGGER IF EXISTS `update_paid_at`;
delimiter ;;
CREATE TRIGGER `update_paid_at` BEFORE UPDATE ON `bills` FOR EACH ROW BEGIN
  IF NEW.payment_status = 'paid' AND OLD.payment_status != 'paid' THEN
    SET NEW.paid_at = NOW();
  END IF;
END
;;
delimiter ;

SET FOREIGN_KEY_CHECKS = 1;
