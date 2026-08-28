enum AppEnvironmentName {
  local,
  audit,
  staging,
  production;

  static AppEnvironmentName parse(String value) {
    return AppEnvironmentName.values.firstWhere(
      (environment) => environment.name == value,
      orElse: () => AppEnvironmentName.local,
    );
  }
}

class AppEnvironment {
  const AppEnvironment({
    required this.name,
    this.supabaseUrl = '',
    this.supabasePublishableKey = '',
    this.matchSpaceV2 = true,
    this.billingEnabled = false,
    this.notificationsEnabled = false,
    this.publicContactEnabled = false,
  });

  const AppEnvironment.fromDefines()
    : name = const String.fromEnvironment(
        'TEAMZONE_ENV',
        defaultValue: 'local',
      ),
      supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey = const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      matchSpaceV2 = const bool.fromEnvironment(
        'MATCH_SPACE_V2',
        defaultValue: true,
      ),
      billingEnabled = const bool.fromEnvironment('BILLING_ENABLED'),
      notificationsEnabled = const bool.fromEnvironment(
        'NOTIFICATIONS_ENABLED',
      ),
      publicContactEnabled = const bool.fromEnvironment(
        'PUBLIC_CONTACT_ENABLED',
      );

  final String name;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final bool matchSpaceV2;
  final bool billingEnabled;
  final bool notificationsEnabled;
  final bool publicContactEnabled;

  AppEnvironmentName get parsedName => AppEnvironmentName.parse(name);

  bool get hasSupabaseConfiguration =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.trim().isNotEmpty;
}
