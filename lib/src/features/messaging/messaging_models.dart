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
  });
  final String id, type;
  final String? subject, preview, senderName;
  final int revision, unreadCount;
  final bool muted;
  final bool pinned;
  final bool canSend;
  final bool canManage, canLeave;
  final DateTime lastAt;
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
    this.body,
  });
  final String id, state, senderName;
  final String? body;
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
    mine: json['mine'] as bool,
  );
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

class AllowedRecipient {
  const AllowedRecipient({
    required this.profileId,
    required this.displayName,
    required this.rolePackage,
  });
  final String profileId, displayName, rolePackage;
  factory AllowedRecipient.fromJson(Map<String, dynamic> json) =>
      AllowedRecipient(
        profileId: json['profile_id'] as String,
        displayName: json['display_name'] as String,
        rolePackage: json['role_package'] as String,
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
  factory CrossClubLeader.fromJson(Map<String, dynamic> json) =>
      CrossClubLeader(
        profileId: json['profile_id'] as String,
        displayName: json['display_name'] as String,
        clubName: json['club_name'] as String,
        teamName: json['team_name'] as String,
      );
}

class ContactRequest {
  const ContactRequest({
    required this.id,
    required this.requesterName,
    required this.reasonCode,
    required this.expiresAt,
    this.text,
  });
  final String id, requesterName, reasonCode;
  final String? text;
  final DateTime expiresAt;
  factory ContactRequest.fromJson(Map<String, dynamic> json) => ContactRequest(
    id: json['id'] as String,
    requesterName: json['requester_name'] as String,
    reasonCode: json['reason_code'] as String,
    text: json['request_text'] as String?,
    expiresAt: DateTime.parse(json['expires_at'] as String),
  );
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
  });
  final String id, eventType, category, title, preview, deepLink;
  final bool unread;
  final String canonicalKey;
  final int priority;
  final DateTime createdAt;
  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: json['id'] as String,
        eventType: json['event_type'] as String,
        category: json['category'] as String,
        title: json['title'] as String,
        preview: json['preview'] as String,
        deepLink: json['deep_link'] as String,
        unread: json['unread'] as bool? ?? false,
        canonicalKey: json['canonical_key'] as String,
        priority: (json['priority'] as num).toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
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
    return NotificationCenter(
      items: rows
          .whereType<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList(growable: false),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

List<Map<String, dynamic>> messagingRows(Object? value, String key) {
  final raw = value is Map<String, dynamic> ? value[key] : null;
  if (raw is! List) throw const FormatException('Invalid messaging response.');
  return raw.whereType<Map<String, dynamic>>().toList(growable: false);
}
