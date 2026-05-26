import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/host_event.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';
import 'login_screen.dart';

class EventsDashboardScreen extends StatefulWidget {
  const EventsDashboardScreen({
    super.key,
    required this.authService,
    required this.eventService,
  });

  final AuthService authService;
  final EventService eventService;

  @override
  State<EventsDashboardScreen> createState() => _EventsDashboardScreenState();
}

class _EventsDashboardScreenState extends State<EventsDashboardScreen> {
  bool _loading = true;
  bool _signingOut = false;
  bool _openedFirstEventFlow = false;
  List<HostEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    try {
      final events = await widget.eventService.listHostEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
      });
      if (events.isEmpty && !_openedFirstEventFlow) {
        _openedFirstEventFlow = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _createEvent();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not refresh events: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createEvent() async {
    final event = await Navigator.push<HostEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(eventService: widget.eventService),
      ),
    );
    if (event != null) {
      if (!mounted) return;
      setState(() {
        _events = [event, ..._events.where((item) => item.id != event.id)];
      });
      _loadEvents();
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;

    setState(() => _signingOut = true);
    try {
      await widget.authService.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            authService: widget.authService,
            eventService: widget.eventService,
          ),
        ),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please retry.')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvePalette.ink,
      appBar: AppBar(
        title: Text(
          'Events Dashboard',
          style: GoogleFonts.spaceGrotesk(
            color: EvePalette.bone,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _signingOut ? null : _signOut,
            icon: _signingOut
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createEvent,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
          ? const Center(
              child: Text(
                'No events yet. Tap + to create one.',
                style: TextStyle(color: EvePalette.muted),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadEvents,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 96),
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final event = _events[index];
                  return _EventDashboardCard(
                    event: event,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventDetailScreen(
                            event: event,
                            eventService: widget.eventService,
                          ),
                        ),
                      );
                      await _loadEvents();
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _EventDashboardCard extends StatelessWidget {
  const _EventDashboardCard({required this.event, required this.onTap});

  final HostEvent event;
  final VoidCallback onTap;

  bool get _completed => event.isRevealed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          splashColor: EvePalette.amber.withValues(alpha: 0.08),
          highlightColor: EvePalette.amber.withValues(alpha: 0.04),
          child: Ink(
            decoration: BoxDecoration(
              color: EvePalette.coal,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: EvePalette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverStrip(event: event, completed: _completed),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              event.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.dmSerifDisplay(
                                color: EvePalette.bone,
                                fontSize: 28,
                                height: 0.98,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: EvePalette.sage,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MetricPill(
                            icon: Icons.group_rounded,
                            value: '${event.guestCount}',
                            label: 'Guests',
                          ),
                          const SizedBox(width: 8),
                          _MetricPill(
                            icon: Icons.photo_camera_rounded,
                            value: '${event.photoCount}',
                            label: 'Photos',
                          ),
                          const Spacer(),
                          Text(
                            _completed ? 'Completed' : 'Ongoing',
                            style: GoogleFonts.spaceGrotesk(
                              color: _completed
                                  ? EvePalette.parchment
                                  : EvePalette.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverStrip extends StatelessWidget {
  const _CoverStrip({required this.event, required this.completed});

  final HostEvent event;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (event.coverSignedUrl != null)
              Image.network(
                event.coverSignedUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _CoverFallback(),
              )
            else
              const _CoverFallback(),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    EvePalette.ink.withValues(alpha: 0.02),
                    EvePalette.ink.withValues(alpha: 0.74),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 14,
              child: _StatusBadge(completed: completed),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.9,
          child: Image.asset(
            'assets/images/minimalcamera.jpg',
            fit: BoxFit.cover,
            color: EvePalette.sage,
            colorBlendMode: BlendMode.modulate,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                EvePalette.ink.withValues(alpha: 0.06),
                EvePalette.coal.withValues(alpha: 0.42),
              ],
            ),
          ),
        ),
        Center(
          child: Icon(
            Icons.auto_awesome_rounded,
            color: EvePalette.bone.withValues(alpha: 0.60),
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EvePalette.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: completed
              ? EvePalette.parchment.withValues(alpha: 0.44)
              : EvePalette.amber.withValues(alpha: 0.48),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              completed ? Icons.check_circle_rounded : Icons.bolt_rounded,
              color: completed ? EvePalette.parchment : EvePalette.amber,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              completed ? 'Completed' : 'Ongoing',
              style: GoogleFonts.spaceGrotesk(
                color: completed ? EvePalette.parchment : EvePalette.amber,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EvePalette.ink.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EvePalette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: EvePalette.sage, size: 14),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                color: EvePalette.bone,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: EvePalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
