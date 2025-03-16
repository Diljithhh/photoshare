import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photoshare/models/cross_platform_image.dart';
import 'package:photoshare/screens/sessionModels.dart';
import 'dart:developer' as dev;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:math' as math;

class UploadService {
  final bool isProduction;
  final BuildContext context;
  ValueNotifier<String> statusMessage = ValueNotifier<String>('');

  // Chunk size for multipart uploads (50MB)
  static const int CHUNK_SIZE = 50 * 1024 * 1024;

  // Maximum number of parallel uploads
  static const int MAX_PARALLEL_UPLOADS = 3;

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

  // Check if device is connected to the internet
  Future<bool> isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  // Save upload state to resume later
  Future<void> saveUploadState(
      String eventId, Map<String, dynamic> uploadState) async {
    if (kIsWeb) {
      // Use local storage for web
      // This implementation would need to use a web storage package
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/upload_state_$eventId.json');
    await file.writeAsString(jsonEncode(uploadState));
    dev.log('Saved upload state for event $eventId');
  }

  // Load upload state to resume an upload
  Future<Map<String, dynamic>?> loadUploadState(String eventId) async {
    if (kIsWeb) {
      // Load from web storage
      // This implementation would need to use a web storage package
      return null;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/upload_state_$eventId.json');

      if (await file.exists()) {
        final data = await file.readAsString();
        return jsonDecode(data) as Map<String, dynamic>;
      }
    } catch (e) {
      dev.log('Failed to load upload state: $e');
    }

    return null;
  }

  // Clear upload state once completed
  Future<void> clearUploadState(String eventId) async {
    if (kIsWeb) {
      // Clear from web storage
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/upload_state_$eventId.json');

      if (await file.exists()) {
        await file.delete();
        dev.log('Cleared upload state for event $eventId');
      }
    } catch (e) {
      dev.log('Failed to clear upload state: $e');
    }
  }

  // Chunked and resumable upload with presigned URLs
  Future<List<String>> uploadImagesWithPresignedUrls(
      String eventId, List<CrossPlatformImage> selectedImages) async {
    if (!isProduction) {
      // For non-production environments, use the original method
      return _uploadImagesWithPresignedUrlsOriginal(eventId, selectedImages);
    }

    try {
      // Check for existing upload state
      final savedState = await loadUploadState(eventId);
      Map<String, dynamic> uploadState = savedState ??
          {
            'event_id': eventId,
            'files': <Map<String, dynamic>>[],
            'completed_files': <String>[],
            'public_urls': <String>[],
          };

      // If we have a saved state, reuse the completed files and initialize structure for new files
      List<String> completedFiles =
          List<String>.from(uploadState['completed_files'] ?? []);
      List<String> publicUrls =
          List<String>.from(uploadState['public_urls'] ?? []);

      // Prepare the list of files that need uploading (excluding already completed ones)
      List<CrossPlatformImage> filesToUpload = [];
      for (var image in selectedImages) {
        final fileName = image.originalFile.name;
        if (!completedFiles.contains(fileName)) {
          filesToUpload.add(image);
        }
      }

      if (filesToUpload.isEmpty) {
        statusMessage.value = 'All files already uploaded.';
        return publicUrls;
      }

      // Start the upload process
      statusMessage.value =
          'Continuing upload for ${filesToUpload.length} files...';

      // Setup connectivity stream to monitor connection changes
      final connectivitySubscription =
          Connectivity().onConnectivityChanged.listen((result) async {
        if (result == ConnectivityResult.none) {
          statusMessage.value =
              'Internet connection lost. Waiting to resume...';
        } else {
          statusMessage.value =
              'Internet connection restored. Resuming uploads...';
        }
      });

      try {
        // Request presigned URLs for the files
        statusMessage.value =
            'Getting presigned URLs for ${filesToUpload.length} files...';

        final response = await http.post(
          Uri.parse('$apiBaseUrl/api/v1/generate-multipart-upload-urls'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'event_id': eventId,
            'file_names':
                filesToUpload.map((img) => img.originalFile.name).toList(),
          }),
        );

        if (response.statusCode != 200) {
          throw Exception(
              'Failed to get multipart upload URLs: ${response.statusCode} - ${response.body}');
        }

        final data = jsonDecode(response.body);
        final List<dynamic> uploadConfigs = data['upload_configs'];

        // Process each file
        final filesToProcess =
            math.min(filesToUpload.length, uploadConfigs.length);

        // Set up a queue for parallel uploads
        List<Future<void>> uploadFutures = [];

        for (int i = 0; i < filesToProcess; i++) {
          final image = filesToUpload[i];
          final uploadConfig = uploadConfigs[i];
          final fileName = image.originalFile.name;
          final uploadId = uploadConfig['upload_id'];
          final fileUrl = uploadConfig['file_url'];

          // Add file to upload state if not already there
          bool fileExists = false;
          for (var file in uploadState['files']) {
            if (file['file_name'] == fileName) {
              fileExists = true;
              break;
            }
          }

          if (!fileExists) {
            uploadState['files'].add({
              'file_name': fileName,
              'upload_id': uploadId,
              'file_url': fileUrl,
              'completed_parts': <int>[],
              'status': 'in_progress',
            });

            // Save the updated state
            await saveUploadState(eventId, uploadState);
          }

          // Find the file data in our state
          Map<String, dynamic>? fileData;
          for (var file in uploadState['files']) {
            if (file['file_name'] == fileName) {
              fileData = file;
              break;
            }
          }

          if (fileData == null) {
            throw Exception('File data not found in upload state');
          }

          // Start upload for this file
          final uploadFuture = _uploadFileInChunks(
            eventId,
            image,
            uploadState,
            fileData,
            uploadConfig,
          );

          uploadFutures.add(uploadFuture);

          // Limit parallel uploads
          if (uploadFutures.length >= MAX_PARALLEL_UPLOADS ||
              i == filesToProcess - 1) {
            // Wait for the current batch to complete
            await Future.wait(uploadFutures);
            uploadFutures = [];
          }
        }

        // Wait for any remaining uploads
        await Future.wait(uploadFutures);

        // Update the status one last time
        statusMessage.value = 'All uploads completed!';

        // Collect all public URLs for the uploaded files
        publicUrls.clear();
        for (var file in uploadState['files']) {
          if (file['status'] == 'completed') {
            publicUrls.add(file['file_url']);

            // Add to completed files if not already there
            if (!completedFiles.contains(file['file_name'])) {
              completedFiles.add(file['file_name']);
            }
          }
        }

        // Update and save the final state
        uploadState['completed_files'] = completedFiles;
        uploadState['public_urls'] = publicUrls;
        await saveUploadState(eventId, uploadState);

        // Clear the upload state if everything is complete
        if (publicUrls.length == selectedImages.length) {
          await clearUploadState(eventId);
        }

        return publicUrls;
      } finally {
        // Clean up connectivity subscription
        await connectivitySubscription.cancel();
      }
    } catch (e) {
      dev.log('Error during chunked upload: $e');
      statusMessage.value = 'Upload failed: $e';
      rethrow;
    }
  }

