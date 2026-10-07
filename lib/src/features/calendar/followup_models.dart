// Event KPIs and the follow-up tab (see api.get_event_followup).

double? _number(Object? value) => value is num ? value.toDouble() : null;

/// A KPI that can be set as a goal for an event (built-in catalog).
class KpiCatalogEntry {
  const KpiCatalogEntry({
    required this.key,
    required this.label,
    required this.valueType,
    required this.direction,
    required this.source,
  });
  final String key, label, valueType, direction, source;

  /// Counted by TeamZone (attendance, answers, result) rather than entered.
  bool get isAutomatic => source == 'auto';

  factory KpiCatalogEntry.fromJson(Map<String, dynamic> json) =>
      KpiCatalogEntry(
        key: json['key'] as String,
        label: json['label'] as String,
        valueType: json['value_type'] as String,
        direction: json['direction'] as String,
        source: json['source'] as String,
      );
}

class KpiTrendPoint {
  const KpiTrendPoint({
    required this.eventId,
    required this.startsAt,
    required this.current,
    this.actual,
    this.target,
  });
  final String eventId;
  final DateTime startsAt;
  final bool current;
  final double? actual, target;

  factory KpiTrendPoint.fromJson(Map<String, dynamic> json) => KpiTrendPoint(
    eventId: json['event_id'] as String,
    startsAt: DateTime.parse(json['starts_at'] as String),
    current: json['current'] as bool? ?? false,
    actual: _number(json['actual'] ?? json['attendance_rate']),
    target: _number(json['target']),
  );
}

/// A KPI goal on an event, with its actual value and outcome.
class EventKpi {
  const EventKpi({
    required this.id,
    required this.kpiKey,
    required this.label,
    required this.valueType,
    required this.direction,
    required this.source,
    required this.comparator,
    required this.target,
    required this.visibleToPlayers,
    required this.revision,
    required this.status,
    this.actual,
    this.trend = const [],
  });
  final String id, kpiKey, label, valueType, direction, source, comparator;
  final double target;
  final double? actual;
  final bool visibleToPlayers;
  final int revision;

  /// achieved, missed, missing (ended without value) or pending.
  final String status;
  final List<KpiTrendPoint> trend;

  bool get isManual => source == 'manual';

  factory EventKpi.fromJson(Map<String, dynamic> json) => EventKpi(
    id: json['id'] as String,
    kpiKey: json['kpi_key'] as String,
    label: json['label'] as String,
    valueType: json['value_type'] as String,
    direction: json['direction'] as String,
    source: json['source'] as String,
    comparator: json['comparator'] as String,
    target: _number(json['target']) ?? 0,
    actual: _number(json['actual']),
    visibleToPlayers: json['visible_to_players'] as bool? ?? false,
    revision: (json['revision'] as num?)?.toInt() ?? 1,
    status: json['status'] as String? ?? 'pending',
    trend: [
      for (final point in json['trend'] as List? ?? const [])
        if (point is Map)
          KpiTrendPoint.fromJson(Map<String, dynamic>.from(point)),
    ],
  );
}

class AttendanceSummary {
  const AttendanceSummary({
    this.called = 0,
    this.accepted = 0,
    this.declined = 0,
    this.pending = 0,
    this.present = 0,
    this.late = 0,
    this.partial = 0,
    this.absent = 0,
    this.registered = 0,
    this.unregistered = 0,
    this.lateMinutesAverage,
    this.attendanceRate,
    this.responseRate,
  });
  final int called, accepted, declined, pending;
  final int present, late, partial, absent, registered, unregistered;
  final double? lateMinutesAverage, attendanceRate, responseRate;

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AttendanceSummary(
      called: count('called'),
      accepted: count('accepted'),
      declined: count('declined'),
      pending: count('pending'),
      present: count('present'),
      late: count('late'),
      partial: count('partial'),
      absent: count('absent'),
      registered: count('registered'),
      unregistered: count('unregistered'),
      lateMinutesAverage: _number(json['late_minutes_avg']),
      attendanceRate: _number(json['attendance_rate']),
      responseRate: _number(json['response_rate']),
    );
  }
}

class FollowupTodo {
  const FollowupTodo({required this.kind, required this.count});

  /// attendance, kpi_values, match_result or match_report.
  final String kind;
  final int count;
}

class EventFollowup {
  const EventFollowup({
    required this.eventId,
    required this.eventType,
    required this.ended,
    required this.isLeader,
    required this.canEditTargets,
    required this.canRecordValues,
    required this.summary,
    required this.kpis,
    this.teamAverageAttendance,
    this.declineReasons = const {},
    this.attendanceTrend = const [],
    this.todos = const [],
  });
  final String eventId, eventType;
  final bool ended, isLeader, canEditTargets, canRecordValues;
  final AttendanceSummary summary;
  final double? teamAverageAttendance;
  final Map<String, int> declineReasons;
  final List<KpiTrendPoint> attendanceTrend;
  final List<EventKpi> kpis;
  final List<FollowupTodo> todos;

  factory EventFollowup.fromJson(Map<String, dynamic> json) => EventFollowup(
    eventId: json['event_id'] as String,
    eventType: json['event_type'] as String? ?? 'activity',
    ended: json['ended'] as bool? ?? false,
    isLeader: json['is_leader'] as bool? ?? false,
    canEditTargets: json['can_edit_targets'] as bool? ?? false,
    canRecordValues: json['can_record_values'] as bool? ?? false,
    summary: AttendanceSummary.fromJson(
      Map<String, dynamic>.from(json['summary'] as Map? ?? const {}),
    ),
    teamAverageAttendance: _number(json['team_average_attendance']),
    declineReasons: {
      for (final reason in json['decline_reasons'] as List? ?? const [])
        if (reason is Map)
          reason['code'] as String: (reason['count'] as num).toInt(),
    },
    attendanceTrend: [
      for (final point in json['attendance_trend'] as List? ?? const [])
        if (point is Map)
          KpiTrendPoint.fromJson(Map<String, dynamic>.from(point)),
    ],
    kpis: [
      for (final kpi in json['kpis'] as List? ?? const [])
        if (kpi is Map) EventKpi.fromJson(Map<String, dynamic>.from(kpi)),
    ],
    todos: [
      for (final todo in json['todos'] as List? ?? const [])
        if (todo is Map)
          FollowupTodo(
            kind: todo['kind'] as String,
            count: (todo['count'] as num?)?.toInt() ?? 1,
          ),
    ],
  );
}
