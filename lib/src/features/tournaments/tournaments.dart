import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';

/// Webtools Turneringsplanerare in the app: leaders find searchable
/// tournaments and register their team, put the tournament days in the
/// team's calendar, and an activity shows its tournament matches.
abstract interface class TournamentServices {
  Future<List<TeamTournament>> listMyTeamTournaments();
  Future<List<LeaderTeam>> listLeaderTeams();
  Future<List<FoundTournament>> searchTournaments(String text);
  Future<void> registerTeam({
    required String classId,
    required String teamId,
    required String teamName,
    required String clubName,
    required String contactName,
    required String contactEmail,
    String? contactPhone,
    String? notes,
  });

  /// The team's tournament days in its calendar: how many were added and
  /// moved.
  Future<({int created, int moved})> syncTeamCalendar(String registrationId);
  Future<EventTournament?> getEventTournament(String eventId);

  /// Your e-mail, for the registration's contact.
  String? get accountEmail;
}

class LeaderTeam {
  const LeaderTeam({
    required this.teamId,
    required this.teamName,
    required this.clubName,
  });
  final String teamId, teamName, clubName;

  factory LeaderTeam.fromJson(Map<String, dynamic> json) => LeaderTeam(
    teamId: json['team_id'] as String,
    teamName: json['team_name'] as String,
    clubName: json['club_name'] as String,
  );
}

/// A registration of one of your teams.
class TeamTournament {
  const TeamTournament({
    required this.registrationId,
    required this.tournamentId,
    required this.tournamentName,
    required this.startsOn,
    required this.endsOn,
    required this.className,
    required this.teamName,
    required this.status,
    required this.paid,
    required this.schedulePublished,
    required this.calendarDays,
    this.location,
    this.teamzoneTeamName,
    this.feeSek,
    this.paymentInfo,
  });
  final String registrationId, tournamentId, tournamentName, className;
  final String teamName, status;
  final DateTime startsOn, endsOn;
  final bool paid, schedulePublished;
  final int calendarDays;
  final String? location, teamzoneTeamName, paymentInfo;
  final int? feeSek;

  bool get approved => status == 'approved';

  factory TeamTournament.fromJson(Map<String, dynamic> json) => TeamTournament(
    registrationId: json['registration_id'] as String,
    tournamentId: json['tournament_id'] as String,
    tournamentName: json['tournament_name'] as String,
    startsOn: DateTime.parse(json['starts_on'] as String),
    endsOn: DateTime.parse(json['ends_on'] as String),
    className: json['class_name'] as String,
    teamName: json['team_name'] as String,
    status: json['status'] as String,
    paid: json['paid'] as bool? ?? false,
    schedulePublished: json['schedule_published'] as bool? ?? false,
    calendarDays: (json['calendar_days'] as num?)?.toInt() ?? 0,
    location: json['location'] as String?,
    teamzoneTeamName: json['teamzone_team_name'] as String?,
    feeSek: (json['fee_sek'] as num?)?.toInt(),
    paymentInfo: json['payment_info'] as String?,
  );
}

class TournamentClassInfo {
  const TournamentClassInfo({
    required this.id,
    required this.name,
    required this.format,
    required this.approved,
    this.description,
    this.maxTeams,
    this.feeSek,
  });
  final String id, name, format;
  final int approved;
  final String? description;
  final int? maxTeams, feeSek;

  bool get full => maxTeams != null && approved >= maxTeams!;

  factory TournamentClassInfo.fromJson(Map<String, dynamic> json) =>
      TournamentClassInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        format: json['format'] as String,
        approved: (json['approved'] as num?)?.toInt() ?? 0,
        description: json['description'] as String?,
        maxTeams: (json['max_teams'] as num?)?.toInt(),
        feeSek: (json['fee_sek'] as num?)?.toInt(),
      );
}

class FoundTournament {
  const FoundTournament({
    required this.id,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    required this.registrationOpen,
    required this.classes,
    this.sport,
    this.location,
    this.description,
    this.organizerName,
    this.paymentInfo,
  });
  final String id, name;
  final DateTime startsOn, endsOn;
  final bool registrationOpen;
  final List<TournamentClassInfo> classes;
  final String? sport, location, description, organizerName, paymentInfo;

