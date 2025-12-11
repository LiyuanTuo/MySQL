import streamlit as st
import mysql.connector
import pandas as pd
import json
import time
import random
from datetime import datetime, timedelta

# ================= 1. 数据库配置 =================
# ⚠️⚠️⚠️ 请在这里修改为你自己的 MySQL 密码 ⚠️⚠️⚠️
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "780327",  # <--- 改这里！改这里！
    "database": "cloud"
}

def get_connection():
    return mysql.connector.connect(**DB_CONFIG)

# ================= 2. 自动初始化数据 (防止报错) =================
def init_db_data():
    """检查并插入基础数据，防止外键报错"""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        # 1. 确保有测试用户 (ID=1)
        cursor.execute("SELECT user_id FROM users WHERE user_id = 1")
        if not cursor.fetchone():
            sql_user = """
            INSERT INTO users (user_id, user_name, user_password, email, role, balance, status) 
            VALUES (1, 'DemoUser', '123456', 'student@seu.edu.cn', 'user', 1000.00, 'active')
            """
            cursor.execute(sql_user)
            st.toast("✅ 已自动创建测试用户 (ID=1)")

        # 2. 确保有物理资源 (NPU, Memory, Storage) 用于分配
        # 检查 NPU
        cursor.execute("SELECT count(*) FROM npus")
        if cursor.fetchone()[0] == 0:
            cursor.execute("INSERT INTO npus (npu_serial, NPU_memory, hourly_rate, fluency) VALUES ('NPU-A100-01', 32, 2.5, 1500)")
            cursor.execute("INSERT INTO npus (npu_serial, NPU_memory, hourly_rate, fluency) VALUES ('NPU-A100-02', 32, 2.5, 1500)")
        
        # 检查 Memory
        cursor.execute("SELECT count(*) FROM memory")
        if cursor.fetchone()[0] == 0:
            cursor.execute("INSERT INTO memory (memory_name, memory_size, memory_type) VALUES ('Samsung DDR5', 64, 'DDR5')")
        
        # 检查 Storage
        cursor.execute("SELECT count(*) FROM storagevolume")
        if cursor.fetchone()[0] == 0:
            cursor.execute("INSERT INTO storagevolume (volume_name, size_gb, volume_type) VALUES ('Local SSD', 1000, 'SSD')")

        conn.commit()
    except Exception as e:
        st.error(f"初始化数据失败: {e}")
    finally:
        conn.close()

# ================= 3. 页面主逻辑 =================
st.set_page_config(page_title="SEU Cloud 模拟平台", layout="wide", page_icon="☁️")

# 运行初始化检查
try:
    init_db_data()
except Exception as e:
    st.error(f"连接数据库失败，请检查密码！错误: {e}")
    st.stop()

st.title("☁️ SEU Cloud 云计算资源调度模拟")
st.markdown("### 东南大学数据库课程设计演示")

# 侧边栏：用户信息
conn = get_connection()
user_info = pd.read_sql("SELECT user_name, balance FROM users WHERE user_id=1", conn).iloc[0]
conn.close()
st.sidebar.header(f"👤 用户: {user_info['user_name']}")
st.sidebar.metric("账户余额", f"¥ {user_info['balance']}")

# 模拟当前登录用户 ID
CURRENT_USER_ID = 1

st.divider()

col1, col2, col3 = st.columns(3)

# --- 阶段一：提交请求 (Request) ---
with col1:
    st.header("1. 提交资源申请")
    st.info("步骤：插入 Requests 表")
    
    with st.form("request_form"):
        req_type = st.selectbox("用途类型", ["深度学习训练", "大数据分析", "Web服务"])
        c_cpu = st.slider("CPU 核心数", 1, 32, 4)
        c_mem = st.slider("内存大小 (GB)", 8, 128, 16)
        c_disk = st.slider("磁盘大小 (GB)", 100, 2000, 500)
        
        if st.form_submit_button("🚀 提交申请"):
            conn = get_connection()
            cursor = conn.cursor()
            try:
                params = json.dumps({"cpu": c_cpu, "memory": c_mem, "disk": c_disk})
                # 对应 SQL 中的 requests 表
                sql = """
                INSERT INTO requests (user_id, request_type, status, parameters, submit_time) 
                VALUES (%s, %s, 'pending', %s, NOW())
                """
                cursor.execute(sql, (CURRENT_USER_ID, req_type, params))
                conn.commit()
                st.success("✅ 请求已写入数据库！")
            except Exception as e:
                st.error(f"提交失败: {e}")
            finally:
                conn.close()

