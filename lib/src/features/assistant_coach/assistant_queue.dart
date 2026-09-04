import 'package:flutter/foundation.dart';

enum AssistantDeliveryMode { direct, digest, inAssistant, off }

enum AssistantPostPriority {
  urgent(10),
  attention(20),
  routine(30),
  positive(40);

  const AssistantPostPriority(this.rank);
  final int rank;

  static AssistantPostPriority fromRank(int rank) => switch (rank) {
    <= 10 => urgent,
    <= 20 => attention,
    <= 30 => routine,
    _ => positive,
  };
}

@immutable
class AssistantQueuePost {
  const AssistantQueuePost({
    required this.signalKey,
    required this.sourceId,
    required this.canonicalKey,
    required this.primaryAreaKey,
    required this.priority,
    required this.deliveryMode,
    required this.observedAt,
    required this.authorized,
    required this.dismissed,
    this.source = '',
    this.freshUntil,
    this.explanation = '',
    this.safeAction = '',
  });

  factory AssistantQueuePost.fromJson(Map<String, dynamic> json) {
    final priority = json['priority'];
    final observedAt = json['observedAt'];
    if (json['signalKey'] is! String ||
        json['sourceId'] is! String ||
        json['canonicalKey'] is! String ||
        json['primaryAreaKey'] is! String ||
        priority is! num ||
        observedAt is! String) {
      throw const FormatException('Invalid assistant queue post.');
    }
    return AssistantQueuePost(
      signalKey: json['signalKey'] as String,
      sourceId: json['sourceId'] as String,
      canonicalKey: json['canonicalKey'] as String,
      primaryAreaKey: json['primaryAreaKey'] as String,
      priority: AssistantPostPriority.fromRank(priority.toInt()),
      deliveryMode: assistantDeliveryModeFromWire(
        json['deliveryMode'] as String? ?? 'off',
      ),
      observedAt: DateTime.parse(observedAt),
      authorized: json['authorized'] == true,
      dismissed: json['dismissed'] == true,
      source: json['source'] as String? ?? '',
      freshUntil: json['freshUntil'] is String
          ? DateTime.parse(json['freshUntil'] as String)
          : null,
      explanation: json['explanation'] as String? ?? '',
      safeAction: json['safeAction'] as String? ?? '',
    );
  }

  final String signalKey;
  final String sourceId;
  final String canonicalKey;
  final String primaryAreaKey;
  final AssistantPostPriority priority;
  final AssistantDeliveryMode deliveryMode;
  final DateTime observedAt;
  final bool authorized;
  final bool dismissed;
  final String source;
  final DateTime? freshUntil;
  final String explanation;
  final String safeAction;

  bool isStaleAt(DateTime now) =>
      freshUntil != null && !freshUntil!.isAfter(now);
}

AssistantDeliveryMode assistantDeliveryModeFromWire(String value) =>
    switch (value) {
      'direct' => AssistantDeliveryMode.direct,
      'digest' => AssistantDeliveryMode.digest,
      'in_assistant' => AssistantDeliveryMode.inAssistant,
      'off' => AssistantDeliveryMode.off,
      _ => throw FormatException('Unknown assistant delivery mode: $value'),
    };

List<AssistantQueuePost> buildAssistantQueue(
  Iterable<AssistantQueuePost> candidates,
) {
  final winners = <String, AssistantQueuePost>{};
  for (final candidate in candidates) {
    if (!candidate.authorized || candidate.dismissed) continue;
    final current = winners[candidate.canonicalKey];
    if (current == null || _compareAssistantPosts(candidate, current) < 0) {
      winners[candidate.canonicalKey] = candidate;
    }
  }
  final result = winners.values.toList(growable: false)
    ..sort(_compareAssistantPosts);
  return List.unmodifiable(result);
}

int _compareAssistantPosts(AssistantQueuePost a, AssistantQueuePost b) {
  var result = a.priority.rank.compareTo(b.priority.rank);
  if (result != 0) return result;
  result = b.observedAt.compareTo(a.observedAt);
  if (result != 0) return result;
  result = a.signalKey.compareTo(b.signalKey);
  if (result != 0) return result;
  return a.sourceId.compareTo(b.sourceId);
}

const assistantDirectLimitPer24Hours = 3;
const assistantDigestLimitPer24Hours = 1;

@immutable
class AssistantDeliveryPlan {
  const AssistantDeliveryPlan({
    required this.direct,
    required this.digest,
    required this.inAssistant,
    required this.off,
  });

  final List<AssistantQueuePost> direct;
  final List<AssistantQueuePost> digest;
  final List<AssistantQueuePost> inAssistant;
  final List<AssistantQueuePost> off;
}

AssistantDeliveryPlan planAssistantDelivery(
  Iterable<AssistantQueuePost> queue, {
  int directRemaining = assistantDirectLimitPer24Hours,
  int digestRemaining = assistantDigestLimitPer24Hours,
}) {
  final direct = <AssistantQueuePost>[];
  final digest = <AssistantQueuePost>[];
  final inAssistant = <AssistantQueuePost>[];
  final off = <AssistantQueuePost>[];
  for (final post in queue) {
    switch (post.deliveryMode) {
      case AssistantDeliveryMode.direct:
        if (direct.length < directRemaining) {
          direct.add(post);
        } else if (digestRemaining > 0) {
          digest.add(post);
        } else {
          inAssistant.add(post);
        }
      case AssistantDeliveryMode.digest:
        if (digestRemaining > 0) {
          digest.add(post);
        } else {
          inAssistant.add(post);
        }
      case AssistantDeliveryMode.inAssistant:
        inAssistant.add(post);
      case AssistantDeliveryMode.off:
        off.add(post);
    }
  }
  return AssistantDeliveryPlan(
    direct: List.unmodifiable(direct),
    digest: List.unmodifiable(digest),
    inAssistant: List.unmodifiable(inAssistant),
    off: List.unmodifiable(off),
  );
}

bool isAssistantDeliveryMode(String value) =>
    const {'direct', 'digest', 'in_assistant', 'off'}.contains(value);
