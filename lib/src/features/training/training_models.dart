/// The Training module (decision package 11, MFD-08): a training session
/// with its blocks in order.
library;

import 'package:teamzone_app/src/features/team_development/team_development_models.dart';

/// The part of the session a block is in, as the old app's sessions.
enum TrainingPart {
  warmup('Uppvärmning'),
  main('Huvuddel'),
  finish('Avslutning');

  const TrainingPart(this.label);
  final String label;

  static TrainingPart from(Object? value) => switch (value) {
    'warmup' => warmup,
    'finish' => finish,
    _ => main,
  };
}

enum TrainingPlayerTeam {
  blue('Blått lag'),
  red('Rött lag'),
  green('Grönt lag'),
  yellow('Gult lag'),
  neutral('Neutral');

  const TrainingPlayerTeam(this.label);
  final String label;
}

/// A roster reference plus display-name snapshot, or an unnamed player.
class TrainingBlockPlayer {
  const TrainingBlockPlayer({
    this.personId,
    this.rosterId,
    this.name = '',
    this.team = TrainingPlayerTeam.blue,
  });
  final String? personId, rosterId;
  String get id => rosterId ?? personId ?? '';
  final String name;
  final TrainingPlayerTeam team;
  factory TrainingBlockPlayer.fromJson(Map<String, dynamic> json) =>
      TrainingBlockPlayer(
        personId: json['person_id'] as String?,
        rosterId: json['roster_id'] as String?,
        name: json['name'] as String? ?? '',
        team:
            TrainingPlayerTeam.values
                .where((team) => team.name == json['team'])
                .firstOrNull ??
            TrainingPlayerTeam.blue,
      );
  Map<String, Object?> toJson() => {
    'person_id': personId,
    if (id.isNotEmpty) 'roster_id': id,
    'name': name,
    'team': team.name,
  };
  TrainingBlockPlayer withTeam(TrainingPlayerTeam value) => TrainingBlockPlayer(
    personId: personId,
    rosterId: rosterId,
    name: name,
    team: value,
  );
}

/// One exercise in the session.
class TrainingBlock {
  const TrainingBlock({
    required this.part,
    required this.title,
    this.minutes = 0,
    this.organisation = '',
    this.coachingPoints = '',
    this.phase,
    this.sourceKind = 'own',
    this.sourceId,
    this.players = const [],
  });
  factory TrainingBlock.fromJson(Map<String, dynamic> json) => TrainingBlock(
    part: TrainingPart.from(json['part']),
    title: json['title'] as String? ?? '',
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    organisation: json['organisation'] as String? ?? '',
    coachingPoints: json['coaching_points'] as String? ?? '',
    phase: json['phase'] == null ? null : PrincipleArea.from(json['phase']),
    sourceKind: json['source_kind'] as String? ?? 'own',
    sourceId: json['source_id'] as String?,
    players: [
      for (final player
          in (json['players'] as List? ?? const []).whereType<Map>())
        TrainingBlockPlayer.fromJson(Map<String, dynamic>.from(player)),
    ],
  );
  final TrainingPart part;
  final String title, organisation, coachingPoints, sourceKind;
  final int minutes;
  final List<TrainingBlockPlayer> players;

  /// The phase of the game the exercise trains, if any.
  final PrincipleArea? phase;
  final String? sourceId;

  Map<String, Object?> toJson() => {
    'part': part.name,
    'title': title,
    'minutes': minutes,
    'organisation': organisation,
    'coaching_points': coachingPoints,
    'phase': phase?.key,
    'source_kind': sourceKind,
    'source_id': sourceId,
    'players': [for (final player in players) player.toJson()],
  };

  TrainingBlock copyWith({
    TrainingPart? part,
    String? title,
    int? minutes,
    String? organisation,
    String? coachingPoints,
    PrincipleArea? phase,
    bool clearPhase = false,
    List<TrainingBlockPlayer>? players,
  }) => TrainingBlock(
    part: part ?? this.part,
    title: title ?? this.title,
    minutes: minutes ?? this.minutes,
    organisation: organisation ?? this.organisation,
    coachingPoints: coachingPoints ?? this.coachingPoints,
    phase: clearPhase ? null : phase ?? this.phase,
    sourceKind: sourceKind,
    sourceId: sourceId,
    players: players ?? this.players,
  );
}

