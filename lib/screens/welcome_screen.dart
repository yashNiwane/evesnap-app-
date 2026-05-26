import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/events_dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../theme/eve_palette.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.authService,
    required this.eventService,
  });

  final AuthService authService;
  final EventService eventService;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _exitController;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<Offset> _textExitOffset;
  late final Animation<Offset> _imageExitOffset;
  StreamSubscription<AuthState>? _authSubscription;
  bool _isExiting = false;
  bool _openingDashboard = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );

    _scale = Tween<double>(begin: 0.02, end: 1.0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutExpo),
    );

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.12, 1.0, curve: Curves.easeOut),
      ),
    );

    _textExitOffset =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-1.15, 0)).animate(
          CurvedAnimation(
            parent: _exitController,
            curve: Curves.easeInOutCubic,
          ),
        );

    _imageExitOffset =
        Tween<Offset>(begin: Offset.zero, end: const Offset(1.15, 0)).animate(
          CurvedAnimation(
            parent: _exitController,
            curve: Curves.easeInOutCubic,
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
    _introController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  void _openDashboard() {
    if (!mounted || _openingDashboard) {
      return;
    }

    _openingDashboard = true;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => EventsDashboardScreen(
          authService: widget.authService,
          eventService: widget.eventService,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _openLogin() async {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    await _exitController.forward();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          authService: widget.authService,
          eventService: widget.eventService,
        ),
      ),
    );
    if (!mounted) return;
    _exitController.reset();
    setState(() => _isExiting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TopLine(),
              const Spacer(),
              SlideTransition(
                position: _imageExitOffset,
                child: Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Container(
                        width: 232,
                        height: 348,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: EvePalette.coal,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: EvePalette.line),
                        ),
                        child: Image.asset(
                          'assets/images/minimalcamera.jpg',
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          color: const Color(0xFF798396),
                          colorBlendMode: BlendMode.modulate,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              SlideTransition(
                position: _textExitOffset,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Eve\nSnap',
                      textAlign: TextAlign.left,
                      style: GoogleFonts.bebasNeue(
                        color: EvePalette.bone,
                        fontSize: 86,
                        height: 0.82,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Private event memories.',
                      style: GoogleFonts.spaceGrotesk(
                        color: EvePalette.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              FilledButton(
                onPressed: _isExiting ? null : _openLogin,
                style: FilledButton.styleFrom(
                  backgroundColor: EvePalette.bone,
                  foregroundColor: EvePalette.ink,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(
                  _isExiting ? '...' : 'Enter',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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

class _TopLine extends StatelessWidget {
  const _TopLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '01',
          style: GoogleFonts.spaceGrotesk(
            color: EvePalette.bone,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: EvePalette.line, thickness: 1)),
        const SizedBox(width: 10),
        Text(
          'private / social',
          style: GoogleFonts.spaceGrotesk(
            color: EvePalette.parchment,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
