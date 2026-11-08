import '../../core/identity/identity_models.dart';
import 'calendar_models.dart';

Map<String, dynamic>? _owningTeam(EventDetails event) {
  for (final team in event.teams) {
    if (event.owningTeamId != null && team['team_id'] == event.owningTeamId) {
      return team;
    }
  }
  for (final team in event.teams) {
    if (team['relation'] == 'primary') return team;
  }
  return null;
}

/// Resolve a bare deep link within the caller's existing authorized contexts.
/// A related shared-team context is deliberately retained, including its limits.
TeamZoneContext eventDetailsContext(
  EventDetails event,
  TeamZoneContext active,
  List<TeamZoneContext> available,
) {
  bool sameClub(TeamZoneContext c) =>
      event.clubId == null || c.clubId == event.clubId;
  bool related(TeamZoneContext c) =>
      sameClub(c) &&
      (c.teamId == null || event.teams.any((t) => t['team_id'] == c.teamId));
  if (related(active)) return active;
  final owner = _owningTeam(event)?['team_id'];
  for (final c in available) {
    if (sameClub(c) && owner != null && c.teamId == owner) return c;
  }
  for (final c in available) {
    if (sameClub(c) && c.teamId == null) return c;
  }
  for (final c in available) {
    if (related(c)) return c;
  }
  return active;
}

/// Label the event's owner, never an unrelated currently selected team.
/// Club names come only from already authorized identity contexts.
String eventDetailsSubtitle(
  EventDetails event,
  TeamZoneContext active,
  List<TeamZoneContext> available, {
  required String fallback,
}) {
  final owner = _owningTeam(event);
  final contexts = [active, ...available];
  String? clubId = event.clubId;
  if (clubId == null && owner != null) {
    for (final c in contexts) {
      if (c.teamId == owner['team_id']) {
        clubId = c.clubId;
        break;
      }
    }
  }
  String? clubName;
  if (clubId != null) {
    for (final c in contexts) {
      if (c.clubId == clubId) {
        clubName = c.clubName;
        break;
      }
    }
  }
  final teamName = (owner?['name'] as String?)?.trim();
  final labels = [
    clubName,
    teamName,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
  return labels.isEmpty ? fallback : labels.join(' · ');
}
