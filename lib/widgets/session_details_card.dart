import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:photoshare/screens/sessionModels.dart';

class SessionDetailsCard extends StatelessWidget {
  final SessionResponse session;

  const SessionDetailsCard({Key? key, required this.session}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                        session.sessionLink,
                        style: const TextStyle(color: Colors.blue),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: session.sessionLink));
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
                    'View photos at: ${session.sessionLink}\nPassword: ${session.password}';
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
                final uri = Uri.parse(session.sessionLink);
                final pathSegments = uri.pathSegments;
                if (pathSegments.length >= 2 && pathSegments[0] == 'session') {
                  final sessionId = pathSegments[1];
                  // Use go_router for navigation
                  context.go('/session/$sessionId');
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
