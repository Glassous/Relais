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

  // RSS Feeds CRUD
  static Future<List<dynamic>> getRssFeeds() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/api/admin/rss/feeds"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Get RSS feeds error: $e");
    }
    return [];
  }

  static Future<Map<String, dynamic>?> createRssFeed(Map<String, dynamic> feedData) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/admin/rss/feeds"),
        headers: _headers,
        body: jsonEncode(feedData),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Create RSS feed error: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> updateRssFeed(String id, Map<String, dynamic> feedData) async {
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/api/admin/rss/feeds/$id"),
        headers: _headers,
        body: jsonEncode(feedData),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Update RSS feed error: $e");
    }
    return null;
  }

  static Future<bool> deleteRssFeed(String id) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/api/admin/rss/feeds/$id"),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Delete RSS feed error: $e");
    }
    return false;
  }

  static Future<bool> triggerScrape(String id, {String? modelId}) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/api/admin/rss/feeds/$id/scrape"),
        headers: _headers,
        body: modelId != null ? jsonEncode({"model_id": modelId}) : null,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Trigger scrape error: $e");
    }
    return false;
  }

  static Stream<String> triggerScrapeStream(String id, {String? modelId}) async* {
    final client = http.Client();
    try {
      String url = "$baseUrl/api/admin/rss/feeds/$id/scrape-stream";
      if (modelId != null && modelId.isNotEmpty) {
        url += "?model_id=$modelId";
      }
      final request = http.Request("GET", Uri.parse(url));
      request.headers.addAll(_headers);

      final response = await client.send(request);
      if (response.statusCode == 200) {
        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          yield line;
        }
      } else {
        yield "error: Status code ${response.statusCode}";
      }
    } catch (e) {
      yield "error: $e";
    } finally {
      client.close();
    }
  }

  // RSS Articles
  static Future<List<dynamic>> getRssArticles({String? feedId}) async {
    try {
      String url = "$baseUrl/api/admin/rss/articles";
      if (feedId != null && feedId.isNotEmpty) {
        url += "?feed_id=$feedId";
      }
      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Get RSS articles error: $e");
    }
    return [];
  }

  static Future<bool> deleteRssArticle(String id) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/api/admin/rss/articles/$id"),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Delete RSS article error: $e");
    }
    return false;
  }

  static Future<bool> clearAllRssArticles() async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/api/admin/rss/articles"),
        headers: _headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Clear all RSS articles error: $e");
    }
    return false;
  }
}