# --- 阶段二：系统调度 (Scheduling) ---
with col2:
    st.header("2. 系统调度处理")
    st.info("步骤：关联资源 -> 创建实例 -> 更新请求")
    
    conn = get_connection()
    pending_count = pd.read_sql("SELECT COUNT(*) FROM requests WHERE status='pending'", conn).iloc[0,0]
    conn.close()
    
    st.metric("待处理请求", f"{pending_count} 个")

    if st.button("⚙️ 执行调度 (模拟后台)"):
        if pending_count == 0:
            st.warning("无待处理请求")
        else:
            with st.status("正在分配物理资源...", expanded=True) as status:
                conn = get_connection()
                cursor = conn.cursor()
                try:
                    conn.start_transaction()
                    
                    # 1. 锁定一个 pending 请求
                    cursor.execute("SELECT request_id, parameters FROM requests WHERE status='pending' LIMIT 1 FOR UPDATE")
                    req = cursor.fetchone()
                    
                    if req:
                        req_id = req[0]
                        params = json.loads(req[1])
                        st.write(f"处理请求 ID: {req_id}")
                        
                        # 2. 获取物理资源ID (简化逻辑：直接取第一个可用的)
                        cursor.execute("SELECT NPU_id FROM npus LIMIT 1")
                        phy_npu = cursor.fetchone()[0]
                        cursor.execute("SELECT memory_id FROM memory LIMIT 1")
                        phy_mem = cursor.fetchone()[0]
                        cursor.execute("SELECT volume_id FROM storagevolume LIMIT 1")
                        phy_vol = cursor.fetchone()[0]
                        
                        # 3. 插入虚拟资源表 (virtualcpu, virtualmemory, virtualvolume)
                        st.write("构建虚拟化层...")
                        cursor.execute("INSERT INTO virtualcpu (NPU_id, virtual_cores, status) VALUES (%s, %s, 'in_use')", (phy_npu, params['cpu']))
                        vir_cpu_id = cursor.lastrowid
                        
                        cursor.execute("INSERT INTO virtualmemory (memory_id, virtual_size, status) VALUES (%s, %s, 'in_use')", (phy_mem, params['memory']))
                        vir_mem_id = cursor.lastrowid
                        
                        cursor.execute("INSERT INTO virtualvolume (volume_id, virtual_size, status) VALUES (%s, %s, 'attached')", (phy_vol, params['disk']))
                        vir_vol_id = cursor.lastrowid
                        
                        # 4. 创建虚拟机实例 (VirtualComputers)
                        # ⚠️ 注意：根据最新的 SQL，这里移除了 user_id，增加了 request_id
                        st.write("写入 VirtualComputers 表...")
                        node_name = random.randint(1000, 9999)
                        hourly_price = 1.5 + (params['cpu'] * 0.5)
                        
                        sql_vm = """
                        INSERT INTO virtualcomputers 
                        (request_id, node_name, node_display_name, vir_NPU_id, vir_memory_id, vir_volume_id, hourly_price, status)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, 'running')
                        """
                        cursor.execute(sql_vm, (req_id, node_name, f"Node-{node_name}", vir_cpu_id, vir_mem_id, vir_vol_id, hourly_price))
                        new_node_id = cursor.lastrowid
                        
                        # 5. 回填 Requests 表中的 node_id
                        cursor.execute("UPDATE requests SET status='completed', node_id=%s, start_time=NOW() WHERE request_id=%s", (new_node_id, req_id))
                        
                        # 6. 写日志
                        cursor.execute("INSERT INTO use_log (user_id, request_id, action, details) VALUES (%s, %s, 'create', 'System Auto-allocated')", (CURRENT_USER_ID, req_id))
                        
                        conn.commit()
                        status.update(label="调度成功！实例已上线", state="complete", expanded=False)
                        st.balloons()
                except Exception as e:
                    conn.rollback()
                    st.error(f"调度失败: {e}")
                finally:
                    conn.close()

