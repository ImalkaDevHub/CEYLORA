import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/trip_photos_provider.dart';

/// Full-screen, swipeable, zoomable view of a trip's photos with delete.
class PhotoViewerScreen extends StatefulWidget {
  final String tripId;
  final int initialIndex;
  const PhotoViewerScreen(
      {super.key, required this.tripId, required this.initialIndex});

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final provider = context.read<TripPhotosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final photos = provider.photosFor(widget.tripId);
    if (_index < 0 || _index >= photos.length) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('It will be removed from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialog).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await provider.remove(photos[_index]);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = context.watch<TripPhotosProvider>().photosFor(widget.tripId);

    // Everything was deleted (or cleared): nothing left to show.
    if (photos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Photos')),
        body: const Center(child: Text('No photos.')),
      );
    }

    final index = _index.clamp(0, photos.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text('${index + 1} of ${photos.length}'),
        actions: [
          IconButton(
            tooltip: 'Delete photo',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _controller,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(photos[i].path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
