class AppConfig {
  static const String appName = 'Medical CRM';
  static const String appVersion = '1.0.0';
  static const int appVersionCode = 100;

  // Supabase Configuration (توضع هنا أو تؤخذ من .env)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key-here',
  );
}

