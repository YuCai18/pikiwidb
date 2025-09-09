#!/bin/bash

rm *.log
rm -r ./dbtest

mkdir ./dbtest
rm -rf ./dbtest/*
mkdir ./dbtest/sourceDB
mkdir ./dbtest/targetDB
mkdir ./dbtest/migrateDB

PROJECT_ROOT="/data1/caiyu/pikiwidb"

cp $PROJECT_ROOT/output/pika ./dbtest/sourceDB/
cp $PROJECT_ROOT/output/pika ./dbtest/targetDB/
cp $PROJECT_ROOT/output/pika ./dbtest/migrateDB/

cp $PROJECT_ROOT/conf/pika.conf ./dbtest/sourceDB/
cp $PROJECT_ROOT/conf/pika.conf ./dbtest/targetDB/
cp $PROJECT_ROOT/tools/pika_migrate/conf/pika.conf ./dbtest/migrateDB/

sed -i.bak  \
    -e 's|thread-num : 1|thread-num : 8|'    \
    -e 's|thread-pool-size : 12|thread-pool-size : 64|'    \
    -e 's|write-buffer-size : 268435456|write-buffer-size : 256M|'    \
    -e 's|#daemonize : yes|domonize: yes|'    \
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
    -e 's|port : 9221|port : 9231|'    \
    -e 's|#daemonize : yes|domonize: yes|'    \
    -e 's|#rate-limiter-bandwidth : 1099511627776|rate-limiter-bandwidth : 1099511627776|'    \
    -e 's|max-background-jobs : 3|max-background-jobs : 12|'    \
    -e 's|log-path : ./log/|log-path : ./dbtest/targetDB/log|'    \
    -e 's|db-path : ./db/|db-path : ./dbtest/targetDB/db/|'    \
    -e 's|dump-path : ./dump/|dump-path : ./dbtest/targetDB/dump/|'    \
    -e 's|db-sync-path : ./dbsync/|db-sync-path : ./dbtest/targetDB/dbsync/|'    \
    -e 's|pidfile : ./pika.pid|pidfile : ./dbtest/targetDB/pika.pid|'    \
    ./dbtest/targetDB/pika.conf

sed -i.bak  \
    -e 's|thread-num : 1|thread-num : 8|'    \
    -e 's|thread-pool-size : 12|thread-pool-size : 64|'    \
    -e 's|write-buffer-size : 268435456|write-buffer-size : 256M|'    \
    -e 's|port : 9221|port : 9251|'    \
    -e 's|#daemonize : yes|domonize: yes|'    \
    -e 's|#rate-limiter-bandwidth : 1099511627776|rate-limiter-bandwidth : 1099511627776|'    \
    -e 's|max-background-jobs : 3|max-background-jobs : 12|'    \
    -e 's|log-path : ./log/|log-path : ./dbtest/migrateDB/log/|'    \
    -e 's|db-path : ./db/|db-path : ./dbtest/migrateDB/db/|'    \
    -e 's|db-sync-path : ./dbsync/|db-sync-path : ./dbtest/migrateDB/dbsync/|'    \
    -e 's|pidfile : ./pika.pid|pidfile : ./dbtest/migrateDB/pika.pid|'    \
    -e 's|dump-path : ./dump/|dump-path : ./dbtest/migrateDB/dump/|'    \
    -e 's|redis-sender-num  : 10|redis-sender-num  : 100|'  \
    ./dbtest/migrateDB/pika.conf


# start pika
./dbtest/sourceDB/pika -c ./dbtest/sourceDB/pika.conf &
./dbtest/targetDB/pika -c ./dbtest/targetDB/pika.conf &

sleep 20

# start test
./consistency_benchmark -mp 9221 -d 60 -r 60 -n 500000 -log-file SET-12345.log SET __key__ __data__ &
./consistency_benchmark -mp 9221 -d 59 -r 59 -n 500000 -log-file HSET-12345.log HSET __key__ __key__ __data__ & 
./consistency_benchmark -mp 9221 -d 58 -r 58 -n 500000 -log-file LPUSH-12345.log LPUSH __key__ __key__ __key__ &
./consistency_benchmark -mp 9221 -d 57 -r 57 -n 500000 -log-file SADD-12345.log SADD __key__ __key__ __data__ &
./consistency_benchmark -mp 9221 -d 56 -r 56 -n 500000 -log-file ZADD-12345.log ZADD __key__ 10 __key__ 9 __key__ &
./consistency_benchmark -mp 9221 -d 55 -r 55 -n 500000 -log-file XADD-12345.log XADD __key__ 1 __key__ __data__ 


./consistency_benchmark -mp 9221 -d 60 -r 60 -n 500000 -random-seed 54321 -log-file SET-54321.log SET __key__ __data__ & 
./consistency_benchmark -mp 9221 -d 59 -r 59 -n 500000 -random-seed 54321 -log-file HSET-54321.log HSET __key__ __key__ __data__ & 
./consistency_benchmark -mp 9221 -d 58 -r 58 -n 500000 -random-seed 54321 -log-file LPUSH-54321.log LPUSH __key__ __key__ __key__ &
./consistency_benchmark -mp 9221 -d 57 -r 57 -n 500000 -random-seed 54321 -log-file SADD-54321.log SADD __key__ __key__ __data__ &
./consistency_benchmark -mp 9221 -d 56 -r 56 -n 500000 -random-seed 54321 -log-file ZADD-54321.log ZADD __key__ 10 __key__ 9 __key__ &
./consistency_benchmark -mp 9221 -d 55 -r 55 -n 500000 -random-seed 54321 -log-file XADD-54321.log XADD __key__ 1 __key__ __data__ __key__ __data__ 


# start migrateDB
./dbtest/migrateDB/pika -c ./dbtest/migrateDB/pika.conf &
sleep 20
redis-cli -p 9221 -c config set expire-logs-nums 10000
redis-cli -p 9231 -c config set expire-logs-nums 10000
redis-cli -p 9251 -c config set expire-logs-nums 10000

redis-cli -p 9251 -c slaveof 127.0.0.1 9221

# continue write duration migrate
./consistency_benchmark -mp 9221 -d 60 -r 60 -n 500000 -random-seed 54321 -log-file DEL-54321.log DEL __key__ __data__ &
./consistency_benchmark -mp 9221 -d 59 -r 59 -n 500000 -random-seed 54321 -log-file HDEL-54321.log HDEL __key__ __key__ __data__ &  
./consistency_benchmark -mp 9221 -d 58 -r 58 -n 500000 -random-seed 54321 -log-file LPOP-54321.log LPOP __key__ __key__ __key__ &
./consistency_benchmark -mp 9221 -d 57 -r 57 -n 500000 -random-seed 54321 -log-file SREM-54321.log SREM __key__ __key__ __data__ &
./consistency_benchmark -mp 9221 -d 56 -r 56 -n 500000 -random-seed 54321 -log-file ZREM-54321.log ZREM __key__ __key__ __key__ &
./consistency_benchmark -mp 9221 -d 55 -r 55 -n 500000 -random-seed 54321 -log-file XDEL-54321.log XDEL __key__ 1 __key__ __data__ __key__ __data__ &