  // Helper method to upload a file in chunks
  Future<void> _uploadFileInChunks(
    String eventId,
    CrossPlatformImage image,
    Map<String, dynamic> uploadState,
    Map<String, dynamic> fileData,
    Map<String, dynamic> uploadConfig,
  ) async {
    final fileName = image.originalFile.name;
    final uploadId = uploadConfig['upload_id'];

    try {
      // Read the file as bytes
      final bytes = await image.originalFile.readAsBytes();
      final fileSize = bytes.length;

      // Calculate number of chunks
      final numChunks = (fileSize / CHUNK_SIZE).ceil();

      // Get previously completed parts
      List<int> completedParts =
          List<int>.from(fileData['completed_parts'] ?? []);

      // Update status
      statusMessage.value =
          'Uploading $fileName (${completedParts.length}/$numChunks parts completed)';

      // Get presigned URLs for each part that hasn't been uploaded yet
      for (int partNumber = 1; partNumber <= numChunks; partNumber++) {
        // Skip already completed parts
        if (completedParts.contains(partNumber)) {
          continue;
        }

        // Check connection before starting part upload
        if (!await isConnected()) {
          statusMessage.value =
              'Connection lost. Saving progress and waiting to resume...';
          await saveUploadState(eventId, uploadState);

          // Wait for connection to be restored
          bool connected = false;
          while (!connected) {
            await Future.delayed(const Duration(seconds: 5));
            connected = await isConnected();
            if (connected) {
              statusMessage.value = 'Connection restored. Resuming upload...';
            }
          }
        }

        // Get presigned URL for this part
        final partUrlResponse = await http.post(
          Uri.parse('$apiBaseUrl/api/v1/get-presigned-upload-part-url'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'event_id': eventId,
            'file_name': fileName,
            'upload_id': uploadId,
            'part_number': partNumber,
          }),
        );

        if (partUrlResponse.statusCode != 200) {
          throw Exception(
              'Failed to get part upload URL: ${partUrlResponse.statusCode} - ${partUrlResponse.body}');
        }

        final partData = jsonDecode(partUrlResponse.body);
        final partUrl = partData['presigned_url'];

        // Calculate start and end of this chunk
        final start = (partNumber - 1) * CHUNK_SIZE;
        final end = math.min(partNumber * CHUNK_SIZE, fileSize);
        final chunkSize = end - start;

        // Extract chunk from file bytes
        final chunk = bytes.sublist(start, end);

        statusMessage.value =
            'Uploading part $partNumber/$numChunks of $fileName...';

        // Upload the part
        final partResponse = await http.put(
          Uri.parse(partUrl),
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': chunkSize.toString(),
          },
          body: chunk,
        );

        if (partResponse.statusCode != 200) {
          throw Exception(
              'Failed to upload part $partNumber: ${partResponse.statusCode}');
        }

        // Extract the ETag from the response (needed for completing the multipart upload)
        final etag = partResponse.headers['etag'] ?? '';

        // Record successful part upload
        if (!completedParts.contains(partNumber)) {
          completedParts.add(partNumber);
          fileData['completed_parts'] = completedParts;
          fileData['part_$partNumber\_etag'] = etag.replaceAll('"', '');

          // Save progress after each chunk
          await saveUploadState(eventId, uploadState);
        }

        // Update status with progress
        statusMessage.value =
            'Uploaded part $partNumber/$numChunks of $fileName';
      }

