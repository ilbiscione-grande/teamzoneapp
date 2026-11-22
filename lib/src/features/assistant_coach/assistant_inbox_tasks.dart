import '../../app/product_route_contract.dart';
import '../../core/identity/identity_models.dart';
import '../overview/overview_models.dart';
import '../overview/overview_services.dart';
import '../roster/roster_models.dart';
import 'assistant_task_preferences.dart';
import 'assistant_tasks.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';

/// The most unread inbox items the assistant lists, newest first.
const assistantInboxLimit = 8;

bool isAssistantInboxKind(String kind) => kind.startsWith('inbox_');

/// Representation in other teams, for the teams you lead: requests waiting
/// for your approval, and players recently made available by their own team.
/// Shown under the team's context (the active one first), opening the team's
/// representation sheet.
Future<List<AssistantTask>> loadAssistantRepresentationTasks({
  required List<TeamZoneContext> contexts,
  required TeamZoneContext? activeContext,
  required OverviewServices overview,
  required AssistantTaskPreferences preferences,
}) async {
  if (overview is! RepresentationTaskServices) return const [];
  final result = <AssistantTask>[];
  try {
    final rows = await (overview as RepresentationTaskServices)
        .listMyRepresentationTasks()
        .timeout(const Duration(seconds: 15));
    for (final row in rows) {
      final kind = switch (row.kind) {
        'decide' => 'team_representation_requests',
        'available' => 'team_representation_available',
        _ => null,
      };
      if (kind == null || row.count <= 0 || !preferences.shows(kind)) continue;
      bool inTeam(TeamZoneContext item) =>
          item.clubId == row.clubId && item.teamId == row.teamId;
      if (preferences.currentTeamOnly &&
          (activeContext == null || !inTeam(activeContext))) {
        continue;
      }
      final context = activeContext != null && inTeam(activeContext)
          ? activeContext
          : contexts
                .where((item) => inTeam(item) && item.rolePackage == 'leader')
                .followedBy(contexts.where(inTeam))
                .firstOrNull;
      if (context == null) continue;
      result.add(
        AssistantTask(
          context: context,
          task: LeaderHomeTask(
            kind: kind,
            title: kind == 'team_representation_requests'
                ? 'Representation att godkänna'
                : 'Spelare som kan representera laget',
            count: row.count,
            route: Uri(
              path: ProductRouteContract.team,
              queryParameters: {
                'action': 'representation',
                'context': context.id,
              },
            ).toString(),
            priority: 40,
          ),
          eventId: row.teamId,
          generatedAt: DateTime.now(),
          stale: false,
          eventTitle: context.teamName ?? context.clubName,
        ),
      );
    }
  } catch (error) {
    AppErrors.caught('assistant_inbox_tasks.representation', error);
  }
  return result;
}

/// New contact details sent through a team's contact update page, for the
/// teams whose squad you manage: one task per team with the number waiting,
/// opening the team's contact update view. Details sent to the club rather
/// than a team stay in the inbox only. [loadIntake] is the roster's intake
/// overview for a club; a club that fails to load is left out.
Future<List<AssistantTask>> loadAssistantIntakeTasks({
  required List<TeamZoneContext> contexts,
  required TeamZoneContext? activeContext,
  required Future<IntakeOverview> Function(String clubId)? loadIntake,
  required AssistantTaskPreferences preferences,
}) async {
  const kind = 'team_contact_details';
  if (loadIntake == null || !preferences.shows(kind)) return const [];
  bool manages(TeamZoneContext item) =>
      item.teamId != null &&
      (item.can('team.roster.manage') || item.can('club.memberships.manage'));
  final teams = [
    for (final item in contexts)
      if (manages(item) &&
          (!preferences.currentTeamOnly ||
              (activeContext != null &&
                  item.clubId == activeContext.clubId &&
                  item.teamId == activeContext.teamId)))
        item,
  ];
  final result = <AssistantTask>[];
  for (final clubId in {for (final item in teams) item.clubId}) {
    final IntakeOverview overview;
    try {
      overview = await loadIntake(clubId).timeout(const Duration(seconds: 15));
    } catch (error) {
      AppErrors.caught('assistant_inbox_tasks.intake', error);
      continue;
    }
    final counts = <String, int>{};
    for (final submission in overview.submissions) {
      if (submission.teamId case final teamId?) {
        counts[teamId] = (counts[teamId] ?? 0) + 1;
      }
    }
    for (final MapEntry(key: teamId, value: count) in counts.entries) {
      bool inTeam(TeamZoneContext item) =>
          item.clubId == clubId && item.teamId == teamId;
      // The active context first, then a leader context for the team.
      final context = activeContext != null && inTeam(activeContext)
          ? activeContext
          : teams
                .where((item) => inTeam(item) && item.rolePackage == 'leader')
                .followedBy(teams.where(inTeam))
                .firstOrNull;
      if (context == null) continue;
      result.add(
        AssistantTask(
          context: context,
          task: LeaderHomeTask(
            kind: kind,
            title: 'Nya kontaktuppgifter',
            count: count,
            route: Uri(
              path: ProductRouteContract.team,
              queryParameters: {'action': 'intake', 'context': context.id},
            ).toString(),
            priority: 40,
          ),
          eventId: teamId,
          generatedAt: DateTime.now(),
          stale: false,
          eventTitle: context.teamName ?? context.clubName,
        ),
      );
    }
  }
  return result;
}

/// Your unread messages, announcements and other notices (team news,
/// results, changed times, invitations), the newest first. Personal, so
/// shown under the active context; opening one marks it read.
Future<List<AssistantTask>> loadAssistantInboxTasks({
  required List<TeamZoneContext> contexts,
  required TeamZoneContext? activeContext,
  required OverviewServices overview,
  required AssistantTaskPreferences preferences,
}) async {
  if (overview is! InboxAttentionServices) return const [];
  final context = activeContext ?? contexts.firstOrNull;
  if (context == null) return const [];
  final showMessages = preferences.shows('inbox_messages');
  final showNotices = preferences.shows('inbox_notices');
  if (!showMessages && !showNotices) return const [];
  try {
    final center = await (overview as InboxAttentionServices)
        .listInboxAttention()
        .timeout(const Duration(seconds: 15));
    final unread = center.items.where((item) => item.unread).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      for (final item in unread)
        if (item.category == 'message' ? showMessages : showNotices)
          AssistantTask(
            context: context,
            task: LeaderHomeTask(
              kind: item.category == 'message'
                  ? 'inbox_messages'
                  : 'inbox_notices',
              title: item.title,
              count: item.messageCount > 0 ? item.messageCount : 1,
              route: item.deepLink,
              priority: 45,
            ),
            eventId: item.id,
            generatedAt: item.createdAt,
            stale: false,
            eventTitle: [
              if (item.senderName case final sender? when sender.isNotEmpty)
                sender,
              (item.messagePreview ?? item.preview).trim(),
            ].where((part) => part.isNotEmpty).join(': '),
          ),
    ].take(assistantInboxLimit).toList();
  } catch (error) {
    AppErrors.caught('assistant_inbox_tasks.inbox', error);
    return const [];
  }
}
