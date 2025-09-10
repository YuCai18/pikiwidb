#!/bin/bash
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 60 -d 60 -n 500000 -checkMode 1 -log-file SET-12345-check.log SET __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 59 -d 59 -n 500000 -checkMode 1 -log-file HSET-12345-check.log HSET __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 58 -d 58 -n 500000 -checkMode 1 -log-file LPUSH-12345-check.log LPUSH __key__ __key__ __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 57 -d 57 -n 500000 -checkMode 1 -log-file SADD-12345-check.log SADD __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 56 -d 56 -n 500000 -checkMode 1 -log-file ZADD-12345-check.log ZADD __key__ 10 __key__ 9 __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 55 -d 55 -n 500000 -checkMode 1 -log-file XADD-12345-check.log XADD __key__ 1 __key__ __data__ 


./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 60 -d 60 -n 500000 -random-seed 54321 -checkMode 1 -log-file SET-54321-check.log SET __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 59 -d 59 -n 500000 -random-seed 54321 -checkMode 1 -log-file HSET-54321-check.log HSET __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 58 -d 58 -n 500000 -random-seed 54321 -checkMode 1 -log-file LPUSH-54321-check.log LPUSH __key__ __key__ __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 57 -d 57 -n 500000 -random-seed 54321 -checkMode 1 -log-file SADD-54321-check.log SADD __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 56 -d 56 -n 500000 -random-seed 54321 -checkMode 1 -log-file ZADD-54321-check.log ZADD __key__ 10 __key__ 9 __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6379 -su root -spw ****** -r 55 -d 55 -n 500000 -random-seed 54321 -checkMode 1 -log-file XADD-54321-check.log XADD __key__ 1 __key__ __data__ 

echo "等待所有检查任务完成..."
wait

echo "=== 分析检查结果 ==="

# 分析检查结果
total_checks=0
passed_checks=0
failed_checks=0

for log_file in *-check.log; do
    if [ -f "$log_file" ]; then
        total_checks=$((total_checks + 1))
        echo "分析 $log_file:"
        
        # 检查日志中的错误信息（这里需要根据实际日志格式调整）
        if grep -q "Total Errors.*0 \[0.00%\]" "$log_file" 2>/dev/null; then
            echo "  ✓ PASSED - 数据一致性检查通过"
            passed_checks=$((passed_checks + 1))
        elif grep -q -i "error\|fail\|inconsistent" "$log_file" 2>/dev/null; then
            echo "  ✗ FAILED - 发现数据不一致"
            failed_checks=$((failed_checks + 1))
            echo "  错误详情:"
            grep -i "error\|fail\|inconsistent" "$log_file" | head -5
        else
            echo "  ? UNKNOWN - 无法确定检查结果"
            failed_checks=$((failed_checks + 1))
        fi
    fi
done

echo ""
echo "=== 检查总结 ==="
echo "总检查项目: $total_checks"
echo "通过: $passed_checks"
echo "失败: $failed_checks"

if [ $failed_checks -eq 0 ] && [ $total_checks -gt 0 ]; then
    echo "✓ 数据迁移一致性检查 - 全部通过！"
    exit_code=0
else
    echo "✗ 数据迁移一致性检查 - 存在问题！"
    exit_code=1
fi

echo "关闭PikaDB实例..."
redis-cli -p 9251 -c SHUTDOWN 2>/dev/null || echo "端口9251关闭失败"
redis-cli -p 9221 -c SHUTDOWN 2>/dev/null || echo "端口9221关闭失败"  
redis-cli -p 9231 -c SHUTDOWN 2>/dev/null || echo "端口9231关闭失败"

echo "检查完成时间: $(date)"
exit $exit_code
