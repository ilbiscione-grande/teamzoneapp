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
  });
  final String eventId, state, cursor;
  final int revision, rosterRevision, scoreUs, scoreOpponent;
  final Map<String, dynamic> clock;
  final List<Map<String, dynamic>> facts;

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
    );
  }
}
