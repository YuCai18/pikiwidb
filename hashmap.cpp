#include <iostream>
#include <vector>
#include <list>
#include <string>
#include <functional>

template<typename K, typename V>
class HashMap {
private:
    // 哈希表的节点结构
    struct Node {
        K key;
        V value;
        
        Node(const K& k, const V& v) : key(k), value(v) {}
    };
    
    // 使用vector存储链表，每个位置是一个链表来处理冲突
    std::vector<std::list<Node>> table;
    size_t bucket_count;
    size_t size;
    
    // 负载因子阈值
    static constexpr double MAX_LOAD_FACTOR = 0.75;
    
    // 哈希函数
    size_t hash(const K& key) const {
        std::hash<K> hasher;
        return hasher(key) % bucket_count;
    }
    
    // 重新哈希，当负载因子过高时扩容
    void rehash() {
        auto old_table = std::move(table);
        
        bucket_count *= 2;
        table = std::vector<std::list<Node>>(bucket_count);
        size = 0;
        
        // 重新插入所有元素
        for (const auto& bucket : old_table) {
            for (const auto& node : bucket) {
                insert(node.key, node.value);
            }
        }
    }
    
public:
    // 构造函数
    HashMap(size_t initial_bucket_count = 16) 
        : bucket_count(initial_bucket_count), size(0) {
        table.resize(bucket_count);
    }
    
    // 插入或更新键值对
    void insert(const K& key, const V& value) {
        // 检查是否需要扩容
        if (static_cast<double>(size) / bucket_count > MAX_LOAD_FACTOR) {
            rehash();
        }
        
        size_t index = hash(key);
        auto& bucket = table[index];
        
        // 检查键是否已存在，如果存在则更新值
        for (auto& node : bucket) {
            if (node.key == key) {
                node.value = value;
                return;
            }
        }
        
        // 键不存在，添加新节点
        bucket.emplace_back(key, value);
        size++;
    }
    
    // 查询操作，返回指向值的指针，如果不存在返回nullptr
    V* find(const K& key) {
        size_t index = hash(key);
        auto& bucket = table[index];
        
        for (auto& node : bucket) {
            if (node.key == key) {
                return &node.value;
            }
        }
        
        return nullptr;  // 未找到
    }
    
    // 查询操作（const版本）
    const V* find(const K& key) const {
        size_t index = hash(key);
        const auto& bucket = table[index];
        
        for (const auto& node : bucket) {
            if (node.key == key) {
                return &node.value;
            }
        }
        
        return nullptr;  // 未找到
    }
    
    // 删除操作
    bool remove(const K& key) {
        size_t index = hash(key);
        auto& bucket = table[index];
        
        for (auto it = bucket.begin(); it != bucket.end(); ++it) {
            if (it->key == key) {
                bucket.erase(it);
                size--;
                return true;
            }
        }
        
        return false;  // 未找到要删除的键
    }
    
    // 检查键是否存在
    bool contains(const K& key) const {
        return find(key) != nullptr;
    }
    
    // 获取当前元素数量
    size_t get_size() const {
        return size;
    }
    
    // 获取桶的数量
    size_t get_bucket_count() const {
        return bucket_count;
    }
    
    // 获取负载因子
    double load_factor() const {
        return static_cast<double>(size) / bucket_count;
    }
    
    // 打印哈希表状态（用于调试）
    void print_status() const {
        std::cout << "HashMap Status:" << std::endl;
        std::cout << "Size: " << size << std::endl;
        std::cout << "Bucket Count: " << bucket_count << std::endl;
        std::cout << "Load Factor: " << load_factor() << std::endl;
        std::cout << "Bucket Distribution:" << std::endl;
        
        for (size_t i = 0; i < bucket_count; ++i) {
            if (!table[i].empty()) {
                std::cout << "Bucket " << i << ": " << table[i].size() << " items" << std::endl;
            }
        }
        std::cout << std::endl;
    }
};

// 测试函数
void test_hashmap() {
    std::cout << "=== HashMap测试 ===" << std::endl;
    
    HashMap<std::string, int> map;
    
    // 测试插入
    std::cout << "插入测试:" << std::endl;
    map.insert("apple", 100);
    map.insert("banana", 200);
    map.insert("orange", 300);
    map.insert("grape", 400);
    map.insert("watermelon", 500);
    
    std::cout << "插入了5个元素" << std::endl;
    map.print_status();
    
    // 测试查询
    std::cout << "查询测试:" << std::endl;
    auto* value = map.find("apple");
    if (value) {
        std::cout << "找到 apple: " << *value << std::endl;
    } else {
        std::cout << "未找到 apple" << std::endl;
    }
    
    value = map.find("banana");
    if (value) {
        std::cout << "找到 banana: " << *value << std::endl;
    } else {
        std::cout << "未找到 banana" << std::endl;
    }
    
    value = map.find("cherry");
    if (value) {
        std::cout << "找到 cherry: " << *value << std::endl;
    } else {
        std::cout << "未找到 cherry" << std::endl;
    }
    
    // 测试更新
    std::cout << "\n更新测试:" << std::endl;
    map.insert("apple", 150);  // 更新apple的值
    value = map.find("apple");
    if (value) {
        std::cout << "更新后的 apple: " << *value << std::endl;
    }
    
    // 测试contains
    std::cout << "\ncontains测试:" << std::endl;
    std::cout << "包含 'orange': " << (map.contains("orange") ? "是" : "否") << std::endl;
    std::cout << "包含 'mango': " << (map.contains("mango") ? "是" : "否") << std::endl;
    
    // 测试删除
    std::cout << "\n删除测试:" << std::endl;
    bool removed = map.remove("banana");
    std::cout << "删除 banana: " << (removed ? "成功" : "失败") << std::endl;
    std::cout << "删除后查询 banana: " << (map.find("banana") ? "仍存在" : "已删除") << std::endl;
    
    map.print_status();
}

// 测试大量数据和自动扩容
void test_large_data() {
    std::cout << "=== 大数据测试（自动扩容） ===" << std::endl;
    
    HashMap<int, std::string> map(4);  // 从小容量开始
    
    std::cout << "初始状态:" << std::endl;
    map.print_status();
    
    // 插入大量数据触发扩容
    for (int i = 0; i < 20; ++i) {
        map.insert(i, "value_" + std::to_string(i));
    }
    
    std::cout << "插入20个元素后:" << std::endl;
    map.print_status();
    
    // 测试查询
    std::cout << "查询测试:" << std::endl;
    for (int i = 0; i < 20; i += 5) {
        auto* value = map.find(i);
        if (value) {
            std::cout << "键 " << i << ": " << *value << std::endl;
        }
    }
}

int main() {
    test_hashmap();
    std::cout << std::endl;
    test_large_data();
    
    return 0;
}