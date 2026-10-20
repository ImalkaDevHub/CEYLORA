import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip_photo.dart';
import '../providers/trip_photos_provider.dart';
import '../screens/photo_viewer_screen.dart';
import '../services/photo_picker.dart';

/// "Photos" block on the trip screen: a thumbnail grid and an Add button that
/// offers the camera or the gallery. Photos are stored on this device only.
class TripPhotosSection extends StatefulWidget {
  final String tripId;
  const TripPhotosSection({super.key, required this.tripId});

  @override
  State<TripPhotosSection> createState() => _TripPhotosSectionState();
}

class _TripPhotosSectionState extends State<TripPhotosSection> {
  @override
  void initState() {
    super.initState();
    // After the first frame so the provider notifies outside of build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TripPhotosProvider>().load(widget.tripId);
    });
  }

  Future<void> _add() async {
    final provider = context.read<TripPhotosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(sheet).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(sheet).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final error = await provider.add(widget.tripId, source);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripPhotosProvider>();
    final photos = provider.photosFor(widget.tripId);
    final busy = provider.isBusy(widget.tripId);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                  photos.isEmpty ? 'Photos' : 'Photos (${photos.length})',
                  style: theme.textTheme.titleMedium),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : _add,
              icon: busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!provider.hasLoaded(widget.tripId))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (photos.isEmpty)
          Text('No photos yet. Add some to remember this trip.',
              style: theme.textTheme.bodyMedium)
        else
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < photos.length; i++)
                _Thumbnail(
                  key: ValueKey(photos[i].path),
                  photo: photos[i],
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PhotoViewerScreen(
                          tripId: widget.tripId, initialIndex: i))),
                ),
            ],
          ),
        const SizedBox(height: 4),
        Text('Photos are saved on this device only.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final TripPhoto photo;
  final VoidCallback onTap;
  const _Thumbnail({super.key, required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(photo.path),
          fit: BoxFit.cover,
          // Decode small: thumbnails don't need the full-resolution photo.
          cacheWidth: 360,
          errorBuilder: (_, _, _) => Container(
            color: scheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, color: scheme.outline),
          ),
        ),
      ),
    );
  }
}
