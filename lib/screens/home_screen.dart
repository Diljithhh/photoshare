import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  double _uploadProgress = 0.0;
  String _statusMessage = '';
  bool _isProduction = true; // Default to production mode
  SessionResponse? _sessionResponse;
  bool _useDirectUpload =
      true; // Toggle between direct upload and presigned URLs
  late UploadService _uploadService;
  bool _showSettings = false;

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
      // Simulate progress updates based on status message
      if (_isUploading) {
        if (_statusMessage.contains('Uploading file')) {
          // Extract current file number and total files
          final regex = RegExp(r'Uploading file (\d+) of (\d+)');
          final match = regex.firstMatch(_statusMessage);
          if (match != null && match.groupCount >= 2) {
            final current = int.parse(match.group(1)!);
            final total = int.parse(match.group(2)!);
            _uploadProgress = current / total;
          }
        } else if (_statusMessage.contains('successful')) {
          _uploadProgress = 1.0;
        }
      }
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
      _statusMessage = '';
      _sessionResponse = null;
      _uploadProgress = 0.0;
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
      _uploadProgress =
          0.05; // Start with a small progress to indicate we're starting
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
        _uploadProgress = 0.9; // Almost done
      });

      final session = await _uploadService.createSession(eventId, uploadedUrls);

      setState(() {
        _sessionResponse = session;
        _statusMessage = 'Upload complete!';
        _uploadProgress = 1.0; // Done
      });
    } catch (e) {
      print('Error during upload process: $e');
      setState(() {
        _statusMessage = 'Upload failed: $e';
        _uploadProgress = 0.0;
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(),

              // Main content
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Bulk Image Upload',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload multiple images and get a secure sharing link',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Upload area
                    _buildUploadArea(),

                    // Progress bar
                    if (_isUploading || _uploadProgress > 0)
                      _buildProgressIndicator(),

                    // Upload complete or session details
                    if (_sessionResponse != null) _buildUploadComplete(),

                    const SizedBox(height: 48),
                  ],
                ),
              ),

              // Footer
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // BulkUploader logo/text
          Row(
            children: [
              Icon(Icons.cloud_upload, color: Colors.blueGrey[800]),
              const SizedBox(width: 8),
              Text(
                'BulkUploader',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
            ],
          ),
          const Spacer(),
          // Help button
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showSettings = !_showSettings;
              });
            },
            icon: Icon(
                _showSettings ? Icons.settings_outlined : Icons.help_outline),
            label: Text(_showSettings ? 'Settings' : 'Help'),
            style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
          ),
          const SizedBox(width: 8),
          // Account button
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Account'),
            style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadArea() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showSettings)
            _buildSettingsPanel()
          else if (_selectedImages.isEmpty)
            Column(
              children: [
                Icon(Icons.cloud_upload, size: 48, color: Colors.grey[400]),


                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                Text(
                  '${_selectedImages.length} files selected',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _isUploading ? null : _uploadImages,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),


                      child:
                          Text(_isUploading ? 'Uploading...' : 'Upload Files'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _isUploading ? null : _clearImages,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Display image grid preview
                // _buildImagePreview(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Advanced Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

          // Environment toggle
          _buildSettingSwitch(
            'Environment',
            'Local',
            'Production',
            _isProduction,
            (value) {
              setState(() {
                _isProduction = value;
                _uploadService = UploadService(
                  isProduction: _isProduction,
                  context: context,
                );
                _uploadService.statusMessage.addListener(_updateStatusMessage);
              });
            },
          ),

          const SizedBox(height: 12),

          // Upload method toggle
          _buildSettingSwitch(
            'Upload Method',
            'Presigned URLs',
            'Direct Upload',
            _useDirectUpload,
            (value) {
              setState(() => _useDirectUpload = value);
            },
          ),

          const SizedBox(height: 12),

          // API URL display
          Text(
            'API URL: ${_uploadService.apiBaseUrl}',
            style: const TextStyle(fontSize: 12),
          ),

          const SizedBox(height: 16),

          // Done button
          Center(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _showSettings = false;
                });
              },
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSwitch(
    String label,
    String leftText,
    String rightText,
    bool value,
    Function(bool) onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          children: [
            Text(leftText,
                style: TextStyle(fontSize: 14, color: Colors.grey[700])),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.blueGrey[700],
            ),
            Text(rightText,
                style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Uploading ${_selectedImages.length} files...',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _uploadProgress,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blueGrey[700]!),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(_uploadProgress * 100).toInt()}%',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadComplete() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700]),
              const SizedBox(width: 8),
              const Text(
                'Upload Complete!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Share Link
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share Link',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sessionResponse?.sessionLink ?? '',
                        style: const TextStyle(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _sessionResponse?.sessionLink ?? ''));

                        // Copy link to clipboard
                        if (_sessionResponse != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Link copied to clipboard')),
                          );
                        }
                      },
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Access Password
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Access Password',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _sessionResponse?.password ?? '',
                        style: const TextStyle(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _sessionResponse?.password ?? ''));
                        // Copy password to clipboard
                        if (_sessionResponse != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Password copied to clipboard')),
                          );
                        }
                      },
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: _selectedImages.isEmpty
          ? const Center(child: Text('No images selected'))
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                final image = _selectedImages[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Display image based on platform
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: kIsWeb
                          ? Image.network(
                              image.previewUrl!,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              image.platformFile as io.File,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: Colors.grey[100],
      child: Center(
        child: Text(
          '© BulkUploader. All rights reserved.',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