  factory FoundTournament.fromJson(Map<String, dynamic> json) =>
      FoundTournament(
        id: json['id'] as String,
        name: json['name'] as String,
        startsOn: DateTime.parse(json['starts_on'] as String),
        endsOn: DateTime.parse(json['ends_on'] as String),
        registrationOpen: json['registration_is_open'] as bool? ?? false,
        classes: (json['classes'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TournamentClassInfo.fromJson)
            .toList(growable: false),
        sport: json['sport'] as String?,
        location: json['location'] as String?,
        description: json['description'] as String?,
        organizerName: json['organizer_name'] as String?,
        paymentInfo: json['payment_info'] as String?,
      );
}

class TournamentMatchInfo {
  const TournamentMatchInfo({
    required this.id,
    required this.played,
    this.homeName,
    this.awayName,
    this.label,
    this.groupName,
    this.pitchName,
    this.startsAt,
    this.homeScore,
    this.awayScore,
    this.homePenalties,
    this.awayPenalties,
  });
  final String id;
  final bool played;
  final String? homeName, awayName, label, groupName, pitchName;
  final DateTime? startsAt;
  final int? homeScore, awayScore, homePenalties, awayPenalties;

  /// "2–1", "1–1 (4–3 str.)", or null before it is played.
  String? get score {
    if (!played || homeScore == null || awayScore == null) return null;
    final penalties = homePenalties != null && awayPenalties != null
        ? ' ($homePenalties–$awayPenalties str.)'
        : '';
    return '$homeScore–$awayScore$penalties';
  }

  factory TournamentMatchInfo.fromJson(Map<String, dynamic> json) =>
      TournamentMatchInfo(
        id: json['id'] as String,
        played: json['status'] == 'played',
        homeName: json['home_name'] as String?,
        awayName: json['away_name'] as String?,
        label: json['label'] as String?,
        groupName: json['group_name'] as String?,
        pitchName: json['pitch_name'] as String?,
        startsAt: json['starts_at'] == null
            ? null
            : DateTime.parse(json['starts_at'] as String),
        homeScore: (json['home_score'] as num?)?.toInt(),
        awayScore: (json['away_score'] as num?)?.toInt(),
        homePenalties: (json['home_penalties'] as num?)?.toInt(),
        awayPenalties: (json['away_penalties'] as num?)?.toInt(),
      );
}

class StandingInfo {
  const StandingInfo({
    required this.teamName,
    required this.played,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
  });
  final String teamName;
  final int played, goalsFor, goalsAgainst, points;

  factory StandingInfo.fromJson(Map<String, dynamic> json) => StandingInfo(
    teamName: json['team_name'] as String,
    played: (json['played'] as num?)?.toInt() ?? 0,
    goalsFor: (json['goals_for'] as num?)?.toInt() ?? 0,
    goalsAgainst: (json['goals_against'] as num?)?.toInt() ?? 0,
    points: (json['points'] as num?)?.toInt() ?? 0,
  );
}

/// An activity's tournament: the team's matches that day and its group.
class EventTournament {
  const EventTournament({
    required this.tournamentName,
    required this.className,
    required this.teamName,
    required this.matches,
    required this.groups,
  });
  final String tournamentName, className, teamName;
  final List<TournamentMatchInfo> matches;
  final List<({String name, List<StandingInfo> standings})> groups;

