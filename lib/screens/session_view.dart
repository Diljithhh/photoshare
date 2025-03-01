import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'dart:math';

// This is the view that handles password authentication and photo display
class SessionView extends StatefulWidget {
  final String sessionId;

  const SessionView({super.key, required this.sessionId});

  @override
  State<SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<SessionView> {
  final TextEditingController _passwordController = TextEditingController();
  String? _accessToken;
  List<String> _photos = [];
  Set<String> _selectedPhotos = {};
  bool _isLoading = false;
  String? _errorMessage;

  // Extract clean session ID in case the full URL was passed
  String get _cleanSessionId {
    final sessionId = widget.sessionId;
    // Check if sessionId is actually a URL
    if (sessionId.contains('/')) {
      final match = RegExp(r'/session/([^/?&#]+)').firstMatch(sessionId);
      if (match != null && match.groupCount >= 1) {
        return match.group(1)!;
      }
    }
    return sessionId;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if we need to add /api/v1 or if it's already in the URL
      final baseUrl =
          dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';
      // Make sure the endpoint format matches what the backend expects
      // final endpoint = '$baseUrl/api/v1/session/${_cleanSessionId}/auth';
// final endpoint = '$baseUrl/session/${_cleanSessionId}/auth';
final endpoint = '$baseUrl/api/v1/session/${_cleanSessionId}/auth';





      print('AUTHENTICATION DEBUG:');
      print('Base URL: $baseUrl');
      print('Endpoint: $endpoint');
      print('Clean Session ID: ${_cleanSessionId}');
      print('Original Session ID: ${widget.sessionId}');

      // Test if the endpoint is accessible
      try {
        final testResponse = await http.get(Uri.parse(baseUrl));
        print('Base URL connection test: ${testResponse.statusCode}');
        if (testResponse.statusCode != 200) {
          print(
              'Base URL test response: ${testResponse.body.substring(0, min(100, testResponse.body.length))}...');
        }
      } catch (e) {
        print('Base URL connection error: $e');
      }

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': _passwordController.text}),
      );

      print('Auth response status: ${response.statusCode}');
      print('Auth response headers: ${response.headers}');

      // Print first part of response body to debug
      final previewLength = min(500, response.body.length);
      print(
          'Auth response preview: ${response.body.substring(0, previewLength)}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          setState(() {
            _accessToken = data['access_token'];
          });
          await _fetchPhotos();
        } catch (jsonError) {
          setState(() {
            _errorMessage =
                'JSON parse error: $jsonError\nResponse: ${response.body.substring(0, min(100, response.body.length))}...';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Authentication failed (${response.statusCode})';
        });
      }
    } catch (e) {
      print('Authentication error: $e');
      setState(() {
        _errorMessage = 'Authentication failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchPhotos() async {
    if (_accessToken == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final baseUrl =
          dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';
      final endpoint = '$baseUrl/api/v1/session/${_cleanSessionId}/photos';

      print('FETCH PHOTOS DEBUG:');
      print('Photos endpoint: $endpoint');
      print('Using access token: ${_accessToken!.substring(0, 10)}...');

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      print('Photos response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          setState(() {
            _photos = List<String>.from(data['photos']);
          });
          print('Fetched ${_photos.length} photos successfully');
        } catch (jsonError) {
          print('Error parsing photos JSON: $jsonError');
          setState(() {
            _errorMessage = 'Failed to parse photos data';
          });
        }
      } else {
        print(
            'Failed to fetch photos: ${response.statusCode} - ${response.body}');
        setState(() {
          _errorMessage = 'Failed to fetch photos (${response.statusCode})';
        });
      }
    } catch (e) {
      print('Error fetching photos: $e');
      setState(() {
        _errorMessage = 'Error loading photos: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSelections() async {
    if (_accessToken == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final baseUrl =
          dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';
      final endpoint = '$baseUrl/api/v1/session/${_cleanSessionId}/select';

      print('SAVE SELECTIONS DEBUG:');
      print('Save endpoint: $endpoint');
      print('Saving ${_selectedPhotos.length} photos');

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'selected_urls': _selectedPhotos.toList(),
        }),
      );

      print('Save response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selections saved successfully')),
        );
      } else {
        print(
            'Failed to save selections: ${response.statusCode} - ${response.body}');
        setState(() {
          _errorMessage = 'Failed to save selections (${response.statusCode})';
        });
      }
    } catch (e) {
      print('Error saving selections: $e');
      setState(() {
        _errorMessage = 'Error saving selections: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildAuthenticationView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Enter Password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onSubmitted: (_) => _authenticate(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _authenticate,
            child: _isLoading
                ? const CircularProgressIndicator()
                : const Text('View Photos'),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return Column(
      children: [
        Expanded(
          child: MasonryGridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final isSelected = _selectedPhotos.contains(photo);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedPhotos.remove(photo);
                    } else {
                      _selectedPhotos.add(photo);
                    }
                  });
                },
                child: Stack(
                  children: [
                    Image.network(
                      photo,
                      fit: BoxFit.cover,
                    ),
                    if (isSelected)
                      Positioned.fill(
                        child: Container(
                          color: Colors.blue.withOpacity(0.3),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Text('${_selectedPhotos.length} photos selected'),
              const Spacer(),
              ElevatedButton(
                onPressed: _selectedPhotos.isEmpty ? null : _saveSelections,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Save Selections'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Photos'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body:
          _accessToken == null ? _buildAuthenticationView() : _buildPhotoGrid(),
    );
  }
}
