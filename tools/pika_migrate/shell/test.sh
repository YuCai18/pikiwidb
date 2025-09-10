#!/bin/bash

sudo pkill -f "pika"
sudo pkill redis-server
redis-server --daemonize yes
rm *.log
rm -r ./db
rm -r ./log
rm -r ./dbtest

mkdir ./dbtest
rm -rf ./dbtest/*
mkdir ./dbtest/sourceDB
mkdir ./dbtest/migrateDB

PROJECT_ROOT="/data1/caiyu/pikiwidb"

cp $PROJECT_ROOT/output/pika ./dbtest/sourceDB/
cp $PROJECT_ROOT/output/pika ./dbtest/migrateDB/

cp $PROJECT_ROOT/conf/pika.conf ./dbtest/sourceDB/
cp $PROJECT_ROOT/tools/pika_migrate/conf/pika.conf ./dbtest/migrateDB/

sed -i.bak  \
    -e 's|thread-num : 1|thread-num : 8|'    \
    -e 's|thread-pool-size : 12|thread-pool-size : 64|'    \
    -e 's|write-buffer-size : 268435456|write-buffer-size : 256M|'    \
    -e 's|#daemonize : yes|daemonize: yes|'    \
    -e 's|#rate-limiter-bandwidth : 1099511627776|rate-limiter-bandwidth : 1099511627776|'    \
    -e 's|max-background-jobs : 3|max-background-jobs : 12|'    \
    -e 's|log-path : ./log/|log-path : ./dbtest/sourceDB/log/|'    \
    -e 's|db-path : ./db/|db-path : ./dbtest/sourceDB/db/|'    \
    -e 's|db-sync-path : ./dbsync/|db-sync-path : ./dbtest/sourceDB/dbsync/|'    \
    -e 's|dump-path : ./dump/|dump-path : ./dbtest/sourceDB/dump/|'    \
    -e 's|pidfile : ./pika.pid|pidfile : ./dbtest/sourceDB/pika.pid|'    \
    ./dbtest/sourceDB/pika.conf

sed -i.bak  \
    -e 's|thread-num : 1|thread-num : 8|'    \
    -e 's|thread-pool-size : 12|thread-pool-size : 64|'    \
    -e 's|write-buffer-size : 268435456|write-buffer-size : 256M|'    \
    -e 's|port : 9222|port : 9251|'    \
    -e 's|#daemonize : yes|daemonize: yes|'    \
    -e 's|#rate-limiter-bandwidth : 1099511627776|rate-limiter-bandwidth : 1099511627776|'    \
    -e 's|max-background-jobs : 3|max-background-jobs : 12|'    \
    -e 's|log-path : ./log/|log-path : ./dbtest/migrateDB/log/|'    \
    -e 's|db-path : ./db/|db-path : ./dbtest/migrateDB/db/|'    \
    -e 's|db-sync-path : ./dbsync/|db-sync-path : ./dbtest/migrateDB/dbsync/|'    \
    -e 's|pidfile : ./pika.pid|pidfile : ./dbtest/migrateDB/pika.pid|'    \
    -e 's|dump-path : ./dump/|dump-path : ./dbtest/migrateDB/dump/|'    \
    -e 's|redis-sender-num  : 10|redis-sender-num  : 100|'  \
    ./dbtest/migrateDB/pika.conf

echo "启动源数据库..."
# start pika
./dbtest/sourceDB/pika -c ./dbtest/sourceDB/pika.conf &

sleep 20

echo "=== 开始数据迁移测试 ==="
echo "测试数据规模: 600万条记录 (初始300万 + 迁移期间300万)"

# 记录测试开始时间
test_start_time=$(date +%s)
echo "测试开始时间: $(date)"

echo "第一阶段: 写入初始测试数据 (300万条)..."
data_write_start_time=$(date +%s)

./consistency_benchmark -mp 9221 -d 60 -r 60 -n 500000 -log-file SET-12345.log SET __key__ __data__ &
set1_pid=$!
./consistency_benchmark -mp 9221 -d 59 -r 59 -n 500000 -log-file HSET-12345.log HSET __key__ __key__ __data__ & 
hset1_pid=$!
./consistency_benchmark -mp 9221 -d 58 -r 58 -n 500000 -log-file LPUSH-12345.log LPUSH __key__ __key__ __key__ &
lpush1_pid=$!
./consistency_benchmark -mp 9221 -d 57 -r 57 -n 500000 -log-file SADD-12345.log SADD __key__ __key__ __data__ &
sadd1_pid=$!
./consistency_benchmark -mp 9221 -d 56 -r 56 -n 500000 -log-file ZADD-12345.log ZADD __key__ 10 __key__ 9 __key__ &
zadd1_pid=$!
./consistency_benchmark -mp 9221 -d 55 -r 55 -n 500000 -log-file XADD-12345.log XADD __key__ 1 __key__ __data__ &
xadd1_pid=$!

echo "等待第一轮写入完成..."
wait $set1_pid $hset1_pid $lpush1_pid $sadd1_pid $zadd1_pid $xadd1_pid

data_write_end_time=$(date +%s)
data_write_duration=$((data_write_end_time - data_write_start_time))
echo "✓ 第一轮写入完成，耗时: ${data_write_duration}秒"

# 统计初始数据的磁盘占用
initial_data_size=$(du -sh ./dbtest/sourceDB/db/ 2>/dev/null | cut -f1 || echo "0")
initial_data_bytes=$(du -sb ./dbtest/sourceDB/db/ 2>/dev/null | cut -f1 || echo "0")
echo "初始数据磁盘占用: ${initial_data_size}"

echo "启动迁移工具..."
# start migrateDB
./dbtest/migrateDB/pika -c ./dbtest/migrateDB/pika.conf &
sleep 20

# 检查迁移工具是否正常启动（通过端口检查）
echo "检查迁移工具启动状态..."
migrate_check_count=0
max_migrate_checks=30

while [ $migrate_check_count -lt $max_migrate_checks ]; do
    if redis-cli -p 9251 ping >/dev/null 2>&1; then
        echo "✓ 迁移工具启动成功"
        break
    fi
    
    migrate_check_count=$((migrate_check_count + 1))
    echo "  等待迁移工具启动... ($migrate_check_count/$max_migrate_checks)"
    sleep 2
done

if [ $migrate_check_count -ge $max_migrate_checks ]; then
    echo "❌ 迁移工具启动失败或超时"
    echo "检查日志文件："
    tail -20 ./dbtest/migrateDB/log/pika.ERROR 2>/dev/null || echo "无错误日志"
    exit 1
fi

echo "设置binlog保留数量..."
redis-cli -p 9221 -c config set expire-logs-nums 10000
redis-cli -p 9251 -c config set expire-logs-nums 10000

echo "第二阶段: 建立主从关系并开始数据迁移..."
migration_start_time=$(date +%s)
echo "数据迁移开始时间: $(date)"

echo "建立主从关系..."
redis-cli -p 9251 -c slaveof 127.0.0.1 9221

echo "等待主从关系建立..."
sleep 10

echo "第三阶段: 迁移期间写入测试数据 (300万条)..."
migrate_write_start_time=$(date +%s)

# 迁移期间的增量写入操作（不包括DEL操作）
./consistency_benchmark -mp 9221 -d 60 -r 60 -n 500000 -random-seed 54321 -log-file SET-54321.log SET __key__ __data__ & 
set2_pid=$!
./consistency_benchmark -mp 9221 -d 59 -r 59 -n 500000 -random-seed 54321 -log-file HSET-54321.log HSET __key__ __key__ __data__ & 
hset2_pid=$!
./consistency_benchmark -mp 9221 -d 58 -r 58 -n 500000 -random-seed 54321 -log-file LPUSH-54321.log LPUSH __key__ __key__ __key__ &
lpush2_pid=$!
./consistency_benchmark -mp 9221 -d 57 -r 57 -n 500000 -random-seed 54321 -log-file SADD-54321.log SADD __key__ __key__ __data__ &
sadd2_pid=$!
./consistency_benchmark -mp 9221 -d 56 -r 56 -n 500000 -random-seed 54321 -log-file ZADD-54321.log ZADD __key__ 10 __key__ 9 __key__ &
zadd2_pid=$!
./consistency_benchmark -mp 9221 -d 55 -r 55 -n 500000 -random-seed 54321 -log-file XADD-54321.log XADD __key__ 1 __key__ __data__ __key__ __data__ &
xadd2_pid=$!

echo "等待迁移期间的写操作完成..."

# 等待增量写入操作完成
wait $set2_pid $hset2_pid $lpush2_pid $sadd2_pid $zadd2_pid $xadd2_pid

migrate_write_end_time=$(date +%s)
migrate_write_duration=$((migrate_write_end_time - migrate_write_start_time))
echo "✓ 迁移期间写入完成，耗时: ${migrate_write_duration}秒"

# 统计600万数据的总磁盘占用
total_source_data_size=$(du -sh ./dbtest/sourceDB/db/ 2>/dev/null | cut -f1 || echo "0")
total_source_data_bytes=$(du -sb ./dbtest/sourceDB/db/ 2>/dev/null | cut -f1 || echo "0")
echo "源数据库总数据量(600万条): ${total_source_data_size}"

echo "=== 写入测试完成 ==="
echo "等待数据同步完成..."

# 智能等待数据迁移完成
echo "监控数据迁移进度..."
migration_timeout=300  # 5分钟超时
start_time=$(date +%s)
last_check_time=0

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    # 检查超时
    if [ $elapsed -gt $migration_timeout ]; then
        echo "⚠ 数据迁移等待超时 (${migration_timeout}秒)"
        break
    fi
    
    # 每10秒检查一次日志
    if [ $((current_time - last_check_time)) -ge 10 ]; then
        # 检查日志中是否有完成标志
        if grep -q "Retransmit Finish" ./dbtest/migrateDB/log/pika.INFO 2>/dev/null; then
            migration_end_time=$(date +%s)
            migration_duration=$((migration_end_time - migration_start_time))
            echo "✓ 检测到数据迁移完成标志"
            echo "数据迁移完成时间: $(date)"
            echo "数据迁移总耗时: ${migration_duration}秒"
            
            # 统计迁移后的磁盘占用
            migrated_data_size=$(du -sh ./dbtest/migrateDB/db/ 2>/dev/null | cut -f1 || echo "0")
            migrated_data_bytes=$(du -sb ./dbtest/migrateDB/db/ 2>/dev/null | cut -f1 || echo "0")
            echo "迁移后数据量: ${migrated_data_size}"
            
            sleep 5  # 额外等待5秒确保完全完成
            break
        fi
        
        # 检查是否有错误
        if [ -f "./dbtest/migrateDB/log/pika.ERROR" ] && [ -s "./dbtest/migrateDB/log/pika.ERROR" ]; then
            echo "⚠ 检测到错误日志，请检查:"
            tail -5 ./dbtest/migrateDB/log/pika.ERROR
        fi
        
        echo "  数据迁移进行中... (已等待 ${elapsed}秒)"
        last_check_time=$current_time
    fi
    
    sleep 5
done

# 如果超时退出，也记录时间和磁盘占用
if [ -z "$migration_end_time" ]; then
    migration_end_time=$(date +%s)
    migration_duration=$((migration_end_time - migration_start_time))
    echo "数据迁移阶段结束时间: $(date)"
    echo "数据迁移耗时: ${migration_duration}秒 (可能未完全完成)"
    
    # 即使超时也统计目标数据库的磁盘占用
    migrated_data_size=$(du -sh ./dbtest/migrateDB/db/ 2>/dev/null | cut -f1 || echo "0")
    migrated_data_bytes=$(du -sb ./dbtest/migrateDB/db/ 2>/dev/null | cut -f1 || echo "0")
    echo "当前迁移数据量: ${migrated_data_size}"
fi

echo "数据迁移阶段完成，开始一致性检查..."

echo "开始数据一致性检查..."

# 数据一致性检查函数
check_data_consistency() {
    echo "=== 数据一致性检查开始 ==="
    
    # 检查数据库连接
    echo "检查数据库连接状态..."
    if ! redis-cli -p 9221 ping >/dev/null 2>&1; then
        echo "✗ 源数据库连接失败 (端口 9221)"
        return 1
    fi
    
    if ! redis-cli -p 9251 ping >/dev/null 2>&1; then
        echo "✗ 目标数据库连接失败 (端口 9251)"
        return 1
    fi
    
    echo "✓ 数据库连接正常"
    
    # 获取基本统计信息
    echo "获取数据库统计信息..."
    source_dbsize=$(redis-cli -p 9221 dbsize 2>/dev/null || echo "0")
    target_dbsize=$(redis-cli -p 9251 dbsize 2>/dev/null || echo "0")
    
    echo "源数据库键数量: $source_dbsize"
    echo "目标数据库键数量: $target_dbsize"
    
    # 检查键数量是否一致
    if [ "$source_dbsize" != "$target_dbsize" ]; then
        echo "✗ 键数量不一致！源库: $source_dbsize, 目标库: $target_dbsize"
        return 1
    fi
    
    echo "✓ 键数量一致"
    
    # 检查主从同步状态
    echo "检查主从同步状态..."
    slave_info=$(redis-cli -p 9251 info replication 2>/dev/null | grep "master_link_status:up" || echo "")
    if [ -z "$slave_info" ]; then
        echo "⚠ 主从连接可能存在问题"
    else
        echo "✓ 主从连接正常"
    fi
    
    # 随机抽样检查数据一致性
    echo "开始随机抽样数据一致性检查..."
    
    # 获取所有键
    redis-cli -p 9221 --scan > /tmp/source_keys.txt 2>/dev/null
    total_keys=$(wc -l < /tmp/source_keys.txt)
    
    if [ "$total_keys" -eq 0 ]; then
        echo "✗ 未找到任何数据键"
        return 1
    fi
    
    # 随机选择100个键进行检查（或全部键如果少于100个）
    sample_size=100
    if [ "$total_keys" -lt "$sample_size" ]; then
        sample_size=$total_keys
    fi
    
    echo "从 $total_keys 个键中随机抽样 $sample_size 个进行检查..."
    
    # 随机抽样
    shuf /tmp/source_keys.txt | head -n $sample_size > /tmp/sample_keys.txt
    
    inconsistent_count=0
    checked_count=0
    
    while read -r key; do
        if [ -z "$key" ]; then
            continue
        fi
        
        checked_count=$((checked_count + 1))
        
        # 获取键的类型
        key_type=$(redis-cli -p 9221 type "$key" 2>/dev/null)
        
        case "$key_type" in
            "string")
                source_value=$(redis-cli -p 9221 get "$key" 2>/dev/null)
                target_value=$(redis-cli -p 9251 get "$key" 2>/dev/null)
                ;;
            "hash")
                source_value=$(redis-cli -p 9221 hgetall "$key" 2>/dev/null | sort)
                target_value=$(redis-cli -p 9251 hgetall "$key" 2>/dev/null | sort)
                ;;
            "list")
                source_value=$(redis-cli -p 9221 lrange "$key" 0 -1 2>/dev/null)
                target_value=$(redis-cli -p 9251 lrange "$key" 0 -1 2>/dev/null)
                ;;
            "set")
                source_value=$(redis-cli -p 9221 smembers "$key" 2>/dev/null | sort)
                target_value=$(redis-cli -p 9251 smembers "$key" 2>/dev/null | sort)
                ;;
            "zset")
                source_value=$(redis-cli -p 9221 zrange "$key" 0 -1 withscores 2>/dev/null)
                target_value=$(redis-cli -p 9251 zrange "$key" 0 -1 withscores 2>/dev/null)
                ;;
            "stream")
                source_value=$(redis-cli -p 9221 xrange "$key" - + 2>/dev/null)
                target_value=$(redis-cli -p 9251 xrange "$key" - + 2>/dev/null)
                ;;
            *)
                echo "跳过未知类型键: $key (类型: $key_type)"
                continue
                ;;
        esac
        
        if [ "$source_value" != "$target_value" ]; then
            echo "✗ 数据不一致: $key (类型: $key_type)"
            inconsistent_count=$((inconsistent_count + 1))
            
            # 记录不一致的详情（仅前50个字符）
            echo "  源库值: $(echo "$source_value" | cut -c1-50)..."
            echo "  目标库值: $(echo "$target_value" | cut -c1-50)..."
        fi
        
        # 显示进度
        if [ $((checked_count % 10)) -eq 0 ]; then
            echo "已检查 $checked_count/$sample_size 个键..."
        fi
        
    done < /tmp/sample_keys.txt
    
    # 清理临时文件
    rm -f /tmp/source_keys.txt /tmp/sample_keys.txt
    
    # 输出检查结果
    echo ""
    echo "=== 数据一致性检查结果 ==="
    echo "检查键数量: $checked_count"
    echo "不一致键数量: $inconsistent_count"
    echo "一致性比例: $(( (checked_count - inconsistent_count) * 100 / checked_count ))%"
    
    if [ "$inconsistent_count" -eq 0 ]; then
        echo "✓ 数据一致性检查通过！"
        return 0
    else
        echo "✗ 发现数据不一致！"
        return 1
    fi
}

# 执行数据一致性检查
echo "第四阶段: 数据一致性检查..."
consistency_start_time=$(date +%s)

if check_data_consistency; then
    consistency_end_time=$(date +%s)
    consistency_duration=$((consistency_end_time - consistency_start_time))
    echo "✓ 数据一致性检查通过，耗时: ${consistency_duration}秒"
    
    echo "第五阶段: 执行删除操作测试..."
    del_start_time=$(date +%s)
    
    # 现在执行删除操作，测试删除同步
    ./consistency_benchmark -mp 9221 -d 60 -r 60 -n 100000 -random-seed 54321 -log-file DEL-54321.log DEL __key__ __data__ &
    del_pid=$!
    ./consistency_benchmark -mp 9221 -d 59 -r 59 -n 100000 -random-seed 54321 -log-file HDEL-54321.log HDEL __key__ __key__ __data__ &  
    hdel_pid=$!
    ./consistency_benchmark -mp 9221 -d 58 -r 58 -n 100000 -random-seed 54321 -log-file LPOP-54321.log LPOP __key__ __key__ __key__ &
    lpop_pid=$!
    ./consistency_benchmark -mp 9221 -d 57 -r 57 -n 100000 -random-seed 54321 -log-file SREM-54321.log SREM __key__ __key__ __data__ &
    srem_pid=$!
    ./consistency_benchmark -mp 9221 -d 56 -r 56 -n 100000 -random-seed 54321 -log-file ZREM-54321.log ZREM __key__ __key__ __key__ &
    zrem_pid=$!
    ./consistency_benchmark -mp 9221 -d 55 -r 55 -n 100000 -random-seed 54321 -log-file XDEL-54321.log XDEL __key__ 1 __key__ __data__ __key__ __data__ &
    xdel_pid=$!
    
    echo "等待删除操作完成..."
    wait $del_pid $hdel_pid $lpop_pid $srem_pid $zrem_pid $xdel_pid
    
    del_end_time=$(date +%s)
    del_duration=$((del_end_time - del_start_time))
    echo "✓ 删除操作完成，耗时: ${del_duration}秒"
    
    # 等待删除操作同步
    echo "等待删除操作同步..."
    sleep 30
    
    # 统计删除操作后的磁盘占用变化
    after_del_source_size=$(du -sh ./dbtest/sourceDB/db/ 2>/dev/null | cut -f1 || echo "0")
    after_del_migrate_size=$(du -sh ./dbtest/migrateDB/db/ 2>/dev/null | cut -f1 || echo "0")
    echo "删除操作后源数据库: ${after_del_source_size}"
    echo "删除操作后迁移数据库: ${after_del_migrate_size}"
    
    echo "第六阶段: 最终数据一致性验证..."
    final_check_start_time=$(date +%s)
    
    if check_data_consistency; then
        final_check_end_time=$(date +%s)
        final_check_duration=$((final_check_end_time - final_check_start_time))
        echo "✓ 最终数据一致性检查通过，耗时: ${final_check_duration}秒"
        test_result=0
    else
        final_check_end_time=$(date +%s)
        final_check_duration=$((final_check_end_time - final_check_start_time))
        echo "❌ 最终数据一致性检查失败，耗时: ${final_check_duration}秒"
        test_result=1
    fi
else
    consistency_end_time=$(date +%s)
    consistency_duration=$((consistency_end_time - consistency_start_time))
    echo "❌ 数据一致性检查失败，耗时: ${consistency_duration}秒"
    test_result=1
fi

echo "按任意键关闭所有服务..."
read -n 1

echo "关闭服务..."

# 清理可能遗留的后台进程
cleanup_background_processes() {
    echo "清理后台进程..."
    
    # 查找并终止所有 consistency_benchmark 进程
    local pids=$(pgrep -f "consistency_benchmark" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "发现遗留的 consistency_benchmark 进程: $pids"
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "终止进程 $pid..."
                kill -TERM "$pid" 2>/dev/null
                sleep 2
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null
                fi
            fi
        done
        echo "✓ 后台进程清理完成"
    else
        echo "✓ 没有发现遗留的后台进程"
    fi
}

shutdown_pika_service() {
    local port=$1
    local service_name=$2
    local max_wait=30
    local wait_count=0
    
    echo "正在关闭 $service_name (端口 $port)..."
    
    # 首先尝试通过redis-cli SHUTDOWN命令优雅关闭
    if redis-cli -p $port -c SHUTDOWN 2>/dev/null; then
        echo "  已发送SHUTDOWN命令到端口 $port"
    else
        echo "  无法通过redis-cli关闭端口 $port"
    fi
    
    # 等待服务自然关闭
    while [ $wait_count -lt $max_wait ]; do
        if ! redis-cli -p $port ping >/dev/null 2>&1; then
            echo "  ✓ $service_name 已正常关闭"
            return 0
        fi
        sleep 1
        wait_count=$((wait_count + 1))
        if [ $((wait_count % 5)) -eq 0 ]; then
            echo "  等待 $service_name 关闭... ($wait_count/${max_wait}s)"
        fi
    done
    
    # 如果服务还没关闭，尝试通过PID文件强制关闭
    local pid_file=""
    if [ $port -eq 9221 ]; then
        pid_file="./dbtest/sourceDB/pika.pid"
    elif [ $port -eq 9251 ]; then
        pid_file="./dbtest/migrateDB/pika.pid"
    fi
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "  通过PID文件关闭 $service_name (PID: $pid)..."
            kill -TERM "$pid" 2>/dev/null
            sleep 5
            
            # 检查进程是否已关闭
            if kill -0 "$pid" 2>/dev/null; then
                echo "  强制关闭 $service_name (PID: $pid)..."
                kill -KILL "$pid" 2>/dev/null
                sleep 2
            fi
            
            if ! kill -0 "$pid" 2>/dev/null; then
                echo "  ✓ $service_name 已通过信号关闭"
                rm -f "$pid_file"
                return 0
            fi
        fi
    fi
    
    # 最后尝试通过进程名查找并关闭
    echo "  尝试通过进程名查找并关闭 $service_name..."
    local pids=$(pgrep -f "pika.*$port" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "  找到相关进程: $pids"
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "  关闭进程 $pid..."
                kill -TERM "$pid" 2>/dev/null
                sleep 3
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null
                fi
            fi
        done
        echo "  ✓ $service_name 相关进程已关闭"
        return 0
    fi
    
    echo "  ⚠ 无法确认 $service_name 是否完全关闭"
    return 1
}

# 首先清理后台进程
cleanup_background_processes

# 关闭迁移工具 (端口 9251)
shutdown_pika_service 9251 "迁移工具"

# 关闭源数据库 (端口 9221)  
shutdown_pika_service 9221 "源数据库"

# 清理可能遗留的PID文件
rm -f ./dbtest/sourceDB/pika.pid ./dbtest/migrateDB/pika.pid 2>/dev/null

echo "所有服务已关闭"

# 计算总测试时间
test_end_time=$(date +%s)
total_test_duration=$((test_end_time - test_start_time))

echo ""
echo "========================================"
echo "           数据迁移测试总结"
echo "========================================"
echo "测试开始时间: $(date -d "@$test_start_time")"
echo "测试结束时间: $(date -d "@$test_end_time")"
echo "总测试耗时: ${total_test_duration}秒"
echo ""
echo "各阶段耗时统计:"
echo "  初始数据写入 (300万条): ${data_write_duration}秒"
echo "  迁移期间写入 (300万条): ${migrate_write_duration}秒"
if [ -n "$migration_duration" ]; then
    echo "  数据迁移总耗时: ${migration_duration}秒"
fi
if [ -n "$consistency_duration" ]; then
    echo "  数据一致性检查: ${consistency_duration}秒"
fi
if [ -n "$del_duration" ]; then
    echo "  删除操作测试: ${del_duration}秒"
fi
if [ -n "$final_check_duration" ]; then
    echo "  最终一致性验证: ${final_check_duration}秒"
fi
echo ""
echo "数据统计:"
echo "  总测试数据量: 600万条记录"
echo "  数据类型: SET, HSET, LPUSH, SADD, ZADD, XADD"
if [ -n "$migration_duration" ] && [ $migration_duration -gt 0 ]; then
    migration_rate=$((6000000 / migration_duration))
    echo "  迁移速度: 约 ${migration_rate} 条/秒"
fi
echo ""
echo "磁盘占用统计:"
if [ -n "$initial_data_size" ]; then
    echo "  初始数据(300万条): ${initial_data_size}"
fi
if [ -n "$total_source_data_size" ]; then
    echo "  源数据库(600万条): ${total_source_data_size}"
fi
if [ -n "$migrated_data_size" ]; then
    echo "  迁移后数据库: ${migrated_data_size}"
fi

# 计算数据压缩比和单条记录平均大小
if [ -n "$total_source_data_bytes" ] && [ "$total_source_data_bytes" -gt 0 ]; then
    avg_record_size=$((total_source_data_bytes / 6000000))
    echo "  平均每条记录: ${avg_record_size} 字节"
fi

if [ -n "$total_source_data_bytes" ] && [ -n "$migrated_data_bytes" ] && [ "$migrated_data_bytes" -gt 0 ]; then
    if [ "$total_source_data_bytes" -gt "$migrated_data_bytes" ]; then
        compression_ratio=$(echo "scale=2; $total_source_data_bytes / $migrated_data_bytes" | bc 2>/dev/null || echo "N/A")
        if [ "$compression_ratio" != "N/A" ]; then
            echo "  数据压缩比: ${compression_ratio}:1"
        fi
    elif [ "$migrated_data_bytes" -gt "$total_source_data_bytes" ]; then
        expansion_ratio=$(echo "scale=2; $migrated_data_bytes / $total_source_data_bytes" | bc 2>/dev/null || echo "N/A")
        if [ "$expansion_ratio" != "N/A" ]; then
            echo "  数据膨胀比: ${expansion_ratio}:1"
        fi
    else
        echo "  数据大小: 相同"
    fi
fi
echo ""

if [ $test_result -eq 0 ]; then
    echo "🎉 数据迁移测试完成 - 成功！"
    echo "✓ 所有数据已成功迁移并通过一致性验证"
else
    echo "❌ 数据迁移测试完成 - 失败！"
    echo "✗ 数据一致性验证未通过，请检查日志"
fi

exit $test_result