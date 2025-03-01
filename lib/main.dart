import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:photoshare/screens/sessionModels.dart';
import 'package:photoshare/screens/session_view.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:photoshare/utils/router.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");
   usePathUrlStrategy(); //

  runApp(const MyApp());
}

// Web image class to handle images on web platform
class WebImage {
  final XFile file;
  final String url;

  WebImage({required this.file, required this.url});
}

// A class to handle both web and mobile images
class CrossPlatformImage {
  final XFile originalFile;
  final dynamic platformFile; // File for mobile, html.File for web
  final String? previewUrl; // For web only

  CrossPlatformImage({
    required this.originalFile,
    required this.platformFile,
    this.previewUrl,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: AppRouter().router,
      title: 'PhotoShare',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // initialRoute: '/',
      // onGenerateRoute: (settings) {
      //   // Check if this is a direct session URL with no path segments (could be from a deep link)
      //   if (settings.name != null && settings.name!.contains('/session/')) {
      //     // Extract session ID from the URL
      //     final url = settings.name!;
      //     print('URLsaasaas: $url');
      //     // Extract session ID from URL like https://photoshare-dn8f.onrender.com/session/7f5432b5-746b-457e-a8ba-39fc45e0cb71
      //     final sessionIdMatch = RegExp(r'/session/([^/?&#]+)').firstMatch(url);
      //     print('sessionIdMatch: $sessionIdMatch');
      //     if (sessionIdMatch != null && sessionIdMatch.groupCount >= 1) {
      //       final sessionId = sessionIdMatch.group(1);
      //       print('sessionId: $sessionId');
      //       return MaterialPageRoute(
      //         builder: (context) => SessionView(sessionId: sessionId!),
      //       );
      //     }
      //   }

      //   // Handle '/session/:id' routes (standard path segments)
      //   final uri = Uri.parse(settings.name ?? '/');
      //   final pathSegments = uri.pathSegments;

      //   if (pathSegments.length >= 2 && pathSegments[0] == 'session') {
      //     final sessionId = pathSegments[1];
      //     return MaterialPageRoute(
      //       builder: (context) => SessionView(sessionId: sessionId),
      //     );
      //   }

      //   // Default route
      //   return MaterialPageRoute(
      //     builder: (context) => const PhotoShareApp(),
      //   );
      // },
      // home: const PhotoShareApp(),
    );
  }
}

class PhotoShareApp extends StatefulWidget {
  const PhotoShareApp({Key? key}) : super(key: key);

  @override
  _PhotoShareAppState createState() => _PhotoShareAppState();
}

class _PhotoShareAppState extends State<PhotoShareApp> {
  final ImagePicker _picker = ImagePicker();
  final List<CrossPlatformImage> _selectedImages = [];
  bool _isUploading = false;
  String _statusMessage = '';
  bool _isProduction = false;
  SessionResponse? _sessionResponse;
  bool _useDirectUpload =
      true; // Toggle between direct upload and presigned URLs

  // Environment URLs
  final String _localApiUrl = 'http://localhost:8000';
  final String _productionApiUrl =
      dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';

  // Get current API URL based on environment
  String get _apiBaseUrl => _isProduction ? _productionApiUrl : _localApiUrl;

