import 'dart:convert';
import 'package:http/http.dart' as http;

// Run this function from a main.dart temporary entry point to test authentication
Future<void> testAuthentication() async {
  final baseUrl = 'https://photoshare-dn8f.onrender.com';
  final sessionId =
      '7871bb84-c93e-4036-b73d-8982a0fa417b'; // Use the session ID from error
  final endpoint = '$baseUrl/api/v1/session/$sessionId/auth';

  // Try a simple test password
  const testPassword = 'test123';

  print('DEBUG TEST AUTH:');
  print('Endpoint: $endpoint');
  print('Test password: $testPassword');

  try {
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': testPassword}),
    );

    print('Response status: ${response.statusCode}');
    print('Response headers: ${response.headers}');
    print('Response body: ${response.body}');
  } catch (e) {
    print('Error testing authentication: $e');
  }
}