  factory EventTournament.fromJson(Map<String, dynamic> json) =>
      EventTournament(
        tournamentName: json['tournament_name'] as String,
        className: json['class_name'] as String,
        teamName: json['team_name'] as String,
        matches: (json['matches'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TournamentMatchInfo.fromJson)
            .toList(growable: false),
        groups: (json['groups'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(
              (group) => (
                name: group['name'] as String,
                standings: (group['standings'] as List? ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .map(StandingInfo.fromJson)
                    .toList(growable: false),
              ),
            )
            .toList(growable: false),
      );
}

/// The API's error codes as sentences.
String tournamentErrorText(Object error) {
  final text = error.toString();
  for (final entry in const {
    'registration_closed': 'Anmälan är stängd.',
    'class_full': 'Klassen är full.',
    'team_name_taken': 'Ett lag med det namnet är redan anmält i klassen.',
    'team_already_registered': 'Laget är redan anmält i klassen.',
    'invalid_email': 'Skriv en giltig e-postadress.',
    'not_team_leader': 'Du kan bara anmäla lag där du är ledare.',
    'not_approved': 'Anmälan är inte godkänd än.',
    'schedule_not_published': 'Arrangören har inte publicerat spelschemat än.',
    'no_matches': 'Laget har inga matcher med tid än.',
  }.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'Det gick inte. Försök igen.';
}

String _dateSpan(BuildContext context, DateTime startsOn, DateTime endsOn) {
  final localizations = MaterialLocalizations.of(context);
  if (startsOn == endsOn) return localizations.formatMediumDate(startsOn);
  return '${localizations.formatShortMonthDay(startsOn)}–${localizations.formatMediumDate(endsOn)}';
}

/// "Turneringar" for leaders: your teams' registrations, the calendar, and
/// searching for open tournaments to register in.
class TournamentsPage extends StatefulWidget {
  const TournamentsPage({
    super.key,
    required this.services,
    this.activeTeamId,
    this.contactName,
  });
  final TournamentServices services;

  /// The team the app is in, chosen first when registering.
  final String? activeTeamId;
  final String? contactName;

  @override
  State<TournamentsPage> createState() => _TournamentsPageState();
}

class _TournamentsPageState extends State<TournamentsPage> {
  late Future<List<TeamTournament>> _mine = _loadMine();
  Future<List<FoundTournament>>? _found;
  final _search = TextEditingController();
  Timer? _debounce;
  String? _syncing;

  Future<List<TeamTournament>> _loadMine() async {
    try {
      return await widget.services.listMyTeamTournaments();
    } catch (error) {
      AppErrors.caught('tournaments._loadMine', error);
      rethrow;
    }
  }

  Future<List<FoundTournament>> _searchFor(String text) async {
    try {
      return await widget.services.searchTournaments(text);
    } catch (error) {
      AppErrors.caught('tournaments._search', error);
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    _found = _searchFor('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _found = _searchFor(text);
      });
    });
  }

  Future<void> _sync(TeamTournament item) async {
    setState(() => _syncing = item.registrationId);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    try {
      final result = await widget.services.syncTeamCalendar(
        item.registrationId,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.created > 0
                ? '${result.created == 1 ? 'En dag är inlagd' : '${result.created} dagar är inlagda'} i lagets kalender.'
                : result.moved > 0
                ? 'Kalendern är uppdaterad med de nya tiderna.'
                : 'Kalendern stämmer redan med spelschemat.',
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _mine = _loadMine();
        });
      }
    } catch (error) {
      AppErrors.caught('tournaments._sync', error);
      messenger.showSnackBar(
        SnackBar(content: Text(tournamentErrorText(error))),
      );
    } finally {
      if (mounted) setState(() => _syncing = null);
    }
  }

  Future<void> _register(FoundTournament tournament) async {
    final registered = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RegisterSheet(
        services: widget.services,
        tournament: tournament,
        activeTeamId: widget.activeTeamId,
        contactName: widget.contactName,
      ),
    );
    if (registered == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(registered)));
    setState(() {
      _mine = _loadMine();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Turneringar')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _mine = _loadMine();
            _found = _searchFor(_search.text);
          });
          await _mine.catchError((_) => const <TeamTournament>[]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Lagets turneringar', style: theme.textTheme.titleMedium),
            FutureBuilder<List<TeamTournament>>(
              future: _mine,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Turneringarna kunde inte hämtas.'),
                  );
                }
                final items = snapshot.data ?? const <TeamTournament>[];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Inga anmälda lag än. Sök efter en turnering nedan.',
                    ),
                  );
                }
                return Column(
                  children: [for (final item in items) _teamCard(item)],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Hitta turnering', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('tournament-search'),
              controller: _search,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Namn, ort eller sport',
              ),
            ),
            FutureBuilder<List<FoundTournament>>(
              future: _found,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Sökningen gick inte. Försök igen.'),
                  );
                }
                final found = snapshot.data ?? const <FoundTournament>[];
                if (found.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Inga öppna turneringar hittades. Har du fått en anmälningslänk från arrangören kan du anmäla laget där.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final tournament in found)
                      ListTile(
                        key: ValueKey('tournament-found-${tournament.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.emoji_events_outlined),
                        title: Text(tournament.name),
                        subtitle: Text(
                          [
                            _dateSpan(
                              context,
                              tournament.startsOn,
                              tournament.endsOn,
                            ),
                            ?tournament.location,
                            ?tournament.sport,
                            tournament.registrationOpen
                                ? 'Anmälan öppen'
                                : 'Anmälan stängd',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _register(tournament),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamCard(TeamTournament item) {
    final theme = Theme.of(context);
    final status = switch (item.status) {
      'approved' => 'Godkänd',
      'pending' => 'Väntar på godkännande',
      _ => item.status,
    };
    final fee = item.feeSek != null && item.feeSek! > 0
        ? (item.paid ? 'Avgiften är betald' : 'Avgift ${item.feeSek} kr')
        : null;
    return Card(
      key: ValueKey('team-tournament-${item.registrationId}'),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.tournamentName, style: theme.textTheme.titleSmall),
            Text(
              [
                _dateSpan(context, item.startsOn, item.endsOn),
                ?item.location,
                '${item.teamName} i ${item.className}',
              ].join(' · '),
            ),
            Text([status, ?fee].join(' · '), style: theme.textTheme.bodySmall),
            if (!item.paid && fee != null && item.paymentInfo != null)
              Text(
                'Betalning: ${item.paymentInfo}',
                style: theme.textTheme.bodySmall,
              ),
            if (item.approved) ...[
              const SizedBox(height: 8),
              if (!item.schedulePublished)
                Text(
                  'Spelschemat är inte publicerat än. Då kan du lägga in turneringen i lagets kalender.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    key: ValueKey('tournament-sync-${item.registrationId}'),
                    onPressed: _syncing == null ? () => _sync(item) : null,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(
                      item.calendarDays > 0
                          ? 'Uppdatera lagets kalender'
                          : 'Lägg in i lagets kalender',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tournament found by search: its classes, and registering your team.
class _RegisterSheet extends StatefulWidget {
  const _RegisterSheet({
    required this.services,
    required this.tournament,
    this.activeTeamId,
    this.contactName,
  });
  final TournamentServices services;
  final FoundTournament tournament;
  final String? activeTeamId, contactName;

  @override
  State<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends State<_RegisterSheet> {
  late final Future<List<LeaderTeam>> _teams = widget.services
      .listLeaderTeams()
      .catchError((Object error) {
        AppErrors.caught('tournaments._RegisterSheet.teams', error);
        return const <LeaderTeam>[];
      });
  String? _teamId, _classId;
  late final _contact = TextEditingController(text: widget.contactName ?? '');
  late final _email = TextEditingController(
    text: widget.services.accountEmail ?? '',
  );
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(LeaderTeam team) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.registerTeam(
        classId: _classId!,
        teamId: team.teamId,
        teamName: '${team.clubName} ${team.teamName}',
        clubName: team.clubName,
        contactName: _contact.text.trim(),
        contactEmail: _email.text.trim(),
        contactPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        '${team.teamName} är anmält till ${widget.tournament.name}. Arrangören godkänner anmälan.',
      );
    } catch (error) {
      AppErrors.caught('tournaments._RegisterSheet.submit', error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tournamentErrorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tournament = widget.tournament;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: FutureBuilder<List<LeaderTeam>>(
        future: _teams,
        builder: (context, snapshot) {
          final teams = snapshot.data ?? const <LeaderTeam>[];
          final team =
              teams.where((item) => item.teamId == _teamId).firstOrNull ??
              teams
                  .where((item) => item.teamId == widget.activeTeamId)
                  .firstOrNull ??
              teams.firstOrNull;
          return ListView(
            shrinkWrap: true,
            children: [
              Text(tournament.name, style: theme.textTheme.titleLarge),
              Text(
                [
                  _dateSpan(context, tournament.startsOn, tournament.endsOn),
                  ?tournament.location,
                  if (tournament.organizerName != null)
                    'Arrangör ${tournament.organizerName}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (tournament.description case final description?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(description),
                ),
              const SizedBox(height: 12),
              if (!tournament.registrationOpen)
                const Text('Anmälan är stängd.')
              else if (snapshot.connectionState != ConnectionState.done)
                const Center(child: CircularProgressIndicator())
              else if (teams.isEmpty)
                const Text(
                  'Du behöver vara ledare för ett lag för att anmäla det.',
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('tournament-register-team'),
                  initialValue: team?.teamId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Lag'),
                  items: [
                    for (final item in teams)
                      DropdownMenuItem(
                        value: item.teamId,
                        child: Text('${item.teamName} · ${item.clubName}'),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _teamId = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: const ValueKey('tournament-register-class'),
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Klass'),
                  items: [
                    for (final item in tournament.classes)
                      DropdownMenuItem(
                        value: item.id,
                        enabled: !item.full,
                        child: Text(
                          [
                            item.name,
                            ?item.description,
                            if (item.feeSek != null && item.feeSek! > 0)
                              '${item.feeSek} kr',
                            if (item.full) 'full',
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _classId = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contact,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Kontaktperson'),
                ),
                TextField(
                  controller: _email,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-post'),
                ),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefon (frivilligt)',
                  ),
                ),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Meddelande till arrangören (frivilligt)',
                  ),
                ),
                if (tournament.paymentInfo case final info?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Avgiften betalas till arrangören: $info',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey('tournament-register-submit'),
                  onPressed:
                      _busy ||
                          team == null ||
                          _classId == null ||
                          _contact.text.trim().isEmpty ||
                          _email.text.trim().isEmpty
                      ? null
                      : () => _submit(team),
                  child: const Text('Anmäl laget'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// On an activity from a tournament: the team's matches that day and the
/// group's table. Nothing for other activities.
class EventTournamentSection extends StatefulWidget {
  const EventTournamentSection({
    super.key,
    required this.eventId,
    required this.services,
  });
  final String eventId;
  final TournamentServices services;

  @override
  State<EventTournamentSection> createState() => _EventTournamentSectionState();
}

class _EventTournamentSectionState extends State<EventTournamentSection> {
  late Future<EventTournament?> _tournament = _load();

  Future<EventTournament?> _load() async {
    try {
      return await widget.services.getEventTournament(widget.eventId);
    } catch (error) {
      AppErrors.caught('tournaments.EventTournamentSection', error);
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant EventTournamentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) _tournament = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<EventTournament?>(
    future: _tournament,
    builder: (context, snapshot) {
      final tournament = snapshot.data;
      if (tournament == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      String time(DateTime value) =>
          TimeOfDay.fromDateTime(value.toLocal()).format(context);
      return Card(
        key: const ValueKey('event-tournament'),
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tournament.tournamentName} · ${tournament.className}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              for (final match in tournament.matches)
                ListTile(
                  key: ValueKey('event-tournament-match-${match.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: SizedBox(
                    width: 48,
                    child: Text(
                      match.startsAt == null ? '–' : time(match.startsAt!),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  title: Text(
                    '${match.homeName ?? '?'} – ${match.awayName ?? '?'}',
                  ),
                  subtitle: Text(
                    [
                      match.label ??
                          (match.groupName == null
                              ? null
                              : 'Grupp ${match.groupName}'),
                      match.pitchName,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: match.score == null
                      ? null
                      : Text(match.score!, style: theme.textTheme.titleSmall),
                ),
              for (final group in tournament.groups)
                if (group.standings.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Grupp ${group.name}',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  for (final (index, row) in group.standings.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(width: 20, child: Text('${index + 1}')),
                          Expanded(
                            child: Text(
                              row.teamName,
                              style: row.teamName == tournament.teamName
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : null,
                            ),
                          ),
                          SizedBox(width: 28, child: Text('${row.played}')),
                          SizedBox(
                            width: 52,
                            child: Text('${row.goalsFor}–${row.goalsAgainst}'),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${row.points}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
            ],
          ),
        ),
      );
    },
  );
}
