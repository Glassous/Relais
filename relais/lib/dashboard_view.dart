import 'package:flutter/material.dart';
import 'api_service.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final stats = await ApiService.getDashboardStats();
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "获取统计数据失败: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchStats,
              child: const Text("重试"),
            ),
          ],
        ),
      );
    }

    final summary = _stats?['summary'] ?? {};
    final trends = _stats?['trends'] as List? ?? [];
    final models = _stats?['models'] as List? ?? [];
    final keys = _stats?['keys'] as List? ?? [];
    final logs = _stats?['logs'] as List? ?? [];

    final int totalPrompt = summary['total_prompt'] ?? 0;
    final int totalCompletion = summary['total_completion'] ?? 0;
    final int totalReasoning = summary['total_reasoning'] ?? 0;
    final int totalRequests = summary['total_requests'] ?? 0;
    final int successRequests = summary['success_requests'] ?? 0;

    final double successRate = totalRequests > 0 ? (successRequests / totalRequests) * 100 : 0.0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row of KPI Cards
          Row(
            children: [
              Expanded(child: _buildKpiCard("输入 Token (Prompt)", totalPrompt.toString(), Icons.arrow_downward, Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _buildKpiCard("输出 Token (Completion)", totalCompletion.toString(), Icons.arrow_upward, Colors.green)),
              const SizedBox(width: 16),
              Expanded(child: _buildKpiCard("深度思考 Token (Reasoning)", totalReasoning.toString(), Icons.psychology_outlined, Colors.purple)),
              const SizedBox(width: 16),
              Expanded(child: _buildKpiCard("请求总量 (成功率)", "$totalRequests 次 (${successRate.toStringAsFixed(1)}%)", Icons.online_prediction, Colors.teal)),
            ],
          ),
          const SizedBox(height: 28),

          // Mid-section Grid (Distributions)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Model distribution
              Expanded(
                child: _buildDistributionCard("模型使用排行 (Tokens)", models, (item) {
                  return item['_id'] ?? '未知模型';
                }, (item) {
                  return item['total_tokens'] ?? 0;
                }, theme, isDark),
              ),
              const SizedBox(width: 20),
              // API Key distribution
              Expanded(
                child: _buildDistributionCard("API 密钥使用排行 (Tokens)", keys, (item) {
                  return item['_id'] ?? '无名称密钥';
                }, (item) {
                  return item['total_tokens'] ?? 0;
                }, theme, isDark),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Trend Chart (Simulated high-end custom layout)
          if (trends.isNotEmpty) ...[
            _buildTrendSection(trends, theme, isDark),
            const SizedBox(height: 28),
          ],

          // Recent Request Logs Table
          _buildLogsSection(logs, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionCard(
    String title,
    List<dynamic> items,
    String Function(dynamic) getName,
    int Function(dynamic) getValue,
    ThemeData theme,
    bool isDark,
  ) {
    // Find max value to draw proportion bars
    int maxValue = 0;
    for (var item in items) {
      final val = getValue(item);
      if (val > maxValue) {
        maxValue = val;
      }
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text("暂无数据", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length > 5 ? 5 : items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final name = getName(item);
                  final val = getValue(item);
                  final percent = maxValue > 0 ? val / maxValue : 0.0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            Text("$val tokens", style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent,
                            backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendSection(List<dynamic> trends, ThemeData theme, bool isDark) {
    // Find max requests for trend scaling
    int maxRequests = 0;
    for (var t in trends) {
      final reqs = t['requests'] ?? 0;
      if (reqs > maxRequests) {
        maxRequests = reqs;
      }
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("近 7 天请求活跃趋势", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: trends.map<Widget>((t) {
                  final date = t['_id'] ?? '';
                  final requests = t['requests'] ?? 0;
                  final heightRatio = maxRequests > 0 ? requests / maxRequests : 0.0;
                  final displayDate = date.length > 5 ? date.substring(5) : date; // MM-DD

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(requests.toString(), style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                      const SizedBox(height: 4),
                      Container(
                        width: 32,
                        height: 100 * heightRatio + 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(heightRatio > 0.1 ? heightRatio : 0.1),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          border: Border.all(color: theme.colorScheme.primary, width: 1),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(displayDate, style: const TextStyle(fontSize: 10)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsSection(List<dynamic> logs, ThemeData theme, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("最近中转请求日志", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _fetchStats,
                  tooltip: "刷新数据",
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text("暂无中转请求日志", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                ),
              )
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.5), // 时间
                  1: FlexColumnWidth(2.5), // 密钥
                  2: FlexColumnWidth(2),   // 映射模型
                  3: FlexColumnWidth(1.2), // Prompt
                  4: FlexColumnWidth(1.2), // Completion
                  5: FlexColumnWidth(1.2), // Reasoning
                  6: FlexColumnWidth(1.2), // 耗时
                  7: FlexColumnWidth(1.2), // 状态
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12, width: 1)),
                    ),
                    children: const [
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("请求时间", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("网关密钥", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("中转模型", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("输入", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("输出", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("思考", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("耗时", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text("状态", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    ],
                  ),
                  ...logs.map((logItem) {
                    final String timeStr = logItem['created_at'] != null
                        ? DateTime.parse(logItem['created_at']).toLocal().toString().substring(5, 19)
                        : '-';
                    final String keyName = logItem['api_key_name'] ?? '已删除密钥';
                    final String modelName = logItem['model_name'] ?? '-';
                    final int prompt = logItem['prompt_tokens'] ?? 0;
                    final int completion = logItem['completion_tokens'] ?? 0;
                    final int reasoning = logItem['reasoning_tokens'] ?? 0;
                    final int duration = logItem['duration_ms'] ?? 0;
                    final int code = logItem['status_code'] ?? 200;

                    final isSuccess = code >= 200 && code < 400;

                    return TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04), width: 1)),
                      ),
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(timeStr, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(keyName, style: const TextStyle(fontSize: 12))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(modelName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(prompt.toString(), style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(completion.toString(), style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(reasoning.toString(), style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: reasoning > 0 ? Colors.purpleAccent : null))),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text("${duration}ms", style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            code.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: isSuccess ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
