/// Team Development Plan (decision package 11, MFD-10): the team's plan for
/// a season, its periods and its goals.
library;

part 'team_development_match_values.dart';
part 'team_development_exercises.dart';

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

/// Where a goal belongs: the whole season (long-term), one period or one
/// block (short-term), or the short term up to a date (the earlier kind).
enum GoalHorizon {
  season('Säsongsmål'),
  period('Periodens mål'),
  block('Blockets mål'),
  short('Kortsiktigt mål');

  const GoalHorizon(this.label);
  final String label;

  static GoalHorizon from(Object? value) => switch (value) {
    'period' => period,
    'block' => block,
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

/// A few weeks of a period with their own focus, principles and goals; the
/// starting point when a training in it is prepared.
class DevelopmentBlock {
  const DevelopmentBlock({
    required this.id,
    required this.periodId,
    required this.name,
    required this.startsOn,
    required this.endsOn,
    this.focus = '',
    this.principleIds = const [],
  });
  factory DevelopmentBlock.fromJson(Map<String, dynamic> json) =>
      DevelopmentBlock(
        id: json['id'] as String,
        periodId: json['period_id'] as String,
        name: json['name'] as String? ?? '',
        startsOn: _date(json['starts_on']),
        endsOn: _date(json['ends_on']),
        focus: json['focus'] as String? ?? '',
        principleIds: [
          for (final row
              in (json['principles'] as List? ?? const []).whereType<Map>())
            row['id'] as String,
        ],
      );
  final String id, periodId, name, focus;
  final DateTime startsOn, endsOn;

  /// The plan's principles in focus, in the order chosen.
  final List<String> principleIds;

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
    this.blockId,
    this.description = '',
    this.targetOn,
    this.state = GoalState.open,
    this.updatedAt,
    this.updatedBy,
    this.links = const [],
  });
  factory TeamGoal.fromJson(Map<String, dynamic> json) => TeamGoal(
    id: json['id'] as String,
    horizon: GoalHorizon.from(json['horizon']),
    periodId: json['period_id'] as String?,
    blockId: json['block_id'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    targetOn: json['target_on'] == null ? null : _date(json['target_on']),
    state: GoalState.from(json['state']),
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    updatedBy: json['updated_by'] as String?,
    links: [
      for (final row in (json['links'] as List? ?? const []).whereType<Map>())
        GoalLink.fromJson(Map<String, dynamic>.from(row)),
    ],
  );
  final String id, title, description;
  final GoalHorizon horizon;
  final String? periodId, blockId, updatedBy;
  final DateTime? targetOn, updatedAt;
  final GoalState state;
  final List<GoalLink> links;
}

/// A link on a goal (a video, an exercise), shown to the players or not.
class GoalLink {
  const GoalLink({
    required this.id,
    required this.title,
    required this.url,
    this.visible = false,
  });
  factory GoalLink.fromJson(Map<String, dynamic> json) => GoalLink(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    visible: json['visible'] == true,
  );
  final String id, title, url;
  final bool visible;
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
    this.blocks = const [],
    this.goals = const [],
    this.principles = const [],
    this.kpis = const [],
    this.checkins = const [],
    this.checkinEveryDays,
    this.sharing = const PlanSharing(),
    this.updatedAt,
    this.updatedBy,
    this.matches = const [],
    this.matchButtons = const [],
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
    blocks: [
      for (final row in (json['blocks'] as List? ?? const []).whereType<Map>())
        DevelopmentBlock.fromJson(Map<String, dynamic>.from(row)),
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
    sharing: PlanSharing.fromJson(
      Map<String, dynamic>.from(json['sharing'] as Map? ?? const {}),
    ),
    matches: [
      for (final row in (json['matches'] as List? ?? const []).whereType<Map>())
        PlanMatch.fromJson(Map<String, dynamic>.from(row)),
    ],
    matchButtons: [
      for (final row
          in (json['match_buttons'] as List? ?? const []).whereType<Map>())
        (id: row['id'] as String? ?? '', label: row['label'] as String? ?? ''),
    ],
  );
  final String id, title, vision;
  final DateTime startsOn, endsOn;
  final int revision;
  final DateTime? updatedAt;
  final String? updatedBy;
  final List<DevelopmentPeriod> periods;

