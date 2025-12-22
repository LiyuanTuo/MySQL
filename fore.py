import streamlit as st
import pandas as pd
import mysql.connector
from mysql.connector import Error

# 导入拆分后的模块
import user as user_view
import admin as admin_view

# ================= 1. 配置与常量定义 =================

st.set_page_config(page_title="HPC 资源管理平台 (MySQL版)", layout="wide")

# MySQL 数据库配置 (请根据实际情况修改)
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "780327",  # 请替换为实际密码
    "database": "cloud",
    "charset": "utf8mb4",    # 强制字符集
    "collation": "utf8mb4_0900_ai_ci" # 强制排序规则，与表结构一致
}

# 硬件节点配置 - 必须与 init.sql 中的资源池匹配
# 参数说明: 
# - queue: 对应 npus 表中的 queue_type
# - req_cores: 对应 sp_create_instance 的 p_req_cores
# - req_gpu_mem: 对应 sp_create_instance 的 p_req_gpu_mem (GB)
# - req_ram: 对应 sp_create_instance 的 p_req_ram (GB)
# - req_disk: 对应 sp_create_instance 的 p_req_disk (GB)
VM_PACKAGES = {
    "gpu": {
        "v100_std": {
            "name": "V100 标准计算节点",
            "queue": "gpu_v100", 
            "desc": "适用于深度学习训练，单卡独占",
            "specs": {"显卡": "V100 32GB", "CPU": "24 Cores", "内存": "512 GB", "磁盘": "200 GB"},
            "db_params": {"req_cores": 24, "req_gpu_mem": 32, "req_ram": 512, "req_disk": 200},
            "price": 15.0
        },
        "a100_ultra": {
            "name": "A100 高性能集群",
            "queue": "gpuB",
            "desc": "全节点独占，超大显存模型训练",
            "specs": {"显卡": "A100 80GB x 8", "CPU": "96 Cores", "内存": "1 TB", "磁盘": "2 TB"},
            "db_params": {"req_cores": 96, "req_gpu_mem": 640, "req_ram": 1024, "req_disk": 2000},
            "price": 50.0
        }
    },
    "cpu": {
        "cpu_general": {
            "name": "通用计算节点 (6126)",
            "queue": "cpu_6126",
            "specs": {"CPU": "Xeon 6126 (24核)", "内存": "192 GB", "磁盘": "100 GB"},
            "db_params": {"req_cores": 24, "req_gpu_mem": 0, "req_ram": 192, "req_disk": 100},
            "price": 3.0
        }
    }
}

# ================= 2. 数据库连接辅助 =================

def get_connection():
    """获取 MySQL 数据库连接"""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        if conn.is_connected():
            return conn
    except Error as e:
        st.error(f"数据库连接失败: {e}")
        return None

# ================= 3. 主程序入口 =================

def main():
    # 1. 侧边栏：身份切换 (调试用)
    with st.sidebar:
        st.title("HPC 调度控制台")
        st.caption("架构: Slurm-like MySQL Schema")
        debug_role = st.radio("选择当前身份", ["普通用户 (Student)", "管理员 (Admin)"])
        
        st.info("说明：\n1. 资源分配由 MySQL 存储过程原子性处理\n2. 严格校验物理资源池(npus/memory)")

    # 2. 获取当前模拟的用户信息
    conn = get_connection()
    if not conn:
        st.stop()
        
    cursor = conn.cursor(dictionary=True)
    
    # 对应 init.sql 中的预置用户
    if "管理员" in debug_role:
        cursor.execute("SELECT * FROM users WHERE user_name='Admin'")
    else:
        cursor.execute("SELECT * FROM users WHERE user_name='Student'")
    
    current_user = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if not current_user:
        st.error("未找到用户信息，请检查 init.sql 是否已导入。")
        return

    # 3. 路由分发
    if current_user['role'] == 'admin':
        admin_view.render_admin_dashboard(DB_CONFIG)
    else:
        user_view.render_user_dashboard(DB_CONFIG, current_user, VM_PACKAGES)

if __name__ == "__main__":
    main()