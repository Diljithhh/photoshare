import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

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
