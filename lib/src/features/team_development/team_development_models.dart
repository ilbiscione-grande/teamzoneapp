/// Team Development Plan (decision package 11, MFD-10): the team's plan for
/// a season, its periods and its goals.
library;

DateTime _date(Object? value) => DateTime.parse(value as String);

/// A period's phase of the season.
enum PeriodPhase {
  preseason('Försäsong'),
  competition('Tävling'),
  breakTime('Uppehåll'),
  other('Annan');

  const PeriodPhase(this.label);
  final String label;

  String get key => this == breakTime ? 'break' : name;

  static PeriodPhase from(Object? value) => switch (value) {
    'preseason' => preseason,
    'competition' => competition,
    'break' => breakTime,
    _ => other,
  };
}

/// Where a goal belongs: the whole season, one period, or the short term
/// up to a date (before a match or a block of trainings).
enum GoalHorizon {
  season('Säsongsmål'),
  period('Periodens mål'),
  short('Kortsiktigt mål');

  const GoalHorizon(this.label);
  final String label;

  static GoalHorizon from(Object? value) => switch (value) {
    'period' => period,
    'short' => short,
    _ => season,
  };
}

enum GoalState {
  open('Pågår'),
  achieved('Uppnått'),
  dropped('Släppt');

  const GoalState(this.label);
  final String label;

  static GoalState from(Object? value) => switch (value) {
    'achieved' => achieved,
    'dropped' => dropped,
    _ => open,
  };
}

class DevelopmentPeriod {
  const DevelopmentPeriod({
    required this.id,
    required this.name,
    required this.phase,
    required this.startsOn,
    required this.endsOn,
    this.focus = '',
  });
  factory DevelopmentPeriod.fromJson(Map<String, dynamic> json) =>
      DevelopmentPeriod(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        phase: PeriodPhase.from(json['phase']),
        startsOn: _date(json['starts_on']),
        endsOn: _date(json['ends_on']),
        focus: json['focus'] as String? ?? '',
      );
  final String id, name, focus;
  final PeriodPhase phase;
  final DateTime startsOn, endsOn;

  bool contains(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return !date.isBefore(startsOn) && !date.isAfter(endsOn);
  }
}

class TeamGoal {
  const TeamGoal({
    required this.id,
    required this.horizon,
    required this.title,
    this.periodId,
    this.description = '',
    this.targetOn,
    this.state = GoalState.open,
    this.updatedAt,
    this.updatedBy,
  });
  factory TeamGoal.fromJson(Map<String, dynamic> json) => TeamGoal(
    id: json['id'] as String,
    horizon: GoalHorizon.from(json['horizon']),
    periodId: json['period_id'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    targetOn: json['target_on'] == null ? null : _date(json['target_on']),
    state: GoalState.from(json['state']),
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    updatedBy: json['updated_by'] as String?,
  );
  final String id, title, description;
  final GoalHorizon horizon;
  final String? periodId, updatedBy;
  final DateTime? targetOn, updatedAt;
  final GoalState state;
}

/// One season's plan with its periods (in date order) and goals.
class SeasonPlan {
  const SeasonPlan({
    required this.id,
    required this.title,
    required this.startsOn,
    required this.endsOn,
    required this.revision,
    this.vision = '',
    this.periods = const [],
    this.goals = const [],
    this.principles = const [],
    this.kpis = const [],
    this.checkins = const [],
    this.checkinEveryDays,
    this.updatedAt,
    this.updatedBy,
  });
  factory SeasonPlan.fromJson(Map<String, dynamic> json) => SeasonPlan(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    vision: json['vision'] as String? ?? '',
    startsOn: _date(json['starts_on']),
    endsOn: _date(json['ends_on']),
    revision: (json['revision'] as num?)?.toInt() ?? 0,
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    updatedBy: json['updated_by'] as String?,
    periods: [
      for (final row in (json['periods'] as List? ?? const []).whereType<Map>())
        DevelopmentPeriod.fromJson(Map<String, dynamic>.from(row)),
    ],
    goals: [
      for (final row in (json['goals'] as List? ?? const []).whereType<Map>())
        TeamGoal.fromJson(Map<String, dynamic>.from(row)),
    ],
    principles: [
      for (final row
          in (json['principles'] as List? ?? const []).whereType<Map>())
        TeamPrinciple.fromJson(Map<String, dynamic>.from(row)),
    ],
    kpis: [
      for (final row in (json['kpis'] as List? ?? const []).whereType<Map>())
        TeamKpi.fromJson(Map<String, dynamic>.from(row)),
    ],
    checkins: [
      for (final row
          in (json['checkins'] as List? ?? const []).whereType<Map>())
        TeamCheckin.fromJson(Map<String, dynamic>.from(row)),
    ],
    checkinEveryDays: (json['checkin_every_days'] as num?)?.toInt(),
  );
  final String id, title, vision;
  final DateTime startsOn, endsOn;
  final int revision;
  final DateTime? updatedAt;
  final String? updatedBy;
  final List<DevelopmentPeriod> periods;
  final List<TeamGoal> goals;
  final List<TeamPrinciple> principles;
  final List<TeamKpi> kpis;

  /// Newest first.
  final List<TeamCheckin> checkins;

  /// How often the goals are checked; null: never.
  final int? checkinEveryDays;

  List<TeamCheckin> checkinsOfGoal(String goalId) => [
    for (final checkin in checkins)
      if (checkin.goalId == goalId) checkin,
  ];

  List<TeamCheckin> checkinsOfKpi(String kpiId) => [
    for (final checkin in checkins)
      if (checkin.kpiId == kpiId) checkin,
  ];

