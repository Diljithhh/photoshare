// import 'package:flutter/material.dart';
// import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

// class PhotoGrid extends StatelessWidget {
//   final List<String> photos;
//   final Set<String> selectedPhotos;
//   final Function(String) onPhotoTap;
//   final VoidCallback onSaveSelections;
//   final bool isLoading;

//   const PhotoGrid({
//     Key? key,
//     required this.photos,
//     required this.selectedPhotos,
//     required this.onPhotoTap,
//     required this.onSaveSelections,
//     required this.isLoading,
//   }) : super(key: key);

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         Expanded(
//           child: MasonryGridView.count(
//             crossAxisCount: 3,
//             mainAxisSpacing: 4,
//             crossAxisSpacing: 4,
//             itemCount: photos.length,
//             itemBuilder: (context, index) {
//               final photoUrl = photos[index];
//               final isSelected = selectedPhotos.contains(photoUrl);
//               return GestureDetector(
//                 onTap: () => onPhotoTap(photoUrl),
//                 child: Stack(
//                   children: [
//                     Image.network(photoUrl, fit: BoxFit.cover),
//                     if (isSelected)
//                       Positioned.fill(
//                         child: Container(
//                           color: Colors.blue.withOpacity(0.3),
//                           child: const Icon(Icons.check, color: Colors.white),
//                         ),
//                       ),
//                   ],
//                 ),
//               );
//             },
//           ),
//         ),
//         Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Row(
//             children: [
//               Text('${selectedPhotos.length} photos selected'),
//               const Spacer(),
//               ElevatedButton(
//                 onPressed: isLoading ? null : onSaveSelections,
//                 child: isLoading
//                     ? const CircularProgressIndicator()
//                     : const Text('Save Selections'),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class PhotoGrid extends StatelessWidget {
  final List<String> photos;
  final Set<String> selectedPhotos;
  final Function(String) onPhotoTap;
  final VoidCallback onSaveSelections;
  final bool isLoading;

  const PhotoGrid({
    Key? key,
    required this.photos,
    required this.selectedPhotos,
    required this.onPhotoTap,
    required this.onSaveSelections,
    required this.isLoading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _buildPhotoGrid(),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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
          Icon(Icons.photo_library, color: Colors.blueGrey[800]),
          const SizedBox(width: 8),
          Text(
            'Photo Selection',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
            ),
          ),
          const Spacer(),
          Text(
            '${selectedPhotos.length} selected',
            style: TextStyle(
              color: Colors.blueGrey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return MasonryGridView.count(
      crossAxisCount: 4, // Increased for more columns
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photoUrl = photos[index];
        final isSelected = selectedPhotos.contains(photoUrl);
        return GestureDetector(
          onTap: () => onPhotoTap(photoUrl),
          child: Stack(
            children: [
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
              ),
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    color: Colors.blueGrey[700]!.withOpacity(0.7),
                    child: const Icon(Icons.check, color: Colors.white),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '${selectedPhotos.length} photos selected',
            style: TextStyle(
              color: Colors.blueGrey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: isLoading ? null : onSaveSelections,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Save Selections'),
          ),
        ],
      ),
    );
  }
}
