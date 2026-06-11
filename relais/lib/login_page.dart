import 'package:flutter/material.dart';
import 'api_service.dart';
import 'main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _serverController = TextEditingController(text: ApiService.baseUrl);
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    final password = _passwordController.text.trim();
    final serverUrl = _serverController.text.trim();

    if (password.isEmpty) {
      setState(() {
        _errorMessage = "请输入密码";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    ApiService.baseUrl = serverUrl;

    final success = await ApiService.login(password);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (success) {
      Navigator.pushReplacementNamed(context, '/');
    } else {
      setState(() {
        _errorMessage = "密码错误或无法连接到服务器";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () {
              ThemeController.toggleTheme();
              setState(() {});
            },
            tooltip: "切换深浅色模式",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(36.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Logo / Icon (Monochrome styling)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                        ),
                        child: Icon(
                          Icons.dashboard_customize_outlined,
                          size: 36,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "RELAIS",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "个人自部署工作区管理面板",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Server URL Input
                    TextField(
                      controller: _serverController,
                      decoration: const InputDecoration(
                        labelText: "服务器地址",
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password Input
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      onSubmitted: (_) => _handleLogin(),
                      decoration: const InputDecoration(
                        labelText: "访问密码",
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Login Button (MD3 FilledButton)
                    FilledButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.black : Colors.white),
                              ),
                            )
                          : const Text(
                              "验证登录",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),

                    const SizedBox(height: 20),
                    // Mirror Station Link (MD3 OutlinedButton)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/');
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        side: BorderSide(
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "返回使用文档中心 ←",
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
