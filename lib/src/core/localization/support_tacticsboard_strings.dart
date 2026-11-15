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
  String get sourceNote => isSwedish
      ? 'Från Tacticsboard på webtools.teamzoneapp.se, i samma databas som '
            'appen. Bara antal.'
      : 'From Tacticsboard on webtools.teamzoneapp.se, in the same database '
            'as the app. Counts only.';

  String section(String name) => switch (name) {
    'accounts' => isSwedish ? 'Konton' : 'Accounts',
    'billing' => isSwedish ? 'Provperioder' : 'Trials',
    'subscriptions' => isSwedish ? 'Abonnemang' : 'Subscriptions',
    'projects' => isSwedish ? 'Projekt' : 'Projects',
    'live' => isSwedish ? 'Livelektioner' : 'Live lessons',
    'sharing' => isSwedish ? 'Delat' : 'Shared',
    'active' => isSwedish ? 'Aktiva i Webtools' : 'Active in Webtools',
    'boards' => isSwedish ? 'Tavlor' : 'Boards',
    'tools' => isSwedish ? 'Verktyg på tavlorna' : 'Tools on the boards',
    'uses' => isSwedish ? 'Använt i perioden' : 'Used in the period',
    'library' => isSwedish ? 'Mallar och bibliotek' : 'Templates and library',
    'live_activity' =>
      isSwedish
          ? 'I livelektionerna i perioden'
          : 'In live lessons in the period',
    _ => name,
  };

  String label(String section, String key) => section == 'tools'
      ? tool(key)
      : isSwedish
      ? switch ('$section.$key') {
          'active.now' => 'Just nu (senaste 5 min)',
          'active.today' => 'I dag',
          'active.last_7_days' => 'Senaste 7 dagarna',
          'active.last_30_days' => 'Senaste 30 dagarna',
          'active.in_period' => 'I perioden',
          'boards.total' => 'Tavlor totalt',
          'boards.animated' => 'Med animering',
          'boards.frames' => 'Bilder i animeringar',
          'boards.view_full' => 'Hel plan',
          'boards.view_attack' => 'Anfallshalva',
          'boards.view_defend' => 'Försvarshalva',
          'boards.view_empty' => 'Tom yta',
          'uses.starter' => 'Färdiga tavlor',
          'uses.template' => 'Egna mallar',
          'uses.library' => 'Eget bibliotek',
          'uses.shared' => 'Från biblioteket',
          'uses.page' => 'Sidvisningar',
          'library.starters' => 'TeamZones övningar',
          'library.templates' => 'Egna mallar',
          'library.favorites' => 'Favoritmarkeringar',
          'library.folders' => 'Mappar',
          'library.pinned' => 'Fästa projekt',
          'library.versions_in_period' => 'Sparade versioner i perioden',
          'live_activity.messages_in_period' => 'Chattmeddelanden',
          'live_activity.questions_in_period' => 'Frågor',
          'live_activity.answers_in_period' => 'Svar på frågor',
          'live_activity.drawings_in_period' => 'Ritningar',
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
          'active.now' => 'Right now (last 5 min)',
          'active.today' => 'Today',
          'active.last_7_days' => 'Last 7 days',
          'active.last_30_days' => 'Last 30 days',
          'active.in_period' => 'In the period',
          'boards.total' => 'Boards in total',
          'boards.animated' => 'Animated',
          'boards.frames' => 'Frames in animations',
          'boards.view_full' => 'Full pitch',
          'boards.view_attack' => 'Attacking half',
          'boards.view_defend' => 'Defending half',
          'boards.view_empty' => 'Empty area',
          'uses.starter' => 'Ready boards',
          'uses.template' => 'Own templates',
          'uses.library' => 'Own library',
          'uses.shared' => 'From the library',
          'uses.page' => 'Page views',
          'library.starters' => "TeamZone's exercises",
          'library.templates' => 'Own templates',
          'library.favorites' => 'Favourite marks',
          'library.folders' => 'Folders',
          'library.pinned' => 'Pinned projects',
          'library.versions_in_period' => 'Versions saved in the period',
          'live_activity.messages_in_period' => 'Chat messages',
          'live_activity.questions_in_period' => 'Questions',
          'live_activity.answers_in_period' => 'Answers to questions',
          'live_activity.drawings_in_period' => 'Drawings',
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
          'active' when key == 'now' =>
            'Konton som haft Webtools öppet de senaste fem minuterna. En öppen '
                'flik säger till ungefär en gång i minuten.',
          'active' => 'Konton som haft Webtools öppet minst en gång.',
          'boards' => 'Tavlorna i de projekt som finns nu.',
          'tools' =>
            'Hur många av den sortens objekt som ligger på tavlorna i de '
                'projekt som finns nu, i alla bilder.',
          'uses' when key == 'page' => 'Sidor som öppnats i Webtools.',
          'uses' =>
            'Gånger det använts för att börja ett projekt eller en tavla.',
          'library' => 'Antal just nu, versionerna i perioden.',
          'live_activity' => 'Det deltagarna gjort i livelektionerna.',
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
          'active' when key == 'now' =>
            'Accounts with Webtools open in the last five minutes. An open '
                'tab reports about once a minute.',
          'active' => 'Accounts that had Webtools open at least once.',
          'boards' => 'The boards in the projects that exist now.',
          'tools' =>
            'How many objects of that kind are on the boards of the projects '
                'that exist now, in all frames.',
          'uses' when key == 'page' => 'Pages opened in Webtools.',
          'uses' => 'Times it was used to start a project or a board.',
          'library' => 'Count right now, versions in the period.',
          'live_activity' => 'What participants did in the live lessons.',
          _ => 'Count right now.',
        };

  String series(String key) => isSwedish
      ? switch (key) {
          'new_accounts' => 'Nya konton per dag',
          'trials_started' => 'Startade provperioder per dag',
          'new_subscriptions' => 'Nya abonnemang per dag',
          'new_projects' => 'Nya projekt per dag',
          'live_sessions' => 'Startade livelektioner per dag',
          'active' => 'Aktiva konton per dag',
          'page_views' => 'Sidvisningar per dag',
          'uses' => 'Användningar per dag',
          _ => key,
        }
      : switch (key) {
          'new_accounts' => 'New accounts per day',
          'trials_started' => 'Trials started per day',
          'new_subscriptions' => 'New subscriptions per day',
          'new_projects' => 'New projects per day',
          'live_sessions' => 'Live lessons started per day',
          'active' => 'Active accounts per day',
          'page_views' => 'Page views per day',
          'uses' => 'Uses per day',
          _ => key,
        };

  String tool(String key) => switch (key) {
    'player' => isSwedish ? 'Spelare' : 'Players',
    'ball' => isSwedish ? 'Bollar' : 'Balls',
    'cone' => isSwedish ? 'Koner' : 'Cones',
    'pole' => isSwedish ? 'Käppar' : 'Poles',
    'mannequin' => isSwedish ? 'Dockor' : 'Mannequins',
    'goal' => isSwedish ? 'Mål' : 'Goals',
    'line' => isSwedish ? 'Linjer och pilar' : 'Lines and arrows',
    'freehand' => isSwedish ? 'Frihandsritning' : 'Freehand',
    'rect' => isSwedish ? 'Rektanglar' : 'Rectangles',
    'ellipse' => isSwedish ? 'Ellipser' : 'Ellipses',
    'text' => isSwedish ? 'Texter' : 'Texts',
    'chain' => isSwedish ? 'Kedjor' : 'Chains',
    _ => isSwedish ? 'Annat ($key)' : 'Other ($key)',
  };

  String ranking(String name) => switch (name) {
    'starters' =>
      isSwedish ? 'Mest använda färdiga tavlor' : 'Most used ready boards',
    'shared' =>
      isSwedish ? 'Mest använt ur biblioteket' : 'Most used from the library',
    'favorites' => isSwedish ? 'Flest favoriter' : 'Most favourites',
    'pages' => isSwedish ? 'Mest besökta sidor' : 'Most visited pages',
    _ => name,
  };
  String get rankingEmpty =>
      isSwedish ? 'Inget i perioden än.' : 'Nothing in the period yet.';
  String activitySince(String? date) => date == null
      ? (isSwedish
            ? 'Aktiva, sidor och användning räknas från den dag Webtools '
                  'med mätningen driftsätts.'
            : 'Active accounts, pages and uses are counted from the day '
                  'Webtools with the counting is deployed.')
      : (isSwedish
            ? 'Aktiva, sidor och användning räknas sedan $date.'
            : 'Active accounts, pages and uses are counted since $date.');

  /// A ready board's name; the key is the project kind and the board, e.g.
  /// `match.lineup`.
  String starter(String key) {
    final parts = key.split('.');
    final kind = switch (parts.first) {
      'match' => 'Match',
      'training' => isSwedish ? 'Träning' : 'Training',
      'education' => isSwedish ? 'Utbildning' : 'Education',
      _ => parts.first,
    };
    final board = parts.length < 2 ? '' : parts[1];
    final name = isSwedish
        ? switch (board) {
            'lineup' => 'Uppställning',
            'build-up' => 'Speluppbyggnad',
            'attack' || 'attacking-shape' => 'Anfallsspel',
            'defence' || 'defensive-shape' => 'Försvarsspel',
            'corner-for' => 'Hörna anfall',
            'corner-against' => 'Hörna försvar',
            'free-kick-for' => 'Frispark anfall',
            'free-kick-against' => 'Frispark försvar',
            'throw-in-for' => 'Inkast anfall',
            'throw-in-against' => 'Inkast försvar',
            'warm-up' => 'Uppvärmning',
            'technique' => 'Teknik',
            'passing' => 'Passningsövning',
            'possession' => 'Possession',
            'finishing' => 'Avslut',
            'small-sided' => 'Smålagsspel',
            'principle' => 'Princip',
            'pressing' => 'Press',
            'transitions' => 'Omställningar',
            _ => board,
          }
        : switch (board) {
            'lineup' => 'Line-up',
            'build-up' => 'Build-up',
            'attack' || 'attacking-shape' => 'Attacking play',
            'defence' || 'defensive-shape' => 'Defending',
            'corner-for' => 'Corner, attacking',
            'corner-against' => 'Corner, defending',
            'free-kick-for' => 'Free kick, attacking',
            'free-kick-against' => 'Free kick, defending',
            'throw-in-for' => 'Throw-in, attacking',
            'throw-in-against' => 'Throw-in, defending',
            'warm-up' => 'Warm-up',
            'technique' => 'Technique',
            'passing' => 'Passing drill',
            'possession' => 'Possession',
            'finishing' => 'Finishing',
            'small-sided' => 'Small-sided game',
            'principle' => 'Principle',
            'pressing' => 'Pressing',
            'transitions' => 'Transitions',
            _ => board,
          };
    return '$name · $kind';
  }

  /// A Webtools page by its pattern.
  String page(String key) => switch (key) {
    '/' => isSwedish ? 'Startsidan' : 'Start page',
    '/tacticsboard' =>
      isSwedish ? 'Tacticsboard, projekten' : 'Tacticsboard, projects',
    '/tacticsboard/[id]' =>
      isSwedish ? 'Tacticsboard, ett projekt' : 'Tacticsboard, a project',
    '/tacticsboard/bibliotek' => isSwedish ? 'Biblioteket' : 'The library',
    '/tacticsboard/mapp/[id]' => isSwedish ? 'En mapp' : 'A folder',
    '/tacticsboard/demo' => isSwedish ? 'Demon' : 'The demo',
    '/tacticsboard/granska' =>
      isSwedish ? 'Granska anmälningar' : 'Review reports',
    '/delad/[token]' => isSwedish ? 'Delad tavla' : 'Shared board',
    '/delad/mapp/[token]' => isSwedish ? 'Delad mapp' : 'Shared folder',
    '/live' => isSwedish ? 'Live, starta' : 'Live, start',
    '/live/[code]' => isSwedish ? 'En livelektion' : 'A live lesson',
    '/konto' => isSwedish ? 'Kontot' : 'The account',
    '/logga-in' => isSwedish ? 'Logga in' : 'Sign in',
    '/support/tacticsboard' => isSwedish ? 'Hjälp' : 'Help',
    '/support/tacticsboard/[guide]' =>
      isSwedish ? 'En hjälpguide' : 'A help guide',
    'other' => isSwedish ? 'Annan sida' : 'Other page',
    _ => key,
  };
}
