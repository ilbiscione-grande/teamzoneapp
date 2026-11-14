import 'package:flutter/widgets.dart';

/// Copy for TeamZone support's admin page (platform support, not club admin).
class SupportStrings {
  const SupportStrings._(this.isSwedish);
  final bool isSwedish;

  static SupportStrings of(BuildContext context) => SupportStrings._(
    Localizations.localeOf(context).languageCode.toLowerCase() == 'sv',
  );

  String get casesTab => isSwedish ? 'Ärenden' : 'Cases';
  String get clubsTab => isSwedish ? 'Klubbar' : 'Clubs';
  String get retry => isSwedish ? 'Försök igen' : 'Try again';
  String get searchClubs => isSwedish ? 'Sök klubb' : 'Search clubs';
  String get onlyAttention =>
      isSwedish ? 'Bara de som behöver hjälp' : 'Only those needing help';
  String get clubsFailed => isSwedish
      ? 'Klubbarna kunde inte laddas.'
      : 'The clubs could not be loaded.';
  String get clubFailed => isSwedish
      ? 'Klubben kunde inte laddas.'
      : 'The club could not be loaded.';
  String get noClubs => isSwedish ? 'Inga klubbar' : 'No clubs';
  String get noAttention => isSwedish
      ? 'Ingen klubb behöver hjälp just nu.'
      : 'No club needs help right now.';
  String clubsSummary(int total, int attention) => isSwedish
      ? '$total klubbar · $attention behöver hjälp'
      : '$total clubs · $attention need help';
  String get noAdmin => isSwedish
      ? 'Saknar klubbadmin med konto'
      : 'No club admin with an account';
  String admins(int count) => isSwedish
      ? (count == 1 ? '1 klubbadmin' : '$count klubbadmins')
      : (count == 1 ? '1 club admin' : '$count club admins');
  String teams(int count) => isSwedish
      ? (count == 1 ? '1 lag' : '$count lag')
      : (count == 1 ? '1 team' : '$count teams');
  String people(int count) => isSwedish ? '$count personer' : '$count people';
  String accounts(int count) => isSwedish
      ? (count == 1 ? '1 konto' : '$count konton')
      : (count == 1 ? '1 account' : '$count accounts');
  String pendingChanges(int count) => isSwedish
      ? (count == 1
            ? '1 väntande styrelseändring'
            : '$count väntande styrelseändringar')
      : (count == 1
            ? '1 pending board change'
            : '$count pending board changes');
  String oldestSince(String date) =>
      isSwedish ? 'äldsta från $date' : 'oldest from $date';
  String get boardForming =>
      isSwedish ? 'Styrelsen bildas' : 'Board being formed';
  String verification(String value) => switch (value) {
    'official' => isSwedish ? 'Officiell' : 'Official',
    'pending' => isSwedish ? 'Verifiering väntar' : 'Verification pending',
    'rejected' => isSwedish ? 'Verifiering avslagen' : 'Verification rejected',
    'revoked' => isSwedish ? 'Verifiering återkallad' : 'Verification revoked',
    _ => isSwedish ? 'Ej verifierad' : 'Not verified',
  };
  String clubStatus(String value) => switch (value) {
    'active' => isSwedish ? 'Aktiv' : 'Active',
    'ended' => isSwedish ? 'Avslutad' : 'Ended',
    'suspended' => isSwedish ? 'Avstängd' : 'Suspended',
    _ => value,
  };
  String get adminsHeading => isSwedish ? 'Klubbadmins' : 'Club admins';
  String get adminsExplained => isSwedish
      ? 'De som har Medlemmar och lag. Bara de med konto och utan slutdatum räknas.'
      : 'Those with Members and teams. Only those with an account and no end date count.';
  String get boardHeading => isSwedish ? 'Styrelse' : 'Board';
  String get pendingHeading =>
      isSwedish ? 'Väntande styrelseändringar' : 'Pending board changes';
  String get teamsHeading => isSwedish ? 'Lag' : 'Teams';
  String get none => isSwedish ? 'Inga' : 'None';
  String get noAccount => isSwedish ? 'Inget konto' : 'No account';
  String endsOn(String date) => isSwedish ? 'slutar $date' : 'ends $date';
  String change(String action, String office, String name) => isSwedish
      ? '${action == 'grant' ? 'Lägg till' : 'Ta bort'} $office: $name'
      : '${action == 'grant' ? 'Add' : 'Remove'} $office: $name';
  String approvals(int count, String date) => isSwedish
      ? '$count godkännanden · föreslagen $date'
      : '$count approvals · proposed $date';
  String get viewLogged => isSwedish
      ? 'Att du öppnade klubben sparas i supportens logg.'
      : 'That you opened the club is saved in the support log.';
}
