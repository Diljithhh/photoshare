import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Run this directly to test authentication without the main app
void main() {
  runApp(const AuthTesterApp());
}

class AuthTesterApp extends StatelessWidget {
  const AuthTesterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auth Tester',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthTesterScreen(),
    );
  }
}

class AuthTesterScreen extends StatefulWidget {
  const AuthTesterScreen({Key? key}) : super(key: key);

  @override
  _AuthTesterScreenState createState() => _AuthTesterScreenState();
}

class _AuthTesterScreenState extends State<AuthTesterScreen> {
  final TextEditingController _sessionIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _result = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Use the session ID from your error message
    _sessionIdController.text = '7871bb84-c93e-4036-b73d-8982a0fa417b';
    // Use a simple test password
    _passwordController.text = 'test123';
  }

  @override
  void dispose() {
    _sessionIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _testAuth() async {
    setState(() {
      _isLoading = true;
      _result = 'Testing...';
    });

    try {
      final baseUrl = 'https://photoshare-dn8f.onrender.com';
      final sessionId = _sessionIdController.text;
      final password = _passwordController.text;
      final endpoint = '$baseUrl/api/v1/session/$sessionId/auth';

      print('Testing auth with:');
      print('Endpoint: $endpoint');
      print('Password: $password');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      );

      setState(() {
        _result = 'Status: ${response.statusCode}\n'
            'Headers: ${response.headers}\n'
            'Body: ${response.body}';
      });
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Authentication Tester')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _sessionIdController,
              decoration: const InputDecoration(
                labelText: 'Session ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testAuth,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Test Authentication'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black12,
                  child: SelectableText(_result),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
