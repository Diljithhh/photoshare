import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:developer' as dev;

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
  bool _isProduction = true; // Default to production mode
  bool _useImageProxy = true; // Whether to use backend proxy for images

  // Environment URLs
  // For actual devices, use your computer's local network IP instead of localhost
  final String _localApiUrl = '10.0.2.2:8000'; // For Android emulator
  final String _productionApiUrl =
      dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';

  // Get current API URL based on environment
  String get _apiBaseUrl {
    if (_isProduction) {
      return _productionApiUrl;
    } else {
      // Handle different platforms for local development
      if (kIsWeb) {
        return 'http://localhost:8000';
      } else if (Platform.isAndroid) {
        return 'http://$_localApiUrl'; // Use 10.0.2.2 for Android emulator
      } else if (Platform.isIOS) {
        return 'http://localhost:8000'; // For iOS simulator
      } else {
        return 'http://$_localApiUrl';
      }
    }
  }

  // Use this to transform an S3 URL to a proxied URL that goes through the backend
  String _transformImageUrl(String originalUrl) {
    // Check if the URL is null or empty
    if (originalUrl.isEmpty) {
      dev.log('Empty URL provided to _transformImageUrl');
      return originalUrl;
    }

    // Log URL for debugging
    dev.log(
        'Processing URL: ${originalUrl.substring(0, min(50, originalUrl.length))}...');

    try {
      final Uri uri = Uri.parse(originalUrl);
      final bool isS3Url =
          uri.host.contains('.s3.') || uri.host.contains('s3.amazonaws.com');

      // If we're in development and using the proxy
      if (!_isProduction && _useImageProxy) {
        // Handle both s3.amazonaws.com and s3.ap-south-1.amazonaws.com formats
        if (isS3Url) {
          final path = uri.path;

          // We need to encode the key for use in a query parameter
          final encodedKey = Uri.encodeComponent(path);
          // Return a URL that proxies through our backend
          return '$_apiBaseUrl/api/v1/proxy-image?url=$encodedKey';
        }
      }

      // For production S3 URLs: Use direct-access endpoint to avoid CORS issues
      if (_isProduction && isS3Url) {
        // Check if this is a presigned URL
        final bool isPresignedUrl =
            uri.queryParameters.containsKey('X-Amz-Signature');

        if (isPresignedUrl) {
          // To avoid CORS issues with presigned URLs, use our backend as a proxy
          // This ensures the image will display properly in all browsers
          final encodedUrl = Uri.encodeComponent(originalUrl);
          return '$_apiBaseUrl/api/v1/direct-access?url=$encodedUrl';
        } else {
          // Direct S3 URL without presigning - log a warning
          dev.log(
              'WARNING: Direct S3 URL without presigning in production - likely to cause 403 errors: $originalUrl');

          // Try to proxy it anyway
          final encodedUrl = Uri.encodeComponent(originalUrl);
          return '$_apiBaseUrl/api/v1/direct-access?url=$encodedUrl';
        }
      }
    } catch (e) {
      dev.log(
          'Error processing URL in _transformImageUrl: $e, URL: $originalUrl');
    }

    // Return the original URL if no transformation is needed or if there was an error
    return originalUrl;
  }

  // Helper to retry loading an image with refreshed presigned URL if needed
  Future<String?> _refreshPresignedUrl(String originalUrl) async {
    if (!_isProduction || _accessToken == null) return null;

    try {
      // Extract key from the URL
      final Uri uri = Uri.parse(originalUrl);
      final path = uri.path;
      // Extract the path components from something like /bucket-name/event-id/session-id/file.jpg
      final pathParts =
          path.split('/').where((part) => part.isNotEmpty).toList();

      if (pathParts.length >= 3) {
        final endpoint = '$_apiBaseUrl/api/v1/refresh-image-url';
        final response = await http
            .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'path': path,
          }),
        )
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Timeout refreshing image URL');
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['presigned_url'] != null) {
            return data['presigned_url'] as String;
          }
        }
      }
    } catch (e) {
      dev.log('Error refreshing presigned URL: $e');
    }

    return null;
  }

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
      // Make sure the endpoint format matches what the backend expects
      final endpoint = '$_apiBaseUrl/api/v1/session/${_cleanSessionId}/auth';

      dev.log('AUTHENTICATION DEBUG:');
      dev.log('API Base URL: $_apiBaseUrl');
      dev.log('Endpoint: $endpoint');
      dev.log('Clean Session ID: ${_cleanSessionId}');
      dev.log('Original Session ID: ${widget.sessionId}');

      // Test if the endpoint is accessible
      try {
        final testResponse = await http.get(Uri.parse(_apiBaseUrl)).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Connection timed out. Server may be unreachable.');
          },
        );
        dev.log('Base URL connection test: ${testResponse.statusCode}');
        if (testResponse.statusCode != 200) {
          dev.log(
              'Base URL test response: ${testResponse.body.substring(0, min(100, testResponse.body.length))}...');
        }
      } catch (e) {
        dev.log('Base URL connection error: $e');
        if (!_isProduction) {
          setState(() {
            _errorMessage = '''
Connection error: $e
For local testing, check:
1. Is your backend server running? (python run_local.py)
2. If using an emulator, make sure the backend is accessible at $_apiBaseUrl
3. If using a physical device, update _localApiUrl with your computer's IP
''';
          });
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      // Log the password being sent for debugging
      final password = _passwordController.text;
      dev.log('Password being sent: $password');

      final response = await http
          .post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception(
              'Authentication request timed out. Check server status.');
        },
      );

      dev.log('Auth response status: ${response.statusCode}');
      dev.log('Auth response headers: ${response.headers}');

      // Print first part of response body to debug
      final previewLength = min(500, response.body.length);
      dev.log(
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
        // Enhanced error reporting
        dev.log('FULL ERROR RESPONSE:');
        dev.log('Status code: ${response.statusCode}');
        dev.log('Headers: ${response.headers}');
        dev.log('Body: ${response.body}');

        try {
          final errorData = jsonDecode(response.body);
          setState(() {
            _errorMessage =
                'Authentication failed (${response.statusCode}): ${errorData['detail'] ?? 'Unknown error'}';
          });
        } catch (e) {
          setState(() {
            _errorMessage =
                'Authentication failed (${response.statusCode}): ${response.body}';
          });
        }
      }
    } catch (e) {
      dev.log('Authentication error: $e');
      setState(() {
        if (!_isProduction) {
          _errorMessage = '''
Authentication failed: $e
For local testing, check:
1. Backend running at $_apiBaseUrl?
2. Correct session ID? (${_cleanSessionId})
3. Password hashing configured properly?
4. Check backend logs for more details.
''';
        } else {
          _errorMessage = 'Authentication failed: $e';
        }
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
      final endpoint = '$_apiBaseUrl/api/v1/session/${_cleanSessionId}/photos';

      dev.log('FETCH PHOTOS DEBUG:');
      dev.log('Photos endpoint: $endpoint');
      dev.log(
          'Using access token: ${_accessToken!.substring(0, min(10, _accessToken!.length))}...');

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Request timed out while fetching photos.');
        },
      );

      dev.log('Photos response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final List<String> fetchedPhotos = List<String>.from(data['photos']);

          // Check if we're in local development mode with image proxy option
          if (!_isProduction && _useImageProxy) {
            // Log that we're potentially modifying image URLs
            dev.log('Using image proxy for local development');
          }

          setState(() {
            _photos = fetchedPhotos;
          });

          dev.log('Fetched ${_photos.length} photos successfully');

          // Log a sample URL for debugging
          if (_photos.isNotEmpty) {
            dev.log('Sample photo URL: ${_photos.first}');
          }
        } catch (jsonError) {
          dev.log('Error parsing photos JSON: $jsonError');
          setState(() {
            _errorMessage = 'Failed to parse photos data';
          });
        }
      } else {
        dev.log(
            'Failed to fetch photos: ${response.statusCode} - ${response.body}');
        setState(() {
          _errorMessage = 'Failed to fetch photos (${response.statusCode})';
        });
      }
    } catch (e) {
      dev.log('Error fetching photos: $e');
      setState(() {
        if (!_isProduction) {
          _errorMessage = '''
Error loading photos: $e
For local testing, check:
1. JWT token validation is working correctly?
2. Session data exists in DynamoDB?
3. Check backend logs for more details.
''';
        } else {
          _errorMessage = 'Error loading photos: $e';
        }
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
      final endpoint = '$_apiBaseUrl/api/v1/session/${_cleanSessionId}/select';

      dev.log('SAVE SELECTIONS DEBUG:');
      dev.log('Save endpoint: $endpoint');
      dev.log('Saving ${_selectedPhotos.length} photos');

      final response = await http
          .post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'selected_urls': _selectedPhotos.toList(),
        }),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Request timed out while saving selections.');
        },
      );

      dev.log('Save response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selections saved successfully')),
        );
      } else {
        dev.log(
            'Failed to save selections: ${response.statusCode} - ${response.body}');
        setState(() {
          _errorMessage = 'Failed to save selections (${response.statusCode})';
        });
      }
    } catch (e) {
      dev.log('Error saving selections: $e');
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
          // Environment toggle - only show in debug mode
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Development Settings',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Environment:'),
                      Row(
                        children: [
                          const Text('Local'),
                          Switch(
                            value: _isProduction,
                            onChanged: (value) {
                              setState(() {
                                _isProduction = value;
                                // Clear any existing error when switching
                                _errorMessage = null;
                              });
                              dev.log(
                                  'Using ${_isProduction ? "production" : "local"} environment');
                            },
                          ),
                          const Text('Production'),
                        ],
                      ),
                    ],
                  ),
                  // Only show image proxy toggle in local development
                  if (!_isProduction)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Handle S3 Access:'),
                        Row(
                          children: [
                            Switch(
                              value: _useImageProxy,
                              onChanged: (value) {
                                setState(() {
                                  _useImageProxy = value;
                                });
                                dev.log(
                                    'Image proxy ${_useImageProxy ? "enabled" : "disabled"}');
                              },
                            ),
                            const Text('Use Proxy'),
                          ],
                        ),
                      ],
                    ),
                  Text('API URL: $_apiBaseUrl',
                      style: const TextStyle(fontSize: 12)),
                  Text('Session ID: $_cleanSessionId',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
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
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.red[100],
                width: double.infinity,
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red[900]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return Column(
      children: [
        if (!_isProduction && _photos.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.blue[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'S3 Access: ${_useImageProxy ? "Using proxy" : "Direct S3"}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Image Count: ${_photos.length}',
                  style: TextStyle(fontSize: 12),
                ),
                if (_photos.isNotEmpty && !_useImageProxy)
                  Text(
                    '⚠️ If images fail to load with 403 error, enable "Use Proxy" in settings',
                    style: TextStyle(color: Colors.red[800]),
                  ),
              ],
            ),
          ),
        // Production environment banner for S3 access issues
        if (_isProduction && _photos.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.amber[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'S3 Photo Access: Production Mode',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'If images fail with 403 errors, they may have expired. Contact support.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        Expanded(
          child: _photos.isEmpty
              ? const Center(child: Text('No photos available'))
              : MasonryGridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final originalUrl = _photos[index];
                    final displayUrl = _transformImageUrl(originalUrl);
                    final isSelected = _selectedPhotos.contains(originalUrl);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedPhotos.remove(originalUrl);
                          } else {
                            _selectedPhotos.add(originalUrl);
                          }
                        });
                      },
                      child: Stack(
                        children: [
                          _buildImageWithRetry(displayUrl, originalUrl),
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

  // Build image with retry mechanism
  Widget _buildImageWithRetry(String displayUrl, String originalUrl) {
    return StatefulBuilder(
      builder: (context, setImageState) {
        // Track loading and error states within this image
        bool isRetrying = false;
        bool hasError = false;
        String? errorMessage;

        // Detect if this is a presigned URL
        bool isPresignedUrl = originalUrl.contains('X-Amz-Signature');
        bool isS3Url = originalUrl.contains('s3.amazonaws.com');
        bool isProxiedUrl = displayUrl.contains('/direct-access') ||
            displayUrl.contains('/proxy-image');

        return Image.network(
          displayUrl,
          fit: BoxFit.cover,
          // Add cache headers to avoid rechecking repeatedly
          headers: isProxiedUrl ? {} : null,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // Log error details for debugging
            dev.log('Error loading image $displayUrl: $error');
            hasError = true;

            // Detect ProgressEvent errors (usually CORS related)
            final errorString = error.toString();

            // Check for different error types and classify them
            if (errorString.contains('[object ProgressEvent]')) {
              errorMessage = 'CORS Error';
              // For S3 URLs, this is almost always a 403 Forbidden error
              if (isS3Url && isPresignedUrl) {
                errorMessage = 'Access Denied (CORS)';
                dev.log(
                    'CORS error with S3 presigned URL - likely 403 Forbidden');
              }
            } else if (errorString.contains('403')) {
              errorMessage = '403 Forbidden';
            } else if (errorString.contains('401')) {
              errorMessage = '401 Unauthorized';
            } else if (errorString.contains('timeout')) {
              errorMessage = 'Connection Timeout';
            } else {
              errorMessage = 'Loading Error';
            }

            return Container(
              color: Colors.grey[300],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.red[700], size: 32),
                  Text(
                    errorMessage!,
                    style: TextStyle(color: Colors.red[900], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  if (isS3Url && isPresignedUrl)
                    Text(
                      'S3 presigned URL may have expired',
                      style: TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  if (_isProduction && isS3Url && !isProxiedUrl)
                    TextButton(
                      onPressed: isRetrying
                          ? null
                          : () async {
                              setImageState(() {
                                isRetrying = true;
                              });

                              // For production and S3 URL, apply proxy solution
                              final encodedUrl =
                                  Uri.encodeComponent(originalUrl);
                              final proxiedUrl =
                                  '$_apiBaseUrl/api/v1/direct-access?url=$encodedUrl';

                              // Update the URL in the photos list
                              int index = _photos.indexOf(originalUrl);
                              if (index >= 0) {
                                setState(() {
                                  // We're not changing the original URL in the list,
                                  // just the display URL by re-rendering the widget
                                  setImageState(() {
                                    isRetrying = false;
                                  });
                                });

                                // Show the image loading dialog
                                await showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text('Fixing Image Access'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text('Routing through backend...'),
                                          SizedBox(height: 8),
                                          Text(
                                            'The app is accessing the image through your backend to avoid CORS restrictions.',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );

                                // Close dialog and rebuild image
                                Navigator.of(context).pop();

                                // Refresh all photos through the backend
                                await _fetchPhotos();

                                // Show success message
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'All images refreshed through backend')),
                                );
                              } else {
                                setImageState(() {
                                  isRetrying = false;
                                });

                                // Show error message
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Failed to fix image - please use Settings to refresh all'),
                                    backgroundColor: Colors.red,
                                    action: SnackBarAction(
                                      label: 'Settings',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) =>
                                              _buildSettingsDialog(context),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              }
                            },
                      child: Text(
                        isRetrying ? 'Loading...' : 'Fix Image',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (!_isProduction && !_useImageProxy)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _useImageProxy = true;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Proxy enabled for all images')),
                        );
                      },
                      child: Text(
                        'Enable Proxy',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Helper method to build settings dialog
  Widget _buildSettingsDialog(BuildContext context) {
    return AlertDialog(
      title: Text('Image Access Settings'),
      content: StatefulBuilder(
        builder: (context, setDialogState) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Production mode settings
                if (_isProduction) ...[
                  Text(
                    'S3 Image Access Issues in Production',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),

                  // CORS specific issue info
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CORS Access Issue Detected',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red[800]),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Your browser is blocking direct access to S3 images due to cross-origin restrictions.',
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Solution: Generate new presigned URLs for all images by clicking "Refresh All".',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),

                  Text(
                    'If you\'re seeing 403 or CORS errors:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                      '1. Presigned URLs may have expired (typically after 1 hour)'),
                  Text(
                      '2. S3 bucket permissions or CORS settings may have changed'),
                  Text('3. AWS credentials may be invalid'),
                  SizedBox(height: 12),

                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.yellow[100],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technical Details',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('Session ID: $_cleanSessionId',
                            style: TextStyle(fontSize: 12)),
                        Text(
                          'URLs using presigned method: ${_photos.where((url) => url.contains('X-Amz-Signature')).length}/${_photos.length}',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],

                // Development mode settings
                if (!_isProduction) ...[
                  // Keep existing development mode settings
                  Text(
                    'S3 images may return 403 Forbidden in local development',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  // ... Other development settings
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        if (_isProduction)
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Show loading indicator
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Refreshing all image URLs...')),
              );

              // Fetch new photos with fresh URLs
              await _fetchPhotos();

              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('All image URLs refreshed')),
              );
            },
            child: Text('Refresh All'),
          ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text('Close'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('Select Photos'),
            if (!_isProduction)
              Container(
                margin: EdgeInsets.only(left: 8),
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'LOCAL',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_accessToken != null)
            IconButton(
              icon: Icon(Icons.settings),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Image Access Settings'),
                    content: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Development mode settings
                              if (!_isProduction) ...[
                                Text(
                                  'S3 images may return 403 Forbidden in local development',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Options to fix:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                    '1. Enable "Use Proxy" to route S3 requests through backend'),
                                Text(
                                    '2. Add a proxy-image endpoint to your backend'),
                                Text(
                                    '3. Make S3 bucket objects public (not recommended)'),
                                Text(
                                    '4. Generate pre-signed URLs on the backend'),
                                SizedBox(height: 12),
                                SwitchListTile(
                                  title: Text('Use Image Proxy'),
                                  subtitle: Text(
                                      'Route image requests through backend'),
                                  value: _useImageProxy,
                                  onChanged: (value) {
                                    setDialogState(() {
                                      _useImageProxy = value;
                                    });
                                    setState(() {}); // Update parent state
                                  },
                                ),
                              ],

                              // Production mode settings
                              if (_isProduction) ...[
                                Text(
                                  'S3 Image Access Issues in Production',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'If you\'re seeing 403 Forbidden errors:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                SizedBox(height: 4),
                                Text(
                                    '1. Presigned URLs may have expired (typically after 1 hour)'),
                                Text(
                                    '2. S3 bucket permissions may have changed'),
                                Text('3. AWS credentials may be invalid'),
                                SizedBox(height: 12),
                                Text(
                                  'Troubleshooting:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                                SizedBox(height: 4),
                                Text(
                                    '• Try the "Refresh URL" button on images with errors'),
                                Text(
                                    '• Check that your session is still valid'),
                                Text(
                                    '• Contact your administrator if issues persist'),
                                SizedBox(height: 12),
                                Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.yellow[100],
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Technical Details',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text('Session ID: $_cleanSessionId',
                                          style: TextStyle(fontSize: 12)),
                                      Text(
                                          'URLs using presigned method: ${_photos.where((url) => url.contains('X-Amz-Signature')).length}/${_photos.length}',
                                          style: TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    actions: [
                      if (_isProduction)
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _fetchPhotos(); // Refresh all photos
                          },
                          child: Text('Refresh All'),
                        ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body:
          _accessToken == null ? _buildAuthenticationView() : _buildPhotoGrid(),
    );
  }
}
