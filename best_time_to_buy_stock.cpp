#include <iostream>
#include <vector>
#include <algorithm>
#include <climits>

class Solution {
public:
    // 方法1: 一次遍历 - 最优解法
    // 时间复杂度: O(n), 空间复杂度: O(1)
    int maxProfit(std::vector<int>& prices) {
        if (prices.empty() || prices.size() < 2) {
            return 0;
        }
        
        int minPrice = prices[0];  // 记录到目前为止的最低价格
        int maxProfit = 0;         // 记录到目前为止的最大利润
        
        for (int i = 1; i < prices.size(); i++) {
            // 如果当前价格更低，更新最低价格
            if (prices[i] < minPrice) {
                minPrice = prices[i];
            } else {
                // 计算当前卖出能获得的利润
                int currentProfit = prices[i] - minPrice;
                // 更新最大利润
                maxProfit = std::max(maxProfit, currentProfit);
            }
        }
        
        return maxProfit;
    }
    
    // 方法2: 动态规划思路
    // 时间复杂度: O(n), 空间复杂度: O(1)
    int maxProfitDP(std::vector<int>& prices) {
        if (prices.empty() || prices.size() < 2) {
            return 0;
        }
        
        // dp[i][0] 表示第i天不持有股票的最大利润
        // dp[i][1] 表示第i天持有股票的最大利润
        int hold = -prices[0];  // 持有股票（买入）
        int sold = 0;           // 不持有股票
        
        for (int i = 1; i < prices.size(); i++) {
            int newSold = std::max(sold, hold + prices[i]);  // 今天卖出或者继续不持有
            int newHold = std::max(hold, -prices[i]);        // 今天买入或者继续持有
            
            sold = newSold;
            hold = newHold;
        }
        
        return sold;  // 最后不持有股票的状态就是最大利润
    }
    
    // 方法3: 暴力解法（仅用于理解，效率较低）
    // 时间复杂度: O(n²), 空间复杂度: O(1)
    int maxProfitBruteForce(std::vector<int>& prices) {
        if (prices.empty() || prices.size() < 2) {
            return 0;
        }
        
        int maxProfit = 0;
        
        for (int i = 0; i < prices.size() - 1; i++) {
            for (int j = i + 1; j < prices.size(); j++) {
                int profit = prices[j] - prices[i];
                maxProfit = std::max(maxProfit, profit);
            }
        }
        
        return maxProfit;
    }
};

// 测试函数
void testCase(std::vector<int> prices, int expected, const std::string& testName) {
    Solution solution;
    
    // 测试三种方法
    int result1 = solution.maxProfit(prices);
    int result2 = solution.maxProfitDP(prices);
    int result3 = solution.maxProfitBruteForce(prices);
    
    std::cout << "=== " << testName << " ===" << std::endl;
    std::cout << "输入: [";
    for (int i = 0; i < prices.size(); i++) {
        std::cout << prices[i];
        if (i < prices.size() - 1) std::cout << ", ";
    }
    std::cout << "]" << std::endl;
    
    std::cout << "期望结果: " << expected << std::endl;
    std::cout << "方法1结果: " << result1 << (result1 == expected ? " ✓" : " ✗") << std::endl;
    std::cout << "方法2结果: " << result2 << (result2 == expected ? " ✓" : " ✗") << std::endl;
    std::cout << "方法3结果: " << result3 << (result3 == expected ? " ✓" : " ✗") << std::endl;
    std::cout << std::endl;
}

int main() {
    std::cout << "=== 力扣 - 买卖股票的最佳时机 ===" << std::endl;
    std::cout << "题目: 给定股票价格数组，只能买入一次、卖出一次，求最大利润" << std::endl;
    std::cout << std::endl;
    
    // 测试用例1: 经典示例
    testCase({7, 1, 5, 3, 6, 4}, 5, "测试用例1");
    
    // 测试用例2: 价格持续下跌
    testCase({7, 6, 4, 3, 1}, 0, "测试用例2");
    
    // 测试用例3: 价格持续上涨
    testCase({1, 2, 3, 4, 5}, 4, "测试用例3");
    
    // 测试用例4: 只有两个价格
    testCase({1, 5}, 4, "测试用例4");
    
    // 测试用例5: 相同价格
    testCase({3, 3, 3, 3}, 0, "测试用例5");
    
    // 测试用例6: 空数组
    testCase({}, 0, "测试用例6");
    
    // 测试用例7: 单个元素
    testCase({5}, 0, "测试用例7");
    
    // 测试用例8: 大幅波动
    testCase({3, 2, 6, 5, 0, 3}, 4, "测试用例8");
    
    std::cout << "=== 算法分析 ===" << std::endl;
    std::cout << "方法1 - 一次遍历:" << std::endl;
    std::cout << "  时间复杂度: O(n)" << std::endl;
    std::cout << "  空间复杂度: O(1)" << std::endl;
    std::cout << "  核心思想: 记录历史最低价格，计算当前价格卖出的利润" << std::endl;
    std::cout << std::endl;
    
    std::cout << "方法2 - 动态规划:" << std::endl;
    std::cout << "  时间复杂度: O(n)" << std::endl;
    std::cout << "  空间复杂度: O(1)" << std::endl;
    std::cout << "  核心思想: 维护持有/不持有股票两种状态的最大利润" << std::endl;
    std::cout << std::endl;
    
    std::cout << "方法3 - 暴力解法:" << std::endl;
    std::cout << "  时间复杂度: O(n²)" << std::endl;
    std::cout << "  空间复杂度: O(1)" << std::endl;
    std::cout << "  核心思想: 枚举所有买入卖出的组合" << std::endl;
    
    return 0;
}