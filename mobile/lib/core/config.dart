class AppConfig {
  static const String appName = 'Medical CRM';
  static const String appVersion = '1.0.0';
  static const int appVersionCode = 100;

  // Supabase Configuration Live
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tobahtnzxccvkkqwlqok.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_-Uh3L2jZTDLSGvNHONga1Q_Ce-_P04D',
  );
}