# --- 阶段三：计费 (Billing) ---
# --- 阶段三：计费 (支付并下线) ---
with col3:
    st.header("3. 计费与结算")
    st.info("结算后实例将自动停止")
    
    conn = get_connection()
    # ⚠️ 这里的查询条件是 status='running'，只有运行中的机器才会显示
    sql_running = f"""
    SELECT vc.node_id, vc.node_display_name, vc.hourly_price, vc.request_id 
    FROM virtualcomputers vc 
    JOIN requests r ON vc.request_id = r.request_id
    WHERE r.user_id = {CURRENT_USER_ID} AND vc.status='running'
    ORDER BY vc.node_id DESC LIMIT 1
    """
    running_vm = pd.read_sql(sql_running, conn)
    conn.close()
    
    if not running_vm.empty:
        vm_data = running_vm.iloc[0]
        st.success(f"当前待结算实例: {vm_data['node_display_name']}")
        
        price_per_hour = float(vm_data['hourly_price'])
        st.write(f"单价: **¥{price_per_hour}/小时**")
        
        run_hours = st.slider("模拟运行时长 (Hours)", 1, 24, 5, key="bill_slider")
        total_estimated = price_per_hour * run_hours
        
        st.metric(label="本期账单总额", value=f"¥ {total_estimated:.2f}")
        
        if st.button("💰 支付并下线实例 (Pay & Stop)"):
            conn = get_connection()
            cursor = conn.cursor()
            try:
                start_dt = datetime.now()
                end_dt = start_dt + timedelta(hours=run_hours)
                
                # 1. 插入账单记录
                sql_bill = """
                INSERT INTO bills (user_id, request_id, node_id, start_time, end_time, hourly_rate, cost_amount, payment_status)
                VALUES (%s, %s, %s, %s, %s, %s, %s, 'paid')
                """
                cursor.execute(sql_bill, (CURRENT_USER_ID, int(vm_data['request_id']), int(vm_data['node_id']), start_dt, end_dt, price_per_hour, total_estimated))
                
                # 2. 扣除用户余额
                cursor.execute(f"UPDATE users SET balance = balance - {total_estimated} WHERE user_id={CURRENT_USER_ID}")
                
                # 3. 🌟 新增：将机器状态改为 'stopped'
                # 这样下次查询 'running' 时，这台机器就不会再出现了
                cursor.execute(f"UPDATE virtualcomputers SET status='stopped' WHERE node_id={int(vm_data['node_id'])}")
                
                conn.commit()
                st.success("✅ 支付成功！实例已停止运行。")
                time.sleep(1)
                st.rerun() # 刷新页面，列表清空
            except Exception as e:
                st.error(f"操作失败: {e}")
            finally:
                conn.close()
    else:
        # 当所有机器都 stopped 后，显示这个状态
        st.success("🎉 所有实例均已结算完成，无运行中机器。")

st.divider()

# ================= 4. 全局数据透视 (Dashboard) =================
st.subheader("🔍 数据库底层数据透视")
tabs = st.tabs(["Requests (请求)", "VirtualComputers (实例)", "Bills (账单)", "Users (用户)"])

conn = get_connection()
with tabs[0]:
    st.caption("Requests 表：存储用户原始需求")
    st.dataframe(pd.read_sql("SELECT * FROM requests ORDER BY request_id DESC", conn))
with tabs[1]:
    st.caption("VirtualComputers 表：通过 request_id 关联")
    st.dataframe(pd.read_sql("SELECT * FROM virtualcomputers ORDER BY node_id DESC", conn))
with tabs[2]:
    st.caption("Bills 表：usage_hours 是自动计算的")
    st.dataframe(pd.read_sql("SELECT * FROM bills ORDER BY bill_id DESC", conn))
with tabs[3]:
    st.caption("Users 表：查看余额变化")
    st.dataframe(pd.read_sql("SELECT * FROM users", conn))
conn.close()