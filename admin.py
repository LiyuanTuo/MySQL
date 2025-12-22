import streamlit as st
import pandas as pd
import mysql.connector
import json
from datetime import datetime

def get_connection(db_config):
    return mysql.connector.connect(**db_config)

def approve_request(db_config, req_id, user_id, params):
    """
    调用 MySQL 存储过程 sp_create_instance 进行资源分配
    """
    conn = get_connection(db_config)
    cursor = conn.cursor()
    
    try:
        # 提取存储过程所需的参数
        db_p = params.get('db_params', {})
        p_queue = params.get('queue')
        
        # 准备输出参数 (node_id)
        # MySQL Connector 调用存储过程方式: callproc
        # 参数顺序: user_id, queue_name, cores, gpu_mem, ram, disk, OUT node_id
        args = [
            user_id, 
            p_queue, 
            db_p.get('req_cores', 1),
            db_p.get('req_gpu_mem', 0),
            db_p.get('req_ram', 1),
            db_p.get('req_disk', 10),
            0 # 占位符，用于接收 OUT 参数
        ]
        
        result_args = cursor.callproc('sp_create_instance', args)
        
        # 获取输出参数 node_id (在 result_args 的最后一个位置)
        new_node_id = result_args[-1]
        
        if new_node_id and new_node_id > 0:
            # 资源分配成功
            # 更新原始请求状态为 'approved' (注意：存储过程内部会创建一条新的 'create_vm' 类型的系统请求记录)
            cursor.execute("UPDATE requests SET status='approved' WHERE request_id=%s", (req_id,))
            conn.commit()
            st.success(f"资源分配成功！节点ID: {new_node_id}")
            return True
        else:
            # 资源不足或分配失败 (存储过程返回 -1)
            st.error("资源池资源不足 (CPU/GPU/内存)，分配失败。")
            return False
            
    except mysql.connector.Error as err:
        st.error(f"数据库错误: {err}")
        return False
    finally:
        cursor.close()
        conn.close()

def reject_request(db_config, req_id):
    conn = get_connection(db_config)
    cursor = conn.cursor()
    cursor.execute("UPDATE requests SET status='rejected' WHERE request_id=%s", (req_id,))
    conn.commit()
    cursor.close()
    conn.close()

def render_admin_dashboard(db_config):
    """
    渲染管理员控制台 (模拟调度器)
    """
    st.header("集群调度控制台 (Admin)")
    st.markdown("---")
    
    conn = get_connection(db_config)
    cursor = conn.cursor(dictionary=True)
    
    # 1. 资源池概览 (实时读取 npus 和 memory 表)
    st.subheader("物理资源池状态")
    c1, c2 = st.columns(2)
    with c1:
        st.markdown("**计算节点 (NPUs)**")
        cursor.execute("SELECT queue_type, COUNT(*) as total_nodes, SUM(available_cores) as free_cores, SUM(available_memory) as free_gpu_mem FROM npus GROUP BY queue_type")
        npu_stats = pd.DataFrame(cursor.fetchall())
        st.dataframe(npu_stats, use_container_width=True, hide_index=True)
        
    with c2:
        st.markdown("**内存池 (Memory)**")
        cursor.execute("SELECT queue_type, SUM(available_size) as free_ram_gb FROM memory GROUP BY queue_type")
        mem_stats = pd.DataFrame(cursor.fetchall())
        st.dataframe(mem_stats, use_container_width=True, hide_index=True)

    st.markdown("---")

    # 2. 待审批请求 (作业队列)
    st.subheader("作业等待队列")
    cursor.execute("SELECT * FROM requests WHERE status='pending' ORDER BY submit_time ASC")
    requests = pd.DataFrame(cursor.fetchall())
    
    if requests.empty:
        st.info("当前无等待作业")
    else:
        for _, req in requests.iterrows():
            with st.container(border=True):
                c1, c2, c3 = st.columns([4, 1, 1])
                try:
                    params = json.loads(req['parameters'])
                except:
                    params = {"queue": "unknown", "name": "Error"}

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