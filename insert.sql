USE `cloud`;

-- ============================================================
-- 初始化物理资源数据
-- 必须执行此脚本，否则 Python 调度器无法找到物理资源，会报错 NoneType
-- ============================================================

-- 1. 插入 NPU (处理器) 数据
INSERT INTO `npus` (npu_serial, NPU_memory, hourly_rate, fluency, status) VALUES 
('NPU-Alpha-001', 32, 2.50, 1500, 'available'),
('NPU-Beta-002', 64, 5.00, 2000, 'available'),
('NPU-Gamma-003', 128, 10.00, 3000, 'available');

-- 2. 插入 Memory (内存) 数据
INSERT INTO `memory` (memory_name, memory_size, memory_type, status) VALUES 
('Samsung DDR4-16G', 16, 'DDR4', 'available'),
('Hynix DDR5-32G', 32, 'DDR5', 'available'),
('Kingston DDR4-64G', 64, 'DDR4', 'available'),
('Micron DDR5-128G', 128, 'DDR5', 'available');

-- 3. 插入 StorageVolume (硬盘) 数据
INSERT INTO `storagevolume` (volume_name, size_gb, volume_type, status) VALUES 
('System Disk SSD', 500, 'SSD', 'available'),
('Data Disk HDD', 1000, 'HDD', 'available'),
('High Perf NVMe', 2000, 'SSD', 'available');

-- 4. 确保有一个测试用户 (如果之前没加过)
INSERT INTO `users` (user_id, user_name, user_password, email, role, balance, status) 
VALUES (2, 'TestUser', '123456', 'student2@seu.edu.cn', 'user', 1000.00, 'active');