  /// In date order.
  final List<DevelopmentBlock> blocks;
  final List<TeamGoal> goals;
  final List<TeamPrinciple> principles;
  final List<TeamKpi> kpis;

  /// Newest first.
  final List<TeamCheckin> checkins;

  /// The earlier interval between check-ins; no longer what makes goals
  /// due (see [goalsDue]).
  final int? checkinEveryDays;

  /// What the team's players and guardians see.
  final PlanSharing sharing;

  /// The season's played matches, oldest first, with what they add up to.
  final List<PlanMatch> matches;

  /// The team's own Live buttons, which a key figure can count.
  final List<({String id, String label})> matchButtons;

  /// A key figure's values, newest first: with a source, one per played
  /// match (the counted value, or the one set by hand for the match), and
  /// the values added by hand.
  List<KpiValue> valuesOfKpi(TeamKpi kpi) {
    final source = kpi.source;
    final own = checkinsOfKpi(kpi.id);
    if (source == null) {
      return [for (final checkin in own) KpiValue.of(checkin)];
    }
    return [
      for (final match in matches)
        if (own.where((c) => c.eventId == match.eventId).firstOrNull
            case final set?)
          KpiValue.of(set, match: match)
        else if (match.valueOf(source) case final counted?)
          KpiValue(
            on: match.playedOn,
            value: counted,
            match: match,
            counted: true,
          ),
      for (final checkin in own)
        if (checkin.eventId == null) KpiValue.of(checkin),
    ]..sort((a, b) => b.on.compareTo(a.on));
  }

  List<TeamCheckin> checkinsOfGoal(String goalId) => [
    for (final checkin in checkins)
      if (checkin.goalId == goalId) checkin,
  ];

  List<TeamCheckin> checkinsOfKpi(String kpiId) => [
    for (final checkin in checkins)
      if (checkin.kpiId == kpiId) checkin,
  ];

  /// When what [goal] belongs to ends: its block, its period, the season,
  /// or its date.
  DateTime? goalEnds(TeamGoal goal) => switch (goal.horizon) {
    GoalHorizon.season => endsOn,
    GoalHorizon.period =>
      periods.where((period) => period.id == goal.periodId).firstOrNull?.endsOn,
    GoalHorizon.block =>
      blocks.where((block) => block.id == goal.blockId).firstOrNull?.endsOn,
    GoalHorizon.short => goal.targetOn,
  };

  /// The goals to check now, as the assistant counts them: open, what they
  /// belong to ended within four weeks, and not checked from a week before
  /// that end.
  List<TeamGoal> goalsDue(DateTime day) {
    final today = DateTime(day.year, day.month, day.day);
    return [
      for (final goal in goals)
        if (goal.state == GoalState.open)
          if (goalEnds(goal) case final ended?)
            if (!ended.isAfter(today) &&
                !ended.isBefore(today.subtract(const Duration(days: 28))) &&
                !checkinsOfGoal(goal.id).any(
                  (checkin) => !checkin.checkedOn.isBefore(
                    ended.subtract(const Duration(days: 7)),
                  ),
                ))
              goal,
    ];
  }

  DevelopmentPeriod? periodOn(DateTime day) =>
      periods.where((period) => period.contains(day)).firstOrNull;

  DevelopmentBlock? blockOn(DateTime day) =>
      blocks.where((block) => block.contains(day)).firstOrNull;

  List<DevelopmentBlock> blocksOf(String periodId) => [
    for (final block in blocks)
      if (block.periodId == periodId) block,
  ];

  /// The period now, else the next one, else none.
  DevelopmentPeriod? currentOrNext(DateTime day) =>
      periodOn(day) ??
      periods.where((period) => period.startsOn.isAfter(day)).firstOrNull;

