import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsDialog extends StatelessWidget {
  final ApiService apiService;
  final String sessionId;
  final String accessToken;
  final VoidCallback onRefresh;

  const SettingsDialog({
    Key? key,
    required this.apiService,
    required this.sessionId,
    required this.accessToken,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Image Access Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'S3 Image Access Issues',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('If you\'re seeing 403 or CORS errors:'),
          const Text('1. Presigned URLs may have expired'),
          const Text('2. S3 bucket permissions may have changed'),
          const Text('3. AWS credentials may be invalid'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            onRefresh();
            Navigator.of(context).pop();
          },
          child: const Text('Refresh All'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
