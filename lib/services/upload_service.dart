import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photoshare/models/cross_platform_image.dart';
import 'package:photoshare/screens/sessionModels.dart';
import 'dart:developer' as dev;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class UploadService {
  final bool isProduction;
  final BuildContext context;
  ValueNotifier<String> statusMessage = ValueNotifier<String>('');

  // Environment URLs
  // For actual devices, use your computer's local network IP instead of localhost
  final String _localApiUrl =
      '10.0.2.2:8000'; // For Android emulator, use 10.0.2.2 which maps to host loopback
  final String _productionApiUrl =
      dotenv.env['API_URL'] ?? 'https://photoshare-dn8f.onrender.com';

  UploadService({required this.isProduction, required this.context});

  // Get current API URL based on environment
  String get apiBaseUrl {
    if (isProduction) {
      return _productionApiUrl;
    } else {
      // When running on a physical device, use your computer's IP address
      // When running on an emulator, use 10.0.2.2 (Android) or localhost (iOS)
      if (kIsWeb) {
        return 'http://localhost:8000';
      } else if (Platform.isAndroid) {
        return 'http://$_localApiUrl'; // Make sure http:// is included for Android
      } else if (Platform.isIOS) {
        return 'http://localhost:8000'; // For iOS simulator
      } else {
        return 'http://$_localApiUrl';
      }
    }
  }

  // Direct upload method
  Future<List<String>> uploadImagesDirectly(
      String eventId, List<CrossPlatformImage> selectedImages) async {
    try {
      statusMessage.value = 'Uploading images directly...';

      // Create a multipart request
      final uri = Uri.parse('$apiBaseUrl/api/v1/upload-multiple-photos');
      dev.log('Upload URL: $uri');

      // Add debug info to the status
      statusMessage.value = 'Connecting to: $uri';

      final request = http.MultipartRequest('POST', uri);

      // Add event_id as a form field
      request.fields['event_id'] = eventId;

      // Add all files to the request
      for (var image in selectedImages) {
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
          final file = image.platformFile as File;
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
      statusMessage.value =
          'Sending ${selectedImages.length} files to server...';

      try {
        final streamedResponse = await request.send().timeout(
          const Duration(minutes: 30),
          onTimeout: () {
            throw Exception(
                'Connection timed out. Check your network and backend server.');
          },
        );

        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          statusMessage.value =
              'Upload successful! Uploaded ${responseData['uploaded_files'].length} files.';
          dev.log('Direct upload response: ${response.body}');

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
        if (!isProduction) {
          // Provide detailed debugging for local environment
          statusMessage.value = '''
Local upload failed: $e
Check:
1. Is your backend server running at $apiBaseUrl?
2. Is CORS configured correctly on your backend?
3. If using physical device, is it on the same network as your computer?
4. Try updating _localApiUrl to your computer's actual IP address
''';
        }
        rethrow;
      }
    } catch (e) {
      dev.log('Error during direct upload: $e', error: e);
      statusMessage.value = 'Direct upload failed: $e';
      rethrow;
    }
  }

  // Presigned URL upload method
  Future<List<String>> uploadImagesWithPresignedUrls(
      String eventId, List<CrossPlatformImage> selectedImages) async {
    try {
      statusMessage.value = 'Getting presigned URLs...';

      // Get presigned URLs
      final presignedUrlsResponse = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/generate-upload-urls'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_id': eventId,
          'num_photos': selectedImages.length,
        }),
      );

      dev.log(
          'Presigned URLs response status: ${presignedUrlsResponse.statusCode}');
      dev.log('Presigned URLs response body: ${presignedUrlsResponse.body}');

      if (presignedUrlsResponse.statusCode != 200) {
        throw Exception(
            'Failed to get upload URLs from ${isProduction ? "production" : "local"} server: ${presignedUrlsResponse.statusCode} - ${presignedUrlsResponse.body}');
      }

      final presignedData = jsonDecode(presignedUrlsResponse.body);
      final List<String> presignedUrls =
          List<String>.from(presignedData['presigned_urls']);
      final String sessionId = presignedData['session_id'];

      statusMessage.value =
          'Got ${presignedUrls.length} presigned URLs. Uploading files...';

      // Create a separate list of URLs that we'll return to create the session
      List<String> publicUrls = [];

      // We need to construct public URLs for the uploaded files
      for (int i = 0; i < presignedUrls.length; i++) {
        final Uri presignedUri = Uri.parse(presignedUrls[i]);
        final String path = presignedUri.path;
        final String host = presignedUri.host;

        // Extract the bucket name from the host (if available)
        // The format will typically be: {bucket-name}.s3.{region}.amazonaws.com
        final String publicUrl = 'https://$host$path';
        publicUrls.add(publicUrl);
      }

      // Upload each file using its presigned URL
      for (int i = 0;
          i < selectedImages.length && i < presignedUrls.length;
          i++) {
        final image = selectedImages[i];
        final presignedUrl = presignedUrls[i];

        statusMessage.value =
            'Uploading file ${i + 1} of ${selectedImages.length}...';

        try {
          // Read file as bytes
          final bytes = await image.originalFile.readAsBytes();

          // Different implementation for web vs mobile
          if (kIsWeb) {
            // For web, we need to work around CORS by using a proxy server
            // or by proxying the upload through our backend

            // Option 1: Use our backend as a proxy for the upload
            final proxyResponse = await http.post(
              Uri.parse('$apiBaseUrl/api/v1/proxy-upload'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'presigned_url': presignedUrl,
                'file_content': base64Encode(bytes),
              }),
            );

            if (proxyResponse.statusCode != 200) {
              throw Exception(
                  'Failed to upload file ${i + 1} via proxy: ${proxyResponse.statusCode} - ${proxyResponse.body}');
            }

            dev.log('Successfully uploaded file ${i + 1} through proxy server');
          } else {
            // For mobile, we can use HttpClient which bypasses CORS
            final request = await HttpClient().putUrl(Uri.parse(presignedUrl));
            request.headers.set('Content-Type', 'image/jpeg');
            request.add(bytes);

            final response = await request.close();
            final responseBody = await response.transform(utf8.decoder).join();

            if (response.statusCode != 200) {
              throw Exception(
                  'Failed to upload file ${i + 1}: ${response.statusCode} - $responseBody');
            }

            dev.log(
                'Successfully uploaded file ${i + 1} with status code: ${response.statusCode}');
          }
        } catch (e) {
          dev.log('Error uploading file ${i + 1}: $e');
          throw Exception('Failed to upload file ${i + 1}: $e');
        }
      }

      statusMessage.value = 'Upload successful! Session ID: $sessionId';

      // Return the public URLs for creating the session
      return publicUrls;
    } catch (e) {
      dev.log('Error during presigned URL upload: $e');
      statusMessage.value = 'Presigned URL upload failed: $e';
      rethrow;
    }
  }

  // Function to create a session with the uploaded photos
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
        final responseData = jsonDecode(response.body);
        return SessionResponse.fromJson(responseData);
      } else {
        throw Exception(
            'Failed to create session: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      dev.log('Error creating session: $e');
      rethrow;
    }
  }
}
