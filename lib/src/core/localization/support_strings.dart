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

  // Statistik (part 2).
  String get usageTab => isSwedish ? 'Statistik' : 'Statistics';
  String get usageFailed => isSwedish
      ? 'Statistiken kunde inte laddas.'
      : 'The statistics could not be loaded.';
  String periodDays(int days) => isSwedish ? '$days dagar' : '$days days';
  String get accountsHeading => isSwedish ? 'Konton' : 'Accounts';
  String get activeHeading => isSwedish ? 'Aktiva' : 'Active';
  String get appsHeading => isSwedish ? 'Appar' : 'Apps';
  String get clubsHeading => isSwedish ? 'Klubbar och lag' : 'Clubs and teams';
  String get areasHeading =>
      isSwedish ? 'Användning per område' : 'Use per area';
  String get productsHeading =>
      isSwedish ? 'Prenumerationer och enheter' : 'Subscriptions and devices';
  String get dailyHeading =>
      isSwedish ? 'Aktiva konton per dag' : 'Active accounts per day';
  String get total => isSwedish ? 'Totalt' : 'Total';
  String get newInPeriod => isSwedish ? 'Nya i perioden' : 'New in period';
  String get linkedToClub =>
      isSwedish ? 'Kopplade till klubb' : 'Linked to a club';
  String get today => isSwedish ? 'I dag' : 'Today';
  String get last7 => isSwedish ? 'Senaste 7 dagarna' : 'Last 7 days';
  String get last30 => isSwedish ? 'Senaste 30 dagarna' : 'Last 30 days';
  String get inPeriod => isSwedish ? 'I perioden' : 'In period';
  String accountType(String value) => switch (value) {
    'member' => isSwedish ? 'Medlemskonton' : 'Member accounts',
    'follower' => isSwedish ? 'Följarkonton' : 'Follower accounts',
    _ => isSwedish ? 'Övriga konton' : 'Other accounts',
  };
  String app(String value) => switch (value) {
    'web' => isSwedish ? 'Webben' : 'Web',
    'android' => 'Android',
    'ios' => 'iPhone',
    'tacticsboard' => 'Tacticsboard',
    'webtools' => 'Webtools',
    _ => value,
  };
  String club(String key) => switch (key) {
    'active' => isSwedish ? 'Aktiva klubbar' : 'Active clubs',
    'official' => isSwedish ? 'Officiella klubbar' : 'Official clubs',
    'new_in_period' => isSwedish ? 'Nya klubbar' : 'New clubs',
    'teams' => isSwedish ? 'Lag' : 'Teams',
    'people' => isSwedish ? 'Personer i klubbar' : 'People in clubs',
    _ => key,
  };
  String area(String key) => switch (key) {
    'events_created' => isSwedish ? 'Aktiviteter skapade' : 'Events created',
    'callup_answers' => isSwedish ? 'Svar på kallelser' : 'Call-up answers',
    'attendance_recorded' =>
      isSwedish ? 'Närvaro registrerad' : 'Attendance recorded',
    'messages_sent' => isSwedish ? 'Meddelanden skickade' : 'Messages sent',
    'tactics_projects_created' =>
      isSwedish
          ? 'Tacticsboard-projekt skapade'
          : 'Tacticsboard projects created',
    'tactics_live_sessions' =>
      isSwedish ? 'Livelektioner i Tacticsboard' : 'Tacticsboard live lessons',
    'bookings_created' => isSwedish ? 'Bokningar skapade' : 'Bookings created',
    _ => key,
  };
  String subscription(String key) => switch (key) {
    'webtool.tacticsboard' =>
      isSwedish ? 'Tacticsboard, aktiva' : 'Tacticsboard, active',
    _ => key,
  };
  String pushDevices(String platform) => isSwedish
      ? 'Enheter med push (${app(platform)})'
      : 'Devices with push (${app(platform)})';
  String get noApps => isSwedish
      ? 'Ingen app registrerad i perioden ännu.'
      : 'No app recorded in the period yet.';
  String sinceNote(String activity, String? apps) => isSwedish
      ? 'Aktiva dagar sparas sedan $activity${apps == null ? '' : ', vilken app sedan $apps'}. Bara antal, inga namn.'
      : 'Active days are recorded since $activity${apps == null ? '' : ', which app since $apps'}. Counts only, no names.';
  String dayTooltip(String date, int active, int created) => isSwedish
      ? '$date: $active aktiva, $created nya konton'
      : '$date: $active active, $created new accounts';
}
