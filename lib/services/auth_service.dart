import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AppAuthException implements Exception {
  AppAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  bool get isSignedIn => _client.auth.currentSession != null;

  bool get isHostSignedIn =>
      _client.auth.currentSession != null &&
      _client.auth.currentUser?.isAnonymous != true;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> continueWithGoogle() async {
    if (isHostSignedIn) {
      return;
    }

    if (_client.auth.currentUser?.isAnonymous == true) {
      await _client.auth.signOut();
    }

    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseConfig.authRedirectUrl,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      queryParams: const {'prompt': 'select_account'},
    );
    debugPrint(
      '[EveAuth] launched Google OAuth=$launched redirect=${SupabaseConfig.authRedirectUrl}',
    );
    if (!launched) {
      throw AppAuthException('Could not open Google sign-in.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