  // Event ID controller
  final TextEditingController _eventIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Generate a random event ID if none provided
    _eventIdController.text = const Uuid().v4();
  }

  @override
  void dispose() {
    _eventIdController.dispose();
    super.dispose();
  }

  // Pick images from gallery
  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();

      if (pickedFiles.isNotEmpty) {
        final newImages = <CrossPlatformImage>[];

        for (var xFile in pickedFiles) {
          if (kIsWeb) {
            // On web, create previewUrl from XFile
            newImages.add(CrossPlatformImage(
              originalFile: xFile,
              platformFile: xFile, // For web, we just keep the XFile
              previewUrl:
                  xFile.path, // On web, xFile.path is already a blob URL
            ));
          } else {
            // On mobile, create a File
            newImages.add(CrossPlatformImage(
              originalFile: xFile,
              platformFile: io.File(xFile.path),
              previewUrl: null,
            ));
          }
        }

        setState(() {
          _selectedImages.addAll(newImages);
          _statusMessage = 'Selected ${_selectedImages.length} images';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error picking images: $e';
      });
      print('Error picking images: $e');
    }
  }

  // Clear selected images
  void _clearImages() {
    setState(() {
      _selectedImages.clear();
      _statusMessage = 'Cleared all images';
    });
  }

  // Upload images using the appropriate method
  Future<void> _uploadImages() async {
    if (_selectedImages.isEmpty) {
      setState(() {
        _statusMessage = 'Please select images first';
      });
      return;
    }

    final String eventId = _eventIdController.text.trim();
    if (eventId.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an event ID';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _statusMessage = 'Starting upload process...';
      _sessionResponse = null; // Reset any previous session
    });

    try {
      List<String> uploadedUrls = [];

      if (_useDirectUpload) {
        // Direct upload approach - returns List<String> with file URLs
        uploadedUrls = await _uploadImagesDirectly(eventId);
      } else {
        // Presigned URL approach - returns List<String> with presigned URLs
        // We need to convert these to public URLs
        final presignedUrls = await _uploadImagesWithPresignedUrls(eventId);

        // For simplicity, we'll just use the presigned URLs directly
        // In a real app, you might need to construct proper S3 URLs
        uploadedUrls = presignedUrls;
      }

      // Create a session with the uploaded photos
      setState(() {
        _statusMessage = 'Creating sharing session...';
      });

      final session = await createSession(eventId, uploadedUrls);

      setState(() {
        _sessionResponse = session;
        _statusMessage = 'Upload complete and session created!';
      });
    } catch (e) {
      print('Error during upload process: $e');
      setState(() {
        _statusMessage = 'Upload failed: $e';
      });
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  // Direct upload method (new approach)
  Future<List<String>> _uploadImagesDirectly(String eventId) async {
    try {
      setState(() {
        _statusMessage = 'Uploading images directly...';
      });

      // Create a multipart request
      final uri = Uri.parse('$_apiBaseUrl/api/v1/upload-multiple-photos');
      final request = http.MultipartRequest('POST', uri);

      // Add event_id as a form field
      request.fields['event_id'] = eventId;

      // Add all files to the request
      for (var image in _selectedImages) {
        final fileName = image.originalFile.name;

        if (kIsWeb) {
          // For web, read the file as bytes from XFile
          final bytes = await image.originalFile.readAsBytes();

          final multipartFile = http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: fileName,
          );
          request.files.add(multipartFile);
        } else {
          // For mobile, use the File object's stream
          final file = image.platformFile as io.File;
          final fileStream = http.ByteStream(file.openRead());
          final length = await file.length();

          final multipartFile = http.MultipartFile(
            'files', // This must match the parameter name in your FastAPI endpoint
            fileStream,
            length,
            filename: fileName,
          );
          request.files.add(multipartFile);
        }
      }

      // Send the request
      setState(() {
        _statusMessage = 'Sending files to server...';
      });

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        setState(() {
          _statusMessage =
              'Upload successful! Uploaded ${responseData['uploaded_files'].length} files.';
        });
        print('Direct upload response: ${response.body}');

        // Extract file URLs from the response
        final List<dynamic> uploadedFiles = responseData['uploaded_files'];
        return uploadedFiles
            .map<String>((item) => item['file_url'] as String)
            .toList();
      } else {
        throw Exception(
            'Failed to upload images: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error during direct upload: $e');
      setState(() {
        _statusMessage = 'Direct upload failed: $e';
      });
      rethrow;
    }
  }

  // Presigned URL upload method (original approach)
  Future<List<String>> _uploadImagesWithPresignedUrls(String eventId) async {
    try {
      setState(() {
        _statusMessage = 'Getting presigned URLs...';
      });

      // Get presigned URLs
      final presignedUrlsResponse = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/generate-upload-urls'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_id': eventId,
          'num_photos': _selectedImages.length,
        }),
      );

      print(
          'Presigned URLs response status: ${presignedUrlsResponse.statusCode}');
      print('Presigned URLs response body: ${presignedUrlsResponse.body}');

      if (presignedUrlsResponse.statusCode != 200) {
        throw Exception(
            'Failed to get upload URLs from ${_isProduction ? "production" : "local"} server: ${presignedUrlsResponse.statusCode} - ${presignedUrlsResponse.body}');
      }

      final presignedData = jsonDecode(presignedUrlsResponse.body);
      final List<String> presignedUrls =
          List<String>.from(presignedData['presigned_urls']);
      final String sessionId = presignedData['session_id'];

      setState(() {
        _statusMessage =
            'Got ${presignedUrls.length} presigned URLs. Uploading files...';
      });

      // Upload each file using its presigned URL
      for (int i = 0;
          i < _selectedImages.length && i < presignedUrls.length;
          i++) {
        final image = _selectedImages[i];
        final presignedUrl = presignedUrls[i];

        setState(() {
          _statusMessage =
              'Uploading file ${i + 1} of ${_selectedImages.length}...';
        });

        // Read file as bytes
        final bytes = await image.originalFile.readAsBytes();

        // Upload to S3 using presigned URL
        final uploadResponse = await http.put(
          Uri.parse(presignedUrl),
          headers: {'Content-Type': 'image/jpeg'},
          body: bytes,
        );

        if (uploadResponse.statusCode != 200) {
          throw Exception(
              'Failed to upload file ${i + 1}: ${uploadResponse.statusCode}');
        }
      }

      setState(() {
        _statusMessage = 'Upload successful! Session ID: $sessionId';
      });

      // Return the presigned URLs
      return presignedUrls;
    } catch (e) {
      print('Error during presigned URL upload: $e');
      setState(() {
        _statusMessage = 'Presigned URL upload failed: $e';
      });
      rethrow;
    }
  }

  // Function to create a session with the uploaded photos
  Future<SessionResponse> createSession(
      String eventId, List<String> photoUrls) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/session/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_id': eventId,
          'photo_urls': photoUrls,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return SessionResponse.fromJson(responseData);
      } else {
        throw Exception(
            'Failed to create session: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PhotoShare'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Environment toggle
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Settings',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
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
                                  });
                                  print(
                                      'Switched to ${_isProduction ? "production" : "local"} environment');
                                },
                              ),
                              const Text('Production'),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Upload Method:'),
                          Row(
                            children: [
                              const Text('Presigned URLs'),
                              Switch(
                                value: _useDirectUpload,
                                onChanged: (value) {
                                  setState(() {
                                    _useDirectUpload = value;
                                  });
                                  print(
                                      'Switched to ${_useDirectUpload ? "direct upload" : "presigned URLs"}');
                                },
                              ),
                              const Text('Direct Upload'),
                            ],
                          ),
                        ],
                      ),
                      Text('API URL: $_apiBaseUrl',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Event ID input
              TextField(
                controller: _eventIdController,
                decoration: const InputDecoration(
                  labelText: 'Event ID',
                  border: OutlineInputBorder(),
                  hintText: 'Enter event ID or use generated one',
                ),
              ),
              const SizedBox(height: 16),

              // Image selection and upload buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImages,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Select Images'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _clearImages,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear Images'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadImages,
                icon: const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? 'Uploading...' : 'Upload Images'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Status message
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: _statusMessage.contains('failed') ||
                          _statusMessage.contains('Error')
                      ? Colors.red[100]
                      : Colors.green[100],
                  child: Text(_statusMessage),
                ),
              const SizedBox(height: 16),
              if (_sessionResponse != null)
                _buildSessionDetailsCard(_sessionResponse!),

              // Selected images preview
              Container(
                height: 300, // Fixed height for the grid
                child: _selectedImages.isEmpty
                    ? const Center(child: Text('No images selected'))
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: _selectedImages.length,
                        itemBuilder: (context, index) {
                          final image = _selectedImages[index];
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              // Display image based on platform
                              kIsWeb
                                  ? Image.network(
                                      image.previewUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      image.platformFile as io.File,
                                      fit: BoxFit.cover,
                                    ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black54,
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Add this widget to display session details
  Widget _buildSessionDetailsCard(SessionResponse session) {
    // Convert the backend URL to frontend URL if needed
    String displaySessionLink = session.sessionLink;
    if (displaySessionLink.contains('photoshare-dn8f.onrender.com')) {
      final frontendUrl =
          dotenv.env['FRONTEND_URL'] ?? 'https://photo-share-app-id.web.app';
      displaySessionLink = '$frontendUrl/session/${session.sessionId}';
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Session Created Successfully!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Session Link with copy button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Share Link:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        displaySessionLink,
                        style: const TextStyle(color: Colors.blue),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: displaySessionLink));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Password with copy button
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Password:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        session.password,
                        style: const TextStyle(
                            fontFamily: 'monospace', letterSpacing: 1.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                 context.go('/session/${session.sessionId}');

                    Clipboard.setData(ClipboardData(text: session.password));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Password copied to clipboard')),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),


            // Copy both at once button
            ElevatedButton.icon(
              onPressed: () {

                final textToCopy =
                    'View photos at: ${displaySessionLink}\nPassword: ${session.password}';
                Clipboard.setData(ClipboardData(text: textToCopy));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Link and password copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy Link & Password'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),

            // Add view session button
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // Extract session ID from the session link
                final uri = Uri.parse(displaySessionLink);
                final pathSegments = uri.pathSegments;
                if (pathSegments.length >= 2 && pathSegments[0] == 'session') {
                  final sessionId = pathSegments[1];
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SessionView(sessionId: sessionId),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Invalid session link format')),
                  );
                }
              },
              icon: const Icon(Icons.photo_library),
              label: const Text('View Photos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
