// import 'package:flutter/material.dart';

// import 'package:photoshare/screens/auth_view.dart';
// import 'package:photoshare/screens/photo_grid.dart';
// import 'package:photoshare/screens/settings.dart';
// import 'package:photoshare/services/api_service.dart';





// class SessionsView extends StatefulWidget {
//   final String sessionId;

//   const SessionsView({super.key, required this.sessionId});

//   @override
//   State<SessionsView> createState() => _SessionsViewState();
// }

// class _SessionsViewState extends State<SessionsView> {
//   final ApiService _apiService = ApiService();
//   String? _accessToken;
//   List<String> _photos = [];
//   Set<String> _selectedPhotos = {};
//   bool _isLoading = false;
//   String? _errorMessage;

//   Future<void> _authenticate(String password) async {
//     setState(() {
//       _isLoading = true;
//       _errorMessage = null;
//     });

//     try {
//       final token = await _apiService.authenticate(widget.sessionId, password);
//       setState(() {
//         _accessToken = token;
//       });
//       await _fetchPhotos();
//     } catch (e) {
//       setState(() {
//         _errorMessage = 'Authentication failed: $e';
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _fetchPhotos() async {
//     if (_accessToken == null) return;

//     setState(() {
//       _isLoading = true;
//       _errorMessage = null;
//     });

//     try {
//       final fetchedPhotos = await _apiService.fetchPhotos(widget.sessionId, _accessToken!);
//       setState(() {
//         _photos = fetchedPhotos;
//       });
//     } catch (e) {
//       setState(() {
//         _errorMessage = 'Error loading photos: $e';
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _saveSelections() async {
//     if (_accessToken == null) return;

//     setState(() {
//       _isLoading = true;
//       _errorMessage = null;
//     });

//     try {
//       await _apiService.saveSelections(widget.sessionId, _accessToken!, _selectedPhotos.toList());
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Selections saved successfully')),
//       );
//     } catch (e) {
//       setState(() {
//         _errorMessage = 'Error saving selections: $e';
//       });
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   void _togglePhotoSelection(String photoUrl) {
//     setState(() {
//       if (_selectedPhotos.contains(photoUrl)) {
//         _selectedPhotos.remove(photoUrl);
//       } else {
//         _selectedPhotos.add(photoUrl);
//       }
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Select Photos'),
//         actions: [
//           if (_accessToken != null)
//             IconButton(
//               icon: const Icon(Icons.settings),
//               onPressed: () => showDialog(
//                 context: context,
//                 builder: (context) => SettingsDialog(
//                   apiService: _apiService,
//                   sessionId: widget.sessionId,
//                   accessToken: _accessToken!,
//                   onRefresh: _fetchPhotos,
//                 ),
//               ),
//             ),
//         ],
//       ),
//       body: _accessToken == null
//           ? AuthenticationView(
//               onAuthenticate: _authenticate,
//               isLoading: _isLoading,
//               errorMessage: _errorMessage,
//             )
//           : PhotoGrid(
//               photos: _photos,
//               selectedPhotos: _selectedPhotos,
//               onPhotoTap: _togglePhotoSelection,
//               onSaveSelections: _saveSelections,
//               isLoading: _isLoading,
//             ),
//     );
//   }
// }