  List<TeamGoal> goalsOf(
    GoalHorizon horizon, {
    String? periodId,
    String? blockId,
  }) => [
    for (final goal in goals)
      if (goal.horizon == horizon &&
          (periodId == null || goal.periodId == periodId) &&
          (blockId == null || goal.blockId == blockId))
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

/// The phase of the game a principle is about, as the Swedish FA names
/// them: four with the ball, each with its opposite without it.
enum PrincipleArea {
  scoring('scoring', 'Komma till avslut och göra mål', true),
  buildUp('build_up', 'Speluppbyggnad', true),
  counter('counter', 'Kontring/omställning', true),
  attackingPlay('attacking_play', 'Anfallsspel', true),
  preventingScoring('preventing_scoring', 'Förhindra och rädda avslut', false),
  preventingBuildUp('preventing_build_up', 'Förhindra speluppbyggnad', false),
  regaining('regaining', 'Återerövring av boll', false),
  defending('defending', 'Försvarsspel', false);

  const PrincipleArea(this.key, this.label, this.withBall);
  final String key, label;
  final bool withBall;

  /// The same phase from the other side: with the ball and without it.
  PrincipleArea get opposite => switch (this) {
    scoring => preventingScoring,
    buildUp => preventingBuildUp,
    counter => regaining,
    attackingPlay => defending,
    preventingScoring => scoring,
    preventingBuildUp => buildUp,
    regaining => counter,
    defending => attackingPlay,
  };

  /// The four pairs, the phase with the ball first.
  static const pairs = [
    (scoring, preventingScoring),
    (buildUp, preventingBuildUp),
    (counter, regaining),
    (attackingPlay, defending),
  ];

  static PrincipleArea from(Object? value) =>
      values.where((area) => area.key == value).firstOrNull ?? attackingPlay;
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
    this.source,
  });
  factory TeamKpi.fromJson(Map<String, dynamic> json) => TeamKpi(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    target: (json['target'] as num?)?.toDouble(),
    higherIsBetter: json['higher_is_better'] != false,
    source: json['source'] as String?,
  );
  final String id, title, unit;
  final double? target;
  final bool higherIsBetter;

  /// What the matches count for it ([kpiSources], or `button:<id>`); null
  /// when its values are added by hand.
  final String? source;

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
    this.eventId,
  });
  factory TeamCheckin.fromJson(Map<String, dynamic> json) => TeamCheckin(
    id: json['id'] as String,
    goalId: json['goal_id'] as String?,
    kpiId: json['kpi_id'] as String?,
    eventId: json['event_id'] as String?,
    checkedOn: _date(json['checked_on']),
    status: CheckinStatus.from(json['status']),
    value: (json['value'] as num?)?.toDouble(),
    note: json['note'] as String? ?? '',
    createdBy: json['created_by'] as String?,
  );
  final String id, note;
  final String? goalId, kpiId, createdBy;

  /// The match a key figure's value was set for by hand.
  final String? eventId;
  final DateTime checkedOn;
  final CheckinStatus? status;
  final double? value;
}

/// The parts of the plan the team's players and guardians see.
class PlanSharing {
  const PlanSharing({
    this.vision = false,
    this.periods = false,
    this.principles = false,
    this.goals = false,
    this.blocks = false,
  });
  factory PlanSharing.fromJson(Map<String, dynamic> json) => PlanSharing(
    vision: json['vision'] == true,
    periods: json['periods'] == true,
    principles: json['principles'] == true,
    goals: json['goals'] == true,
    blocks: json['blocks'] == true,
  );
  final bool vision, periods, principles, goals, blocks;

  bool get any => vision || periods || principles || goals || blocks;

  PlanSharing copyWith({
    bool? vision,
    bool? periods,
    bool? principles,
    bool? goals,
    bool? blocks,
  }) => PlanSharing(
    vision: vision ?? this.vision,
    periods: periods ?? this.periods,
    principles: principles ?? this.principles,
    goals: goals ?? this.goals,
    blocks: blocks ?? this.blocks,
  );
}

