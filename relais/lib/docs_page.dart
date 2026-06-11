import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'api_service.dart';

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  int _activeTab = 0; // 0: API中转, 1: 镜像下载

  @override
  void initState() {
    super.initState();
    // 未登录时仅允许查看下载镜像站说明，默认选中它
    _activeTab = ApiService.token != null ? 0 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLoggedIn = ApiService.token != null;

    // Get current host from browser URL (fallback to localhost if running locally or not in web)
    final Uri? currentUri = Uri.tryParse(Uri.base.toString());
    final String serverHost = currentUri != null && currentUri.host.isNotEmpty
        ? "${currentUri.scheme}://${currentUri.host}${currentUri.port != 80 && currentUri.port != 443 ? ':${currentUri.port}' : ''}"
        : ApiService.baseUrl;

    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.menu_book_outlined, color: theme.colorScheme.primary, size: isMobile ? 24 : 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isMobile ? "Relais 文档" : "Relais 文档与中转服务中心",
                style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () {
              ThemeController.toggleTheme();
              setState(() {});
            },
            tooltip: "切换主题",
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              if (ApiService.token != null) {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacementNamed(context, '/admin');
                }
              } else {
                Navigator.pushNamed(context, '/login');
              }
            },
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: Text(ApiService.token != null ? "管理后台" : "登录后台"),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          SizedBox(width: isMobile ? 8 : 16),
        ],
      ),
      bottomNavigationBar: isMobile && isLoggedIn
          ? NavigationBar(
              selectedIndex: _activeTab,
              onDestinationSelected: (index) {
                setState(() {
                  _activeTab = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.api_outlined),
                  label: "API 中转",
                ),
                NavigationDestination(
                  icon: Icon(Icons.download_for_offline_outlined),
                  label: "镜像下载",
                ),
              ],
            )
          : null,
      body: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 16 : 32,
        ),
        child: isMobile
            ? Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
                  child: SingleChildScrollView(
                    child: _activeTab == 0
                        ? _buildApiTransitDocs(theme, isDark, serverHost)
                        : _buildMirrorDocs(theme, isDark, serverHost),
                  ),
                ),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sidebar Navigation
                  SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isLoggedIn) ...[
                          _buildSidebarButton(0, Icons.api_outlined, "API 中转服务"),
                          const SizedBox(height: 12),
                        ],
                        _buildSidebarButton(1, Icons.download_for_offline_outlined, "镜像下载站"),
                      ],
                    ),
                  ),
                  const SizedBox(width: 40),
                  // Content Area
                  Expanded(
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: SingleChildScrollView(
                          child: _activeTab == 0
                              ? _buildApiTransitDocs(theme, isDark, serverHost)
                              : _buildMirrorDocs(theme, isDark, serverHost),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSidebarButton(int tabIndex, IconData icon, String title) {
    final theme = Theme.of(context);
    final isSelected = _activeTab == tabIndex;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _activeTab = tabIndex),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : (isDark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? (isDark ? Colors.black : Colors.white)
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiTransitDocs(ThemeData theme, bool isDark, String serverHost) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "API 中转服务说明",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          "本服务提供高可用、透明的 OpenAI 兼容 API 中转。您可以在管理后台配置各种第三方 AI 大模型厂商映射，并分配独立的“网关密钥”，实现在各种开发工具中的自定义模型接入。",
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.6),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle(Icons.dns_outlined, "中转 Base URL"),
        const SizedBox(height: 8),
        _buildCopyableField("$serverHost/v1"),
        const SizedBox(height: 24),
        _buildSectionTitle(Icons.terminal_outlined, "在 OpenCode 中配置自定义模型"),
        const SizedBox(height: 12),
        Text(
          "OpenCode 是一个强大的终端 AI 编程助手。您可以通过修改全局配置文件 ~/.config/opencode/opencode.json（或当前项目根目录下的 opencode.json），将模型请求导流至本中转站：",
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.5),
        ),
        const SizedBox(height: 16),
        _buildCodeBlock(
          "{\n"
          "  \"\$schema\": \"https://opencode.ai/config.json\",\n"
          "  \"provider\": {\n"
          "    \"relais-custom\": {\n"
          "      \"npm\": \"@ai-sdk/openai-compatible\",\n"
          "      \"name\": \"Relais Proxy Model\",\n"
          "      \"options\": {\n"
          "        \"baseURL\": \"$serverHost/v1\"\n"
          "      },\n"
          "      \"models\": {\n"
          "        \"your-custom-model-name\": {\n"
          "          \"name\": \"自定义中转模型\"\n"
          "        }\n"
          "      }\n"
          "    }\n"
          "  }\n"
          "}",
        ),
        const SizedBox(height: 20),
        _buildStepItem(1, "登录后台系统，在“模型映射”菜单中配置您的自定义模型，并将目标 URL 与密钥映射至真实的模型供应商（如 DeepSeek-R1、GPT-4o）。"),
        _buildStepItem(2, "在“网关密钥”中创建一个专属的 API 密钥（如 wk-xxxx）。"),
        _buildStepItem(3, "在终端中运行 OpenCode `/connect` 命令，选择 `relais-custom` 服务商并粘贴您刚刚生成的 `wk-xxxx` 密钥，即可开始使用。"),
      ],
    );
  }

  Widget _buildMirrorDocs(ThemeData theme, bool isDark, String serverHost) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "透明镜像下载站",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          "专为网络受限环境下的开发人员设计，本站提供常用开发包管理器与 GitHub 资源的透明加速代理，无需单独配置复杂的翻墙环境即可实现高速包下载。",
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.6),
        ),
        const SizedBox(height: 28),

        // GitHub Mirror
        _buildMirrorSection(
          Icons.code_outlined,
          "1. GitHub 文件及 Release 代理",
          "用于加速下载 GitHub 的发布包（Release）、源码压缩包（Archive）以及原始文本文件（Raw）。",
          "$serverHost/mirror/gh?url=https://github.com/cli/cli/releases/download/v2.40.0/gh_2.40.0_linux_amd64.tar.gz\n\n"
          "# 或者直接作为路径前缀拼接：\n"
          "$serverHost/mirror/gh/https://github.com/cli/cli/releases/download/v2.40.0/gh_2.40.0_linux_amd64.tar.gz",
        ),
        const Divider(height: 40),

        // Flutter Pub Mirror
        _buildMirrorSection(
          Icons.flutter_dash_outlined,
          "2. Dart Pub 镜像代理",
          "修改环境变量 `PUB_HOSTED_URL`，以加速 Flutter 和 Dart 包的拉取。",
          "# 终端临时配置 / Linux / macOS 写入 ~/.bashrc :\n"
          "export PUB_HOSTED_URL=$serverHost/mirror/pub\n\n"
          "# Windows PowerShell 配置 :\n"
          "\$env:PUB_HOSTED_URL=\"$serverHost/mirror/pub\"",
        ),
        const Divider(height: 40),

        // NPM Mirror
        _buildMirrorSection(
          Icons.javascript_outlined,
          "3. NPM Registry 镜像代理",
          "将 NPM 镜像源重定向到本中转，加速前端开发依赖的安装。",
          "# 全局修改 npm 源配置\n"
          "npm config set registry $serverHost/mirror/npm\n\n"
          "# 临时使用本镜像安装某包\n"
          "npm install express --registry=$serverHost/mirror/npm",
        ),
        const Divider(height: 40),

        // Pip Mirror
        _buildMirrorSection(
          Icons.terminal_outlined,
          "4. Python Pip 镜像代理",
          "代理 Python PyPI 官方包管理器依赖下载。",
          "# 使用 pip 临时加速安装包（其中 ${Uri.parse(serverHost).host} 为您当前的服务器 IP）\n"
          "pip install numpy -i $serverHost/mirror/pypi/simple --trusted-host ${Uri.parse(serverHost).host}\n\n"
          "# 设为全局默认源\n"
          "pip config set global.index-url $serverHost/mirror/pypi/simple\n"
          "pip config set global.trusted-host ${Uri.parse(serverHost).host}",
        ),
      ],
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCopyableField(String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("已复制到剪贴板")),
              );
            },
            tooltip: "复制",
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(int step, String description) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              "$step",
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String code) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF181818) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: SelectableText(
            code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("代码已复制到剪贴板")),
              );
            },
            tooltip: "复制配置代码",
          ),
        ),
      ],
    );
  }

  Widget _buildMirrorSection(IconData icon, String title, String desc, String code) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(icon, title),
        const SizedBox(height: 8),
        Text(
          desc,
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildCodeBlock(code),
      ],
    );
  }
}
