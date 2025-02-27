import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'dart:async';

// Add logging function
void log(String message) {
  print('${DateTime.now()} - $message');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  log('Environment loaded. API URL: ${dotenv.env['API_URL']}');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhotoShare',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const PhotoUploadPage(),
    );
  }
}

class PhotoUploadPage extends StatefulWidget {
  const PhotoUploadPage({super.key});

  @override
  State<PhotoUploadPage> createState() => _PhotoUploadPageState();
}

class _PhotoUploadPageState extends State<PhotoUploadPage> {
  final _eventIdController = TextEditingController();
  final List<XFile> _selectedPhotos = [];
  bool _isUploading = false;
  String? _sessionLink;
  String? _sessionPassword;
  String? _errorMessage;

  Future<void> _pickImages() async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage();

      if (images.isNotEmpty) {
        log('Selected ${images.length} images');
        setState(() {
          _selectedPhotos.addAll(images);
        });
      }
    } catch (e) {
      log('Error picking images: $e');
      setState(() {
        _errorMessage = 'Failed to pick images: $e';
      });
    }
  }

  Future<bool> _uploadToS3(String presignedUrl, XFile photo) async {
    try {
      final bytes = await photo.readAsBytes();
      log('File size: ${bytes.length} bytes');

      if (kIsWeb) {
        // Use XMLHttpRequest for web uploads to better handle CORS
        final completer = Completer<bool>();
        final xhr = html.HttpRequest();

        xhr.open('PUT', presignedUrl);
        xhr.setRequestHeader('Content-Type', 'image/jpeg');
        xhr.setRequestHeader('Content-Length', bytes.length.toString());
        xhr.setRequestHeader('Access-Control-Allow-Origin', '*');
        xhr.setRequestHeader('Access-Control-Allow-Methods', 'PUT');
        xhr.setRequestHeader('Access-Control-Allow-Headers', 'Content-Type');
        xhr.withCredentials = false;

        xhr.onLoad.listen((event) {
          log('Upload response status: ${xhr.status}');
          log('Upload response text: ${xhr.responseText}');
          final status = xhr.status ?? 0;
          completer.complete(status >= 200 && status < 300);
        });

        xhr.onError.listen((event) {
          log('XHR Error: ${xhr.statusText}');
          log('XHR Response: ${xhr.responseText}');
          log('XHR Ready State: ${xhr.readyState}');
          completer.complete(false);
        });

        xhr.upload.onProgress.listen((event) {
          if (event.lengthComputable) {
            final total = event.total ?? 0;
            final loaded = event.loaded ?? 0;
            if (total > 0) {
              final percentComplete = ((loaded / total) * 100).round();
              log('Upload progress: $percentComplete%');
            }
          }
        });

        try {
          xhr.send(bytes);
          log('XHR request sent successfully');
        } catch (e) {
          log('XHR send error: $e');
          completer.complete(false);
        }

        return await completer.future;
      } else {
        // Use dio package for mobile
        final dioClient = Dio();
        final response = await dioClient.put(
          presignedUrl,
          data: Stream.fromIterable([bytes]),
          options: Options(
            headers: {
              'Content-Type': 'image/jpeg',
              'Content-Length': bytes.length.toString(),
            },
            followRedirects: true,
            validateStatus: (status) => status! < 400,
          ),
        );

        log('Upload response status: ${response.statusCode}');
        return response.statusCode == 200;
      }
    } catch (e, stackTrace) {
      log('Error in _uploadToS3: $e');
      log('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> _uploadPhotos() async {
    if (_eventIdController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter an event ID';
      });
      return;
    }

    if (_selectedPhotos.isEmpty) {
      setState(() {
        _errorMessage = 'Please select photos to upload';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      log('Starting upload process for ${_selectedPhotos.length} photos');

      // 1. Get presigned URLs
      final url = Uri.parse('${dotenv.env['API_URL']}/upload');
      log('Making request to: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'event_id': _eventIdController.text,
        }),
      );

      log('Presigned URLs response status: ${response.statusCode}');
      log('Presigned URLs response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to get upload URLs: ${response.statusCode} - ${response.body}');
      }

      final presignedData = jsonDecode(response.body);
      final List<String> presignedUrls =
          List<String>.from(presignedData['presigned_urls']);
      final String uploadSessionId = presignedData['session_id'];

      log('Received ${presignedUrls.length} presigned URLs');
      log('Upload session ID: $uploadSessionId');

      // 2. Upload photos using presigned URLs
      final List<String> uploadedUrls = [];

      for (var i = 0; i < _selectedPhotos.length; i++) {
        if (i >= presignedUrls.length) break;

        final photo = _selectedPhotos[i];
        log('Uploading photo ${i + 1}/${_selectedPhotos.length}: ${photo.path}');

        final success = await _uploadToS3(presignedUrls[i], photo);
        if (success) {
          final uploadedUrl = presignedUrls[i].split('?')[0];
          uploadedUrls.add(uploadedUrl);
          log('Successfully uploaded to: $uploadedUrl');
        } else {
          log('Failed to upload photo ${i + 1}');
        }
      }

      if (uploadedUrls.isEmpty) {
        throw Exception('Failed to upload any photos');
      }

      log('Successfully uploaded ${uploadedUrls.length} photos');

      // 3. Create session with uploaded photos
      log('Creating session for uploaded photos');
      final sessionResponse = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/session/create'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'event_id': _eventIdController.text,
          'photo_urls': uploadedUrls,
        }),
      );

      log('Session creation response: ${sessionResponse.statusCode}');
      log('Session creation body: ${sessionResponse.body}');

      if (sessionResponse.statusCode != 200) {
        throw Exception(
            'Failed to create session: ${sessionResponse.statusCode} - ${sessionResponse.body}');
      }

      final sessionData = jsonDecode(sessionResponse.body);
      setState(() {
        _sessionLink = sessionData['access_link'];
        _sessionPassword = sessionData['password'];
        _isUploading = false;
        _errorMessage = null;
      });

      log('Upload process completed successfully');
    } catch (e, stackTrace) {
      log('Error during upload process: $e');
      log('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Upload failed: ${e.toString()}';
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PhotoShare Upload'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _eventIdController,
              decoration: const InputDecoration(
                labelText: 'Event ID',
                hintText: 'Enter a unique event identifier',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.photo_library),
              label: const Text('Select Photos'),
            ),
            const SizedBox(height: 8),
            Text('${_selectedPhotos.length} photos selected'),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: _isUploading ? null : _uploadPhotos,
              child: _isUploading
                  ? const CircularProgressIndicator()
                  : const Text('Upload Photos'),
            ),
            if (_sessionLink != null && _sessionPassword != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Upload Complete!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText('Session Link: $_sessionLink'),
              SelectableText('Password: $_sessionPassword'),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _eventIdController.dispose();
    super.dispose();
  }
}
