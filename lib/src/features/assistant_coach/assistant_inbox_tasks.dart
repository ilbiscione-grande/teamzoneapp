import '../../app/product_route_contract.dart';
import '../../core/identity/identity_models.dart';
import '../overview/overview_models.dart';
import '../overview/overview_services.dart';
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
