class SupabaseConfig {
  static const _defaultUrl = 'https://wymcaanegfcwlaksvlqx.supabase.co';
  static const _defaultAnonKey =
      'sb_publishable_99rXR4xnywnZF64naFfA5A_CfhcE5m_';

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultUrl,
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultAnonKey,
  );
  static const authRedirectUrl = 'com.example.eve://login-callback/';
  static const guestWebBaseUrl = 'https://evesnap.vercel.app/';
  static const photoBucket = 'Event Photos and Videos';
  static const coverBucket = 'Event Covers';
}
