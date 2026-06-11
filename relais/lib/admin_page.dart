import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'main.dart';
import 'dashboard_view.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _activeTab = 0; // 0: Dashboard, 1: Models, 2: API Keys
  List<dynamic> _models = [];
  List<dynamic> _apiKeys = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final models = await ApiService.getModels();
    final keys = await ApiService.getApiKeys();
    setState(() {
      _models = models;
      _apiKeys = keys;
      _isLoading = false;
    });
  }

  void _showModelDialog([Map<String, dynamic>? model]) {
    final isEdit = model != null;
    final nameController = TextEditingController(text: isEdit ? model['custom_name'] : '');
    final urlController = TextEditingController(text: isEdit ? model['provider_base_url'] : '');
    final keyController = TextEditingController(text: isEdit ? model['provider_api_key'] : '');
    final providerModelController = TextEditingController(text: isEdit ? model['provider_model'] : '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                isEdit ? "编辑 AI 模型映射" : "新建 AI 模型映射",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDialogTextField("自定义模型名称", nameController, "e.g., my-gpt-4o"),
                      const SizedBox(height: 16),
                      _buildDialogTextField("提供商 Base URL", urlController, "e.g., https://api.openai.com/v1"),
                      const SizedBox(height: 16),
                      _buildDialogTextField("提供商 API Key", keyController, "sk-xxxxxx", obscure: true),
                      const SizedBox(height: 16),
                      _buildDialogTextField("真实提供商 Model 名称", providerModelController, "e.g., gpt-4o"),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("取消"),
                ),
                FilledButton(
                  onPressed: () async {
                    final data = {
                      "custom_name": nameController.text.trim(),
                      "provider_base_url": urlController.text.trim(),
                      "provider_api_key": keyController.text.trim(),
                      "provider_model": providerModelController.text.trim(),
                    };
                    if (isEdit) {
                      await ApiService.updateModel(model['id'], data);
                    } else {
                      await ApiService.createModel(data);
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      _fetchData();
                    }
                  },
                  child: const Text("保存"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showKeyDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("创建网关 API Key", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogTextField("密钥名称 / 用途说明", nameController, "e.g., 个人本地客户端"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("取消"),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  await ApiService.createApiKey(name);
                }
                if (mounted) {
                  Navigator.pop(context);
                  _fetchData();
                }
              },
              child: const Text("创建"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogTextField(String label, TextEditingController controller, String hint, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Uri? currentUri = Uri.tryParse(Uri.base.toString());
    final String serverHost = currentUri != null && currentUri.host.isNotEmpty
        ? "${currentUri.scheme}://${currentUri.host}${currentUri.port != 80 && currentUri.port != 443 ? ':${currentUri.port}' : ''}"
        : ApiService.baseUrl;

    return Scaffold(
      body: Row(
        children: [
          // MD3 NavigationRail for dashboard navigation
          NavigationRail(
            selectedIndex: _activeTab,
            onDestinationSelected: (index) {
              setState(() {
                _activeTab = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            leading: Column(
              children: [
                const SizedBox(height: 16),
                Icon(Icons.dashboard_customize, color: theme.colorScheme.primary, size: 28),
                const SizedBox(height: 24),
              ],
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                        onPressed: () {
                          ThemeController.toggleTheme();
                          setState(() {});
                        },
                        tooltip: "切换主题",
                      ),
                      const SizedBox(height: 12),
                      IconButton(
                        icon: const Icon(Icons.menu_book_outlined, color: Colors.blueGrey),
                        onPressed: () => Navigator.pushNamed(context, '/'),
                        tooltip: "查看使用文档",
                      ),
                      const SizedBox(height: 12),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.redAccent),
                        onPressed: () {
                          ApiService.logout();
                          Navigator.pushReplacementNamed(context, '/');
                        },
                        tooltip: "退出登录",
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics),
                label: Text("使用仪表盘"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.hub_outlined),
                selectedIcon: Icon(Icons.hub),
                label: Text("模型映射"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.key_outlined),
                selectedIcon: Icon(Icons.key),
                label: Text("网关密钥"),
              ),
            ],
          ),

          const VerticalDivider(thickness: 1, width: 1),

          // Main Content Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeTab == 0
                                ? "Token 统计与分析仪表盘"
                                : _activeTab == 1
                                    ? "AI 模型映射管理"
                                    : "网关 API 密钥管理",
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _activeTab == 0
                                ? "监控流量、Token 消耗以及大模型 API 转发的详细使用统计"
                                : _activeTab == 1
                                    ? "在此处配置中转到真实模型厂商的基础地址和参数映射"
                                    : "生成专属中转密钥，配合 Base URL $serverHost/v1 访问 OpenAI 协议接口",
                            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                          ),
                        ],
                      ),
                      if (_activeTab != 0)
                        FilledButton.icon(
                          onPressed: _activeTab == 1 ? () => _showModelDialog() : _showKeyDialog,
                          icon: const Icon(Icons.add),
                          label: Text(_activeTab == 1 ? "新增模型" : "创建密钥"),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Content Body
                  Expanded(
                    child: _isLoading && _activeTab != 0
                        ? const Center(child: CircularProgressIndicator())
                        : _activeTab == 0
                            ? const DashboardView()
                            : _activeTab == 1
                                ? _buildModelsView()
                                : _buildKeysView(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelsView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_models.isEmpty) {
      return Center(
        child: Text("暂无模型映射配置，请点击右上角新增一个", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
      );
    }

    return ListView.builder(
      itemCount: _models.length,
      itemBuilder: (context, index) {
        final m = _models[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            m['custom_name'] ?? '',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildInfoBadge("目标 URL", m['provider_base_url'] ?? ''),
                          _buildInfoBadge("真实模型", m['provider_model'] ?? ''),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _showModelDialog(m),
                  tooltip: "编辑",
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await ApiService.deleteModel(m['id']);
                    _fetchData();
                  },
                  tooltip: "删除",
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoBadge(String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Text(
        "$label: $value",
        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8), fontSize: 12),
      ),
    );
  }

  Widget _buildKeysView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_apiKeys.isEmpty) {
      return Center(
        child: Text("暂无网关密钥，请点击右上角创建", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
      );
    }

    return ListView.builder(
      itemCount: _apiKeys.length,
      itemBuilder: (context, index) {
        final k = _apiKeys[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SelectableText(
                            k['key'] ?? '',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: k['key'] ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("网关密钥已复制到剪贴板"), duration: Duration(seconds: 1)),
                              );
                            },
                            tooltip: "复制密钥",
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await ApiService.deleteApiKey(k['id']);
                    _fetchData();
                  },
                  tooltip: "删除密钥",
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
