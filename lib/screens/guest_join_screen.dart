import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/host_event.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';
import 'guest_home_screen.dart';

class GuestJoinScreen extends StatefulWidget {
  const GuestJoinScreen({
    super.key,
    required this.event,
    required this.eventService,
  });

  final HostEvent event;
  final EventService eventService;

  @override
  State<GuestJoinScreen> createState() => _GuestJoinScreenState();
}

class _GuestJoinScreenState extends State<GuestJoinScreen> {
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  bool _joining = false;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final nickname = _nameController.text.trim();
    if (nickname.length < 2) {
      _showMessage('Add the name guests will see.');
      _nameFocusNode.requestFocus();
      return;
    }

    setState(() => _joining = true);
    try {
      final guest = await widget.eventService.joinEventAsGuest(
        eventId: widget.event.id,
        nickname: nickname,
      );
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GuestHomeScreen(
            event: widget.event,
            guest: guest,
            eventService: widget.eventService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not join event: $e');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: EvePalette.ink,
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: EdgeInsets.fromLTRB(24, 18, 24, 28 + keyboardInset),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: _joining ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(height: 28),
            _EventPreview(event: widget.event),
            const SizedBox(height: 34),
            Text(
              'What should we call you?',
              style: GoogleFonts.dmSerifDisplay(
                color: EvePalette.bone,
                fontSize: 48,
                height: 0.98,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This name appears beside the moments you add.',
              style: GoogleFonts.spaceGrotesk(
                color: EvePalette.muted,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _join(),
              style: GoogleFonts.spaceGrotesk(
                color: EvePalette.bone,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                hintText: 'Your name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _joining ? null : _join,
              icon: _joining
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(_joining ? 'Joining...' : 'Join event'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventPreview extends StatelessWidget {
  const _EventPreview({required this.event});

  final HostEvent event;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSerifDisplay(
                  color: EvePalette.bone,
                  fontSize: 34,
                  height: 0.96,
                ),
              ),
              if (event.details.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  event.details,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    color: EvePalette.muted,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox.square(
            dimension: 104,
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
