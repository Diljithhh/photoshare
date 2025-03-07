import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  final String _apiBaseUrl = dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';

  Future<String> authenticate(String sessionId, String password) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/v1/session/$sessionId/auth'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['access_token'];
    } else {
      throw Exception('Authentication failed');
    }
  }

  Future<List<String>> fetchPhotos(String sessionId, String accessToken) async {
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/api/v1/session/$sessionId/photos'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['photos']);
    } else {
      throw Exception('Failed to fetch photos');
    }
  }

  Future<void> saveSelections(String sessionId, String accessToken, List<String> selectedPhotos) async {
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/v1/session/$sessionId/select'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'selected_urls': selectedPhotos}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to save selections');
    }
  }

  String transformImageUrl(String originalUrl) {
    // Implement the logic to transform URLs if needed
    return originalUrl;
  }
}
