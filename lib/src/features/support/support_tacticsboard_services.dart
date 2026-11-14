import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/support/support_usage_services.dart'
    show usageInt;

/// TeamZone support only: Tacticsboard's counts (2026-11-14). Tacticsboard
/// is sold from its own database (the production project), so the app
/// project's edge function support-tacticsboard-usage checks the caller and
/// fetches them from there. Counts only, never names.
abstract interface class SupportTacticsboardServices {
  Future<TacticsboardUsage> getTacticsboardUsage({int periodDays = 30});
}

/// The edge function has no address or key for the production project yet.
class TacticsboardUsageNotConfigured implements Exception {
  const TacticsboardUsageNotConfigured();
}

/// The sections the server returns, in the order the tab shows them.
const tacticsboardSections = [
  'accounts',
  'billing',
  'subscriptions',
  'projects',
  'live',
  'sharing',
];

class TacticsboardUsage {
  const TacticsboardUsage({
    required this.periodDays,
    required this.source,
    required this.sections,
    required this.daily,
  });

  factory TacticsboardUsage.fromJson(
    Map<String, dynamic> json, {
    String source = '',
  }) {
    final sections = <String, Map<String, int?>>{};
    for (final name in tacticsboardSections) {
      final value = json[name];
      if (value is! Map) continue;
      sections[name] = {
        for (final entry in value.entries)
          '${entry.key}': entry.value == null ? null : usageInt(entry.value),
      };
    }
    return TacticsboardUsage(
      periodDays: usageInt(json['period_days']),
      source: source,
      sections: sections,
      daily: (json['daily'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TacticsboardDay.fromJson)
          .whereType<TacticsboardDay>()
          .toList(growable: false),
    );
  }

  final int periodDays;

  /// The project the numbers come from (its ref).
  final String source;

  /// Section → key → count. A null count is not recorded there.
  final Map<String, Map<String, int?>> sections;
  final List<TacticsboardDay> daily;

  /// One series from [daily], for a bar chart.
  List<({DateTime day, int value})> series(String key) => [
    for (final day in daily) (day: day.day, value: day.values[key] ?? 0),
  ];
}

class TacticsboardDay {
  const TacticsboardDay({required this.day, required this.values});

  static TacticsboardDay? fromJson(Map<String, dynamic> json) {
    final day = DateTime.tryParse('${json['day']}');
    if (day == null) return null;
    return TacticsboardDay(
      day: day,
      values: {
        for (final entry in json.entries)
          if (entry.key != 'day') entry.key: usageInt(entry.value),
      },
    );
  }

  final DateTime day;

  /// new_accounts, trials_started, new_subscriptions, new_projects,
  /// live_sessions.
  final Map<String, int> values;
}

/// Which daily series belongs to a card, or null when there is none.
String? tacticsboardSeries(String section, String key) => switch (section) {
  'accounts' when key == 'total' || key == 'new_in_period' => 'new_accounts',
  'billing' when key.startsWith('trials_started') => 'trials_started',
  'subscriptions' when key != 'withdrawals_in_period' => 'new_subscriptions',
  'projects' => 'new_projects',
  'live' when key != 'guests_in_period' && key != 'participants_in_period' =>
    'live_sessions',
  _ => null,
};

Future<TacticsboardUsage> fetchTacticsboardUsage(
  SupabaseClient client,
  int periodDays,
) async {
  final FunctionResponse response;
  try {
    response = await client.functions.invoke(
      'support-tacticsboard-usage',
      body: {'period_days': periodDays},
    );
  } on FunctionException catch (error) {
    final details = error.details;
    if (error.status == 503 &&
        details is Map &&
        details['error'] == 'not_configured') {
      throw const TacticsboardUsageNotConfigured();
    }
    rethrow;
  }
  final value = response.data;
  if (value is! Map || value['usage'] is! Map<String, dynamic>) {
    throw const FormatException('Invalid Tacticsboard usage.');
  }
  return TacticsboardUsage.fromJson(
    value['usage'] as Map<String, dynamic>,
    source: '${value['source'] ?? ''}',
  );
}
