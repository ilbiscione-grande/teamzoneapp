import '../../shared/attention/attention_priority.dart';

/// Keeps an older-page request from being silently lost to a newer resync.
class MessageHistoryRequestGate {
  int _generation = 0;
  bool _olderInFlight = false;
  bool _replayOlder = false;

  int startLatest() {
    if (_olderInFlight) _replayOlder = true;
    return ++_generation;
  }

  int startOlder() {
    _olderInFlight = true;
    return _generation;
  }

  bool isCurrent(int generation) => generation == _generation;

  bool finishLatest({required bool hasMore}) {
    _olderInFlight = false;
    final replay = _replayOlder && hasMore;
    _replayOlder = false;
    return replay;
  }

  void failLatest() => _olderInFlight = false;

  void finishOlder() {
    _olderInFlight = false;
    _replayOlder = false;
  }
}

class MessageThreadSummary {
  const MessageThreadSummary({
    required this.id,
    required this.type,
    required this.revision,
    required this.unreadCount,
    required this.muted,
    this.pinned = false,
    this.canSend = true,
    this.canManage = false,
    this.canLeave = false,
    required this.lastAt,
    this.subject,
    this.preview,
    this.senderName,
    this.scopeLabels = const [],
  });
  final String id, type;
  final String? subject, preview, senderName;
  final int revision, unreadCount;
  final bool muted;
  final bool pinned;
  final bool canSend;
  final bool canManage, canLeave;
  final DateTime lastAt;
  final List<String> scopeLabels;
  factory MessageThreadSummary.fromJson(Map<String, dynamic> json) =>
      MessageThreadSummary(
        id: json['id'] as String,
        type: json['thread_type'] as String,
        subject: json['subject'] as String?,
        revision: (json['revision'] as num).toInt(),
        unreadCount: (json['unread_count'] as num).toInt(),
        muted: json['muted'] as bool,
        pinned: json['pinned'] as bool? ?? false,
        canSend: json['can_send'] as bool? ?? true,
        canManage: json['can_manage'] as bool? ?? false,
        canLeave: json['can_leave'] as bool? ?? false,
        lastAt: DateTime.parse(json['last_at'] as String),
        preview: json['last_message_preview'] as String?,
        senderName: json['sender_name'] as String?,
        scopeLabels:
            (json['scope_labels'] as List?)
                ?.whereType<String>()
                .map((label) => label.trim())
                .where((label) => label.isNotEmpty)
                .toList(growable: false) ??
            const [],
      );
}

class MessagingPreferences {
  const MessagingPreferences({required this.pushEnabled});
  final bool pushEnabled;
  factory MessagingPreferences.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid messaging preferences.');
    }
    return MessagingPreferences(pushEnabled: value['push_enabled'] == true);
  }
}

class ThreadMessage {
  const ThreadMessage({
    required this.id,
    required this.revision,
    required this.state,
    required this.createdAt,
    required this.senderName,
    required this.mine,
    this.senderProfileId,
    this.body,
  });
  final String id, state, senderName;
  final String? body, senderProfileId;
  final int revision;
  final DateTime createdAt;
  final bool mine;
  factory ThreadMessage.fromJson(Map<String, dynamic> json) => ThreadMessage(
    id: json['id'] as String,
    revision: (json['revision'] as num).toInt(),
    state: json['state'] as String,
    body: json['body'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    senderName: json['sender_name'] as String,
    senderProfileId: json['sender_profile_id'] as String?,
    mine: json['mine'] as bool,
  );
}

class MessageDisplayGroup {
  const MessageDisplayGroup(this.messages);

  final List<ThreadMessage> messages;
  ThreadMessage get first => messages.first;
  ThreadMessage get last => messages.last;
}

List<MessageDisplayGroup> groupMessagesForDisplay(
  List<ThreadMessage> messages,
) {
  const window = Duration(minutes: 3);
  final groups = <MessageDisplayGroup>[];
  var current = <ThreadMessage>[];
  for (final message in messages) {
    final first = current.isEmpty ? null : current.first;
    final elapsed = first == null
        ? Duration.zero
        : message.createdAt.difference(first.createdAt);
    final sameSender =
        first != null &&
        first.senderProfileId != null &&
        first.senderProfileId == message.senderProfileId;
    if (current.isNotEmpty &&
        (!sameSender || elapsed.isNegative || elapsed > window)) {
      groups.add(MessageDisplayGroup(current));
      current = <ThreadMessage>[];
    }
    current.add(message);
  }
  if (current.isNotEmpty) groups.add(MessageDisplayGroup(current));
  return groups;
}

class MessagePage {
  const MessagePage({
    required this.messages,
    required this.hasMore,
    this.nextBeforeRevision,
  });
  final List<ThreadMessage> messages;
  final bool hasMore;
  final int? nextBeforeRevision;

