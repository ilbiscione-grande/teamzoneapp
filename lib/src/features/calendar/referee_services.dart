import 'package:supabase_flutter/supabase_flutter.dart';

/// REF-01: referees on matches. A match has 0–3 places (Huvuddomare,
/// Assisterande domare 1 and 2). A team's event managers propose referees
/// or write one in; referees and assigners search matches and offer to
/// referee. Both sides confirm when the other side can.

const refereeSlots = ['main', 'assistant_1', 'assistant_2'];

String refereeSlotLabel(String slot) => switch (slot) {
  'main' => 'Huvuddomare',
  'assistant_1' => 'Assisterande domare 1',
  'assistant_2' => 'Assisterande domare 2',
  _ => slot,
};

/// A database reason in Swedish, or a general message.
String refereeErrorText(Object error) {
  final text = error.toString();
  const known = {
    'slot_taken': 'Platsen är redan tillsatt eller har en förfrågan.',
    'slots_in_use': 'Ta bort domarna på de platser som försvinner först.',
    'not_a_match': 'Domare kan bara tillsättas på matcher som ska spelas.',
    'not_a_referee': 'Personen är inte domare längre.',
    'not_pending': 'Förfrågan är redan besvarad.',
  };
  for (final entry in known.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'Det gick inte att spara. Försök igen.';
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class EventReferee {
  const EventReferee({
    required this.id,
    required this.slot,
    required this.state,
    required this.proposedSide,
    required this.name,
    this.personId,
    this.clubName,
    this.external = false,
  });
  factory EventReferee.fromJson(Map<String, dynamic> json) => EventReferee(
    id: json['id'] as String,
    slot: json['slot'] as String? ?? 'main',
    state: json['state'] as String? ?? 'confirmed',
    proposedSide: json['proposed_side'] as String? ?? 'team',
    name: json['name'] as String? ?? '',
    personId: json['person_id'] as String?,
    clubName: json['club_name'] as String?,
    external: json['external'] == true,
  );
  final String id, slot, state, proposedSide, name;
  final String? personId, clubName;
  final bool external;
}

class EventRefereeView {
  const EventRefereeView({
    required this.slots,
    required this.canManage,
    required this.referees,
  });
  factory EventRefereeView.fromJson(Map<String, dynamic> json) =>
      EventRefereeView(
        slots: (json['slots'] as num?)?.toInt() ?? 0,
        canManage: json['can_manage'] == true,
        referees: [
          for (final row
              in (json['referees'] as List? ?? const []).whereType<Map>().map(
                (row) => row.cast<String, dynamic>(),
              ))
            EventReferee.fromJson(row),
        ],
      );
  final int slots;
  final bool canManage;
  final List<EventReferee> referees;

  EventReferee? inSlot(String slot) =>
      referees.where((referee) => referee.slot == slot).firstOrNull;
}

class RefereeCandidate {
  const RefereeCandidate({
    required this.personId,
    required this.name,
    required this.clubName,
    required this.confirmable,
    this.teamName,
  });
  factory RefereeCandidate.fromJson(Map<String, dynamic> json) =>
      RefereeCandidate(
        personId: json['person_id'] as String,
        name: json['name'] as String? ?? '',
        clubName: json['club_name'] as String? ?? '',
        teamName: json['team_name'] as String?,
        confirmable: json['confirmable'] == true,
      );
  final String personId, name, clubName;
  final String? teamName;

  /// Someone (the referee or the club's assigner) confirms; otherwise the
  /// referee is confirmed at once.
  final bool confirmable;
}

/// A match as referees see it: no players, no notes.
class RefereeMatch {
  const RefereeMatch({
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.teamName,
    required this.clubName,
    required this.slotCount,
    this.opponentName,
    this.homeAway,
    this.location,
    this.taken = const {},
  });
  factory RefereeMatch.fromJson(Map<String, dynamic> json) => RefereeMatch(
    eventId: json['event_id'] as String,
    title: json['title'] as String? ?? '',
    startsAt: _time(json['starts_at']) ?? DateTime.now(),
    endsAt: _time(json['ends_at']) ?? DateTime.now(),
    teamName: json['team_name'] as String? ?? '',
    clubName: json['club_name'] as String? ?? '',
    slotCount: (json['referee_slots'] as num?)?.toInt() ?? 0,
    opponentName: json['opponent_name'] as String?,
    homeAway: json['home_away'] as String?,
    location: json['location'] as String?,
    taken: {
      for (final row
          in (json['taken'] as List? ?? const []).whereType<Map>().map(
            (row) => row.cast<String, dynamic>(),
          ))
        row['slot'] as String: row['state'] as String? ?? '',
    },
  );
  final String eventId, title, teamName, clubName;
  final DateTime startsAt, endsAt;

  /// How many referees the team wants; 0 when not chosen yet.
  final int slotCount;
  final String? opponentName, homeAway, location;

  /// Places with a referee or a pending request, and their state.
  final Map<String, String> taken;

  /// The places a referee can offer for: the team's chosen number, at least
  /// the first, minus those already taken.
  List<String> get openSlots => [
    for (final slot in refereeSlots.take(slotCount.clamp(1, 3)))
      if (!taken.containsKey(slot)) slot,
  ];

  /// "J (IF Eksjö Fotboll) – Vetlanda FF" with home and away in order.
  String get matchup {
    final team = '$teamName ($clubName)';
    final opponent = opponentName;
    if (opponent == null || opponent.trim().isEmpty) return team;
    return homeAway == 'away' ? '$opponent – $team' : '$team – $opponent';
  }
}

class RefereeAssignment {
  const RefereeAssignment({
    required this.referee,
    required this.match,
    required this.awaitingMe,
  });
  factory RefereeAssignment.fromJson(Map<String, dynamic> json) =>
      RefereeAssignment(
        referee: EventReferee.fromJson(json),
        match: RefereeMatch.fromJson(
          (json['match'] as Map).cast<String, dynamic>(),
        ),
        awaitingMe: json['awaiting_me'] == true,
      );
  final EventReferee referee;
  final RefereeMatch match;

  /// A team asked: the referee (or the assigner) answers.
  final bool awaitingMe;
}

class RefereePerson {
  const RefereePerson({
    required this.personId,
    required this.name,
    required this.clubName,
    required this.self,
  });
  factory RefereePerson.fromJson(Map<String, dynamic> json) => RefereePerson(
    personId: json['person_id'] as String,
    name: json['name'] as String? ?? '',
    clubName: json['club_name'] as String? ?? '',
    self: json['self'] == true,
  );
  final String personId, name, clubName;
  final bool self;
}

abstract interface class RefereeServices {
  Future<EventRefereeView> getEventReferees(String eventId);
  Future<void> setSlots(String eventId, int count);
  Future<List<RefereeCandidate>> searchReferees(String query);

  /// A referee in TeamZone ([personId]) or one written in ([writtenName]).
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  });
  Future<void> request(String eventId, String slot, String personId);
  Future<void> respond(String refereeId, bool accept);
  Future<void> withdraw(String refereeId);
  Future<List<RefereeMatch>> searchMatches(
    String query,
    DateTime from,
    DateTime to,
  );
  Future<List<RefereePerson>> myRefereePeople();
  Future<List<RefereeAssignment>> myAssignments();
}

