// Add this model class for session response
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:photoshare/utils/utils.dart';
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
    return SessionResponse(
      sessionId: json['session_id'],
      sessionLink: json['session_link'],
      password: json['password'],
    );
  }
}

// Add this function to create a session after upload
Future<SessionResponse> createSession(String eventId, List<String> photoUrls) async {
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
      throw Exception('Failed to create session: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    print('Error creating session: $e');
    rethrow;
  }
}
