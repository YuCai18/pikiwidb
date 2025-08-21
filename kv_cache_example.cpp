#include <iostream>
#include <vector>
#include <memory>
#include <cmath>

// 简化的KV Cache实现示例
class KVCache {
private:
    std::vector<std::vector<float>> cached_keys;    // 缓存的K矩阵
    std::vector<std::vector<float>> cached_values;  // 缓存的V矩阵
    int seq_length;
    int hidden_dim;

public:
    KVCache(int hidden_dim) : hidden_dim(hidden_dim), seq_length(0) {}
    
    // 添加新的K、V到缓存
    void append_kv(const std::vector<float>& new_k, const std::vector<float>& new_v) {
        cached_keys.push_back(new_k);
        cached_values.push_back(new_v);
        seq_length++;
        
        std::cout << "缓存更新: 序列长度 = " << seq_length << std::endl;
    }
    
    // 获取所有缓存的K矩阵
    const std::vector<std::vector<float>>& get_all_keys() const {
        return cached_keys;
    }
    
    // 获取所有缓存的V矩阵
    const std::vector<std::vector<float>>& get_all_values() const {
        return cached_values;
    }
    
    // 模拟attention计算
    std::vector<float> compute_attention(const std::vector<float>& query_current) {
        std::cout << "\n=== Attention计算过程 ===" << std::endl;
        std::cout << "当前Query: [";
        for (int i = 0; i < std::min(3, (int)query_current.size()); i++) {
            std::cout << query_current[i] << " ";
        }
        std::cout << "...]" << std::endl;
        
        // 1. 计算Q与所有K的相似度分数
        std::vector<float> scores;
        for (int i = 0; i < seq_length; i++) {
            float score = 0.0f;
            for (int j = 0; j < hidden_dim; j++) {
                score += query_current[j] * cached_keys[i][j];
            }
            scores.push_back(score);
        }
        
        std::cout << "注意力分数: [";
        for (float score : scores) {
            std::cout << score << " ";
        }
        std::cout << "]" << std::endl;
        
        // 2. Softmax归一化（简化版）
        float sum_exp = 0.0f;
        std::vector<float> exp_scores;
        for (float score : scores) {
            float exp_score = std::exp(score - 1.0f); // 简化的数值稳定性处理
            exp_scores.push_back(exp_score);
            sum_exp += exp_score;
        }
        
        std::vector<float> attention_weights;
        for (float exp_score : exp_scores) {
            attention_weights.push_back(exp_score / sum_exp);
        }
        
        std::cout << "注意力权重: [";
        for (float weight : attention_weights) {
            std::cout << weight << " ";
        }
        std::cout << "]" << std::endl;
        
        // 3. 加权求和所有V
        std::vector<float> output(hidden_dim, 0.0f);
        for (int i = 0; i < seq_length; i++) {
            for (int j = 0; j < hidden_dim; j++) {
                output[j] += attention_weights[i] * cached_values[i][j];
            }
        }
        
        std::cout << "输出向量: [";
        for (int i = 0; i < std::min(3, (int)output.size()); i++) {
            std::cout << output[i] << " ";
        }
        std::cout << "...]" << std::endl;
        
        return output;
    }
    
    void print_cache_status() {
        std::cout << "\n=== KV Cache状态 ===" << std::endl;
        std::cout << "缓存序列长度: " << seq_length << std::endl;
        std::cout << "隐藏维度: " << hidden_dim << std::endl;
        std::cout << "K矩阵形状: [" << seq_length << " x " << hidden_dim << "]" << std::endl;
        std::cout << "V矩阵形状: [" << seq_length << " x " << hidden_dim << "]" << std::endl;
        
        // 显示缓存的K、V
        for (int i = 0; i < seq_length; i++) {
            std::cout << "位置 " << i << " - K: [";
            for (int j = 0; j < std::min(3, hidden_dim); j++) {
                std::cout << cached_keys[i][j] << " ";
            }
            std::cout << "...], V: [";
            for (int j = 0; j < std::min(3, hidden_dim); j++) {
                std::cout << cached_values[i][j] << " ";
            }
            std::cout << "...]" << std::endl;
        }
    }
};

