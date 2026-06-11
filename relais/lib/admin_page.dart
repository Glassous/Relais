import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'main.dart';
import 'dashboard_view.dart';
import 'rss_reader_view.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _activeTab = 0; // 0: Dashboard, 1: Models, 2: API Keys, 3: RSS Reader
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
    final isEdit = model != null && model['id'] != null;

    // Get unique base URLs and their corresponding API keys from _models
    final Map<String, String> baseUrlToKey = {};
    for (var m in _models) {
      final String? url = m['provider_base_url'];
      final String? key = m['provider_api_key'];
      if (url != null && url.isNotEmpty) {
        if (!baseUrlToKey.containsKey(url) || (key != null && key.isNotEmpty)) {
          baseUrlToKey[url] = key ?? '';
        }
      }
    }

    final String initialUrl = model != null ? (model['provider_base_url'] ?? '') : '';
    String initialKey = model != null ? (model['provider_api_key'] ?? '') : '';
    // If the template/provided model has a base URL but no key, look up if we have a key for this URL already
    if (initialKey.isEmpty && initialUrl.isNotEmpty && baseUrlToKey.containsKey(initialUrl)) {
      initialKey = baseUrlToKey[initialUrl]!;
    }

    final nameController = TextEditingController(text: model != null ? model['custom_name'] : '');
    final urlController = TextEditingController(text: initialUrl);
    final keyController = TextEditingController(text: initialKey);
    final providerModelController = TextEditingController(text: model != null ? model['provider_model'] : '');

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
                      _buildDialogTextField(
                        "提供商 Base URL",
                        urlController,
                        "e.g., https://api.openai.com/v1",
                        suffixIcon: baseUrlToKey.isNotEmpty
                            ? PopupMenuButton<String>(
                                icon: const Icon(Icons.arrow_drop_down),
                                onSelected: (String value) {
                                  urlController.text = value;
                                  if (baseUrlToKey[value] != null) {
                                    keyController.text = baseUrlToKey[value]!;
                                  }
                                  setModalState(() {});
                                },
                                itemBuilder: (BuildContext context) {
                                  return baseUrlToKey.keys.map<PopupMenuItem<String>>((String url) {
                                    return PopupMenuItem<String>(
                                      value: url,
                                      child: Text(
                                        url,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }).toList();
                                },
                              )
                            : null,
                      ),
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

  Widget _buildDialogTextField(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    Widget? suffixIcon,
  }) {
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
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }

  void _showProviderSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("选择模型提供商", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_queue_outlined, color: Colors.blue),
                  title: const Text("Kilo Code", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("提供高性价比的多种主流模型及免费模型"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () {
                    Navigator.pop(context);
                    _showKiloModelsDialog();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("取消"),
            ),
          ],
        );
      },
    );
  }

  void _showKiloModelsDialog() {
    List<dynamic> kiloModels = [];
    bool isFetching = true;
    String errorMessage = '';
    final Map<String, bool> expandedStates = {};

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            String getProviderName(Map<String, dynamic> m) {
              final name = m['name'] as String? ?? '';
              if (name.contains(':')) {
                return name.split(':').first.trim();
              }
              final id = m['id'] as String? ?? '';
              if (id.contains('/')) {
                final first = id.split('/').first;
                if (first == 'kilo-auto') return 'Kilo Auto';
                return first.substring(0, 1).toUpperCase() + first.substring(1);
              }
              return '其他';
            }

            // Initiate fetch on first build
            if (isFetching && kiloModels.isEmpty && errorMessage.isEmpty) {
              ApiService.getKiloModels().then((models) {
                setModalState(() {
                  kiloModels = models;
                  isFetching = false;

                  // Initialize first group as expanded, others as collapsed
                  final Set<String> providers = {};
                  for (var m in models) {
                    providers.add(getProviderName(m));
                  }
                  for (int i = 0; i < providers.length; i++) {
                    expandedStates[providers.elementAt(i)] = (i == 0);
                  }
                });
              }).catchError((err) {
                setModalState(() {
                  errorMessage = err.toString();
                  isFetching = false;
                });
              });
            }

            final Map<String, List<dynamic>> groupedModels = {};
            if (!isFetching && errorMessage.isEmpty && kiloModels.isNotEmpty) {
              for (var m in kiloModels) {
                final provider = getProviderName(m);
                groupedModels.putIfAbsent(provider, () => []).add(m);
              }
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.hub_outlined, color: Colors.blue),
                  SizedBox(width: 8),
                  Text("Kilo Code 快捷选择", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 500,
                child: isFetching
                    ? const Center(child: CircularProgressIndicator())
                    : errorMessage.isNotEmpty
                        ? Center(child: Text("加载失败: $errorMessage"))
                        : kiloModels.isEmpty
                            ? const Center(child: Text("未找到可用模型"))
                            : CustomScrollView(
                                slivers: [
                                  for (final provider in groupedModels.keys) ...[
                                    SliverPersistentHeader(
                                      pinned: expandedStates[provider] ?? false,
                                      delegate: ProviderHeaderDelegate(
                                        providerName: provider,
                                        count: groupedModels[provider]!.length,
                                        isExpanded: expandedStates[provider] ?? false,
                                        onTap: () {
                                          setModalState(() {
                                            final bool wasExpanded = expandedStates[provider] ?? false;
                                            if (!wasExpanded) {
                                              // Collapse all others
                                              expandedStates.updateAll((key, value) => false);
                                            }
                                            expandedStates[provider] = !wasExpanded;
                                          });
                                        },
                                      ),
                                    ),
                                    if (expandedStates[provider] ?? false)
                                      SliverList(
                                        delegate: SliverChildListDelegate(
                                          groupedModels[provider]!.map<Widget>((m) {
                                            final id = m['id'] ?? '';
                                            final name = m['name'] ?? '';
                                            final desc = m['description'] ?? '';
                                            final isFree = m['isFree'] == true;

                                            // Pricing info
                                            String pricingStr = "";
                                            final pricing = m['pricing'];
                                            if (isFree) {
                                              pricingStr = "免费";
                                            } else if (pricing != null) {
                                              final prompt = pricing['prompt'];
                                              final comp = pricing['completion'];
                                              if (prompt != null && comp != null) {
                                                double promptD = double.tryParse(prompt.toString()) ?? 0.0;
                                                double compD = double.tryParse(comp.toString()) ?? 0.0;
                                                pricingStr = "输入: \$${(promptD * 1000000).toStringAsFixed(2)}/M | 输出: \$${(compD * 1000000).toStringAsFixed(2)}/M";
                                              }
                                            }

                                            return Card(
                                              margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8, top: 4),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                                side: BorderSide(
                                                  color: isFree
                                                      ? Colors.green.withOpacity(0.3)
                                                      : Colors.grey.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(12.0),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            name,
                                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                          ),
                                                        ),
                                                        if (isFree)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                            decoration: BoxDecoration(
                                                              color: Colors.green.withOpacity(0.1),
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            child: const Text(
                                                              "FREE",
                                                              style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "ID: $id",
                                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey),
                                                    ),
                                                    if (desc.isNotEmpty) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        desc,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                                                      ),
                                                    ],
                                                    if (pricingStr.isNotEmpty) ...[
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        pricingStr,
                                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    Align(
                                                      alignment: Alignment.centerRight,
                                                      child: OutlinedButton.icon(
                                                        onPressed: () {
                                                          Clipboard.setData(ClipboardData(text: id));
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: Text("已复制模型 ID: $id"),
                                                              duration: const Duration(seconds: 1),
                                                            ),
                                                          );
                                                        },
                                                        icon: const Icon(Icons.copy, size: 14),
                                                        label: const Text("复制 ID"),
                                                        style: OutlinedButton.styleFrom(
                                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                  ]
                                ],
                              ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("返回"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 768;

    final Uri? currentUri = Uri.tryParse(Uri.base.toString());
    final String serverHost = currentUri != null && currentUri.host.isNotEmpty
        ? "${currentUri.scheme}://${currentUri.host}${currentUri.port != 80 && currentUri.port != 443 ? ':${currentUri.port}' : ''}"
        : ApiService.baseUrl;

    final Widget contentBody = Padding(
      padding: _activeTab == 3
          ? EdgeInsets.only(
              left: isMobile ? 16.0 : 40.0,
              right: isMobile ? 16.0 : 40.0,
              top: isMobile ? 16.0 : 40.0,
              bottom: 0,
            )
          : EdgeInsets.all(isMobile ? 16.0 : 40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (only for non-RSS tabs)
          if (_activeTab != 3) ...[
            isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeTab == 0
                            ? "Token 统计与分析仪表盘"
                            : _activeTab == 1
                                ? "AI 模型映射管理"
                                : "网关 API 密钥管理",
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _activeTab == 0
                            ? "监控流量、Token 消耗以及大模型 API 转发的详细使用统计"
                            : _activeTab == 1
                                ? "在此处配置中转到真实模型厂商的基础地址和参数映射"
                                : "生成专属中转密钥，配合 Base URL $serverHost/v1 访问 OpenAI 协议接口",
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
                      ),
                      if (_activeTab == 1 || _activeTab == 2) ...[
                        const SizedBox(height: 16),
                        if (_activeTab == 1) ...[
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _showModelDialog(),
                                  icon: const Icon(Icons.add),
                                  label: const Text("新增模型"),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showProviderSelectionDialog(),
                                  icon: const Icon(Icons.list_alt_outlined),
                                  label: const Text("推荐模型"),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _showKeyDialog,
                              icon: const Icon(Icons.add),
                              label: const Text("创建密钥"),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  )
                : Row(
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
                      if (_activeTab == 1 || _activeTab == 2)
                        Row(
                          children: [
                            if (_activeTab == 1) ...[
                              OutlinedButton.icon(
                                onPressed: () => _showProviderSelectionDialog(),
                                icon: const Icon(Icons.list_alt_outlined),
                                label: const Text("推荐模型列表"),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
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
                    ],
                  ),
            SizedBox(height: isMobile ? 20 : 32),
          ],

          // Content Body
          Expanded(
            child: _isLoading && _activeTab != 0
                ? const Center(child: CircularProgressIndicator())
                : _activeTab == 0
                    ? const DashboardView()
                    : _activeTab == 1
                        ? _buildModelsView()
                        : _activeTab == 2
                            ? _buildKeysView()
                            : const RssReaderView(),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              title: const Text("Relais 管理", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              actions: [
                IconButton(
                  icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  onPressed: () {
                    ThemeController.toggleTheme();
                    setState(() {});
                  },
                  tooltip: "切换主题",
                ),
                IconButton(
                  icon: const Icon(Icons.menu_book_outlined, color: Colors.blueGrey),
                  onPressed: () => Navigator.pushNamed(context, '/docs'),
                  tooltip: "查看使用文档",
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  onPressed: () {
                    ApiService.logout();
                    Navigator.pushReplacementNamed(context, '/');
                  },
                  tooltip: "退出登录",
                ),
              ],
            )
          : null,
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: _activeTab,
              onDestinationSelected: (index) {
                setState(() {
                  _activeTab = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.analytics_outlined),
                  selectedIcon: Icon(Icons.analytics),
                  label: "仪表盘",
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: "模型映射",
                ),
                NavigationDestination(
                  icon: Icon(Icons.key_outlined),
                  selectedIcon: Icon(Icons.key),
                  label: "网关密钥",
                ),
                NavigationDestination(
                  icon: Icon(Icons.newspaper_outlined),
                  selectedIcon: Icon(Icons.newspaper),
                  label: "AI新闻",
                ),
              ],
            )
          : null,
      body: isMobile
          ? contentBody
          : Row(
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
                              onPressed: () => Navigator.pushNamed(context, '/docs'),
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
                    NavigationRailDestination(
                      icon: Icon(Icons.newspaper_outlined),
                      selectedIcon: Icon(Icons.newspaper),
                      label: Text("AI新闻"),
                    ),
                  ],
                ),

                const VerticalDivider(thickness: 1, width: 1),

                // Main Content Area
                Expanded(
                  child: contentBody,
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

class ProviderHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String providerName;
  final int count;
  final bool isExpanded;
  final VoidCallback onTap;

  ProviderHeaderDelegate({
    required this.providerName,
    required this.count,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: theme.colorScheme.surface,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          providerName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "共 $count 个模型",
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 56.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant ProviderHeaderDelegate oldDelegate) {
    return oldDelegate.providerName != providerName ||
        oldDelegate.count != count ||
        oldDelegate.isExpanded != isExpanded;
  }
}
