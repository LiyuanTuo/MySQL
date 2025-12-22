import streamlit as st
import pandas as pd
import mysql.connector
import json
from datetime import datetime
from decimal import Decimal

def get_connection(db_config):
    return mysql.connector.connect(**db_config)

def submit_resource_request(db_config, user_id, pkg_key, pkg_data, category):
    conn = get_connection(db_config)
    cursor = conn.cursor()
    params = {
        "category": category,
        "package_key": pkg_key,
        "name": pkg_data['name'],
        "queue": pkg_data['queue'],
        "price": pkg_data['price'],
        "db_params": pkg_data['db_params'] 
    }
    sql = """
    INSERT INTO requests (user_id, request_type, parameters, status, submit_time) 
    VALUES (%s, %s, %s, 'pending', NOW())
    """
    cursor.execute(sql, (user_id, f"申请-{pkg_data['name']}", json.dumps(params)))
    conn.commit()
    cursor.close()
    conn.close()

def pay_bill(db_config, user_id, bill_id, amount):
    conn = get_connection(db_config)
    cursor = conn.cursor()
    try:
        amount_decimal = Decimal(str(amount))
        cursor.execute("SELECT balance FROM users WHERE user_id=%s FOR UPDATE", (user_id,))
        result = cursor.fetchone()
        if not result:
            st.error("用户不存在")
            return False
        current_balance = result[0]
        
        if current_balance < amount_decimal:
            st.error(f"余额不足！当前余额: ¥{current_balance}, 需要: ¥{amount_decimal}")
            return False
            
        new_balance = current_balance - amount_decimal
        cursor.execute("UPDATE users SET balance=%s WHERE user_id=%s", (new_balance, user_id))
        cursor.execute("UPDATE bills SET payment_status='paid' WHERE bill_id=%s", (bill_id,))
        conn.commit()
        st.success(f"支付成功！扣除 ¥{amount_decimal}，剩余余额 ¥{new_balance}")
        return True
    except mysql.connector.Error as err:
        conn.rollback()
        st.error(f"支付交易失败: {err}")
        return False
    finally:
        cursor.close()
        conn.close()

