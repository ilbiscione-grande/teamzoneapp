class WrittenMatchReport {
  const WrittenMatchReport({
    this.body = '',
    this.published = false,
    this.revision = 0,
    this.canEdit = false,
    this.canPublish = false,
  });
  final String body;
  final bool published, canEdit, canPublish;
  final int revision;
  factory WrittenMatchReport.fromJson(Map<String, dynamic> value) =>
      WrittenMatchReport(
        body: value['body'] as String? ?? '',
        published: value['published'] == true,
        revision: (value['revision'] as num? ?? 0).toInt(),
        canEdit: value['can_edit'] == true,
        canPublish: value['can_publish'] == true,
      );
}

class MatchRosterMember {
  const MatchRosterMember({
    required this.personId,
    required this.name,
    required this.sourceState,
  });
  final String personId, name, sourceState;
}

class MatchSnapshot {
  const MatchSnapshot({
    required this.eventId,
    required this.state,
    required this.revision,
    required this.rosterRevision,
    required this.scoreUs,
    required this.scoreOpponent,
    required this.cursor,
    required this.clock,
    required this.facts,
    this.roster = const [],
    this.people = const {},
    this.canManage = false,
    this.serverOffset = Duration.zero,
  });
  final String eventId, state, cursor;
  final int revision, rosterRevision, scoreUs, scoreOpponent;
  final Map<String, dynamic> clock;
  final List<Map<String, dynamic>> facts;

  /// The frozen match squad (from Deltagare), never a copy kept here.
  final List<MatchRosterMember> roster;

  /// Names of everyone referenced by a fact, including people who left a
  /// later roster revision.
  final Map<String, String> people;
  final bool canManage;

  /// Server clock minus device clock when the snapshot was read, so every
  /// leader's device shows the same match time.
  final Duration serverOffset;

  bool get isPaused => clock['paused_at'] != null;
  bool get isRunning => state == 'live' && !isPaused;

  Iterable<Map<String, dynamic>> get activeFacts =>
      facts.where((fact) => fact['state'] != 'voided');

  /// Paused because the current period was ended (rather than a pause
  /// within it), so resuming starts the next period.
  bool get currentPeriodEnded =>
      isPaused &&
      activeFacts.any(
        (fact) =>
            fact['fact_type'] == 'period_end' &&
            ((fact['detail'] as Map?)?['period'] as num?)?.toInt() ==
                currentPeriod,
      );

  Duration elapsedNow() => elapsedAt(DateTime.now().add(serverOffset));

  /// The playing minute ("58'") a fact registered now would get.
  int get currentMinute => state == 'planning' ? 0 : elapsedNow().inMinutes + 1;

  Duration elapsedAt(DateTime now) {
    final startedAt = DateTime.tryParse(clock['started_at'] as String? ?? '');
    if (startedAt == null) return Duration.zero;
    final stoppedAt = DateTime.tryParse(
      clock['completed_at'] as String? ?? clock['paused_at'] as String? ?? '',
    );
    final pausedSeconds = (clock['paused_seconds'] as num? ?? 0).toInt();
    var elapsed =
        (stoppedAt ?? now.toUtc()).difference(startedAt.toUtc()) -
        Duration(seconds: pausedSeconds);
    if (elapsed.isNegative) elapsed = Duration.zero;
    Map<dynamic, dynamic>? latestAnchor;
    for (final fact in facts) {
      if (fact['state'] == 'voided' || fact['fact_type'] != 'period_end') {
        continue;
      }
      final detail = fact['detail'];
      if (detail is Map) latestAnchor = detail;
    }
    final scheduled = (latestAnchor?['scheduled_minute'] as num?)?.toInt();
    final actual = (latestAnchor?['elapsed_seconds'] as num?)?.toInt();
    if (scheduled != null && actual != null) {
      final offset = scheduled * 60 - actual;
      if (offset > 0) elapsed += Duration(seconds: offset);
    }
    return elapsed;
  }

  List<int> get periodMinutes =>
      (clock['period_minutes'] as List? ?? const [45, 45])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList(growable: false);

  int get currentPeriod => (clock['current_period'] as num? ?? 1).toInt();

  factory MatchSnapshot.fromJson(Map<String, dynamic> json) {
    final projection = json['projection'];
    return MatchSnapshot(
      eventId: json['event_id'] as String,
      state: json['state'] as String? ?? 'planning',
      revision: (json['revision'] as num? ?? 0).toInt(),
      rosterRevision: (json['roster_revision'] as num? ?? 0).toInt(),
      scoreUs: projection is Map
          ? (projection['score_us'] as num? ?? 0).toInt()
          : 0,
      scoreOpponent: projection is Map
          ? (projection['score_opponent'] as num? ?? 0).toInt()
          : 0,
      cursor: json['cursor'] as String? ?? '0',
      clock: (json['clock'] as Map?)?.cast<String, dynamic>() ?? const {},
      facts: (json['facts'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      roster: (json['roster'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (member) => MatchRosterMember(
              personId: member['person_id'] as String,
              name: member['name'] as String? ?? '',
              sourceState: member['source_state'] as String? ?? 'accepted',
            ),
          )
          .toList(growable: false),
      people: {
        for (final entry in ((json['people'] as Map?) ?? const {}).entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
      },
      canManage: json['can_manage'] == true,
      serverOffset: switch (DateTime.tryParse(
        json['server_now'] as String? ?? '',
      )) {
        final DateTime serverNow => serverNow.difference(DateTime.now()),
        null => Duration.zero,
      },
    );
  }
}
