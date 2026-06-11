import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String baseUrl = "https://relais.glassous.top";
  static String? token;

  static const String _tokenKey = "relais_token";
  static const String _urlKey = "relais_base_url";

  static Map<String, String> get _headers {
    final headers = {
      "Content-Type": "application/json",
    };
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }

  // Load persisted token and base URL
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
    baseUrl = prefs.getString(_urlKey) ?? "https://relais.glassous.top";
  }

  static Future<void> saveSession(String newToken, String newUrl) async {
    token = newToken;
    baseUrl = newUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, newToken);
    await prefs.setString(_urlKey, newUrl);
  }

  // Auth
  static Future<bool> login(String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"password": password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newToken = data["token"];
        await saveSession(newToken, baseUrl);
        return true;
      }
    } catch (e) {
      print("Login error: $e");
    }
    return false;
  }

  static void logout() {
    token = null;
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_tokenKey);
    });
  }

  // Model Config CRUD
  static Future<List<dynamic>> getModels() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/models"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Get models error: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createModel(Map<String, dynamic> modelData) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/admin/models"),
        headers: _headers,
        body: jsonEncode(modelData),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Create model error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> updateModel(String id, Map<String, dynamic> modelData) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/api/admin/models/$id"),
        headers: _headers,
        body: jsonEncode(modelData),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Update model error: $e");
    }
    return null;
  }

  static Future<bool> deleteModel(String id) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/api/admin/models/$id"),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Delete model error: $e");
    }
    return false;
  }

  // Fetch Kilo Models proxied through backend
  static Future<List<dynamic>> getKiloModels() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/kilo/models"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded["data"] is List) {
          return decoded["data"];
        }
        if (decoded is List) {
          return decoded;
        }
      }
    } catch (e) {
      print("Get Kilo models error: $e");
    }
    return [];
  }

  // Workspace API Keys CRUD
  static Future<List<dynamic>> getApiKeys() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/keys"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Get api keys error: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createApiKey(String name) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/admin/keys"),
        headers: _headers,
        body: jsonEncode({"name": name}),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Create api key error: $e");
    }
    return null;
  }

  static Future<bool> deleteApiKey(String id) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/api/admin/keys/$id"),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Delete api key error: $e");
    }
    return false;
  }

  // Get Dashboard Stats
  static Future<Map<String, dynamic>?> getDashboardStats() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/stats"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Get dashboard stats error: $e");
    }
    return null;
  }
}
