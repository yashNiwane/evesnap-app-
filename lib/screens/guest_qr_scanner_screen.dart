import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/event_service.dart';
import '../theme/eve_palette.dart';
import 'guest_join_screen.dart';

class GuestQrScannerScreen extends StatefulWidget {
  const GuestQrScannerScreen({super.key, required this.eventService});

  final EventService eventService;

  @override
  State<GuestQrScannerScreen> createState() => _GuestQrScannerScreenState();
}

class _GuestQrScannerScreenState extends State<GuestQrScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 120,
  );
  bool _handlingScan = false;
  String? _lastRejectedRaw;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_handlingScan) return;

    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull;
    if (rawValue == null) return;
    debugPrint('[EveGuestQR] raw=$rawValue');
    await _openInvite(rawValue);
  }

  Future<void> _openInvite(String rawValue) async {
    final eventId = _extractEventId(rawValue);
    if (eventId == null) {
      if (_lastRejectedRaw != rawValue) {
        _lastRejectedRaw = rawValue;
        _showMessage('This QR does not include an Eve event id.');
      }
      return;
    }

    setState(() => _handlingScan = true);
    await _controller.stop();
    try {
      final event = await widget.eventService.getEventById(eventId);
      await widget.eventService.saveLastGuestEventId(eventId);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GuestJoinScreen(event: event, eventService: widget.eventService),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not open this event invite.');
      setState(() => _handlingScan = false);
      await _controller.start();
    }
  }

  String? _extractEventId(String rawValue) {
    final trimmed = rawValue.trim();
    final normalized = Uri.decodeFull(trimmed);
    final uri = Uri.tryParse(normalized);
    final fromQuery =
        uri?.queryParameters['event_id'] ??
        uri?.queryParameters['eventId'] ??
        uri?.queryParameters['id'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

    final nestedValues = uri?.queryParameters.values ?? const Iterable.empty();
    for (final value in nestedValues) {
      if (value == normalized) continue;
      final nestedEventId = _extractEventId(value);
      if (nestedEventId != null) return nestedEventId;
    }

    final uuidPattern = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    );
    return uuidPattern.firstMatch(normalized)?.group(0);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _enterInviteManually() async {
    final controller = TextEditingController();
    final rawValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EvePalette.coal,
      showDragHandle: true,
      builder: (context) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 4, 22, 22 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter invite',
                  style: GoogleFonts.dmSerifDisplay(
                    color: EvePalette.bone,
                    fontSize: 34,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: GoogleFonts.spaceGrotesk(color: EvePalette.bone),
                  decoration: const InputDecoration(
                    hintText: 'Paste event link or event id',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, controller.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue'),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    if (rawValue == null || rawValue.trim().isEmpty) return;
    await _openInvite(rawValue);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scanSize = (size.width * 0.72).clamp(220.0, 300.0);

    return Scaffold(
      backgroundColor: EvePalette.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleScan),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  EvePalette.ink.withValues(alpha: 0.86),
                  Colors.transparent,
                  EvePalette.ink.withValues(alpha: 0.90),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Back',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: 'Torch',
                        onPressed: _controller.toggleTorch,
                        icon: const Icon(Icons.flash_on_rounded),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Center(
                    child: Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(color: EvePalette.bone, width: 2),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Scan invite',
                    style: GoogleFonts.dmSerifDisplay(
                      color: EvePalette.bone,
                      fontSize: 50,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Point your camera at the event QR to join as a guest.',
                    style: GoogleFonts.spaceGrotesk(
                      color: EvePalette.parchment,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (_handlingScan) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _handlingScan ? null : _enterInviteManually,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Enter link manually'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EvePalette.bone,
                      side: const BorderSide(color: EvePalette.line),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
