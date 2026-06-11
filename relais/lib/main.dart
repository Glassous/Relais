import 'package:flutter/material.dart';
import 'login_page.dart';
import 'admin_page.dart';
import 'docs_page.dart';
import 'api_service.dart';

// Global Theme controller for light/dark mode
class ThemeController {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);

  static void toggleTheme() {
    themeMode.value = themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, mode, child) {
        return MaterialApp(
          title: 'Relais Workspace',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          // Light Monochromatic Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              secondary: Colors.black87,
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              background: Color(0xFFF8F9FA),
              onBackground: Colors.black,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8F9FA),
            cardTheme: const CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
            ),
            fontFamily: 'Roboto',
          ),
          // Dark Monochromatic Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              secondary: Colors.white70,
              onSecondary: Colors.black,
              surface: Color(0xFF121212),
              onSurface: Colors.white,
              background: Color(0xFF0A0A0A),
              onBackground: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF0A0A0A),
            cardTheme: const CardThemeData(
              color: Color(0xFF161616),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF121212),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            fontFamily: 'Roboto',
          ),
          initialRoute: '/',
          routes: {
            '/': (context) => const InitialDispatcher(),
            '/login': (context) => const LoginPage(),
            '/admin': (context) => const ProtectedAdminRoute(),
          },
        );
      },
    );
  }
}

// Automatically dispatches based on login state
class InitialDispatcher extends StatelessWidget {
  const InitialDispatcher({super.key});

  @override
  Widget build(BuildContext context) {
    if (ApiService.token != null) {
      return const AdminPage();
    } else {
      return const DocsPage();
    }
  }
}

class ProtectedAdminRoute extends StatelessWidget {
  const ProtectedAdminRoute({super.key});

  @override
  Widget build(BuildContext context) {
    // Basic route guard
    if (ApiService.token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }
    return const AdminPage();
  }
}