  /// The goals to check now, as the assistant counts them: open, of the
  /// season, today's period or the short term ahead, last checked (or
  /// changed) an interval ago.
  List<TeamGoal> goalsDue(DateTime day) {
    final every = checkinEveryDays;
    if (every == null) return const [];
    final today = DateTime(day.year, day.month, day.day);
    final period = periodOn(today);
    return [
      for (final goal in goals)
        if (goal.state == GoalState.open &&
            switch (goal.horizon) {
              GoalHorizon.season => true,
              GoalHorizon.period => goal.periodId == period?.id,
              GoalHorizon.short => !goal.targetOn!.isBefore(today),
            } &&
            !(checkinsOfGoal(goal.id).firstOrNull?.checkedOn ??
                    goal.updatedAt ??
                    today)
                .isAfter(today.subtract(Duration(days: every))))
          goal,
    ];
  }

  DevelopmentPeriod? periodOn(DateTime day) =>
      periods.where((period) => period.contains(day)).firstOrNull;

  /// The period now, else the next one, else none.
  DevelopmentPeriod? currentOrNext(DateTime day) =>
      periodOn(day) ??
      periods.where((period) => period.startsOn.isAfter(day)).firstOrNull;

  List<TeamGoal> goalsOf(GoalHorizon horizon, {String? periodId}) => [
    for (final goal in goals)
      if (goal.horizon == horizon &&
          (periodId == null || goal.periodId == periodId))
        goal,
  ];
}

class SeasonSummary {
  const SeasonSummary({
    required this.id,
    required this.title,
    required this.startsOn,
    required this.endsOn,
  });
  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    startsOn: _date(json['starts_on']),
    endsOn: _date(json['ends_on']),
  );
  final String id, title;
  final DateTime startsOn, endsOn;
}

/// The team's seasons and the plan shown: today's season, the next, or
/// the latest; null before the first season.
class TeamDevelopment {
  const TeamDevelopment({
    required this.canEdit,
    this.seasons = const [],
    this.plan,
  });
  factory TeamDevelopment.fromJson(Map<String, dynamic> json) =>
      TeamDevelopment(
        canEdit: json['can_edit'] == true,
        seasons: [
          for (final row
              in (json['seasons'] as List? ?? const []).whereType<Map>())
            SeasonSummary.fromJson(Map<String, dynamic>.from(row)),
        ],
        plan: json['plan'] is Map
            ? SeasonPlan.fromJson(Map<String, dynamic>.from(json['plan']))
            : null,
      );
  final bool canEdit;
  final List<SeasonSummary> seasons;
  final SeasonPlan? plan;
}

/// The area of the game a principle is about.
enum PrincipleArea {
  attack('Anfall'),
  defence('Försvar'),
  transitionAttack('Omställning till anfall'),
  transitionDefence('Omställning till försvar'),
  setPieces('Fasta situationer'),
  general('Allmänt');

  const PrincipleArea(this.label);
  final String label;

  String get key => switch (this) {
    transitionAttack => 'transition_attack',
    transitionDefence => 'transition_defence',
    setPieces => 'set_pieces',
    _ => name,
  };

  static PrincipleArea from(Object? value) =>
      values.where((area) => area.key == value).firstOrNull ?? general;
}

class TeamPrinciple {
  const TeamPrinciple({
    required this.id,
    required this.area,
    required this.title,
    this.description = '',
  });
  factory TeamPrinciple.fromJson(Map<String, dynamic> json) => TeamPrinciple(
    id: json['id'] as String,
    area: PrincipleArea.from(json['area']),
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );
  final String id, title, description;
  final PrincipleArea area;
}

/// A key figure of the team, as shots per match, with its target.
class TeamKpi {
  const TeamKpi({
    required this.id,
    required this.title,
    this.unit = '',
    this.target,
    this.higherIsBetter = true,
  });
  factory TeamKpi.fromJson(Map<String, dynamic> json) => TeamKpi(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    target: (json['target'] as num?)?.toDouble(),
    higherIsBetter: json['higher_is_better'] != false,
  );
  final String id, title, unit;
  final double? target;
  final bool higherIsBetter;

  /// Whether [value] reaches the target; null without a target.
  bool? reaches(double value) => target == null
      ? null
      : higherIsBetter
      ? value >= target!
      : value <= target!;
}

/// How a goal is going at a check-in.
enum CheckinStatus {
  onTrack('På väg'),
  atRisk('I farozonen'),
  offTrack('Inte på väg');

  const CheckinStatus(this.label);
  final String label;

  String get key => switch (this) {
    onTrack => 'on_track',
    atRisk => 'at_risk',
    offTrack => 'off_track',
  };

  static CheckinStatus? from(Object? value) =>
      values.where((status) => status.key == value).firstOrNull;
}

/// A check-in on a goal (its status) or a key figure (its value).
class TeamCheckin {
  const TeamCheckin({
    required this.id,
    required this.checkedOn,
    this.goalId,
    this.kpiId,
    this.status,
    this.value,
    this.note = '',
    this.createdBy,
  });
  factory TeamCheckin.fromJson(Map<String, dynamic> json) => TeamCheckin(
    id: json['id'] as String,
    goalId: json['goal_id'] as String?,
    kpiId: json['kpi_id'] as String?,
    checkedOn: _date(json['checked_on']),
    status: CheckinStatus.from(json['status']),
    value: (json['value'] as num?)?.toDouble(),
    note: json['note'] as String? ?? '',
    createdBy: json['created_by'] as String?,
  );
  final String id, note;
  final String? goalId, kpiId, createdBy;
  final DateTime checkedOn;
  final CheckinStatus? status;
  final double? value;
}