/// What the players and guardians see of the season now (or next): only
/// the shared parts; a part not shared is null.
class SharedTeamPlan {
  const SharedTeamPlan({
    required this.title,
    required this.startsOn,
    required this.endsOn,
    this.vision,
    this.periods,
    this.blocks,
    this.principles,
    this.goals,
  });
  factory SharedTeamPlan.fromJson(Map<String, dynamic> json) {
    List<T>? list<T>(String key, T Function(Map<String, dynamic>) read) =>
        json[key] is List
        ? [
            for (final row in (json[key] as List).whereType<Map>())
              read(Map<String, dynamic>.from(row)),
          ]
        : null;
    return SharedTeamPlan(
      title: json['title'] as String? ?? '',
      startsOn: _date(json['starts_on']),
      endsOn: _date(json['ends_on']),
      vision: json['vision'] as String?,
      periods: list('periods', DevelopmentPeriod.fromJson),
      blocks: list('blocks', DevelopmentBlock.fromJson),
      principles: list('principles', TeamPrinciple.fromJson),
      goals: list('goals', TeamGoal.fromJson),
    );
  }
  final String title;
  final DateTime startsOn, endsOn;
  final String? vision;
  final List<DevelopmentPeriod>? periods;
  final List<DevelopmentBlock>? blocks;
  final List<TeamPrinciple>? principles;
  final List<TeamGoal>? goals;
}

/// What the team's plan says for an event's day, to prepare it with: the
/// block's and period's focus, the principles and the goals ahead. A
/// suggestion only.
class TeamPlanSuggestion {
  const TeamPlanSuggestion({
    required this.planTitle,
    this.periodName,
    this.periodFocus = '',
    this.blockName,
    this.blockFocus = '',
    this.blockPrinciples = const [],
    this.principles = const [],
    this.goals = const [],
    this.exercises = const BlockExercises(),
  });
  factory TeamPlanSuggestion.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? part(String key) =>
        json[key] is Map ? Map<String, dynamic>.from(json[key] as Map) : null;
    List<({PrincipleArea area, String title})> principles(Object? rows) => [
      for (final row in (rows as List? ?? const []).whereType<Map>())
        (
          area: PrincipleArea.from(row['area']),
          title: row['title'] as String? ?? '',
        ),
    ];
    final period = part('period'), block = part('block');
    return TeamPlanSuggestion(
      planTitle: json['plan_title'] as String? ?? '',
      periodName: period?['name'] as String?,
      periodFocus: period?['focus'] as String? ?? '',
      blockName: block?['name'] as String?,
      blockFocus: block?['focus'] as String? ?? '',
      blockPrinciples: principles(block?['principles']),
      principles: principles(json['principles']),
      goals: [
        for (final row in (json['goals'] as List? ?? const []).whereType<Map>())
          row['title'] as String? ?? '',
      ],
      exercises: BlockExercises.fromJson(json['exercises']),
    );
  }
  final String planTitle, periodFocus, blockFocus;

  /// The day's block's exercises, to take into the session.
  final BlockExercises exercises;
  final String? periodName, blockName;

  /// The principles in focus in the day's block, and all the plan's.
  final List<({PrincipleArea area, String title})> blockPrinciples, principles;

  /// The block's goals first, then the period's and the dated ones ahead.
  final List<String> goals;

  bool get isEmpty =>
      blockName == null &&
      periodFocus.trim().isEmpty &&
      principles.isEmpty &&
      goals.isEmpty;
}

/// The suggestion from the team's plan for an event's preparation, read by
/// the services that prepare events (training and match).
abstract interface class TeamPlanSuggestionServices {
  /// Null without the module, a plan for the day, or the right to prepare.
  Future<TeamPlanSuggestion?> teamPlanSuggestion(String eventId);
}
