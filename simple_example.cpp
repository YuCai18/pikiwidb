#include <iostream>
#include <string>

// 简化版本的HashMap，只包含核心功能
template<typename K, typename V>
class SimpleHashMap {
private:
    struct Node {
        K key;
        V value;
        Node* next;
        
        Node(const K& k, const V& v) : key(k), value(v), next(nullptr) {}
    };
    
    Node** table;
    size_t capacity;
    size_t size;
    
    // 简单的哈希函数
    size_t hash(const K& key) const {
        std::hash<K> hasher;
        return hasher(key) % capacity;
    }
    
public:
    // 构造函数
    SimpleHashMap(size_t cap = 16) : capacity(cap), size(0) {
        table = new Node*[capacity];
        for (size_t i = 0; i < capacity; ++i) {
            table[i] = nullptr;
        }
    }
    
    // 析构函数
    ~SimpleHashMap() {
        for (size_t i = 0; i < capacity; ++i) {
            Node* current = table[i];
            while (current) {
                Node* temp = current;
                current = current->next;
                delete temp;
            }
        }
        delete[] table;
    }
    
    // 插入操作
    void insert(const K& key, const V& value) {
        size_t index = hash(key);
        Node* current = table[index];
        
        // 检查键是否已存在
        while (current) {
            if (current->key == key) {
                current->value = value;  // 更新值
                return;
            }
            current = current->next;
        }
        
        // 创建新节点并插入到链表头部
        Node* newNode = new Node(key, value);
        newNode->next = table[index];
        table[index] = newNode;
        size++;
    }
    
    // 查询操作
    V* find(const K& key) {
        size_t index = hash(key);
        Node* current = table[index];
        
        while (current) {
            if (current->key == key) {
                return &(current->value);
            }
            current = current->next;
        }
        
        return nullptr;  // 未找到
    }
    
    // 获取大小
    size_t get_size() const {
        return size;
    }
};

int main() {
    std::cout << "=== 简单HashMap示例 ===" << std::endl;
    
    SimpleHashMap<std::string, int> map;
    
    // 插入数据
    std::cout << "插入数据..." << std::endl;
    map.insert("张三", 85);
    map.insert("李四", 92);
    map.insert("王五", 78);
    map.insert("赵六", 88);
    
    std::cout << "当前元素数量: " << map.get_size() << std::endl;
    
    // 查询数据
    std::cout << "\n查询结果:" << std::endl;
    
    std::string names[] = {"张三", "李四", "王五", "赵六", "钱七"};
    
    for (const auto& name : names) {
        int* score = map.find(name);
        if (score) {
            std::cout << name << " 的分数: " << *score << std::endl;
        } else {
            std::cout << name << " 未找到" << std::endl;
        }
    }
    
    // 更新数据
    std::cout << "\n更新张三的分数为95..." << std::endl;
    map.insert("张三", 95);
    
    int* updated_score = map.find("张三");
    if (updated_score) {
        std::cout << "张三更新后的分数: " << *updated_score << std::endl;
    }
    
    return 0;
}