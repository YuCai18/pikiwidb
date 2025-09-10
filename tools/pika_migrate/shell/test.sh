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

echo "开始写入测试数据..."
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
echo "✓ 第一轮写入操作全部完成"

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

echo "建立主从关系..."
redis-cli -p 9251 -c slaveof 127.0.0.1 9221

echo "等待主从关系建立..."
sleep 10

echo "开始迁移期间的写操作..."
# continue write duration migrate
./consistency_benchmark -mp 9221 -d 60 -r 60 -n 500000 -random-seed 54321 -log-file DEL-54321.log DEL __key__ __data__ &
del_pid=$!
./consistency_benchmark -mp 9221 -d 59 -r 59 -n 500000 -random-seed 54321 -log-file HDEL-54321.log HDEL __key__ __key__ __data__ &  
hdel_pid=$!
./consistency_benchmark -mp 9221 -d 58 -r 58 -n 500000 -random-seed 54321 -log-file LPOP-54321.log LPOP __key__ __key__ __key__ &
lpop_pid=$!
./consistency_benchmark -mp 9221 -d 57 -r 57 -n 500000 -random-seed 54321 -log-file SREM-54321.log SREM __key__ __key__ __data__ &
srem_pid=$!
./consistency_benchmark -mp 9221 -d 56 -r 56 -n 500000 -random-seed 54321 -log-file ZREM-54321.log ZREM __key__ __key__ __key__ &
zrem_pid=$!
./consistency_benchmark -mp 9221 -d 55 -r 55 -n 500000 -random-seed 54321 -log-file XDEL-54321.log XDEL __key__ 1 __key__ __data__ __key__ __data__ &
xdel_pid=$!

echo "等待迁移期间的写操作完成..."

# 等待所有后台进程完成
echo "等待DEL操作完成..."
wait $del_pid 2>/dev/null && echo "✓ DEL操作完成" || echo "⚠ DEL操作异常结束"

echo "等待HDEL操作完成..."
wait $hdel_pid 2>/dev/null && echo "✓ HDEL操作完成" || echo "⚠ HDEL操作异常结束"

echo "等待LPOP操作完成..."
wait $lpop_pid 2>/dev/null && echo "✓ LPOP操作完成" || echo "⚠ LPOP操作异常结束"

echo "等待SREM操作完成..."
wait $srem_pid 2>/dev/null && echo "✓ SREM操作完成" || echo "⚠ SREM操作异常结束"

echo "等待ZREM操作完成..."
wait $zrem_pid 2>/dev/null && echo "✓ ZREM操作完成" || echo "⚠ ZREM操作异常结束"

echo "等待XDEL操作完成..."
wait $xdel_pid 2>/dev/null && echo "✓ XDEL操作完成" || echo "⚠ XDEL操作异常结束"

echo "所有迁移期间的写操作已完成"

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
            echo "✓ 检测到数据迁移完成标志"
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
if check_data_consistency; then
    echo "🎉 数据迁移测试成功！"
    test_result=0
else
    echo "❌ 数据迁移测试失败！"
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

if [ $test_result -eq 0 ]; then
    echo "✓ 数据迁移测试完成 - 成功！"
else
    echo "✗ 数据迁移测试完成 - 失败！"
fi

exit $test_result