def render_user_dashboard(db_config, user, vm_packages):
    st.markdown(f"### 欢迎, {user['user_name']}")
    
    conn = get_connection(db_config)
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT balance, status FROM users WHERE user_id=%s", (user['user_id'],))
    user_info = cursor.fetchone()
    
    c1, c2, c3 = st.columns(3)
    c1.metric("账户余额", f"¥ {user_info['balance']:.2f}")
    c2.metric("账户状态", "正常" if user_info['status'] == 'active' else "受限")
    c3.metric("当前时间", datetime.now().strftime("%H:%M"))

    st.markdown("---")

    tab_apply, tab_jobs, tab_bills = st.tabs(["资源申请", "我的任务", "账单管理"])

    # ==========================================
    # Tab 1: 资源申请 
    # ==========================================
    with tab_apply:
        st.caption("作业提交系统 (Slurm Queue Mode)")
        type_gpu, type_cpu = st.tabs(["GPU 加速计算", "CPU 高性能计算"])
        
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
                                st.success("作业已提交到调度队列，等待审批")

        with type_cpu:
            cols = st.columns(2)
            for idx, (key, pkg) in enumerate(vm_packages['cpu'].items()):
                with cols[idx % 2]:
                    with st.container(border=True):
                        st.markdown(f"#### {pkg['name']}")
                        st.caption(f"队列: `{pkg['queue']}`")
                        st.markdown(f"- **CPU**: {pkg['specs']['CPU']}\n- **内存**: {pkg['specs']['内存']}\n- **磁盘**: {pkg['specs']['磁盘']}")
                        st.markdown("---")
                        b1, b2 = st.columns([1, 1])
                        with b1:
                            st.markdown(f"### ¥{pkg['price']} <span style='color:grey;font-size:0.8em'>/时</span>", unsafe_allow_html=True)
                        with b2:
                            if st.button("提交作业", key=f"btn_cpu_{key}", use_container_width=True):
                                submit_resource_request(db_config, user['user_id'], key, pkg, 'cpu')
                                st.success("作业已提交")

    # ==========================================
    # Tab 2: 我的任务 (修复：区分 completed 和 terminated)
    # ==========================================
    with tab_jobs:
        st.caption("查看任务的生命周期状态")
        
        sql_jobs = """
        SELECT 
            r.request_id, r.request_type, r.status as req_status, r.submit_time,
            vc.node_name, vc.queue_name, vc.status as vc_status
        FROM requests r
        LEFT JOIN virtualcomputers vc ON r.request_id = vc.request_id
        WHERE r.user_id = %s
        ORDER BY r.submit_time DESC
        """
        cursor.execute(sql_jobs, (user['user_id'],))
        jobs = pd.DataFrame(cursor.fetchall())

        if jobs.empty:
            st.info("暂无任务记录")
        else:
            h1, h2, h3, h4 = st.columns([1, 2, 2, 2])
            h1.markdown("**ID**")
            h2.markdown("**任务类型**")
            h3.markdown("**节点/队列**")
            h4.markdown("**当前状态**")
            
            for _, row in jobs.iterrows():
                with st.container(border=True):
                    c1, c2, c3, c4 = st.columns([1, 2, 2, 2])
                    c1.text(row['request_id'])
                    with c2:
                        st.text(row['request_type'])
                        st.caption(str(row['submit_time']).split('.')[0])
                    with c3:
                        if row['node_name']:
                            st.text(f"Node: {row['node_name']}")
                            st.caption(f"Queue: {row['queue_name']}")
                        else:
                            st.text("等待分配...")
                    
                    with c4:
                        status = row['req_status']
                        if status == 'pending':
                            st.warning("排队中")
                        elif status == 'approved':
                            st.success("运行中")
                            st.caption("如需停止请联系管理员")
                        elif status == 'rejected':
                            st.error("已拒绝")
                        # [修复] 将 completed 和 terminated 分开处理
                        elif status == 'completed':
                            st.info("🏁 已完成")
                            st.caption("请前往[账单管理]查看费用")
                        elif status == 'terminated':
                            st.error("异常终止")
                            st.caption("任务非正常结束")
                        else:
                            st.text(status)

    # ==========================================
    # Tab 3: 账单管理 (修复：显示任务原始状态，警示异常账单)
    # ==========================================
    with tab_bills:
        st.caption("查看已完成作业的账单并进行支付")
        
        # [修复] 增加查询 r.status as job_status
        sql_bills = """
        SELECT 
            b.bill_id, b.cost_amount, b.payment_status, b.usage_hours, b.end_time,
            r.request_type, r.request_id, r.status as job_status,
            vc.node_name
        FROM bills b
        JOIN requests r ON b.request_id = r.request_id
        LEFT JOIN virtualcomputers vc ON b.node_id = vc.node_id
        WHERE b.user_id = %s
        ORDER BY b.created_at DESC
        """
        cursor.execute(sql_bills, (user['user_id'],))
        bills_data = pd.DataFrame(cursor.fetchall())
        
        if bills_data.empty:
            st.info("暂无账单记录")
        else:
            unpaid_total = Decimal('0.00')
            for _, row in bills_data.iterrows():
                if row['payment_status'] == 'unpaid' and row['job_status'] != 'terminated':
                     # 仅统计非异常终止的金额，或者全部统计看业务需求
                     unpaid_total += row['cost_amount']
            
            if unpaid_total > 0:
                st.warning(f"当前待支付总额 (正常作业): ¥{unpaid_total:.2f}")
            else:
                st.success("所有正常账单已结清")
            
            st.markdown("---")

            h1, h2, h3, h4, h5 = st.columns([1, 2.5, 1.5, 1.5, 1.5])
            h1.markdown("**账单ID**")
            h2.markdown("**任务详情**")
            h3.markdown("**时长/结束时间**")
            h4.markdown("**金额**")
            h5.markdown("**操作**")

            for _, row in bills_data.iterrows():
                with st.container(border=True):
                    c1, c2, c3, c4, c5 = st.columns([1, 2.5, 1.5, 1.5, 1.5])
                    
                    c1.text(f"#{row['bill_id']}")
                    
                    with c2:
                        st.markdown(f"**{row['request_type']}**")
                        if row['job_status'] == 'terminated':
                            st.markdown(":red[**[异常终止]**]")
                        st.caption(f"Node: {row['node_name']} (ReqID: {row['request_id']})")
                    
                    with c3:
                        st.text(f"{row['usage_hours']:.2f} 小时")
                        st.caption(str(row['end_time']).split('.')[0])
                    
                    with c4:
                        st.markdown(f"**¥{row['cost_amount']:.2f}**")
                    
                    with c5:
                        if row['payment_status'] == 'unpaid':
                            
                            if row['job_status'] == 'terminated':
                                st.error("异常账单")
                                st.caption("请联系管理员核实")
                            else:
                                if st.button("立即支付", key=f"pay_bill_btn_{row['bill_id']}", type="primary", use_container_width=True):
                                    if pay_bill(db_config, user['user_id'], row['bill_id'], row['cost_amount']):
                                        st.rerun()
                        else:
                            st.success("已支付")

    cursor.close()
    conn.close()
