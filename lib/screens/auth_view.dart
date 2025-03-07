// import 'package:flutter/material.dart';

// class AuthenticationView extends StatelessWidget {
//   final Function(String) onAuthenticate;
//   final bool isLoading;
//   final String? errorMessage;

//   AuthenticationView({
//     required this.onAuthenticate,
//     required this.isLoading,
//     this.errorMessage,
//   });

//   final TextEditingController _passwordController = TextEditingController();

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           TextField(
//             controller: _passwordController,
//             decoration: const InputDecoration(
//               labelText: 'Enter Password',
//               border: OutlineInputBorder(),
//             ),
//             obscureText: true,
//             onSubmitted: (_) => onAuthenticate(_passwordController.text),
//           ),
//           const SizedBox(height: 16),
//           ElevatedButton(
//             onPressed: isLoading ? null : () => onAuthenticate(_passwordController.text),
//             child: isLoading
//                 ? const CircularProgressIndicator()
//                 : const Text('View Photos'),
//           ),
//           if (errorMessage != null)
//             Padding(
//               padding: const EdgeInsets.only(top: 16),
//               child: Text(
//                 errorMessage!,
//                 style: const TextStyle(color: Colors.red),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';

class AuthenticationView extends StatelessWidget {
  final Function(String) onAuthenticate;
  final bool isLoading;
  final String? errorMessage;

  AuthenticationView({
    required this.onAuthenticate,
    required this.isLoading,
    this.errorMessage,
  });

  final TextEditingController _passwordController = TextEditingController();

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
                      'Secure Access',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the password to view shared photos',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 48),
                    _buildAuthenticationForm(),
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
          Row(
            children: [
              Icon(Icons.lock, color: Colors.blueGrey[800]),
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
        ],
      ),
    );
  }

  Widget _buildAuthenticationForm() {
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
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Enter Password',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            obscureText: true,
            onSubmitted: (_) => onAuthenticate(_passwordController.text),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isLoading ? null : () => onAuthenticate(_passwordController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              minimumSize: const Size(double.infinity, 48),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('View Photos'),
          ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
        ],
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