class UnconfiguredRefereeServices implements RefereeServices {
  const UnconfiguredRefereeServices();
  Future<T> _fail<T>() => Future.error(StateError('not_configured'));
  @override
  Future<EventRefereeView> getEventReferees(String eventId) => _fail();
  @override
  Future<void> setSlots(String eventId, int count) => _fail();
  @override
  Future<List<RefereeCandidate>> searchReferees(String query) async => const [];
  @override
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  }) => _fail();
  @override
  Future<void> request(String eventId, String slot, String personId) => _fail();
  @override
  Future<void> respond(String refereeId, bool accept) => _fail();
  @override
  Future<void> withdraw(String refereeId) => _fail();
  @override
  Future<List<RefereeMatch>> searchMatches(
    String query,
    DateTime from,
    DateTime to,
  ) async => const [];
  @override
  Future<List<RefereePerson>> myRefereePeople() async => const [];
  @override
  Future<List<RefereeAssignment>> myAssignments() async => const [];
}

class SupabaseRefereeServices implements RefereeServices {
  SupabaseRefereeServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) =>
      _client.schema('api').rpc<Object?>(name, params: params);

  List<Map<String, dynamic>> _rows(Object? value) => [
    if (value is List)
      for (final row in value.whereType<Map>()) row.cast<String, dynamic>(),
  ];

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  Future<EventRefereeView> getEventReferees(String eventId) async {
    final value = await _rpc('get_event_referees', {
      'target_event_id': eventId,
    });
    if (value is! Map) throw StateError('invalid_response');
    return EventRefereeView.fromJson(value.cast<String, dynamic>());
  }

  @override
  Future<void> setSlots(String eventId, int count) async {
    await _rpc('set_event_referee_slots', {
      'target_event_id': eventId,
      'slot_count': count,
    });
  }

  @override
  Future<List<RefereeCandidate>> searchReferees(String query) async => [
    for (final row in _rows(
      await _rpc('search_referees', {'search_text': query}),
    ))
      RefereeCandidate.fromJson(row),
  ];

  @override
  Future<void> propose(
    String eventId,
    String slot, {
    String? personId,
    String? writtenName,
  }) async {
    await _rpc('propose_event_referee', {
      'target_event_id': eventId,
      'target_slot': slot,
      'target_person_id': personId,
      'written_name': writtenName,
    });
  }

  @override
  Future<void> request(String eventId, String slot, String personId) async {
    await _rpc('request_event_referee', {
      'target_event_id': eventId,
      'target_slot': slot,
      'target_person_id': personId,
    });
  }

  @override
  Future<void> respond(String refereeId, bool accept) async {
    await _rpc('respond_event_referee', {
      'target_referee_id': refereeId,
      'accept': accept,
    });
  }

  @override
  Future<void> withdraw(String refereeId) async {
    await _rpc('withdraw_event_referee', {'target_referee_id': refereeId});
  }

  @override
  Future<List<RefereeMatch>> searchMatches(
    String query,
    DateTime from,
    DateTime to,
  ) async => [
    for (final row in _rows(
      await _rpc('search_referee_matches', {
        'search_text': query,
        'from_date': _date(from),
        'to_date': _date(to),
      }),
    ))
      RefereeMatch.fromJson(row),
  ];

  @override
  Future<List<RefereePerson>> myRefereePeople() async => [
    for (final row in _rows(await _rpc('list_my_referee_people')))
      RefereePerson.fromJson(row),
  ];

  @override
  Future<List<RefereeAssignment>> myAssignments() async => [
    for (final row in _rows(await _rpc('list_my_referee_assignments')))
      RefereeAssignment.fromJson(row),
  ];
}
