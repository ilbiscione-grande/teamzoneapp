import 'package:supabase_flutter/supabase_flutter.dart';

/// TeamZone support only: the clubs on the platform (support admin page,
/// part 1). Reads only; opening a club is logged on the server.
abstract interface class SupportClubServices {
  Future<List<SupportClubSummary>> listClubsForSupport();
  Future<SupportClubDetail> getClubForSupport({required String clubId});
}

/// One row in Klubbar. Counts only, no names.
class SupportClubSummary {
  const SupportClubSummary({
    required this.clubId,
    required this.name,
    required this.status,
    required this.verificationStatus,
    required this.createdAt,
    required this.teamCount,
    required this.peopleCount,
    required this.accountCount,
    required this.adminCount,
    required this.boardMandateCount,
    required this.boardForming,
    required this.pendingBoardChanges,
    this.oldestPendingBoardChange,
  });

  factory SupportClubSummary.fromJson(Map<String, dynamic> json) =>
      SupportClubSummary(
        clubId: json['club_id'] as String,
        name: json['club_name'] as String? ?? '',
        status: json['club_status'] as String? ?? '',
        verificationStatus: json['verification_status'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        teamCount: _int(json['team_count']),
        peopleCount: _int(json['people_count']),
        accountCount: _int(json['account_count']),
        adminCount: _int(json['admin_count']),
        boardMandateCount: _int(json['board_mandate_count']),
        boardForming: json['board_forming'] == true,
        pendingBoardChanges: _int(json['pending_board_changes']),
        oldestPendingBoardChange: _date(json['oldest_pending_board_change']),
      );

  final String clubId;
  final String name;
  final String status;
  final String verificationStatus;
  final DateTime createdAt;
  final int teamCount;
  final int peopleCount;
  final int accountCount;

  /// Admins (Medlemmar och lag) who can sign in, with no end date.
  final int adminCount;
  final int boardMandateCount;
  final bool boardForming;
  final int pendingBoardChanges;
  final DateTime? oldestPendingBoardChange;

  bool get isActive => status == 'active';

  /// An active club nobody can manage: support must step in.
  bool get lacksAdmin => isActive && adminCount == 0;

  bool get needsAttention => lacksAdmin || pendingBoardChanges > 0;
}

class SupportClubPerson {
  const SupportClubPerson({
    this.personId,
    required this.name,
    required this.hasAccount,
    this.office,
    this.endsAt,
  });

  factory SupportClubPerson.fromJson(Map<String, dynamic> json) =>
      SupportClubPerson(
        personId: json['person_id'] as String?,
        name: json['name'] as String? ?? '',
        hasAccount: json['has_account'] == true,
        office: json['office'] as String?,
        endsAt: _date(json['ends_at']),
      );

  /// Set for admins (support can take the right away).
  final String? personId;
  final String name;
  final bool hasAccount;
  final String? office;
  final DateTime? endsAt;
}

class SupportBoardChange {
  const SupportBoardChange({
    this.id = '',
    required this.action,
    required this.office,
    required this.name,
    required this.createdAt,
    required this.approvals,
  });

  factory SupportBoardChange.fromJson(Map<String, dynamic> json) =>
      SupportBoardChange(
        id: json['id'] as String? ?? '',
        action: json['action'] as String? ?? '',
        office: json['office'] as String? ?? '',
        name: json['name'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        approvals: _int(json['approvals']),
      );

  final String id;
  final String action;
  final String office;
  final String name;
  final DateTime createdAt;
  final int approvals;
}

/// Someone in the club who can sign in: whom support can make club admin.
class SupportClubAccount {
  const SupportClubAccount({
    required this.personId,
    required this.name,
    required this.isAdmin,
  });

  factory SupportClubAccount.fromJson(Map<String, dynamic> json) =>
      SupportClubAccount(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        isAdmin: json['is_admin'] == true,
      );

  final String personId;
  final String name;
  final bool isAdmin;
}

class SupportClubTeam {
  const SupportClubTeam({
    required this.name,
    required this.status,
    required this.people,
  });

  factory SupportClubTeam.fromJson(Map<String, dynamic> json) =>
      SupportClubTeam(
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? '',
        people: _int(json['people']),
      );

  final String name;
  final String status;
  final int people;
}

class SupportClubDetail {
  const SupportClubDetail({
    required this.clubId,
    required this.name,
    required this.status,
    required this.verificationStatus,
    required this.hasAdminWithAccount,
    required this.boardForming,
    required this.admins,
    required this.board,
    required this.pendingBoardChanges,
    required this.teams,
    this.peopleWithAccount = const [],
  });

  factory SupportClubDetail.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (json[key] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(parse)
            .toList(growable: false);
    return SupportClubDetail(
      clubId: json['club_id'] as String,
      name: json['club_name'] as String? ?? '',
      status: json['club_status'] as String? ?? '',
      verificationStatus: json['verification_status'] as String? ?? '',
      hasAdminWithAccount: json['has_admin_with_account'] == true,
      boardForming: json['board_forming'] == true,
      admins: list('admins', SupportClubPerson.fromJson),
      board: list('board', SupportClubPerson.fromJson),
      pendingBoardChanges: list(
        'pending_board_changes',
        SupportBoardChange.fromJson,
      ),
      teams: list('teams', SupportClubTeam.fromJson),
      peopleWithAccount: list(
        'people_with_account',
        SupportClubAccount.fromJson,
      ),
    );
  }

  final String clubId;
  final String name;
  final String status;
  final String verificationStatus;
  final bool hasAdminWithAccount;
  final bool boardForming;

  /// Everyone holding Medlemmar och lag, also those who do not count
  /// (no account, or an end date).
  final List<SupportClubPerson> admins;
  final List<SupportClubPerson> board;
  final List<SupportBoardChange> pendingBoardChanges;
  final List<SupportClubTeam> teams;
  final List<SupportClubAccount> peopleWithAccount;

  /// Admins who count: an account and no end date.
  int get countingAdmins =>
      admins.where((admin) => admin.hasAccount && admin.endsAt == null).length;
}

/// The Supabase calls, used by SupabaseMembershipServices.
Future<List<SupportClubSummary>> fetchClubsForSupport(
  SupabaseClient client,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>('list_clubs_for_support');
  if (value is! List) {
    throw const FormatException('Invalid support club list.');
  }
  return value
      .whereType<Map<String, dynamic>>()
      .map(SupportClubSummary.fromJson)
      .toList(growable: false);
}

Future<SupportClubDetail> fetchClubForSupport(
  SupabaseClient client,
  String clubId,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>('get_club_for_support', params: {'target_club_id': clubId});
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid support club.');
  }
  return SupportClubDetail.fromJson(value);
}

int _int(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
