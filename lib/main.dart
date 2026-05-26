import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/events_dashboard_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/auth_service.dart';
import 'services/event_service.dart';
import 'theme/eve_palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(SupabaseConfig.url.isNotEmpty, 'SUPABASE_URL is missing.');
  assert(SupabaseConfig.anonKey.isNotEmpty, 'SUPABASE_ANON_KEY is missing.');

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  runApp(const EveApp());
}

class EveApp extends StatelessWidget {
  const EveApp({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final authService = AuthService(client);
    final eventService = EventService(client);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Manrope',
        colorScheme: ColorScheme.fromSeed(
          seedColor: EvePalette.bone,
          brightness: Brightness.dark,
          surface: EvePalette.coal,
          primary: EvePalette.bone,
          secondary: EvePalette.amber,
          tertiary: EvePalette.ember,
        ),
        scaffoldBackgroundColor: EvePalette.ink,
        appBarTheme: const AppBarTheme(
          backgroundColor: EvePalette.ink,
          foregroundColor: EvePalette.bone,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: EvePalette.night,
          hintStyle: const TextStyle(color: EvePalette.muted),
          labelStyle: const TextStyle(color: EvePalette.parchment),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: EvePalette.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: EvePalette.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: EvePalette.amber),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: EvePalette.bone,
            foregroundColor: EvePalette.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: EvePalette.bone,
          foregroundColor: EvePalette.ink,
        ),
        cardTheme: CardThemeData(
          color: EvePalette.coal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      home: _AuthGate(authService: authService, eventService: eventService),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.authService, required this.eventService});

  final AuthService authService;
  final EventService eventService;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = widget.authService.authStateChanges.listen((_) {
      debugPrint(
        '[EveAuth] auth state changed. signedIn=${widget.authService.isSignedIn} host=${widget.authService.isHostSignedIn}',
      );
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[EveAuth] lifecycle=$state signedIn=${widget.authService.isSignedIn} host=${widget.authService.isHostSignedIn}',
    );
    if (state == AppLifecycleState.resumed) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        debugPrint(
          '[EveAuth] resume recheck. signedIn=${widget.authService.isSignedIn} host=${widget.authService.isHostSignedIn}',
        );
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.authService.isHostSignedIn) {
      return EventsDashboardScreen(
        key: const ValueKey('events-dashboard'),
        authService: widget.authService,
        eventService: widget.eventService,
      );
    }

    return WelcomeScreen(
      key: const ValueKey('welcome'),
      authService: widget.authService,
      eventService: widget.eventService,
    );
  }
}
