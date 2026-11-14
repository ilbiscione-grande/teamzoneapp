import 'package:supabase_flutter/supabase_flutter.dart';

/// TeamZone support only: who is a support administrator (support admin
/// page, part 4). Changes need a reason and are logged on the server.
abstract interface class SupportAdminServices {
  Future<List<SupportAdmin>> listSupportAdmins();
  Future<void> grantSupportAdmin({
    required String email,
    required String reason,
  });
  Future<void> revokeSupportAdmin({
    required String profileId,
    required String reason,
  });
}

class SupportAdmin {
  const SupportAdmin({
    required this.profileId,
    required this.name,
    required this.email,
    required this.active,
    required this.createdAt,
    required this.isSelf,
    required this.clubCount,
    this.revokedAt,
  });

  factory SupportAdmin.fromJson(Map<String, dynamic> json) => SupportAdmin(
    profileId: json['profile_id'] as String,
    name: json['display_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    active: json['active'] == true,
    createdAt: DateTime.parse(json['created_at'] as String),
    revokedAt: json['revoked_at'] is String
        ? DateTime.tryParse(json['revoked_at'] as String)
        : null,
    isSelf: json['is_self'] == true,
    clubCount: (json['club_count'] as num?)?.toInt() ?? 0,
  );

  final String profileId;
  final String name;
  final String email;
  final bool active;
  final DateTime createdAt;
  final DateTime? revokedAt;
  final bool isSelf;

  /// Clubs the account has a role in. A support account should have none.
  final int clubCount;
}

Future<List<SupportAdmin>> fetchSupportAdmins(SupabaseClient client) async {
  final value = await client.schema('api').rpc<Object?>('list_support_admins');
  if (value is! List) {
    throw const FormatException('Invalid support admin list.');
  }
  return value
      .whereType<Map<String, dynamic>>()
      .map(SupportAdmin.fromJson)
      .toList(growable: false);
}

Future<void> sendGrantSupportAdmin(
  SupabaseClient client,
  String email,
  String reason,
) => client
    .schema('api')
    .rpc<Object?>(
      'grant_support_admin',
      params: {'target_email': email.trim(), 'reason': reason.trim()},
    );

Future<void> sendRevokeSupportAdmin(
  SupabaseClient client,
  String profileId,
  String reason,
) => client
    .schema('api')
    .rpc<Object?>(
      'revoke_support_admin',
      params: {'target_profile_id': profileId, 'reason': reason.trim()},
    );

/// The server's refusal codes, so the page can explain them.
String? supportAdminRefusal(Object error) {
  final text = error is PostgrestException ? error.message : '$error';
  for (final code in const [
    'last_support_admin',
    'account_not_found',
    'already_support_admin',
    'not_support_admin',
    'reason_required',
  ]) {
    if (text.contains(code)) return code;
  }
  return null;
}