  factory MessagePage.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid message page response.');
    }
    final json = Map<String, dynamic>.from(value);
    final rows = json['messages'];
    if (rows is! List) {
      throw const FormatException('Invalid message page rows.');
    }
    return MessagePage(
      messages: rows
          .whereType<Map<String, dynamic>>()
          .map(ThreadMessage.fromJson)
          .toList(growable: false),
      hasMore: json['has_more'] as bool? ?? false,
      nextBeforeRevision: (json['next_before_revision'] as num?)?.toInt(),
    );
  }
}

List<ThreadMessage> _mergeMessagesById(
  Iterable<ThreadMessage> current,
  Iterable<ThreadMessage> incoming,
) {
  final byId = <String, ThreadMessage>{
    for (final message in current) message.id: message,
    for (final message in incoming) message.id: message,
  };
  return byId.values.toList(growable: false)..sort((a, b) {
    final revisionOrder = a.revision.compareTo(b.revision);
    return revisionOrder != 0 ? revisionOrder : a.id.compareTo(b.id);
  });
}

MessagePage mergeOlderMessagePage(
  List<ThreadMessage> current,
  MessagePage older,
) => MessagePage(
  messages: _mergeMessagesById(current, older.messages),
  hasMore: older.hasMore,
  nextBeforeRevision: older.nextBeforeRevision,
);

MessagePage mergeNewestMessagePage(
  MessagePage newest, {
  required List<ThreadMessage>? current,
  required bool hasLoadedOlder,
  required bool olderHasMore,
  required int? olderCursor,
}) {
  if (!hasLoadedOlder ||
      current == null ||
      !newest.hasMore ||
      newest.messages.isEmpty) {
    return newest;
  }
  final oldestNewestRevision = newest.messages.first.revision;
  return MessagePage(
    messages: _mergeMessagesById(
      current.where((message) => message.revision < oldestNewestRevision),
      newest.messages,
    ),
    hasMore: olderHasMore,
    nextBeforeRevision: olderCursor,
  );
}

/// Who a thread is with, for the inbox: up to three of the most recently
/// active other participants and how many others take part.
class ThreadAvatars {
  const ThreadAvatars({required this.participantCount, required this.people});
  final int participantCount;
  final List<ThreadAvatarPerson> people;
}

/// [imageUrl] is a signed profile picture, or null for initials.
class ThreadAvatarPerson {
  const ThreadAvatarPerson({required this.name, this.imageUrl});
  final String name;
  final String? imageUrl;
}

class AllowedRecipient {
  const AllowedRecipient({
    required this.profileId,
    required this.displayName,
    required this.rolePackage,
    this.teamNames,
  });
  final String profileId, displayName, rolePackage;

  /// The teams the person is in, e.g. "F2013, P2015"; null for club roles.
  final String? teamNames;
  factory AllowedRecipient.fromJson(Map<String, dynamic> json) =>
      AllowedRecipient(
        profileId: json['profile_id'] as String,
        displayName: json['display_name'] as String,
        rolePackage: json['role_package'] as String,
        teamNames: json['team_names'] as String?,
      );
}

class StagedMessageFile {
  const StagedMessageFile({
    required this.id,
    required this.bucket,
    required this.objectKey,
  });
  final String id, bucket, objectKey;
  factory StagedMessageFile.fromJson(Map<String, dynamic> json) =>
      StagedMessageFile(
        id: json['file_id'] as String,
        bucket: json['bucket_id'] as String,
        objectKey: json['object_key'] as String,
      );
}

