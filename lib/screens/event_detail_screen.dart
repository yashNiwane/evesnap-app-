import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/host_event.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.event,
    required this.eventService,
  });

  final HostEvent event;
  final EventService eventService;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _loading = true;
  bool _savingPhotos = false;
  bool _takingPhoto = false;
  final Set<String> _deletingPhotoIds = {};
  List<EventPhoto> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadEventView();
  }

  Future<void> _loadEventView() async {
    setState(() => _loading = true);
    try {
      final stats = await widget.eventService.getEventStats(widget.event.id);
      final photos = await widget.eventService.listEventPhotos(widget.event.id);
      String? coverSignedUrl = widget.event.coverSignedUrl;
      final coverPath = widget.event.coverPath;
      if ((coverSignedUrl == null || coverSignedUrl.isEmpty) &&
          coverPath != null &&
          coverPath.isNotEmpty) {
        coverSignedUrl = await widget.eventService.createCoverSignedUrl(
          coverPath,
        );
      }
      if (!mounted) return;
      setState(() {
        widget.event.guestCount = stats.guestCount;
        widget.event.photoCount = stats.photoCount;
        widget.event.coverSignedUrl = coverSignedUrl;
        _photos = photos;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load event: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revealNow() async {
    if (widget.event.isRevealed) return;
    final shouldReveal = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: EvePalette.coal,
          title: Text(
            'Reveal now?',
            style: GoogleFonts.dmSerifDisplay(color: EvePalette.bone),
          ),
          content: Text(
            'Guests will be able to view the full gallery immediately.',
            style: GoogleFonts.spaceGrotesk(color: EvePalette.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reveal'),
            ),
          ],
        );
      },
    );
    if (shouldReveal != true) return;

    await widget.eventService.revealEventNow(widget.event.id);
    if (!mounted) return;
    setState(() => widget.event.isManuallyRevealed = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Event revealed.')));
  }

  Future<void> _savePhotos() async {
    if (_savingPhotos) return;
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No photos to save yet.')));
      return;
    }

    setState(() => _savingPhotos = true);
    var savedCount = 0;
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      final canSave = hasAccess || await Gal.requestAccess(toAlbum: true);
      if (!canSave) {
        throw Exception('Gallery permission was denied.');
      }

      for (var i = 0; i < _photos.length; i += 1) {
        final photo = _photos[i];
        final bytes = await widget.eventService.downloadPhotoBytes(
          photo.storagePath,
        );
        await Gal.putImageBytes(
          bytes,
          album: 'Eve',
          name: 'eve-${widget.event.id}-${i + 1}',
        );
        savedCount += 1;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $savedCount photo${savedCount == 1 ? '' : 's'} to gallery.',
          ),
        ),
      );
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restart the app fully once to enable gallery saving.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save photos: $e')));
    } finally {
      if (mounted) setState(() => _savingPhotos = false);
    }
  }

  Future<void> _deletePhoto(EventPhoto photo) async {
    if (widget.event.isRevealed || _deletingPhotoIds.contains(photo.id)) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: EvePalette.coal,
          title: Text(
            'Delete photo?',
            style: GoogleFonts.dmSerifDisplay(color: EvePalette.bone),
          ),
          content: Text(
            'This photo will be removed before guests can see it.',
            style: GoogleFonts.spaceGrotesk(color: EvePalette.muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFE5E0),
                foregroundColor: const Color(0xFF36110C),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) return;

    setState(() => _deletingPhotoIds.add(photo.id));
    try {
      await widget.eventService.deleteEventPhoto(
        eventId: widget.event.id,
        photo: photo,
      );
      if (!mounted) return;
      setState(() {
        _photos = _photos.where((item) => item.id != photo.id).toList();
        widget.event.photoCount = widget.event.photoCount > 0
            ? widget.event.photoCount - 1
            : 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete photo: $e')));
    } finally {
      if (mounted) {
        setState(() => _deletingPhotoIds.remove(photo.id));
      }
    }
  }

  void _openPhotoViewer(EventPhoto photo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EvePalette.ink,
      showDragHandle: true,
      builder: (context) {
        return _PhotoViewerSheet(
          photo: photo,
          canDelete: !widget.event.isRevealed,
          isDeleting: _deletingPhotoIds.contains(photo.id),
          onDelete: () {
            Navigator.pop(context);
            _deletePhoto(photo);
          },
        );
      },
    );
  }

  void _openInviteSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EvePalette.coal,
      showDragHandle: true,
      builder: (context) {
        return _InviteSheet(
          event: widget.event,
          onShareQr: _shareQr,
          onShareLink: _shareLink,
        );
      },
    );
  }

  Future<void> _shareQr() async {
    try {
      final painter = QrPainter(
        data: widget.event.link,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: EvePalette.ink,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: EvePalette.ink,
        ),
      );
      const imageSize = 1024.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, imageSize, imageSize),
        Paint()..color = EvePalette.bone,
      );
      painter.paint(canvas, const Size.square(imageSize));
      final image = await recorder.endRecording().toImage(
        imageSize.toInt(),
        imageSize.toInt(),
      );
      final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (imageData == null) {
        throw Exception('Could not create QR image.');
      }

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/eve-${widget.event.id}-invite.png');
      await file.writeAsBytes(imageData.buffer.asUint8List(), flush: true);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], text: 'Join my Eve event: ${widget.event.link}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share QR: $e')));
    }
  }

  Future<void> _shareLink() {
    return Share.share('Join my Eve event: ${widget.event.link}');
  }

  Future<void> _captureHostPhoto() async {
    if (_takingPhoto) return;
    setState(() => _takingPhoto = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2200,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final photo = await widget.eventService.uploadEventPhoto(
        eventId: widget.event.id,
        bytes: bytes,
        fileExt: picked.name.split('.').last,
        caption: 'Captured by host',
        sourceType: 'camera',
      );

      if (!mounted) return;
      setState(() {
        _photos = [photo, ..._photos];
        widget.event.photoCount += 1;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo added to event.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add photo: $e')));
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EvePalette.coal,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy event link'),
                  subtitle: SelectableText(widget.event.link),
                ),
                ListTile(
                  enabled: !widget.event.isRevealed,
                  leading: const Icon(Icons.lock_open_rounded),
                  title: const Text('Reveal now'),
                  onTap: () {
                    Navigator.pop(context);
                    _revealNow();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;

    return Scaffold(
      backgroundColor: EvePalette.ink,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadEventView,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _GlassIconButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.pop(context),
                            tooltip: 'Back',
                          ),
                          const Spacer(),
                          _GlassIconButton(
                            icon: Icons.settings_rounded,
                            onTap: _openSettings,
                            tooltip: 'Settings',
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              event.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.dmSerifDisplay(
                                color: EvePalette.bone,
                                fontSize: 42,
                                height: 0.94,
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          _CoverThumb(event: event),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _EventMeta(event: event),
                      const SizedBox(height: 22),
                      if (!event.isRevealed) ...[
                        _RevealNowPanel(onTap: _revealNow),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          _ActionPill(
                            icon: Icons.download_rounded,
                            label: _savingPhotos ? 'Saving' : 'Save',
                            onTap: _savePhotos,
                          ),
                          const SizedBox(width: 8),
                          _ActionPill(
                            icon: Icons.qr_code_rounded,
                            label: 'Invite',
                            onTap: _openInviteSheet,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _PrimaryActionPill(
                              icon: Icons.photo_camera_rounded,
                              label: _takingPhoto ? 'Adding' : 'Camera',
                              onTap: _captureHostPhoto,
                            ),
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
              else if (_photos.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'No guest photos yet. They will appear here as soon as people start capturing moments.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          color: EvePalette.muted,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  sliver: SliverGrid.builder(
                    itemCount: _photos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.72,
                        ),
                    itemBuilder: (context, index) {
                      final photo = _photos[index];
                      return _PhotoTile(
                        photo: photo,
                        index: index,
                        canDelete: !event.isRevealed,
                        isDeleting: _deletingPhotoIds.contains(photo.id),
                        onOpen: () => _openPhotoViewer(photo),
                        onDelete: () => _deletePhoto(photo),
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
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.event});

  final HostEvent event;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox.square(
        dimension: 74,
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
    );
  }
}

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({
    required this.event,
    required this.onShareQr,
    required this.onShareLink,
  });

  final HostEvent event;
  final VoidCallback onShareQr;
  final VoidCallback onShareLink;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = screenHeight * 0.78;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final qrSize = math.min(
              214.0,
              math.max(154.0, constraints.maxHeight - 196),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Invite guests',
                    style: GoogleFonts.dmSerifDisplay(
                      color: EvePalette.bone,
                      fontSize: 32,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    event.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: qrSize,
                    height: qrSize,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: EvePalette.bone,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: EvePalette.sage.withValues(alpha: 0.18),
                          blurRadius: 42,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: event.link,
                      version: QrVersions.auto,
                      gapless: true,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: EvePalette.ink,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: EvePalette.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _InviteButton(
                          icon: Icons.qr_code_2_rounded,
                          label: 'Share QR',
                          onTap: () {
                            Navigator.pop(context);
                            onShareQr();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InviteButton(
                          icon: Icons.link_rounded,
                          label: 'Share link',
                          onTap: () {
                            Navigator.pop(context);
                            onShareLink();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  const _InviteButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: EvePalette.bone,
        foregroundColor: EvePalette.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EventMeta extends StatelessWidget {
  const _EventMeta({required this.event});

  final HostEvent event;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetaLine(icon: Icons.schedule_rounded, text: _timeStatus),
        const SizedBox(height: 6),
        _MetaLine(
          icon: Icons.groups_rounded,
          text: '${event.guestCount} people joined',
        ),
        const SizedBox(height: 6),
        _MetaLine(
          icon: Icons.photo_library_rounded,
          text: '${event.photoCount} photos',
        ),
      ],
    );
  }

  String get _timeStatus {
    if (event.isRevealed) return 'Completed';
    final remaining = event.revealTime.difference(DateTime.now());
    if (remaining.inMinutes <= 0) return 'Unlocking now';
    if (remaining.inHours >= 24) {
      final days = remaining.inDays;
      return '$days day${days == 1 ? '' : 's'} left';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h left';
    }
    return '${remaining.inMinutes}m left';
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: EvePalette.sage, size: 16),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.spaceGrotesk(
            color: EvePalette.muted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: EvePalette.coal.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EvePalette.line),
          ),
          child: Icon(icon, color: EvePalette.bone),
        ),
      ),
    );
  }
}

class _RevealNowPanel extends StatelessWidget {
  const _RevealNowPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: EvePalette.bone,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.lock_open_rounded,
              color: EvePalette.ink,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reveal now',
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Publish the gallery early.',
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.ink.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: EvePalette.ink),
          ],
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: EvePalette.bone,
        side: const BorderSide(color: EvePalette.line),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PrimaryActionPill extends StatelessWidget {
  const _PrimaryActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: EvePalette.bone,
        foregroundColor: EvePalette.ink,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.index,
    required this.canDelete,
    required this.isDeleting,
    required this.onOpen,
    required this.onDelete,
  });

  final EventPhoto photo;
  final int index;
  final bool canDelete;
  final bool isDeleting;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
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
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    EvePalette.ink.withValues(alpha: 0.20),
                    Colors.transparent,
                    EvePalette.ink.withValues(alpha: 0.20),
                  ],
                ),
              ),
            ),
            if (canDelete)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: EvePalette.ink.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: isDeleting ? null : onDelete,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox.square(
                      dimension: 36,
                      child: Center(
                        child: isDeleting
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                color: EvePalette.bone,
                                size: 19,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    photo.displayCapturedBy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.bone,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (photo.caption.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      photo.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: EvePalette.bone.withValues(alpha: 0.82),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoViewerSheet extends StatelessWidget {
  const _PhotoViewerSheet({
    required this.photo,
    required this.canDelete,
    required this.isDeleting,
    required this.onDelete,
  });

  final EventPhoto photo;
  final bool canDelete;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final viewHeight = MediaQuery.sizeOf(context).height * 0.84;

    return SafeArea(
      child: SizedBox(
        height: viewHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (photo.signedUrl == null)
                        const ColoredBox(color: EvePalette.coal)
                      else
                        InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Image.network(
                            photo.signedUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: EvePalette.coal),
                          ),
                        ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _ViewerIconButton(
                          icon: Icons.close_rounded,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ViewerMetaLine(
                          icon: Icons.person_rounded,
                          text: 'Captured by ${photo.displayCapturedBy}',
                        ),
                        const SizedBox(height: 8),
                        _ViewerMetaLine(
                          icon: Icons.schedule_rounded,
                          text: _formatCapturedAt(photo.displayCapturedAt),
                        ),
                        if (photo.capturedIp != null) ...[
                          const SizedBox(height: 8),
                          _ViewerMetaLine(
                            icon: Icons.wifi_tethering_rounded,
                            text: 'IP ${photo.capturedIp}',
                          ),
                        ],
                        if (photo.caption.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            photo.caption,
                            style: GoogleFonts.spaceGrotesk(
                              color: EvePalette.bone,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canDelete) ...[
                    const SizedBox(width: 12),
                    _DeletePhotoButton(isDeleting: isDeleting, onTap: onDelete),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCapturedAt(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : value.hour > 12
        ? value.hour - 12
        : value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day}/${value.month}/${value.year} at $hour:$minute $suffix';
  }
}

class _ViewerMetaLine extends StatelessWidget {
  const _ViewerMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: EvePalette.sage, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              color: EvePalette.muted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewerIconButton extends StatelessWidget {
  const _ViewerIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EvePalette.ink.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: SizedBox.square(
          dimension: 42,
          child: Icon(icon, color: EvePalette.bone, size: 22),
        ),
      ),
    );
  }
}

class _DeletePhotoButton extends StatelessWidget {
  const _DeletePhotoButton({required this.isDeleting, required this.onTap});

  final bool isDeleting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isDeleting ? null : onTap,
      icon: isDeleting
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_outline_rounded, size: 17),
      label: const Text('Delete'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFFFD4CC),
        disabledForegroundColor: EvePalette.muted,
        side: BorderSide(color: const Color(0xFFFFD4CC).withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: GoogleFonts.spaceGrotesk(
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
