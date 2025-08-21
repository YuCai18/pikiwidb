#include <iostream>
#include <vector>
#include <cmath>

// 简化的KV Cache演示
void demonstrate_kv_cache() {
    std::cout << "=== 为什么KV Cache只存K、V不存Q？ ===" << std::endl;
    std::cout << std::endl;
    
    // 模拟3个时间步的生成过程
    const int seq_len = 3;
    const int hidden_dim = 4;
    
    // 模拟数据
    std::vector<std::vector<float>> all_queries(seq_len, std::vector<float>(hidden_dim));
    std::vector<std::vector<float>> all_keys(seq_len, std::vector<float>(hidden_dim));
    std::vector<std::vector<float>> all_values(seq_len, std::vector<float>(hidden_dim));
    
    // 填充模拟数据
    for (int t = 0; t < seq_len; t++) {
        for (int d = 0; d < hidden_dim; d++) {
            all_queries[t][d] = (t + 1) * 0.1f + d * 0.05f;
            all_keys[t][d] = (t + 1) * 0.2f + d * 0.03f;
            all_values[t][d] = (t + 1) * 0.3f + d * 0.04f;
        }
    }
    
    std::cout << "场景: 自回归文本生成过程" << std::endl;
    std::cout << "tokens: [\"Hello\", \"world\", \"!\"]" << std::endl;
    std::cout << std::endl;
    
    // 模拟每个时间步的计算
    for (int current_step = 0; current_step < seq_len; current_step++) {
        std::cout << "=== 第" << (current_step + 1) << "步生成 ===" << std::endl;
        
        // 1. 显示当前的Q（每次重新计算）
        std::cout << "当前Query Q_" << current_step << ": [";
        for (int d = 0; d < hidden_dim; d++) {
            std::cout << all_queries[current_step][d];
            if (d < hidden_dim - 1) std::cout << ", ";
        }
        std::cout << "]" << std::endl;
        
        // 2. 显示需要的所有K矩阵（包含历史）
        std::cout << "所需的所有Keys K_{0:" << current_step << "}:" << std::endl;
        for (int t = 0; t <= current_step; t++) {
            std::cout << "  K_" << t << ": [";
            for (int d = 0; d < hidden_dim; d++) {
                std::cout << all_keys[t][d];
                if (d < hidden_dim - 1) std::cout << ", ";
            }
            std::cout << "]";
            if (t < current_step) {
                std::cout << " <- 从缓存读取";
            } else {
                std::cout << " <- 新计算";
            }
            std::cout << std::endl;
        }
        
        // 3. 显示需要的所有V矩阵（包含历史）
        std::cout << "所需的所有Values V_{0:" << current_step << "}:" << std::endl;
        for (int t = 0; t <= current_step; t++) {
            std::cout << "  V_" << t << ": [";
            for (int d = 0; d < hidden_dim; d++) {
                std::cout << all_values[t][d];
                if (d < hidden_dim - 1) std::cout << ", ";
            }
            std::cout << "]";
            if (t < current_step) {
                std::cout << " <- 从缓存读取";
            } else {
                std::cout << " <- 新计算";
            }
            std::cout << std::endl;
        }
        
        // 4. 计算attention分数
        std::cout << "Attention计算:" << std::endl;
        std::vector<float> scores;
        for (int t = 0; t <= current_step; t++) {
            float score = 0.0f;
            for (int d = 0; d < hidden_dim; d++) {
                score += all_queries[current_step][d] * all_keys[t][d];
            }
            scores.push_back(score);
            std::cout << "  Q_" << current_step << " · K_" << t << " = " << score << std::endl;
        }
        
        // 5. 简化的softmax
        float sum_scores = 0.0f;
        for (float score : scores) {
            sum_scores += std::exp(score);
        }
        
        std::cout << "Attention权重:" << std::endl;
        std::vector<float> weights;
        for (int t = 0; t <= current_step; t++) {
            float weight = std::exp(scores[t]) / sum_scores;
            weights.push_back(weight);
            std::cout << "  w_" << t << " = " << weight << std::endl;
        }
        
        // 6. 计算输出
        std::vector<float> output(hidden_dim, 0.0f);
        for (int t = 0; t <= current_step; t++) {
            for (int d = 0; d < hidden_dim; d++) {
                output[d] += weights[t] * all_values[t][d];
            }
        }
        
        std::cout << "输出: [";
        for (int d = 0; d < hidden_dim; d++) {
            std::cout << output[d];
            if (d < hidden_dim - 1) std::cout << ", ";
        }
        std::cout << "]" << std::endl;
        
        std::cout << std::endl;
        std::cout << "关键观察:" << std::endl;
        std::cout << "- Q_" << current_step << " 是新计算的，依赖当前输入" << std::endl;
        if (current_step > 0) {
            std::cout << "- K_{0:" << (current_step-1) << "} 和 V_{0:" << (current_step-1) << "} 从缓存读取" << std::endl;
        }
        std::cout << "- K_" << current_step << " 和 V_" << current_step << " 新计算并添加到缓存" << std::endl;
        std::cout << std::endl;
    }
}

int main() {
    std::cout << "🔍 KV Cache原理解析" << std::endl;
    std::cout << "==================" << std::endl;
    std::cout << std::endl;
    
    std::cout << "核心问题: 为什么只缓存K和V，不缓存Q？" << std::endl;
    std::cout << std::endl;
    
    std::cout << "答案要点:" << std::endl;
    std::cout << "1. Q(Query)矩阵的特点:" << std::endl;
    std::cout << "   - 每次生成新token时都需要重新计算" << std::endl;
    std::cout << "   - 依赖于当前的输入状态和上下文" << std::endl;
    std::cout << "   - 不具备重用性" << std::endl;
    std::cout << std::endl;
    
    std::cout << "2. K(Key)和V(Value)矩阵的特点:" << std::endl;
    std::cout << "   - 历史token的K、V一旦计算出来就固定不变" << std::endl;
    std::cout << "   - 可以在后续步骤中重复使用" << std::endl;
    std::cout << "   - 缓存可以避免重复计算，提升效率" << std::endl;
    std::cout << std::endl;
    
    std::cout << "3. 计算公式:" << std::endl;
    std::cout << "   Attention(Q_t, K_{1:t}, V_{1:t}) = softmax(Q_t @ K_{1:t}^T) @ V_{1:t}" << std::endl;
    std::cout << "   - Q_t: 当前时刻的查询（每次重算）" << std::endl;
    std::cout << "   - K_{1:t}: 包含历史的所有键（部分来自缓存）" << std::endl;
    std::cout << "   - V_{1:t}: 包含历史的所有值（部分来自缓存）" << std::endl;
    std::cout << std::endl;
    
    demonstrate_kv_cache();
    
    std::cout << "=== 总结 ===" << std::endl;
    std::cout << "KV Cache的核心优势:" << std::endl;
    std::cout << "✅ 避免重复计算历史token的K、V矩阵" << std::endl;
    std::cout << "✅ 将时间复杂度从O(n²)优化到O(n)" << std::endl;
    std::cout << "✅ 显著提升长序列生成的速度" << std::endl;
    std::cout << "✅ 内存使用合理（只存储必要的K、V）" << std::endl;
    std::cout << std::endl;
    
    std::cout << "为什么不缓存Q:" << std::endl;
    std::cout << "❌ Q矩阵每次都会变化，缓存无意义" << std::endl;
    std::cout << "❌ Q的计算相对K、V更轻量" << std::endl;
    std::cout << "❌ 缓存Q会浪费内存而不带来性能提升" << std::endl;
    
    return 0;
}