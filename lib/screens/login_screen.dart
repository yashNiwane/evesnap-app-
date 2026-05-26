import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';
import 'events_dashboard_screen.dart';
import 'guest_home_screen.dart';
import 'guest_qr_scanner_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.eventService,
  });

  final AuthService authService;
  final EventService eventService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _busy = false;
  bool _hostPressed = false;
  bool _guestPressed = false;
  bool _openingDashboard = false;
  bool _openingGuest = false;
  StreamSubscription<AuthState>? _authSubscription;
  late final AnimationController _controller;
  late final AnimationController _patternController;
  late final Animation<double> _fade;
  late final Animation<double> _hostScale;
  late final Animation<double> _guestScale;
  late final Animation<Offset> _hostSlide;
  late final Animation<Offset> _guestSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _patternController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _hostScale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.18, 0.92, curve: Curves.easeOutExpo),
      ),
    );
    _guestScale = Tween<double>(begin: 0.94, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.30, 1.0, curve: Curves.easeOutExpo),
      ),
    );
    _hostSlide = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _guestSlide = Tween<Offset>(begin: const Offset(0, 0.28), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.18, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    if (widget.authService.isHostSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDashboard());
    }

    _authSubscription = widget.authService.authStateChanges.listen((change) {
      if (widget.authService.isHostSignedIn && mounted) {
        _openDashboard();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _controller.dispose();
    _patternController.dispose();
    super.dispose();
  }

  void _openDashboard() {
    if (!mounted || _openingDashboard) {
      return;
    }

    _openingDashboard = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EventsDashboardScreen(
          authService: widget.authService,
          eventService: widget.eventService,
        ),
      ),
    );
  }

  Future<void> _continueAsHost() async {
    setState(() => _busy = true);
    try {
      await widget.authService.continueWithGoogle();
      if (widget.authService.isHostSignedIn) {
        _openDashboard();
      }
    } on AppAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google auth failed. Please retry.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    if (_openingGuest) return;

    setState(() => _openingGuest = true);
    try {
      final eventId = await widget.eventService.getLastGuestEventId();
      if (eventId != null) {
        final event = await widget.eventService.getEventById(eventId);
        final guest = await widget.eventService.getCurrentGuestProfile(eventId);
        if (guest != null) {
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuestHomeScreen(
                event: event,
                guest: guest,
                eventService: widget.eventService,
              ),
            ),
          );
          return;
        }
      }

      if (eventId != null) {
        await widget.eventService.clearLastGuestEventId();
      }
    } catch (_) {
      await widget.eventService.clearLastGuestEventId();
    } finally {
      if (mounted) setState(() => _openingGuest = false);
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuestQrScannerScreen(eventService: widget.eventService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06080D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _patternController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _FlowPatternPainter(
                        progress: _patternController.value,
                      ),
                    );
                  },
                ),
              ),
              FadeTransition(
                opacity: _fade,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Host or Guest',
                        style: GoogleFonts.sora(
                          color: EvePalette.bone,
                          fontSize: 44,
                          height: 0.95,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'Pick your lane.',
                            style: GoogleFonts.manrope(
                              color: EvePalette.muted,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      SlideTransition(
                        position: _hostSlide,
                        child: ScaleTransition(
                          scale: _hostScale,
                          child: _RoleCard(
                            title: 'Create Event',
                            subtitle: 'Running the event',
                            action: _busy
                                ? 'Connecting...'
                                : 'Sign in / sign up with Google',
                            icon: Icons.login_rounded,
                            pressed: _hostPressed,
                            onTapDown: (_) =>
                                setState(() => _hostPressed = true),
                            onTapCancel: () =>
                                setState(() => _hostPressed = false),
                            onTapUp: (_) =>
                                setState(() => _hostPressed = false),
                            onTap: _busy ? null : _continueAsHost,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SlideTransition(
                        position: _guestSlide,
                        child: ScaleTransition(
                          scale: _guestScale,
                          child: _RoleCard(
                            title: 'Join with QR',
                            subtitle: 'Capturing and viewing moments',
                            action: _openingGuest
                                ? 'Opening...'
                                : 'Open guest view',
                            icon: Icons.arrow_outward_rounded,
                            pressed: _guestPressed,
                            onTapDown: (_) =>
                                setState(() => _guestPressed = true),
                            onTapCancel: () =>
                                setState(() => _guestPressed = false),
                            onTapUp: (_) =>
                                setState(() => _guestPressed = false),
                            onTap: _openingGuest ? null : _continueAsGuest,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowPatternPainter extends CustomPainter {
  const _FlowPatternPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * 0.35;
    final centerX = size.width * 0.5;
    final maxRadius = size.shortestSide * 0.56;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45;

    for (int i = 0; i < 9; i++) {
      final t = (progress + i / 9) % 1.0;
      final radius = maxRadius * t;
      final alpha = ((1.0 - t) * 0.42).clamp(0.0, 1.0);
      ringPaint.color = const Color(0xFF8DA9D8).withValues(alpha: alpha);
      canvas.drawCircle(Offset(centerX, centerY), radius, ringPaint);
    }

    final nodePaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 22; i++) {
      final seed = i * 0.285;
      final x =
          centerX +
          (size.width * 0.35) * (0.5 - (seed % 1.0)) * (0.7 + 0.3 * (progress));
      final y =
          centerY +
          (size.height * 0.22) *
              (0.5 - ((seed * 1.47 + progress) % 1.0)) *
              (0.7 + 0.3 * (1 - progress));
      final pulse = (0.4 + 0.6 * ((progress + i * 0.07) % 1.0));
      nodePaint.color = const Color(0xFFD9E7FF).withValues(alpha: 0.17 * pulse);
      canvas.drawCircle(Offset(x, y), 1.8 + 1.4 * pulse, nodePaint);
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF9BB3D8).withValues(alpha: 0.24);

    final wavePath = Path();
    final amplitude = size.height * 0.03;
    final baseY = centerY - size.height * 0.02;
    for (double x = 0; x <= size.width; x += 8) {
      final k = (x / size.width) * 6.28318 * 2;
      final y = baseY + amplitude * (0.9 * math.sin(k + progress * 6.28318));
      if (x == 0) {
        wavePath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }
    canvas.drawPath(wavePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _FlowPatternPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    required this.icon,
    required this.pressed,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onTap;
  final IconData icon;
  final bool pressed;
  final GestureTapDownCallback onTapDown;
  final GestureTapUpCallback onTapUp;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: pressed ? 0.99 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 78,
        decoration: BoxDecoration(
          color: pressed
              ? EvePalette.bone.withValues(alpha: 0.10)
              : EvePalette.bone.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: pressed
                ? EvePalette.amber.withValues(alpha: 0.72)
                : EvePalette.line.withValues(alpha: 0.86),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            onTapDown: onTapDown,
            onTapUp: onTapUp,
            onTapCancel: onTapCancel,
            splashColor: EvePalette.amber.withValues(alpha: 0.06),
            highlightColor: EvePalette.amber.withValues(alpha: 0.03),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: EvePalette.sage, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.sora(
                            color: EvePalette.bone,
                            fontSize: 19,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          action,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            color: EvePalette.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    offset: pressed ? const Offset(0.10, -0.10) : Offset.zero,
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: EvePalette.amber,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
