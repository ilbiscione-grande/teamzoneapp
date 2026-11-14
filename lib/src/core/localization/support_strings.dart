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

  // Supportadmins (part 4).
  String get adminsTab => isSwedish ? 'Supportadmins' : 'Support admins';
  String get adminsFailed => isSwedish
      ? 'Supportadministratörerna kunde inte laddas.'
      : 'The support administrators could not be loaded.';
  String get adminsIntro => isSwedish
      ? 'Supporten sköts bäst från ett eget konto utan roller i klubbar. Aktiva supportadministratörer får också supportens e-post.'
      : 'Support is best done from an account of its own with no roles in clubs. Active support administrators also receive the support emails.';
  String get addAdmin => isSwedish
      ? 'Lägg till supportadministratör'
      : 'Add support administrator';
  String get removeAdmin => isSwedish ? 'Ta bort' : 'Remove';
  String get removeAdminTitle => isSwedish
      ? 'Ta bort supportadministratör?'
      : 'Remove support administrator?';
  String removeAdminBody(String name, bool self) => isSwedish
      ? self
            ? 'Du tar bort din egen supporträtt. Supportsidan stängs för det här kontot.'
            : '$name kan inte längre använda supportsidan.'
      : self
      ? 'You remove your own support right. The support page closes for this account.'
      : '$name can no longer use the support page.';
  String get emailLabel =>
      isSwedish ? 'Kontots inloggningsadress' : 'The account’s sign-in address';
  String get emailHint => isSwedish
      ? 'Kontot måste redan finnas i TeamZone.'
      : 'The account must already exist in TeamZone.';
  String get reasonLabel => isSwedish ? 'Motivering' : 'Reason';
  String get reasonTooShort =>
      isSwedish ? 'Ange minst 5 tecken.' : 'Enter at least 5 characters.';
  String get cancel => isSwedish ? 'Avbryt' : 'Cancel';
  String get add => isSwedish ? 'Lägg till' : 'Add';
  String get you => isSwedish ? 'du' : 'you';
  String get activeAdmin => isSwedish ? 'Aktiv' : 'Active';
  String revokedOn(String date) =>
      isSwedish ? 'Borttagen $date' : 'Removed $date';
  String sinceDate(String date) => isSwedish ? 'sedan $date' : 'since $date';
  String clubRoles(int count) => isSwedish
      ? 'Har roller i ${count == 1 ? '1 klubb' : '$count klubbar'}'
      : 'Has roles in ${count == 1 ? '1 club' : '$count clubs'}';
  String get earlier => isSwedish ? 'Tidigare' : 'Earlier';
  String get added => isSwedish
      ? 'Supportadministratören är tillagd.'
      : 'The support administrator was added.';
  String get removed => isSwedish
      ? 'Supportadministratören är borttagen.'
      : 'The support administrator was removed.';
  // Part 3: actions on clubs.
  String get grantClubAdmin =>
      isSwedish ? 'Utse klubbadmin' : 'Appoint club admin';
  String get grantClubAdminBody => isSwedish
      ? 'Personen får Medlemmar och lag över klubben, via en klubbroll. Bara personer i klubben med konto kan väljas.'
      : 'The person gets Members and teams over the club, through a club role. Only people in the club with an account can be chosen.';
  String get grantClubAdminConfirm => isSwedish ? 'Utse' : 'Appoint';
  String get personLabel => isSwedish ? 'Person' : 'Person';
  String get choosePerson => isSwedish ? 'Välj en person.' : 'Choose a person.';
  String get noCandidates => isSwedish
      ? 'Ingen mer i klubben har konto.'
      : 'Nobody else in the club has an account.';
  String get removeClubAdmin => isSwedish ? 'Ta bort' : 'Remove';
  String get removeClubAdminTitle =>
      isSwedish ? 'Ta bort klubbadmin' : 'Remove club admin';
  String removeClubAdminBody(String name) => isSwedish
      ? '$name förlorar Medlemmar och lag över klubben. Personens övriga roller finns kvar.'
      : '$name loses Members and teams over the club. Their other roles stay.';
  String get lastAdminWarning => isSwedish
      ? 'Klubben står då utan klubbadmin med konto. Det är ett nödundantag och loggas med din motivering.'
      : 'The club is then left without a club admin with an account. This is an emergency exception and is logged with your reason.';
  String get applyChange => isSwedish ? 'Verkställ' : 'Apply';
  String get cancelChange => isSwedish ? 'Avbryt ändringen' : 'Cancel change';
  String get applyChangeTitle =>
      isSwedish ? 'Verkställ styrelseändringen' : 'Apply the board change';
  String get applyChangeBody => isSwedish
      ? 'Ändringen genomförs utan styrelsens godkännanden. Gör det bara när styrelsen inte kan godkänna själv.'
      : "The change is made without the board's approvals. Only do this when the board cannot approve it itself.";
  String get cancelChangeTitle =>
      isSwedish ? 'Avbryt styrelseändringen' : 'Cancel the board change';
  String get cancelChangeBody => isSwedish
      ? 'Ändringen avbryts och genomförs inte. Styrelsen kan föreslå den igen.'
      : 'The change is cancelled and not made. The board can propose it again.';
  String get clubAdminGranted =>
      isSwedish ? 'Klubbadmin är utsedd.' : 'The club admin is appointed.';
  String get clubAdminRemoved =>
      isSwedish ? 'Klubbadmin är borttagen.' : 'The club admin is removed.';
  String get clubLeftWithoutAdmin => isSwedish
      ? 'Klubbadmin är borttagen. Klubben saknar nu klubbadmin med konto.'
      : 'The club admin is removed. The club now has no club admin with an account.';
  String get changeApplied => isSwedish
      ? 'Styrelseändringen är verkställd.'
      : 'The board change is applied.';
  String get changeCancelled => isSwedish
      ? 'Styrelseändringen är avbruten.'
      : 'The board change is cancelled.';
  String get actionsLogged => isSwedish
      ? 'Åtgärder kräver motivering och loggas.'
      : 'Actions need a reason and are logged.';

  String refusal(String? code) => switch (code) {
    'last_support_admin' =>
      isSwedish
          ? 'Den sista supportadministratören kan inte tas bort. Lägg till en annan först.'
          : 'The last support administrator cannot be removed. Add another one first.',
    'account_not_found' =>
      isSwedish
          ? 'Det finns inget konto med den adressen.'
          : 'There is no account with that address.',
    'already_support_admin' =>
      isSwedish
          ? 'Kontot är redan supportadministratör.'
          : 'The account is already a support administrator.',
    'not_support_admin' =>
      isSwedish
          ? 'Kontot är inte längre supportadministratör.'
          : 'The account is no longer a support administrator.',
    'reason_required' || 'invalid_reason' => reasonTooShort,
    'person_without_account' =>
      isSwedish
          ? 'Personen har inget konto i klubben.'
          : 'The person has no account in the club.',
    'already_club_admin' =>
      isSwedish
          ? 'Personen är redan klubbadmin.'
          : 'The person is already club admin.',
    'not_club_admin' =>
      isSwedish
          ? 'Personen är inte längre klubbadmin.'
          : 'The person is no longer club admin.',
    'board_change_not_pending' =>
      isSwedish
          ? 'Styrelseändringen väntar inte längre.'
          : 'The board change is no longer waiting.',
    'mandate_target_inactive' =>
      isSwedish
          ? 'Personen har inget aktivt uppdrag i klubben, eller mandatet har redan gått ut.'
          : 'The person has no active assignment in the club, or the mandate has already ended.',
    'mandate_overlap' =>
      isSwedish
          ? 'Personen har redan den posten under samma tid.'
          : 'The person already holds that office for the same period.',
    'invalid_state' =>
      isSwedish
          ? 'Mandatet finns inte längre.'
          : 'The mandate no longer exists.',
    _ =>
      isSwedish
          ? 'Ändringen kunde inte sparas.'
          : 'The change could not be saved.',
  };

  // The support site.
  String get siteTitle => isSwedish ? 'TeamZone Support' : 'TeamZone Support';
  String get signOut => isSwedish ? 'Logga ut' : 'Sign out';
  String get notSupportTitle => isSwedish
      ? 'Kontot är inte supportadministratör'
      : 'The account is not a support administrator';
  String get notSupportBody => isSwedish
      ? 'Supportsidan är bara för TeamZones supportadministratörer. Logga in med supportkontot, eller använd appen på app.teamzoneapp.se.'
      : 'The support page is only for TeamZone’s support administrators. Sign in with the support account, or use the app at app.teamzoneapp.se.';
  String get movedTitle =>
      isSwedish ? 'Supporten har flyttat' : 'Support has moved';
  String get movedBody => isSwedish
      ? 'Supportsidan finns nu på support.teamzoneapp.se. Logga in där med supportkontot.'
      : 'The support page is now at support.teamzoneapp.se. Sign in there with the support account.';
  String get openSupport =>
      isSwedish ? 'Öppna supportsidan' : 'Open the support page';
}