      // All parts uploaded, complete the multipart upload
      statusMessage.value = 'Completing multipart upload for $fileName...';

      // Prepare the parts list with ETags
      List<Map<String, dynamic>> parts = [];
      for (int partNumber = 1; partNumber <= numChunks; partNumber++) {
        parts.add({
          'PartNumber': partNumber,
          'ETag': fileData['part_${partNumber}_etag'],
        });
      }

      // Call API to complete the multipart upload
      final completeResponse = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/complete-multipart-upload'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event_id': eventId,
          'file_name': fileName,
          'upload_id': uploadId,
          'parts': parts,
        }),
      );

      if (completeResponse.statusCode != 200) {
        throw Exception(
            'Failed to complete multipart upload: ${completeResponse.statusCode} - ${completeResponse.body}');
      }

      // Mark this file as completed
      fileData['status'] = 'completed';
      await saveUploadState(eventId, uploadState);

      statusMessage.value = 'Completed upload of $fileName';
    } catch (e) {
      dev.log('Error uploading file in chunks: $e');
      fileData['status'] = 'error';
      fileData['error'] = e.toString();
      await saveUploadState(eventId, uploadState);
      rethrow;
    }
  }

  // Legacy implementation for non-production use
  Future<List<String>> _uploadImagesWithPresignedUrlsOriginal(
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
