import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/host_event.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';
import 'eve_camera_screen.dart';

class GuestHomeScreen extends StatefulWidget {
  const GuestHomeScreen({
    super.key,
    required this.event,
    required this.guest,
    required this.eventService,
  });

  final HostEvent event;
  final GuestProfile guest;
  final EventService eventService;

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> {
  bool _loading = true;
  List<EventPhoto> _photos = [];
  final List<_QueuedMoment> _queuedMoments = [];

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() => _loading = true);
    try {
      final photos = await widget.eventService.listEventPhotos(widget.event.id);
      if (!mounted) return;
      setState(() => _photos = photos);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not load moments: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMoment(ImageSource source) async {
    if (widget.event.isRevealed) return;

    try {
      if (source == ImageSource.camera) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => EveCameraScreen(
              closeAfterAccept: false,
              onPhotoAccepted: (image) async => _queueMoment(image, source),
            ),
          ),
        );
        return;
      } else {
        final picked = await ImagePicker().pickImage(
          source: source,
          imageQuality: 88,
          maxWidth: 2200,
        );
        if (picked == null) return;
        await _queueMoment(picked, source);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not add moment: $e');
    }
  }

  Future<void> _queueMoment(XFile picked, ImageSource source) async {
    final queueItem = _QueuedMoment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      path: picked.path,
      source: source,
    );
    if (mounted) {
      setState(() => _queuedMoments.insert(0, queueItem));
    }

    unawaited(_backupQueuedMoment(queueItem, picked));
  }

  Future<void> _backupQueuedMoment(
    _QueuedMoment queueItem,
    XFile picked,
  ) async {
    try {
      final bytes = await picked.readAsBytes();
      final photo = await widget.eventService.uploadEventPhoto(
        eventId: widget.event.id,
        bytes: bytes,
        fileExt: picked.name.split('.').last,
        sourceType: queueItem.source == ImageSource.camera
            ? 'guest_camera'
            : 'gallery',
      );
      if (!mounted) return;
      setState(() {
        _photos = [photo, ..._photos];
        _queuedMoments.removeWhere((item) => item.id == queueItem.id);
        widget.event.photoCount += 1;
      });
      _showMessage('Moment backed up.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _queuedMoments.indexWhere(
          (item) => item.id == queueItem.id,
        );
        if (index >= 0) {
          _queuedMoments[index] = queueItem.copyWith(
            failed: true,
            error: e.toString(),
          );
        }
      });
      _showMessage('A moment could not be backed up.');
    }
  }

  Future<void> _openQueuedMomentActions(_QueuedMoment moment) async {
    final action = await _showMomentActions(
      title: moment.failed ? 'Pending moment' : 'Backing up moment',
      canView: true,
      canDelete: true,
    );
    if (action == _MomentActionChoice.view) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _LocalMomentViewer(path: moment.path),
        ),
      );
      return;
    }
    if (action == _MomentActionChoice.delete) {
      setState(
        () => _queuedMoments.removeWhere((item) => item.id == moment.id),
      );
    }
  }

  Future<void> _openUploadedMomentActions(EventPhoto photo) async {
    final action = await _showMomentActions(
      title: 'Moment',
      canView: photo.signedUrl != null,
      canDelete: true,
    );
    if (action == _MomentActionChoice.view && photo.signedUrl != null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _RemoteMomentViewer(photo: photo)),
      );
      return;
    }
    if (action != _MomentActionChoice.delete) return;

    try {
      await widget.eventService.deleteEventPhoto(
        eventId: widget.event.id,
        photo: photo,
      );
      if (!mounted) return;
      setState(() => _photos.removeWhere((item) => item.id == photo.id));
      _showMessage('Moment deleted.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not delete moment: $e');
    }
  }

  Future<_MomentActionChoice?> _showMomentActions({
    required String title,
    required bool canView,
    required bool canDelete,
  }) {
    return showModalBottomSheet<_MomentActionChoice>(
      context: context,
      backgroundColor: EvePalette.coal,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSerifDisplay(
                    color: EvePalette.bone,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 16),
                if (canView)
                  _MomentAction(
                    icon: Icons.visibility_rounded,
                    title: 'View',
                    onTap: () =>
                        Navigator.pop(context, _MomentActionChoice.view),
                  ),
                if (canView && canDelete) const SizedBox(height: 10),
                if (canDelete)
                  _MomentAction(
                    icon: Icons.delete_outline_rounded,
                    title: 'Delete',
                    onTap: () =>
                        Navigator.pop(context, _MomentActionChoice.delete),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    return Scaffold(
      backgroundColor: EvePalette.ink,
      floatingActionButton: event.isRevealed
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddMomentSheet(context),
              icon: const Icon(Icons.add_a_photo_rounded, size: 24),
              label: const Text('Add moment'),
              extendedPadding: const EdgeInsets.symmetric(horizontal: 24),
              extendedIconLabelSpacing: 12,
              extendedTextStyle: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPhotos,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const Spacer(),
                          Text(
                            widget.guest.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                              color: EvePalette.parchment,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _GuestHero(event: event),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          _GuestMetric(
                            icon: Icons.photo_library_rounded,
                            label:
                                '${_photos.length + _queuedMoments.length} moments',
                          ),
                          const SizedBox(width: 10),
                          _GuestMetric(
                            icon: event.isRevealed
                                ? Icons.lock_open_rounded
                                : Icons.lock_clock_rounded,
                            label: event.isRevealed ? 'Unlocked' : _timeStatus,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_photos.isEmpty && _queuedMoments.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        event.isRevealed
                            ? 'No shared moments yet.'
                            : 'Add the first moment before the gallery unlocks.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          color: EvePalette.muted,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 108),
                  sliver: SliverGrid.builder(
                    itemCount: _queuedMoments.length + _photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.74,
                        ),
                    itemBuilder: (context, index) {
                      if (index < _queuedMoments.length) {
                        return _QueuedMomentTile(
                          moment: _queuedMoments[index],
                          onTap: () =>
                              _openQueuedMomentActions(_queuedMoments[index]),
                        );
                      }
                      return _GuestPhotoTile(
                        photo: _photos[index - _queuedMoments.length],
                        onTap: () => _openUploadedMomentActions(
                          _photos[index - _queuedMoments.length],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _timeStatus {
    final remaining = widget.event.revealTime.difference(DateTime.now());
    if (remaining.inMinutes <= 0) return 'Unlocking';
    if (remaining.inHours >= 24) return '${remaining.inDays}d left';
    if (remaining.inHours > 0) return '${remaining.inHours}h left';
    return '${remaining.inMinutes}m left';
  }

  void _showAddMomentSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EvePalette.coal,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MomentAction(
                  icon: Icons.photo_camera_rounded,
                  title: 'Use camera',
                  onTap: () {
                    Navigator.pop(context);
                    _addMoment(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 10),
                _MomentAction(
                  icon: Icons.photo_library_rounded,
                  title: 'Choose from gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _addMoment(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueuedMoment {
  const _QueuedMoment({
    required this.id,
    required this.path,
    required this.source,
    this.failed = false,
    this.error,
  });

  final String id;
  final String path;
  final ImageSource source;
  final bool failed;
  final String? error;

  _QueuedMoment copyWith({bool? failed, String? error}) {
    return _QueuedMoment(
      id: id,
      path: path,
      source: source,
      failed: failed ?? this.failed,
      error: error ?? this.error,
    );
  }
}

enum _MomentActionChoice { view, delete }

class _GuestHero extends StatelessWidget {
  const _GuestHero({required this.event});

  final HostEvent event;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            event.name,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSerifDisplay(
              color: EvePalette.bone,
              fontSize: 50,
              height: 0.92,
            ),
          ),
        ),
        const SizedBox(width: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox.square(
            dimension: 102,
            child: event.coverSignedUrl == null
                ? Image.asset(
                    'assets/images/minimalcamera.jpg',
                    fit: BoxFit.cover,
                    color: EvePalette.sage,
                    colorBlendMode: BlendMode.modulate,
                  )
                : Image.network(
                    event.coverSignedUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images/minimalcamera.jpg',
                      fit: BoxFit.cover,
                      color: EvePalette.sage,
                      colorBlendMode: BlendMode.modulate,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _GuestMetric extends StatelessWidget {
  const _GuestMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: EvePalette.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: EvePalette.sage, size: 16),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: EvePalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestPhotoTile extends StatelessWidget {
  const _GuestPhotoTile({required this.photo, required this.onTap});

  final EventPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo.signedUrl == null)
              const ColoredBox(color: EvePalette.coal)
            else
              Image.network(
                photo.signedUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: EvePalette.coal),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                photo.displayCapturedBy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  color: EvePalette.bone,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueuedMomentTile extends StatelessWidget {
  const _QueuedMomentTile({required this.moment, required this.onTap});

  final _QueuedMoment moment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(moment.path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: EvePalette.coal),
            ),
            ColoredBox(
              color: EvePalette.ink.withValues(
                alpha: moment.failed ? 0.58 : 0.28,
              ),
            ),
            Center(
              child: moment.failed
                  ? const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFFFD4CC),
                      size: 30,
                    )
                  : const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Text(
                moment.failed ? 'Tap to remove' : 'Backing up',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  color: EvePalette.bone,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MomentAction extends StatelessWidget {
  const _MomentAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: EvePalette.line),
      ),
      leading: Icon(icon, color: EvePalette.bone),
      title: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          color: EvePalette.bone,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LocalMomentViewer extends StatelessWidget {
  const _LocalMomentViewer({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_rounded)),
            ),
            Positioned(
              left: 18,
              top: 18,
              child: _ViewerCloseButton(onTap: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteMomentViewer extends StatelessWidget {
  const _RemoteMomentViewer({required this.photo});

  final EventPhoto photo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              photo.signedUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_rounded)),
            ),
            Positioned(
              left: 18,
              top: 18,
              child: _ViewerCloseButton(onTap: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerCloseButton extends StatelessWidget {
  const _ViewerCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.48),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Close',
        onPressed: onTap,
        icon: const Icon(Icons.close_rounded, color: Colors.white),
      ),
    );
  }
}
