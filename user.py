import streamlit as st
import pandas as pd
import mysql.connector
import json
from datetime import datetime

def get_connection(db_config):
    return mysql.connector.connect(**db_config)

def submit_resource_request(db_config, user_id, pkg_key, pkg_data, category):
    """
    提交资源申请到 requests 表 (状态为 pending)
    实际资源的分配将在管理员审批时通过存储过程触发
    """
    conn = get_connection(db_config)
    cursor = conn.cursor()
    
    # 构建包含物理资源需求的参数 JSON
    params = {
        "category": category,
        "package_key": pkg_key,
        "name": pkg_data['name'],
        "queue": pkg_data['queue'],
        "price": pkg_data['price'],
        # 关键：传递给存储过程的硬件参数
        "db_params": pkg_data['db_params'] 
    }
    
    # 对应 init.sql: requests 表
    sql = """
    INSERT INTO requests (user_id, request_type, parameters, status, submit_time) 
    VALUES (%s, %s, %s, 'pending', NOW())
    """
    cursor.execute(sql, (user_id, f"申请-{pkg_data['name']}", json.dumps(params)))
    conn.commit()
    cursor.close()
    conn.close()

def stop_instance(db_config, node_id):
    """
    停止实例
    注意：在真实场景中，这里应该调用释放资源的存储过程。
    当前仅更新状态演示 UI 变化。
    """
    conn = get_connection(db_config)
    cursor = conn.cursor()
    # 对应 init.sql: virtualcomputers 表
    cursor.execute("UPDATE virtualcomputers SET status='stopped' WHERE node_id=%s", (node_id,))
    conn.commit()
    cursor.close()
    conn.close()

def render_user_dashboard(db_config, user, vm_packages):
    """
    渲染用户端主界面
    """
    st.markdown(f"### 欢迎, {user['user_name']}")
    
    # 获取最新余额
    conn = get_connection(db_config)
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT balance, status FROM users WHERE user_id=%s", (user['user_id'],))
    user_info = cursor.fetchone()
    
    # 状态指标
    c1, c2, c3 = st.columns(3)
    c1.metric("账户余额", f"¥ {user_info['balance']:.2f}")
    c2.metric("账户状态", "正常" if user_info['status'] == 'active' else "受限")
    c3.metric("当前时间", datetime.now().strftime("%H:%M"))

    st.markdown("---")

    tab_apply, tab_manage, tab_bill = st.tabs(["资源申请", "实例管理", "费用账单"])

    # --- Tab 1: 资源申请 ---
    with tab_apply:
        st.caption("作业提交系统 (Slurm Queue Mode)")
        
        type_gpu, type_cpu = st.tabs(["GPU 加速计算", "CPU 高性能计算"])
        
        # 渲染 GPU 列表
        with type_gpu:
            cols = st.columns(2)
            for idx, (key, pkg) in enumerate(vm_packages['gpu'].items()):
                with cols[idx % 2]:
                    with st.container(border=True):
                        st.markdown(f"#### {pkg['name']}")
                        st.caption(f"队列: `{pkg['queue']}`")
                        st.text(pkg['desc'])
                        
                        s_c1, s_c2 = st.columns(2)
                        with s_c1:
                            st.markdown(f"**显卡**: {pkg['specs']['显卡']}")
                            st.markdown(f"**内存**: {pkg['specs']['内存']}")
                        with s_c2:
                            st.markdown(f"**CPU**: {pkg['specs']['CPU']}")
                            st.markdown(f"**磁盘**: {pkg['specs']['磁盘']}")
                        
                        st.markdown("---")
                        b1, b2 = st.columns([1, 1])
                        with b1:
                            st.markdown(f"### ¥{pkg['price']} <span style='color:grey;font-size:0.8em'>/时</span>", unsafe_allow_html=True)
                        with b2:
                            if st.button("提交作业", key=f"btn_gpu_{key}", use_container_width=True):
                                submit_resource_request(db_config, user['user_id'], key, pkg, 'gpu')
                                st.success("作业已提交到调度队列，等待分配")

        # 渲染 CPU 列表
        with type_cpu:
            cols = st.columns(2)
            for idx, (key, pkg) in enumerate(vm_packages['cpu'].items()):
                with cols[idx % 2]:
                    with st.container(border=True):
                        st.markdown(f"#### {pkg['name']}")
                        st.caption(f"队列: `{pkg['queue']}`")
                        st.markdown(f"""
                        - **CPU**: {pkg['specs']['CPU']}
                        - **内存**: {pkg['specs']['内存']}
                        - **磁盘**: {pkg['specs']['磁盘']}
                        """)
                        st.markdown("---")
                        b1, b2 = st.columns([1, 1])
                        with b1:
                            st.markdown(f"### ¥{pkg['price']} <span style='color:grey;font-size:0.8em'>/时</span>", unsafe_allow_html=True)
                        with b2:
                            if st.button("提交作业", key=f"btn_cpu_{key}", use_container_width=True):
                                submit_resource_request(db_config, user['user_id'], key, pkg, 'cpu')
                                st.success("作业已提交")

    # --- Tab 2: 实例管理 ---
    with tab_manage:
        # 关联查询：通过 requests 表找到归属于该用户的 virtualcomputers
        sql_instances = """
        SELECT vc.*, r.request_type 
        FROM virtualcomputers vc
        JOIN requests r ON vc.request_id = r.request_id
        WHERE r.user_id = %s AND vc.status = 'running'
        """
        cursor.execute(sql_instances, (user['user_id'],))
        instances = pd.DataFrame(cursor.fetchall())

        if instances.empty:
            st.info("当前无运行中的计算节点")
        else:
            for _, row in instances.iterrows():
                with st.container(border=True):
                    c1, c2, c3, c4 = st.columns([3, 2, 2, 1])
                    with c1:
                        st.markdown(f"**Node: {row['node_name']}**")
                        st.caption(f"Queue: {row['queue_name']}")
                    with c2:
                        st.text(f"启动: {row['created_at']}")
                    with c3:
                        st.markdown(f"费率: **¥{row['hourly_price']}/h**")
                    with c4:
                        if st.button("停止", key=f"stop_{row['node_id']}", type="primary"):
                            stop_instance(db_config, row['node_id'])
                            st.rerun()

    # --- Tab 3: 账单 ---
    with tab_bill:
        sql_bills = "SELECT * FROM bills WHERE user_id=%s ORDER BY created_at DESC"
        cursor.execute(sql_bills, (user['user_id'],))
        bills = pd.DataFrame(cursor.fetchall())
        
        if bills.empty:
            st.text("暂无账单记录")
        else:
            st.dataframe(bills, use_container_width=True, hide_index=True)
            
    cursor.close()
    conn.close()