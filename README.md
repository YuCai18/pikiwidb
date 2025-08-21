# C++ HashMap实现

这个项目包含了两个C++ HashMap的实现：一个功能完整的版本和一个简化版本。

## 文件说明

- `hashmap.cpp` - 完整功能的HashMap实现
- `simple_example.cpp` - 简化版HashMap实现和使用示例
- `Makefile` - 编译配置文件

## 主要特性

### 完整版HashMap (`hashmap.cpp`)

1. **模板支持** - 支持任意键值类型
2. **冲突处理** - 使用链表法处理哈希冲突
3. **自动扩容** - 当负载因子超过0.75时自动扩容
4. **核心操作**：
   - `insert(key, value)` - 插入或更新键值对
   - `find(key)` - 查询键对应的值，返回指针
   - `remove(key)` - 删除指定键值对
   - `contains(key)` - 检查键是否存在
   - `get_size()` - 获取元素数量
   - `load_factor()` - 获取负载因子
   - `print_status()` - 打印哈希表状态

### 简化版HashMap (`simple_example.cpp`)

1. **基本功能** - 包含插入、查询等核心功能
2. **链表冲突处理** - 使用单向链表处理冲突
3. **简单易懂** - 代码结构清晰，便于学习

## 编译和运行

### 完整版本
```bash
make
./hashmap
```

### 简化版本
```bash
g++ -std=c++11 -Wall -Wextra -O2 -o simple_example simple_example.cpp
./simple_example
```

## 技术实现要点

### 哈希函数
使用C++标准库的`std::hash`模板，支持多种数据类型的哈希计算。

### 冲突处理
采用链地址法（链表法）处理哈希冲突：
- 每个哈希桶维护一个链表
- 冲突的元素插入到对应桶的链表中

### 动态扩容
- 监控负载因子（元素数量/桶数量）
- 当负载因子超过0.75时，桶数量翻倍
- 重新哈希所有现有元素

### 时间复杂度
- **平均情况**：插入、查询、删除都是 O(1)
- **最坏情况**：所有元素冲突到同一个桶，时间复杂度为 O(n)

## 使用示例

```cpp
#include "hashmap.cpp"  // 或者单独编译

int main() {
    HashMap<std::string, int> map;
    
    // 插入数据
    map.insert("apple", 100);
    map.insert("banana", 200);
    
    // 查询数据
    int* value = map.find("apple");
    if (value) {
        std::cout << "找到apple: " << *value << std::endl;
    }
    
    // 检查存在性
    if (map.contains("banana")) {
        std::cout << "包含banana" << std::endl;
    }
    
    // 删除数据
    map.remove("apple");
    
    return 0;
}
```

## 测试结果

程序包含了完整的测试用例，验证了：
- 基本的插入和查询功能
- 键值对的更新操作
- 元素的删除功能
- 自动扩容机制
- 大数据量的性能表现

运行测试可以看到哈希表的负载因子变化和桶的分布情况。