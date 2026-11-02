/// Self-rated effort after a training (PAR-PRIV-04, decided 2026-11-02):
/// from 13 the player answers how hard the session was, 1–10. The player
/// and the team's leaders see it (the leaders in the Team Development
/// Plan's load), and so do the player's guardians. The player can opt out,
/// and an answer is deleted 24 months after the training. Never used for
/// an automatic ranking or selection.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// One person at a training: the actor themselves, or a player they are
/// guardian of.
class SessionEffortPerson {
  const SessionEffortPerson({
    required this.personId,
    required this.name,
    required this.self,
    this.rating,
    this.optedOut = false,
    this.canAnswer = false,
  });
  factory SessionEffortPerson.fromJson(Map<String, dynamic> json) =>
      SessionEffortPerson(
        personId: json['person_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        self: json['self'] == true,
        rating: (json['rating'] as num?)?.toInt(),
        optedOut: json['opted_out'] == true,
        canAnswer: json['can_answer'] == true,
      );
  final String personId, name;
  final bool self, optedOut, canAnswer;
  final int? rating;
}

/// The people the actor answers for or sees at a training; empty when
/// there is no question (too young, not the team's player, before the
/// training).
class SessionEffort {
  const SessionEffort({this.open = false, this.people = const []});
  factory SessionEffort.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return SessionEffort(
      open: map['open'] == true,
      people: [
        for (final row in (map['people'] as List? ?? const []).whereType<Map>())
          SessionEffortPerson.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }

  /// Within the seven days after the training when it can be answered.
  final bool open;
  final List<SessionEffortPerson> people;

  SessionEffortPerson? get me => people.where((p) => p.self).firstOrNull;
}

abstract interface class SessionEffortServices {
  Future<SessionEffort> get(String eventId);

  /// The player's own answer; null takes it back.
  Future<SessionEffort> rate(String eventId, int? rating);

  /// Stops the questions (the answers are deleted) or starts them again.
  Future<SessionEffort> setOptOut(String eventId, bool optOut);
}

class UnconfiguredSessionEffortServices implements SessionEffortServices {
  const UnconfiguredSessionEffortServices();
  @override
  Future<SessionEffort> get(String eventId) async => const SessionEffort();
  @override
  Future<SessionEffort> rate(String eventId, int? rating) async =>
      const SessionEffort();
  @override
  Future<SessionEffort> setOptOut(String eventId, bool optOut) async =>
      const SessionEffort();
}

class SupabaseSessionEffortServices implements SessionEffortServices {
  SupabaseSessionEffortServices(this._client);
  final SupabaseClient _client;

  Future<SessionEffort> _rpc(String name, Map<String, Object?> params) async =>
      SessionEffort.fromJson(
        await _client
            .schema('api')
            .rpc<Object?>(name, params: params)
            .timeout(const Duration(seconds: 15)),
      );

  @override
  Future<SessionEffort> get(String eventId) =>
      _rpc('get_session_effort', {'target_event_id': eventId});

  @override
  Future<SessionEffort> rate(String eventId, int? rating) => _rpc(
    'set_session_effort',
    {'target_event_id': eventId, 'new_rating': rating},
  );

  @override
  Future<SessionEffort> setOptOut(String eventId, bool optOut) => _rpc(
    'set_session_effort_opt_out',
    {'target_event_id': eventId, 'opt_out': optOut},
  );
}

/// Where the event page finds the services, configured at start.
abstract final class SessionEffortFeature {
  static SessionEffortServices services =
      const UnconfiguredSessionEffortServices();

  static void configure(SupabaseClient client) =>
      services = SupabaseSessionEffortServices(client);
}
