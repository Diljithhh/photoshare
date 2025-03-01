// Add this model class for session response
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:photoshare/utils/utils.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SessionResponse {
  final String sessionId;
  final String sessionLink;
  final String password;

  SessionResponse({
    required this.sessionId,
    required this.sessionLink,
    required this.password,
  });

  factory SessionResponse.fromJson(Map<String, dynamic> json) {
    String sessionLink = json['session_link'] as String;
    String sessionId = json['session_id'] as String;

    // Fix the session link if it's using the backend URL
    if (sessionLink.contains('photoshare-dn8f.onrender.com')) {
      final frontendUrl =
          dotenv.env['FRONTEND_URL'] ?? 'https://photo-share-app-id.web.app';
      sessionLink = '$frontendUrl/session/$sessionId';
    }

    return SessionResponse(
      sessionId: sessionId,
      sessionLink: sessionLink,
      password: json['password'],
    );
  }
}

// Add this function to create a session after upload
Future<SessionResponse> createSession(
    String eventId, List<String> photoUrls) async {
  try {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/v1/session/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'event_id': eventId,
        'photo_urls': photoUrls,
      }),
    );

    if (response.statusCode == 200) {
      return SessionResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(
          'Failed to create session: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    print('Error creating session: $e');
    rethrow;
  }
}
