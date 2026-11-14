import 'package:flutter/widgets.dart';

/// Copy for the Logg tab on TeamZone support's admin page.
class SupportLogStrings {
  const SupportLogStrings._(this.isSwedish);
  final bool isSwedish;

  static SupportLogStrings of(BuildContext context) => SupportLogStrings._(
    Localizations.localeOf(context).languageCode.toLowerCase() == 'sv',
  );

  String get tab => isSwedish ? 'Logg' : 'Log';
  String get failed =>
      isSwedish ? 'Loggen kunde inte laddas.' : 'The log could not be loaded.';
  String get empty => isSwedish ? 'Inget i loggen.' : 'Nothing in the log.';
  String get more => isSwedish ? 'Visa äldre' : 'Show older';
  String get includeViews =>
      isSwedish ? 'Visa öppnade klubbar' : 'Show opened clubs';
  String get noName => isSwedish ? 'Utan namn' : 'No name';
  String get you => isSwedish ? 'du' : 'you';

  String area(String? area) => switch (area) {
    'clubs' => isSwedish ? 'Klubbar' : 'Clubs',
    'admins' => isSwedish ? 'Supportadmins' : 'Support admins',
    'cases' => isSwedish ? 'Ärenden' : 'Cases',
    _ => isSwedish ? 'Allt' : 'Everything',
  };

  String action(String type) => isSwedish
      ? switch (type) {
          'support.admin_granted' ||
          'support.admin.grant.v1' => 'Lade till supportadmin',
          'support.admin_revoked' => 'Tog bort supportadmin',
          'support.club_admin_granted' => 'Utsåg klubbadmin',
          'support.club_admin_removed' => 'Tog bort klubbadmin',
          'support.board_change_applied' => 'Verkställde styrelseändring',
          'support.board_change_cancelled' => 'Avbröt styrelseändring',
          'support.club_viewed' => 'Öppnade klubben',
          'support.club_verification.decide.v1' => 'Beslut om verifiering',
          'support.match_pool_reports.decide.v1' =>
            'Beslut om anmälan i matchpoolen',
          'support.protected_name.approve.v1' => 'Godkände skyddat namn',
          'support.protected_name.update.v1' =>
            'Ändrade ärende om skyddat namn',
          _ when type.startsWith('support.protected_name.message') =>
            'Svarade i ärende om skyddat namn',
          _ => type,
        }
      : switch (type) {
          'support.admin_granted' ||
          'support.admin.grant.v1' => 'Added a support admin',
          'support.admin_revoked' => 'Removed a support admin',
          'support.club_admin_granted' => 'Appointed a club admin',
          'support.club_admin_removed' => 'Removed a club admin',
          'support.board_change_applied' => 'Applied a board change',
          'support.board_change_cancelled' => 'Cancelled a board change',
          'support.club_viewed' => 'Opened the club',
          'support.club_verification.decide.v1' => 'Verification decision',
          'support.match_pool_reports.decide.v1' =>
            'Match pool report decision',
          'support.protected_name.approve.v1' => 'Approved a protected name',
          'support.protected_name.update.v1' => 'Changed a protected-name case',
          _ when type.startsWith('support.protected_name.message') =>
            'Answered a protected-name case',
          _ => type,
        };

  /// Short notes from the entry's details, e.g. that the club was left
  /// without a club admin.
  List<String> notes(Map<String, dynamic> details) => [
    if (details['left_without_admin'] == true)
      isSwedish
          ? 'Klubben står nu utan klubbadmin med konto'
          : 'The club is now without a club admin with an account',
    if (details['created_club_role'] == true)
      isSwedish ? 'Klubbrollen skapades' : 'The club role was created',
    if (details['again'] == true)
      isSwedish
          ? 'Hade varit supportadmin förut'
          : 'Had been a support admin before',
    if (details['self'] == true)
      isSwedish ? 'Tog bort sig själv' : 'Removed themself',
    if (details['office'] case final String office)
      isSwedish ? 'Post: $office' : 'Office: $office',
    if (details['approvals'] case final num approvals)
      isSwedish
          ? 'Godkännanden innan: ${approvals.toInt()}'
          : 'Approvals before: ${approvals.toInt()}',
    if (details['decision'] case final String decision)
      isSwedish ? 'Beslut: $decision' : 'Decision: $decision',
    if (details['status'] case final String status)
      isSwedish ? 'Status: $status' : 'Status: $status',
    if (details['resolution_kind'] case final String kind)
      isSwedish ? 'Lösning: $kind' : 'Resolution: $kind',
    if (details['hide'] == true)
      isSwedish ? 'Dolt i matchpoolen' : 'Hidden in the match pool',
  ];

  String reason(String text) =>
      isSwedish ? 'Motivering: $text' : 'Reason: $text';
}
