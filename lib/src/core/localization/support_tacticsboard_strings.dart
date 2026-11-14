import 'package:flutter/widgets.dart';

/// Copy for the Tacticsboard tab on TeamZone support's admin page.
class SupportTacticsboardStrings {
  const SupportTacticsboardStrings._(this.isSwedish);
  final bool isSwedish;

  static SupportTacticsboardStrings of(BuildContext context) =>
      SupportTacticsboardStrings._(
        Localizations.localeOf(context).languageCode.toLowerCase() == 'sv',
      );

  String get tab => 'Tacticsboard';
  String get notConfigured => isSwedish
      ? 'Tacticsboards databas är inte ansluten än. När produktionens adress '
            'och nyckel finns som hemligheter i appens projekt visas siffrorna '
            'här.'
      : "Tacticsboard's database is not connected yet. The numbers appear "
            "here once the production project's address and key are set as "
            "secrets in the app's project.";
  String sourceNote(String source) => isSwedish
      ? 'Från Tacticsboards databas ($source), där kunderna köper på '
            'webtools.teamzoneapp.se. Bara antal.'
      : "From Tacticsboard's database ($source), where customers buy on "
            'webtools.teamzoneapp.se. Counts only.';

  String section(String name) => switch (name) {
    'accounts' => isSwedish ? 'Konton' : 'Accounts',
    'billing' => isSwedish ? 'Provperioder' : 'Trials',
    'subscriptions' => isSwedish ? 'Abonnemang' : 'Subscriptions',
    'projects' => isSwedish ? 'Projekt' : 'Projects',
    'live' => isSwedish ? 'Livelektioner' : 'Live lessons',
    'sharing' => isSwedish ? 'Delat' : 'Shared',
    _ => name,
  };

  String label(String section, String key) => isSwedish
      ? switch ('$section.$key') {
          'accounts.total' => 'Totalt',
          'accounts.new_in_period' => 'Nya i perioden',
          'accounts.signed_in_7_days' => 'Inloggade senaste 7 dagarna',
          'accounts.signed_in_30_days' => 'Inloggade senaste 30 dagarna',
          'accounts.signed_in_in_period' => 'Inloggade i perioden',
          'billing.trials_started' => 'Startade totalt',
          'billing.trials_started_in_period' => 'Startade i perioden',
          'billing.trials_active' => 'Pågår nu',
          'billing.trials_ended_unpaid' => 'Slut utan köp',
          'subscriptions.paying_month' => 'Betalar per månad',
          'subscriptions.paying_year' => 'Betalar per år',
          'subscriptions.ending' => 'Uppsagda, slutar vid periodens slut',
          'subscriptions.grace' => 'Betalning misslyckades',
          'subscriptions.ended' => 'Avslutade',
          'subscriptions.new_in_period' => 'Nya i perioden',
          'subscriptions.withdrawals_in_period' => 'Ångrade köp i perioden',
          'projects.total' => 'Totalt',
          'projects.new_in_period' => 'Nya i perioden',
          'projects.changed_in_period' => 'Ändrade i perioden',
          'projects.owners' => 'Konton med projekt',
          'projects.match' => 'Match',
          'projects.training' => 'Träning',
          'projects.education' => 'Utbildning',
          'live.live_now' => 'Pågår nu',
          'live.sessions_in_period' => 'Startade i perioden',
          'live.participants_in_period' => 'Deltagare i perioden',
          'live.guests_in_period' => 'Varav gäster',
          'sharing.share_links' => 'Aktiva delningslänkar',
          'sharing.library_items' => 'I egna bibliotek',
          'sharing.shared_items' => 'Delade med alla',
          'sharing.open_reports' => 'Anmälningar att granska',
          _ => key,
        }
      : switch ('$section.$key') {
          'accounts.total' => 'Total',
          'accounts.new_in_period' => 'New in the period',
          'accounts.signed_in_7_days' => 'Signed in, last 7 days',
          'accounts.signed_in_30_days' => 'Signed in, last 30 days',
          'accounts.signed_in_in_period' => 'Signed in in the period',
          'billing.trials_started' => 'Started in total',
          'billing.trials_started_in_period' => 'Started in the period',
          'billing.trials_active' => 'Running now',
          'billing.trials_ended_unpaid' => 'Ended without buying',
          'subscriptions.paying_month' => 'Paying monthly',
          'subscriptions.paying_year' => 'Paying yearly',
          'subscriptions.ending' => 'Cancelled, end with the period',
          'subscriptions.grace' => 'Payment failed',
          'subscriptions.ended' => 'Ended',
          'subscriptions.new_in_period' => 'New in the period',
          'subscriptions.withdrawals_in_period' =>
            'Purchases withdrawn in the period',
          'projects.total' => 'Total',
          'projects.new_in_period' => 'New in the period',
          'projects.changed_in_period' => 'Changed in the period',
          'projects.owners' => 'Accounts with projects',
          'projects.match' => 'Match',
          'projects.training' => 'Training',
          'projects.education' => 'Education',
          'live.live_now' => 'Running now',
          'live.sessions_in_period' => 'Started in the period',
          'live.participants_in_period' => 'Participants in the period',
          'live.guests_in_period' => 'Of which guests',
          'sharing.share_links' => 'Active share links',
          'sharing.library_items' => 'In own libraries',
          'sharing.shared_items' => 'Shared with everyone',
          'sharing.open_reports' => 'Reports to review',
          _ => key,
        };

  /// What a card counts, shown when it is opened.
  String counts(String section, String key) => isSwedish
      ? switch (section) {
          'accounts' when key.startsWith('signed_in') =>
            'Konton vars senaste inloggning är inom tiden. Den som är '
                'inloggad sedan länge räknas från sin senaste inloggning.',
          'accounts' => 'Konton, utan gäster i livelektioner.',
          'billing' =>
            'Varje konto kan starta en provperiod på 7 dagar, en gång.',
          'subscriptions' when key == 'withdrawals_in_period' =>
            'Köp som ångrats inom ångerrätten, bara riktiga betalningar.',
          'subscriptions' => 'Abonnemang på Tacticsboard via Stripe.',
          'projects' => 'Projekt som finns, med alla tavlor i dem.',
          'live' => 'Livelektioner och de som anslutit till dem.',
          _ => 'Antal just nu.',
        }
      : switch (section) {
          'accounts' when key.startsWith('signed_in') =>
            'Accounts whose latest sign-in is within the time. Someone '
                'signed in for long counts from their latest sign-in.',
          'accounts' => 'Accounts, not guests in live lessons.',
          'billing' => 'Every account can start a 7-day trial, once.',
          'subscriptions' when key == 'withdrawals_in_period' =>
            'Purchases withdrawn under the right of withdrawal, real '
                'payments only.',
          'subscriptions' => 'Tacticsboard subscriptions through Stripe.',
          'projects' => 'Projects that exist, with all their boards.',
          'live' => 'Live lessons and those who joined them.',
          _ => 'Count right now.',
        };

  String series(String key) => isSwedish
      ? switch (key) {
          'new_accounts' => 'Nya konton per dag',
          'trials_started' => 'Startade provperioder per dag',
          'new_subscriptions' => 'Nya abonnemang per dag',
          'new_projects' => 'Nya projekt per dag',
          'live_sessions' => 'Startade livelektioner per dag',
          _ => key,
        }
      : switch (key) {
          'new_accounts' => 'New accounts per day',
          'trials_started' => 'Trials started per day',
          'new_subscriptions' => 'New subscriptions per day',
          'new_projects' => 'New projects per day',
          'live_sessions' => 'Live lessons started per day',
          _ => key,
        };
}
