import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

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
      final response = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/session/${widget.sessionId}/auth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': _passwordController.text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _accessToken = data['access_token'];
        });
        await _fetchPhotos();
      } else {
        setState(() {
          _errorMessage = 'Invalid password';
        });
      }
    } catch (e) {
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
      final response = await http.get(
        Uri.parse(
            '${dotenv.env['API_URL']}/session/${widget.sessionId}/photos'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _photos = List<String>.from(data['photos']);
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to fetch photos';
        });
      }
    } catch (e) {
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
      final response = await http.post(
        Uri.parse(
            '${dotenv.env['API_URL']}/session/${widget.sessionId}/select'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'selected_urls': _selectedPhotos.toList(),
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selections saved successfully')),
        );
      } else {
        setState(() {
          _errorMessage = 'Failed to save selections';
        });
      }
    } catch (e) {
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