/// A training's session: everything for those who prepare it, a published
/// one for the players. A new one (revision 0) starts from the event's own
/// theme and focus; [eventPlan] is the event's text plan to start from.
class TrainingSession {
  const TrainingSession({
    required this.eventId,
    required this.canEdit,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.revision,
    this.published = false,
    this.theme = '',
    this.goal = '',
    this.eventPlan,
    this.blocks = const [],
    this.updatedBy,
    this.roster = const [],
    this.rosterSaved = true,
  });
  factory TrainingSession.fromJson(Map<String, dynamic> json) =>
      TrainingSession(
        eventId: json['event_id'] as String,
        canEdit: json['can_edit'] == true,
        title: json['title'] as String? ?? '',
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        published: json['published'] == true,
        theme: json['theme'] as String? ?? '',
        goal: json['goal'] as String? ?? '',
        eventPlan: json['event_plan'] as String?,
        rosterSaved: json['roster_saved'] == true,
        roster: [
          for (final player
              in (json['roster'] as List? ?? const []).whereType<Map>())
            TrainingBlockPlayer.fromJson(Map<String, dynamic>.from(player)),
        ],
        updatedBy: json['updated_by'] as String?,
        blocks: [
          for (final row
              in (json['blocks'] as List? ?? const []).whereType<Map>())
            TrainingBlock.fromJson(Map<String, dynamic>.from(row)),
        ],
      );
  final String eventId, title, theme, goal;
  final bool canEdit, published;
  final DateTime startsAt, endsAt;
  final int revision;
  final String? eventPlan, updatedBy;
  final List<TrainingBlock> blocks;
  final List<TrainingBlockPlayer> roster;
  final bool rosterSaved;

  int get minutes => blocks.fold(0, (sum, block) => sum + block.minutes);
  int get eventMinutes => endsAt.difference(startsAt).inMinutes;
}

/// A training in the module's list, with how far its session is planned:
/// `none`, `draft` or `published`.
class ModuleTraining {
  const ModuleTraining({
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.state,
    required this.session,
    this.theme,
    this.minutes = 0,
    this.blocks = 0,
    this.evaluated = false,
    this.rating,
  });
  factory ModuleTraining.fromJson(Map<String, dynamic> json) => ModuleTraining(
    eventId: json['event_id'] as String,
    title: json['title'] as String? ?? '',
    startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
    state: json['state'] as String? ?? 'scheduled',
    session: json['session'] as String? ?? 'none',
    theme: json['theme'] as String?,
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    blocks: (json['blocks'] as num?)?.toInt() ?? 0,
    evaluated: json['evaluated'] == true,
    rating: (json['rating'] as num?)?.toInt(),
  );
  final String eventId, title, state, session;
  final String? theme;
  final DateTime startsAt, endsAt;
  final int minutes, blocks;
  final bool evaluated;
  final int? rating;
}

/// Whether the session's goal was reached.
enum GoalReached {
  yes('Ja'),
  partly('Delvis'),
  no('Nej');

  const GoalReached(this.label);
  final String label;

  static GoalReached? from(Object? value) =>
      values.where((item) => item.name == value).firstOrNull;
}

/// How an exercise went.
enum BlockRating {
  good('Bra'),
  fair('Okej'),
  poor('Mindre bra');

  const BlockRating(this.label);
  final String label;

  static BlockRating? from(Object? value) =>
      values.where((item) => item.name == value).firstOrNull;
}

/// One exercise in the evaluation, by its title in the session.
class EvaluatedBlock {
  const EvaluatedBlock({required this.title, this.rating, this.note = ''});
  factory EvaluatedBlock.fromJson(Map<String, dynamic> json) => EvaluatedBlock(
    title: json['title'] as String? ?? '',
    rating: BlockRating.from(json['rating']),
    note: json['note'] as String? ?? '',
  );
  final String title, note;
  final BlockRating? rating;

  Map<String, Object?> toJson() => {
    'title': title,
    'rating': rating?.name,
    'note': note,
  };
}

/// The leaders' evaluation after the session (decision package 11, step
/// 3), with the attendance against the callups. Revision 0 before it is
/// written.
class TrainingEvaluation {
  const TrainingEvaluation({
    required this.eventId,
    required this.canEdit,
    required this.started,
    required this.revision,
    this.rating,
    this.goalReached,
    this.wentWell = '',
    this.doDifferently = '',
    this.nextTime = '',
    this.blocks = const [],
    this.called = 0,
    this.accepted = 0,
    this.attended = 0,
    this.recorded = 0,
    this.updatedBy,
  });
  factory TrainingEvaluation.fromJson(Map<String, dynamic> json) {
    final attendance = Map<String, dynamic>.from(
      json['attendance'] as Map? ?? const {},
    );
    int count(String key) => (attendance[key] as num?)?.toInt() ?? 0;
    return TrainingEvaluation(
      eventId: json['event_id'] as String,
      canEdit: json['can_edit'] == true,
      started: json['started'] == true,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt(),
      goalReached: GoalReached.from(json['goal_reached']),
      wentWell: json['went_well'] as String? ?? '',
      doDifferently: json['do_differently'] as String? ?? '',
      nextTime: json['next_time'] as String? ?? '',
      blocks: [
        for (final row
            in (json['blocks'] as List? ?? const []).whereType<Map>())
          EvaluatedBlock.fromJson(Map<String, dynamic>.from(row)),
      ],
      called: count('called'),
      accepted: count('accepted'),
      attended: count('attended'),
      recorded: count('recorded'),
      updatedBy: json['updated_by'] as String?,
    );
  }
  final String eventId, wentWell, doDifferently, nextTime;
  final bool canEdit, started;
  final int revision, called, accepted, attended, recorded;
  final int? rating;
  final GoalReached? goalReached;
  final List<EvaluatedBlock> blocks;
  final String? updatedBy;

  bool get written => revision > 0;
}