class MessageFile {
  const MessageFile({
    required this.id,
    required this.messageId,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });
  final String id, messageId, name, mimeType;
  final int sizeBytes;
  factory MessageFile.fromJson(Map<String, dynamic> json) => MessageFile(
    id: json['id'] as String,
    messageId: json['message_id'] as String,
    name: json['original_name'] as String,
    mimeType: json['mime_type'] as String,
    sizeBytes: (json['size_bytes'] as num).toInt(),
  );
}

class CrossClubLeader {
  const CrossClubLeader({
    required this.profileId,
    required this.displayName,
    required this.clubName,
    required this.teamName,
  });
  final String profileId, displayName, clubName, teamName;
  factory CrossClubLeader.fromJson(Map<String, dynamic> json) {
    final displayName = (json['display_name'] as String?)?.trim() ?? '';
    return CrossClubLeader(
      profileId: json['profile_id'] as String,
      displayName: displayName.isEmpty ? 'Ledare' : displayName,
      clubName: json['club_name'] as String,
      teamName: json['team_name'] as String,
    );
  }
}

class ContactRequest {
  const ContactRequest({
    required this.id,
    required this.requesterName,
    required this.requesterAffiliation,
    required this.reasonCode,
    required this.expiresAt,
    this.text,
  });
  final String id, requesterName, requesterAffiliation, reasonCode;
  final String? text;
  final DateTime expiresAt;
  factory ContactRequest.fromJson(Map<String, dynamic> json) => ContactRequest(
    id: json['id'] as String,
    requesterName: json['requester_name'] as String,
    requesterAffiliation: json['requester_affiliation'] as String,
    reasonCode: json['reason_code'] as String,
    text: json['request_text'] as String?,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );
}

/// POOL-01: the match pool. Listings are found and posted on the web; the
/// conversations between the teams' leaders are also in the app.
class MatchPoolSummary {
  const MatchPoolSummary({required this.leader, required this.unread});
  factory MatchPoolSummary.fromJson(Map<String, dynamic> json) =>
      MatchPoolSummary(
        leader: json['leader'] == true,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
      );
  final bool leader;
  final int unread;
}

DateTime? _poolTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

class MatchPoolListing {
  const MatchPoolListing({
    required this.id,
    required this.homeSlot,
    required this.teamName,
    required this.clubName,
    required this.verified,
    required this.placeLabel,
    required this.matchFormat,
    required this.ageClass,
    this.startsAt,
    this.endsAt,
    this.dateFrom,
    this.dateTo,
    this.venueName,
    this.venueSurface,
    this.current = true,
    this.gender,
    this.level,
    this.note,
    this.maxDistanceKm,
    this.own = false,
    this.myInterestId,
    this.canRepublish = false,
    this.state = 'open',
  });
  factory MatchPoolListing.fromJson(Map<String, dynamic> json) =>
      MatchPoolListing(
        id: json['id'] as String,
        homeSlot: json['kind'] == 'home_slot',
        teamName: json['team_name'] as String? ?? '',
        clubName: json['club_name'] as String? ?? '',
        verified: json['verified'] == true,
        placeLabel: json['place_label'] as String? ?? '',
        matchFormat: json['match_format'] as String? ?? '',
        ageClass: json['age_class'] as String? ?? '',
        startsAt: _poolTime(json['starts_at']),
        endsAt: _poolTime(json['ends_at']),
        dateFrom: _poolTime(json['date_from']),
        dateTo: _poolTime(json['date_to']),
        venueName: json['venue_name'] as String?,
        venueSurface: json['venue_surface'] as String?,
        current: json['current'] != false,
        gender: json['gender'] as String?,
        level: json['level'] as String?,
        note: json['note'] as String?,
        maxDistanceKm: (json['max_distance_km'] as num?)?.toInt(),
        own: json['own'] == true,
        myInterestId: (json['my_interest'] as Map?)?['id'] as String?,
        canRepublish: json['can_republish'] == true,
        state: json['state'] as String? ?? 'open',
      );
  final String id, teamName, clubName, placeLabel, matchFormat, ageClass;
  final bool homeSlot, verified, current, own, canRepublish;
  final DateTime? startsAt, endsAt, dateFrom, dateTo;
  final String? venueName, venueSurface, gender, level, note, myInterestId;
  final int? maxDistanceKm;

  /// open, matched, withdrawn, expired, hidden or cancelled.
  final String state;
}

