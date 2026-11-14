import 'package:supabase_flutter/supabase_flutter.dart';

/// TeamZone support only: how the apps are used (support admin page,
/// part 2). Counts only, never names.
abstract interface class SupportUsageServices {
  Future<PlatformUsage> getPlatformUsage({int periodDays = 30});
}

/// More about one card in Statistik: a value per day in the period and a
/// few breakdowns. Counts only; the only names are club names.
abstract interface class SupportUsageDetailServices {
  Future<UsageDetail> getUsageDetail({
    required String metric,
    required String item,
    int periodDays = 30,
  });
}

class UsageRow {
  const UsageRow({required this.key, required this.value, this.label});

  factory UsageRow.fromJson(Map<String, dynamic> json) => UsageRow(
    key: '${json['key'] ?? ''}',
    label: json['label'] as String?,
    value: usageInt(json['value']),
  );

  final String key;

  /// Set for clubs (their name); other keys are codes.
  final String? label;
  final int value;
}

class UsageGroup {
  const UsageGroup({required this.group, required this.rows});

  factory UsageGroup.fromJson(Map<String, dynamic> json) => UsageGroup(
    group: json['group'] as String? ?? '',
    rows: (json['rows'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UsageRow.fromJson)
        .toList(growable: false),
  );

  final String group;
  final List<UsageRow> rows;
}

class UsageDetail {
  const UsageDetail({
    required this.metric,
    required this.item,
    required this.daily,
    required this.groups,
  });

  factory UsageDetail.fromJson(Map<String, dynamic> json) => UsageDetail(
    metric: json['metric'] as String? ?? '',
    item: json['item'] as String? ?? '',
    daily: [
      for (final day
          in (json['daily'] as List? ?? const [])
              .whereType<Map<String, dynamic>>())
        (
          day: DateTime.parse(day['day'] as String),
          value: usageInt(day['value']),
        ),
    ],
    groups: (json['groups'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(UsageGroup.fromJson)
        .toList(growable: false),
  );

  final String metric;
  final String item;
  final List<({DateTime day, int value})> daily;
  final List<UsageGroup> groups;
}

Future<UsageDetail> fetchUsageDetail(
  SupabaseClient client,
  String metric,
  String item,
  int periodDays,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>(
        'get_usage_detail_for_support',
        params: {'metric': metric, 'item': item, 'period_days': periodDays},
      );
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid usage detail.');
  }
  return UsageDetail.fromJson(value);
}

class UsageDay {
  const UsageDay({
    required this.day,
    required this.active,
    required this.newAccounts,
  });

  factory UsageDay.fromJson(Map<String, dynamic> json) => UsageDay(
    day: DateTime.parse(json['day'] as String),
    active: usageInt(json['active']),
    newAccounts: usageInt(json['new_accounts']),
  );

  final DateTime day;
  final int active;
  final int newAccounts;
}

class PlatformUsage {
  const PlatformUsage({
    required this.periodDays,
    required this.accounts,
    required this.accountTypes,
    required this.newAccounts,
    required this.linkedAccounts,
    required this.activeToday,
    required this.active7,
    required this.active30,
    required this.activeInPeriod,
    required this.apps,
    required this.daily,
    required this.clubs,
    required this.areas,
    required this.subscriptions,
    required this.pushDevices,
    this.activitySince,
    this.appsSince,
  });

  factory PlatformUsage.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? value) =>
        value is Map<String, dynamic> ? value : const {};
    Map<String, int> counts(Object? value) =>
        map(value).map((key, count) => MapEntry(key, usageInt(count)));
    final accounts = map(json['accounts']);
    final active = map(json['active']);
    return PlatformUsage(
      periodDays: usageInt(json['period_days']),
      accounts: usageInt(accounts['total']),
      accountTypes: counts(accounts['by_type']),
      newAccounts: usageInt(accounts['new_in_period']),
      linkedAccounts: usageInt(accounts['linked_to_club']),
      activeToday: usageInt(active['today']),
      active7: usageInt(active['last_7_days']),
      active30: usageInt(active['last_30_days']),
      activeInPeriod: usageInt(active['in_period']),
      apps: counts(json['apps']),
      daily: (json['daily'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(UsageDay.fromJson)
          .toList(growable: false),
      clubs: counts(json['clubs']),
      areas: counts(json['areas']),
      subscriptions: counts(json['subscriptions']),
      pushDevices: counts(json['push_devices']),
      activitySince: _date(json['activity_recorded_since']),
      appsSince: _date(json['apps_recorded_since']),
    );
  }

  final int periodDays;
  final int accounts;
  final Map<String, int> accountTypes;
  final int newAccounts;
  final int linkedAccounts;
  final int activeToday;
  final int active7;
  final int active30;
  final int activeInPeriod;

  /// Accounts active in the period per app (web, android, ios, ...).
  final Map<String, int> apps;
  final List<UsageDay> daily;

  /// active, official, new_in_period, teams, people.
  final Map<String, int> clubs;

  /// Things done in the period, per area.
  final Map<String, int> areas;
  final Map<String, int> subscriptions;
  final Map<String, int> pushDevices;

  /// Active days are recorded since this day, apps since [appsSince].
  final DateTime? activitySince;
  final DateTime? appsSince;
}

Future<PlatformUsage> fetchPlatformUsage(
  SupabaseClient client,
  int periodDays,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>(
        'get_platform_usage_for_support',
        params: {'period_days': periodDays},
      );
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid platform usage.');
  }
  return PlatformUsage.fromJson(value);
}

int usageInt(Object? value) => switch (value) {
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
