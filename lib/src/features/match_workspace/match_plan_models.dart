/// One part of the match plan (tactics, set pieces, the opponent) and
/// whether the players see it once the plan is published.
class MatchPlanSection {
  const MatchPlanSection({this.text = '', this.visible = true});
  factory MatchPlanSection.fromJson(Map<String, dynamic> json) =>
      MatchPlanSection(
        text: json['text'] as String? ?? '',
        visible: json['visible'] != false,
      );
  final String text;
  final bool visible;
}

/// A link on the match plan: a video, a scouting page, a document.
class MatchPlanLink {
  const MatchPlanLink({
    required this.id,
    required this.title,
    required this.url,
    required this.visible,
  });
  factory MatchPlanLink.fromJson(Map<String, dynamic> json) => MatchPlanLink(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    visible: json['visible'] == true,
  );
  final String id, title, url;
  final bool visible;
}

/// The Match module's plan for one match (decision package 11, MFD-05). For
/// those who edit it everything; for players the shown parts of a published
/// plan, a missing part being null.
class MatchPlan {
  const MatchPlan({
    required this.eventId,
    required this.canEdit,
    required this.published,
    required this.revision,
    this.opponentName,
    this.homeAway,
    this.startsAt,
    this.tactics,
    this.setPieces,
    this.opponent,
    this.links = const [],
  });

  factory MatchPlan.fromJson(Map<String, dynamic> json) {
    final sections = Map<String, dynamic>.from(
      json['sections'] as Map? ?? const {},
    );
    MatchPlanSection? section(String key) => sections[key] is Map
        ? MatchPlanSection.fromJson(Map<String, dynamic>.from(sections[key]))
        : null;
    return MatchPlan(
      eventId: json['event_id'] as String? ?? '',
      canEdit: json['can_edit'] == true,
      published: json['published'] == true,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      opponentName: json['opponent_name'] as String?,
      homeAway: json['home_away'] as String?,
      startsAt: DateTime.tryParse(
        json['starts_at'] as String? ?? '',
      )?.toLocal(),
      tactics: section('tactics'),
      setPieces: section('set_pieces'),
      opponent: section('opponent'),
      links: [
        for (final row in (json['links'] as List? ?? const []).whereType<Map>())
          MatchPlanLink.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }

  final String eventId;
  final bool canEdit, published;
  final int revision;
  final String? opponentName, homeAway;
  final DateTime? startsAt;
  final MatchPlanSection? tactics, setPieces, opponent;
  final List<MatchPlanLink> links;

  /// Nothing written and no links: a player sees nothing worth a card.
  bool get isEmpty =>
      [
        tactics,
        setPieces,
        opponent,
      ].every((section) => section == null || section.text.trim().isEmpty) &&
      links.isEmpty;
}

/// A match in the module's list, with how far it is prepared:
/// `none`, `draft` or `published` for the plan and the line-up.
class ModuleMatch {
  const ModuleMatch({
    required this.eventId,
    required this.title,
    required this.startsAt,
    required this.state,
    required this.plan,
    required this.lineup,
    this.opponentName,
    this.homeAway,
  });
  factory ModuleMatch.fromJson(Map<String, dynamic> json) => ModuleMatch(
    eventId: json['event_id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    startsAt:
        DateTime.tryParse(json['starts_at'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    state: json['state'] as String? ?? '',
    plan: json['plan'] as String? ?? 'none',
    lineup: json['lineup'] as String? ?? 'none',
    opponentName: json['opponent_name'] as String?,
    homeAway: json['home_away'] as String?,
  );
  final String eventId, title, state, plan, lineup;
  final DateTime startsAt;
  final String? opponentName, homeAway;
}