/// POOL-04: a reported listing, as support sees it.
class MatchPoolReportedListing {
  const MatchPoolReportedListing({
    required this.listing,
    required this.hiddenBySupport,
    required this.openReports,
    required this.reports,
  });
  factory MatchPoolReportedListing.fromJson(Map<String, dynamic> json) =>
      MatchPoolReportedListing(
        listing: MatchPoolListing.fromJson(json),
        hiddenBySupport: json['hidden_by_support'] == true,
        openReports: (json['open_reports'] as num?)?.toInt() ?? 0,
        reports: [
          for (final row
              in (json['reports'] as List? ?? const []).whereType<Map>().map(
                (row) => row.cast<String, dynamic>(),
              ))
            MatchPoolReport.fromJson(row),
        ],
      );
  final MatchPoolListing listing;
  final bool hiddenBySupport;
  final int openReports;
  final List<MatchPoolReport> reports;
}

class MatchPoolReport {
  const MatchPoolReport({
    required this.clubName,
    required this.reason,
    required this.createdAt,
    this.resolution,
  });
  factory MatchPoolReport.fromJson(Map<String, dynamic> json) =>
      MatchPoolReport(
        clubName: json['club_name'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        resolution: json['resolution'] as String?,
      );
  final String clubName, reason;
  final DateTime createdAt;

  /// hidden or dismissed once support has decided.
  final String? resolution;
}

class MatchPoolConversationSummary {
  const MatchPoolConversationSummary({
    required this.id,
    required this.fromListingSide,
    required this.state,
    required this.otherTeamName,
    required this.otherClubName,
    required this.otherVerified,
    required this.unread,
    required this.listing,
    this.lastMessage,
    this.lastActivityAt,
  });
  factory MatchPoolConversationSummary.fromJson(Map<String, dynamic> json) =>
      MatchPoolConversationSummary(
        id: json['id'] as String,
        fromListingSide: json['my_side'] == 'listing',
        state: json['state'] as String? ?? 'pending',
        otherTeamName: json['other_team_name'] as String? ?? '',
        otherClubName: json['other_club_name'] as String? ?? '',
        otherVerified: json['other_verified'] == true,
        unread: json['unread'] == true,
        listing: MatchPoolListing.fromJson(
          (json['listing'] as Map).cast<String, dynamic>(),
        ),
        lastMessage: json['last_message'] as String?,
        lastActivityAt: _poolTime(json['last_activity_at']),
      );
  final String id, state, otherTeamName, otherClubName;
  final bool fromListingSide, otherVerified, unread;
  final MatchPoolListing listing;
  final String? lastMessage;
  final DateTime? lastActivityAt;
}

class MatchPoolMessage {
  const MatchPoolMessage({
    required this.id,
    required this.side,
    required this.body,
    required this.createdAt,
    this.authorName,
  });
  factory MatchPoolMessage.fromJson(Map<String, dynamic> json) =>
      MatchPoolMessage(
        id: json['id'] as String,
        side: json['side'] as String? ?? 'system',
        body: json['body'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        authorName: json['author_name'] as String?,
      );

  /// listing, interest or system.
  final String side, id, body;
  final DateTime createdAt;
  final String? authorName;
}

class MatchPoolConversation {
  const MatchPoolConversation({
    required this.mySide,
    required this.listing,
    required this.interestTeamName,
    required this.interestClubName,
    required this.interestVerified,
    required this.state,
    required this.messages,
    this.myEventId,
    this.proposedStartsAt,
    this.proposedEndsAt,
    this.proposedVenue,
    this.cancelRequestedSide,
    this.cancelRequestedTeamName,
    this.cancelReason,
  });
  factory MatchPoolConversation.fromJson(Map<String, dynamic> json) {
    final interest = (json['interest'] as Map).cast<String, dynamic>();
    return MatchPoolConversation(
      mySide: json['my_side'] as String? ?? 'interest',
      myEventId: json['my_event_id'] as String?,
      listing: MatchPoolListing.fromJson(
        (json['listing'] as Map).cast<String, dynamic>(),
      ),
      interestTeamName: interest['team_name'] as String? ?? '',
      interestClubName: interest['club_name'] as String? ?? '',
      interestVerified: interest['verified'] == true,
      state: interest['state'] as String? ?? 'pending',
      proposedStartsAt: _poolTime(interest['starts_at']),
      proposedEndsAt: _poolTime(interest['ends_at']),
      proposedVenue: interest['venue_name'] as String?,
      cancelRequestedSide: interest['cancel_requested_side'] as String?,
      cancelRequestedTeamName:
          interest['cancel_requested_team_name'] as String?,
      cancelReason: interest['cancel_reason'] as String?,
      messages: [
        for (final row
            in (json['messages'] as List? ?? const []).whereType<Map>().map(
              (row) => row.cast<String, dynamic>(),
            ))
          MatchPoolMessage.fromJson(row),
      ],
    );
  }
  final String mySide, interestTeamName, interestClubName, state;
  final String? myEventId, proposedVenue;

