import 'package:supabase_flutter/supabase_flutter.dart';

/// TeamZone support only: what support has done (support admin page,
/// part 5), newest first, from the audit log.
abstract interface class SupportLogServices {
  /// [area] is null for everything, or clubs, admins or cases. [before]
  /// continues after the last entry of the previous page.
  Future<SupportLogPage> listSupportActions({
    String? area,
    bool includeViews = false,
    DateTime? before,
  });
}

class SupportLogEntry {
  const SupportLogEntry({
    required this.id,
    required this.occurredAt,
    required this.type,
    required this.actor,
    required this.actorIsMe,
    this.club,
    this.target,
    this.reason,
    this.details = const {},
  });

  factory SupportLogEntry.fromJson(Map<String, dynamic> json) =>
      SupportLogEntry(
        id: '${json['id'] ?? ''}',
        occurredAt:
            DateTime.tryParse('${json['occurred_at']}')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        type: json['type'] as String? ?? '',
        actor: (json['actor'] as String? ?? '').trim(),
        actorIsMe: json['actor_is_me'] == true,
        club: json['club'] as String?,
        target: json['target'] as String?,
        reason: json['reason'] as String?,
        details: json['details'] is Map<String, dynamic>
            ? json['details'] as Map<String, dynamic>
            : const {},
      );

  final String id;
  final DateTime occurredAt;

  /// The audit command type, e.g. support.club_admin_granted.
  final String type;

  /// The support administrator's name; empty when the account has none.
  final String actor;
  final bool actorIsMe;
  final String? club;

  /// The person, support administrator or board member it was about.
  final String? target;
  final String? reason;

  /// left_without_admin, action, office, approvals, again, self, decision,
  /// status, resolution_kind, hide.
  final Map<String, dynamic> details;
}

class SupportLogPage {
  const SupportLogPage({required this.entries, required this.more});

  factory SupportLogPage.fromJson(Map<String, dynamic> json) => SupportLogPage(
    entries: (json['entries'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SupportLogEntry.fromJson)
        .toList(growable: false),
    more: json['more'] == true,
  );

  final List<SupportLogEntry> entries;

  /// True when there are older entries.
  final bool more;
}

Future<SupportLogPage> fetchSupportActions(
  SupabaseClient client, {
  String? area,
  bool includeViews = false,
  DateTime? before,
}) async {
  final value = await client
      .schema('api')
      .rpc<Object?>(
        'list_support_actions',
        params: {
          'area': area,
          'include_views': includeViews,
          'before': before?.toUtc().toIso8601String(),
          'page_size': 50,
        },
      );
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid support log.');
  }
  return SupportLogPage.fromJson(value);
}
