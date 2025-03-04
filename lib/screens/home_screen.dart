import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:photoshare/models/cross_platform_image.dart';
import 'package:photoshare/screens/sessionModels.dart';
import 'package:photoshare/services/upload_service.dart';
import 'package:photoshare/widgets/session_details_card.dart';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

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
  bool _isProduction = true; // Default to production mode
  SessionResponse? _sessionResponse;
  bool _useDirectUpload =
      true; // Toggle between direct upload and presigned URLs
  late UploadService _uploadService;

  // Event ID controller
  final TextEditingController _eventIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Generate a random event ID if none provided
    _eventIdController.text = const Uuid().v4();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _uploadService =
        UploadService(isProduction: _isProduction, context: context);
    _uploadService.statusMessage.addListener(_updateStatusMessage);
  }

  void _updateStatusMessage() {
    setState(() {
      _statusMessage = _uploadService.statusMessage.value;
    });
  }

  @override
  void dispose() {
    _eventIdController.dispose();
    _uploadService.statusMessage.removeListener(_updateStatusMessage);
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
        // Direct upload approach
        uploadedUrls =
            await _uploadService.uploadImagesDirectly(eventId, _selectedImages);
      } else {
        // Presigned URL approach
        uploadedUrls = await _uploadService.uploadImagesWithPresignedUrls(
            eventId, _selectedImages);
      }

      // Create a session with the uploaded photos
      setState(() {
        _statusMessage = 'Creating sharing session...';
      });

      final session = await _uploadService.createSession(eventId, uploadedUrls);

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
                                    // Recreate the upload service with the new environment
                                    _uploadService = UploadService(
                                      isProduction: _isProduction,
                                      context: context,
                                    );
                                    _uploadService.statusMessage
                                        .addListener(_updateStatusMessage);
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
                      Text('API URL: ${_uploadService.apiBaseUrl}',
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

              // Session details card if available
              if (_sessionResponse != null)
                SessionDetailsCard(session: _sessionResponse!),

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
}