// 模拟文本生成过程
void simulate_text_generation() {
    std::cout << "=== 模拟文本生成中的KV Cache使用 ===" << std::endl;
    
    const int hidden_dim = 4;  // 简化的隐藏维度
    KVCache kv_cache(hidden_dim);
    
    // 模拟生成过程
    std::vector<std::string> tokens = {"Hello", "world", "this", "is"};
    
    for (int step = 0; step < tokens.size(); step++) {
        std::cout << "\n>>> 第" << (step + 1) << "步: 生成token '" << tokens[step] << "'" << std::endl;
        
        // 1. 计算当前token的K、V（实际中这些来自transformer层）
        std::vector<float> current_k(hidden_dim);
        std::vector<float> current_v(hidden_dim);
        std::vector<float> current_q(hidden_dim);
        
        // 填充模拟数据
        for (int i = 0; i < hidden_dim; i++) {
            current_k[i] = (step + 1) * 0.1f + i * 0.05f;
            current_v[i] = (step + 1) * 0.2f + i * 0.03f;
            current_q[i] = (step + 1) * 0.15f + i * 0.04f;
        }
        
        // 2. 将新的K、V添加到缓存
        kv_cache.append_kv(current_k, current_v);
        
        // 3. 显示缓存状态
        kv_cache.print_cache_status();
        
        // 4. 使用当前Q和缓存的所有K、V计算attention
        auto attention_output = kv_cache.compute_attention(current_q);
        
        std::cout << "\n注意: " << std::endl;
        std::cout << "- Q矩阵每次都重新计算，不需要缓存" << std::endl;
        std::cout << "- K、V矩阵添加到缓存中，供后续步骤重用" << std::endl;
        std::cout << "- 当前step可以看到所有历史信息的K、V" << std::endl;
        
        if (step < tokens.size() - 1) {
            std::cout << "\n按Enter继续下一步..." << std::endl;
            std::cin.get();
        }
    }
}

int main() {
    std::cout << "=== 为什么KV Cache只存K、V不存Q？ ===" << std::endl;
    std::cout << std::endl;
    
    std::cout << "原因分析:" << std::endl;
    std::cout << "1. Q(Query): 每次生成新token时重新计算，依赖当前输入状态" << std::endl;
    std::cout << "2. K(Key): 历史token的K值固定不变，可以缓存重用" << std::endl;
    std::cout << "3. V(Value): 历史token的V值固定不变，可以缓存重用" << std::endl;
    std::cout << std::endl;
    
    std::cout << "计算过程:" << std::endl;
    std::cout << "Attention(Q_t, K_{1:t}, V_{1:t}) = softmax(Q_t @ K_{1:t}^T) @ V_{1:t}" << std::endl;
    std::cout << "- Q_t: 当前时刻的查询（每次重算）" << std::endl;
    std::cout << "- K_{1:t}: 所有历史+当前的键（前面部分来自缓存）" << std::endl;
    std::cout << "- V_{1:t}: 所有历史+当前的值（前面部分来自缓存）" << std::endl;
    std::cout << std::endl;
    
    simulate_text_generation();
    
    std::cout << "\n=== 总结 ===" << std::endl;
    std::cout << "KV Cache的优势:" << std::endl;
    std::cout << "✓ 避免重复计算历史token的K、V矩阵" << std::endl;
    std::cout << "✓ 显著减少计算量，从O(n²)降到O(n)" << std::endl;
    std::cout << "✓ 提高生成速度，特别是长序列生成" << std::endl;
    std::cout << "✓ Q矩阵不需要缓存，因为每次都会重新计算" << std::endl;
    
    return 0;
}