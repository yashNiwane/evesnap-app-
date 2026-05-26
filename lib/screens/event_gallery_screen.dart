import 'package:flutter/material.dart';

import '../models/host_event.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';

class EventGalleryScreen extends StatefulWidget {
  const EventGalleryScreen({
    super.key,
    required this.event,
    required this.eventService,
  });

  final HostEvent event;
  final EventService eventService;

  @override
  State<EventGalleryScreen> createState() => _EventGalleryScreenState();
}

class _EventGalleryScreenState extends State<EventGalleryScreen> {
  bool _loading = true;
  List<EventPhoto> _photos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final photos = await widget.eventService.listEventPhotos(widget.event.id);
      if (!mounted) return;
      setState(() => _photos = photos);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvePalette.ink,
      appBar: AppBar(title: const Text('Event Gallery')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download-all wiring next step.')),
        ),
        icon: const Icon(Icons.download),
        label: const Text('Download All'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _photos.isEmpty
          ? const Center(
              child: Text(
                'No photos uploaded yet.',
                style: TextStyle(color: EvePalette.muted),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _photos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final photo = _photos[index];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GridTile(
                    footer: photo.caption.isEmpty
                        ? null
                        : Container(
                            color: EvePalette.ink.withValues(alpha: 0.72),
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              photo.caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    child: photo.signedUrl == null
                        ? Container(
                            color: EvePalette.coal,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              photo.storagePath,
                              style: const TextStyle(
                                color: EvePalette.muted,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : Image.network(
                            photo.signedUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: EvePalette.coal,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(8),
                              child: const Text(
                                'Could not load photo',
                                style: TextStyle(color: EvePalette.muted),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
    );
  }
}