  /// POOL-02: a pending cancellation request ('listing' or 'interest') and
  /// the team that asked.
  final String? cancelRequestedSide, cancelRequestedTeamName, cancelReason;
  final MatchPoolListing listing;
  final bool interestVerified;
  final DateTime? proposedStartsAt, proposedEndsAt;
  final List<MatchPoolMessage> messages;

  bool get fromListingSide => mySide == 'listing';
  String get otherTeamName =>
      fromListingSide ? interestTeamName : listing.teamName;
  String get otherClubName =>
      fromListingSide ? interestClubName : listing.clubName;
  bool get otherVerified =>
      fromListingSide ? interestVerified : listing.verified;
}

/// PUB-14: a message thread that started on the club site, as its
/// recipients (club administrators or the team's leaders) see it.
class ContactThreadSummary {
  const ContactThreadSummary({
    required this.id,
    required this.clubName,
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.preview,
    required this.lastActivityAt,
    required this.expiresAt,
    required this.handled,
    required this.unread,
    this.teamName,
    this.latestFromSender = true,
  });
  factory ContactThreadSummary.fromJson(Map<String, dynamic> json) =>
      ContactThreadSummary(
        id: json['id'] as String,
        clubName: json['club_name'] as String? ?? '',
        teamName: json['team_name'] as String?,
        senderName: json['sender_name'] as String? ?? '',
        senderEmail: json['sender_email'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        preview: json['preview'] as String? ?? '',
        lastActivityAt: DateTime.parse(json['last_activity_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
        handled: json['handled'] == true,
        unread: json['unread'] == true,
        latestFromSender: json['latest_direction'] != 'out',
      );
  final String id, clubName, senderName, senderEmail, subject, preview;
  final String? teamName;
  final DateTime lastActivityAt, expiresAt;
  final bool handled, unread, latestFromSender;

  /// "P2012 · Alby IF" or the club alone.
  String get recipientLabel =>
      teamName == null ? clubName : '$teamName · $clubName';
}

class ContactMessage {
  const ContactMessage({
    required this.id,
    required this.fromSender,
    required this.body,
    required this.createdAt,
    this.authorName,
    this.emailState,
  });
  factory ContactMessage.fromJson(Map<String, dynamic> json) => ContactMessage(
    id: json['id'] as String,
    fromSender: json['direction'] != 'out',
    body: json['body'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    authorName: json['author_name'] as String?,
    emailState: json['email_state'] as String?,
  );
  final String id, body;
  final bool fromSender;
  final DateTime createdAt;
  final String? authorName;

  /// For answers: pending, processing, sent or failed.
  final String? emailState;
}

class ContactThread {
  const ContactThread({
    required this.id,
    required this.clubName,
    required this.senderName,
    required this.senderEmail,
    required this.subject,
    required this.expiresAt,
    required this.handled,
    required this.messages,
    this.teamName,
  });
  factory ContactThread.fromJson(Map<String, dynamic> json) => ContactThread(
    id: json['id'] as String,
    clubName: json['club_name'] as String? ?? '',
    teamName: json['team_name'] as String?,
    senderName: json['sender_name'] as String? ?? '',
    senderEmail: json['sender_email'] as String? ?? '',
    subject: json['subject'] as String? ?? '',
    expiresAt: DateTime.parse(json['expires_at'] as String),
    handled: json['handled'] == true,
    messages: [
      for (final item in (json['messages'] as List? ?? const []))
        if (item is Map)
          ContactMessage.fromJson(Map<String, dynamic>.from(item)),
    ],
  );
  final String id, clubName, senderName, senderEmail, subject;
  final String? teamName;
  final DateTime expiresAt;
  final bool handled;
  final List<ContactMessage> messages;
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.eventType,
    required this.createdAt,
    required this.category,
    required this.title,
    required this.preview,
    required this.deepLink,
    required this.unread,
    required this.canonicalKey,
    required this.priority,
    this.messageCount = 0,
    this.senderName,
    this.chatName,
    this.messagePreview,
  });
  final String id, eventType, category, title, preview, deepLink;
  final bool unread;
  final String canonicalKey;
  final int priority;
  final int messageCount;
  final String? senderName, chatName, messagePreview;
  final DateTime createdAt;

  NotificationItem asRead() => NotificationItem(
    id: id,
    eventType: eventType,
    createdAt: createdAt,
    category: category,
    title: title,
    preview: preview,
    deepLink: deepLink,
    unread: false,
    canonicalKey: canonicalKey,
    priority: priority,
    messageCount: messageCount,
    senderName: senderName,
    chatName: chatName,
    messagePreview: messagePreview,
  );

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String;
    return NotificationItem(
      id: json['id'] as String,
      eventType: json['event_type'] as String,
      category: category,
      title: json['title'] as String,
      preview: json['preview'] as String,
      deepLink: json['deep_link'] as String,
      unread: json['unread'] as bool? ?? false,
      canonicalKey: json['canonical_key'] as String,
      priority: attentionPriority(category),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      senderName: json['sender_name'] as String?,
      chatName: json['chat_name'] as String?,
      messagePreview: json['message_preview'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class NotificationCenter {
  const NotificationCenter({required this.items, required this.unreadCount});
  final List<NotificationItem> items;
  final int unreadCount;
  factory NotificationCenter.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid notification center.');
    }
    final json = Map<String, dynamic>.from(value);
    final rows = json['items'];
    if (rows is! List) {
      throw const FormatException('Invalid notification items.');
    }
    final parsed = rows
        .whereType<Map<String, dynamic>>()
        .map(NotificationItem.fromJson)
        .toList(growable: false);
    final blockedUnread = _uniqueNotificationAttention(
      parsed.where(_isRetiredOrPrematureAttention),
    ).where((item) => item.unread).length;
    final items = _uniqueNotificationAttention(
      parsed.where((item) => !_isRetiredOrPrematureAttention(item)),
    );
    final serverUnread = (json['unread_count'] as num?)?.toInt() ?? 0;
    final visibleUnread = serverUnread > blockedUnread
        ? serverUnread - blockedUnread
        : 0;
    return NotificationCenter(items: items, unreadCount: visibleUnread);
  }
}

bool _isRetiredOrPrematureAttention(NotificationItem item) {
  final identity = [
    item.eventType,
    item.category,
    item.canonicalKey,
  ].join('|').toLowerCase();
  return identity.contains('watchpoint') ||
      identity.contains('assistant') ||
      identity.contains('ac_signal') ||
      identity.contains('workload.future_review') ||
      identity.contains('high_load') ||
      identity.contains('health.clearance') ||
      identity.contains('medical.');
}

List<NotificationItem> _uniqueNotificationAttention(
  Iterable<NotificationItem> items,
) {
  final byKey = <String, NotificationItem>{};
  for (final item in items) {
    final key = item.canonicalKey.trim().isEmpty
        ? 'id:${item.id}'
        : item.canonicalKey;
    final current = byKey[key];
    if (current == null ||
        item.priority < current.priority ||
        (item.priority == current.priority &&
            item.createdAt.isAfter(current.createdAt))) {
      byKey[key] = item;
    }
  }
  final result = byKey.values.toList(growable: false)
    ..sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      final created = right.createdAt.compareTo(left.createdAt);
      if (created != 0) return created;
      return left.id.compareTo(right.id);
    });
  return result;
}

List<Map<String, dynamic>> messagingRows(Object? value, String key) {
  final raw = value is Map<String, dynamic> ? value[key] : null;
  if (raw is! List) throw const FormatException('Invalid messaging response.');
  return raw.whereType<Map<String, dynamic>>().toList(growable: false);
}
