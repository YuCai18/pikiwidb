#!/bin/bash
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 60 -d 60 -n 500000 -checkMode 1 -log-file SET-12345-check.log SET __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 59 -d 59 -n 500000 -checkMode 1 -log-file HSET-12345-check.log HSET __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 58 -d 58 -n 500000 -checkMode 1 -log-file LPUSH-12345-check.log LPUSH __key__ __key__ __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 57 -d 57 -n 500000 -checkMode 1 -log-file SADD-12345-check.log SADD __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 56 -d 56 -n 500000 -checkMode 1 -log-file ZADD-12345-check.log ZADD __key__ 10 __key__ 9 __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 55 -d 55 -n 500000 -checkMode 1 -log-file XADD-12345-check.log XADD __key__ 1 __key__ __data__ 


./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 60 -d 60 -n 500000 -random-seed 54321 -checkMode 1 -log-file SET-54321-check.log SET __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 59 -d 59 -n 500000 -random-seed 54321 -checkMode 1 -log-file HSET-54321-check.log HSET __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 58 -d 58 -n 500000 -random-seed 54321 -checkMode 1 -log-file LPUSH-54321-check.log LPUSH __key__ __key__ __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 57 -d 57 -n 500000 -random-seed 54321 -checkMode 1 -log-file SADD-54321-check.log SADD __key__ __key__ __data__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 56 -d 56 -n 500000 -random-seed 54321 -checkMode 1 -log-file ZADD-54321-check.log ZADD __key__ 10 __key__ 9 __key__ &
./consistency_benchmark -mh 127.0.0.1 -mp 9221 -sh x.x.x.x -sp 6380 -su root -spw ****** -r 55 -d 55 -n 500000 -random-seed 54321 -checkMode 1 -log-file XADD-54321-check.log XADD __key__ 1 __key__ __data__ 

redis-cli -p 9251 -c SHUTDOWN
redis-cli -p 9221 -c SHUTDOWN
redis-cli -p 9231 -c SHUTDOWN
