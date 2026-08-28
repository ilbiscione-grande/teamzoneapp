import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';

abstract interface class MessagingServices {
  Future<List<MessageThreadSummary>> listThreads(List<String> contextIds);
  Stream<void> watchInboxInvalidations();
  Future<List<ThreadMessage>> listMessages(String threadId);
  Future<MessagePage> listMessagePage(String threadId, {int? beforeRevision});
  Stream<void> watchThreadInvalidations(String threadId);
  Future<List<AllowedRecipient>> resolveRecipients(
    String contextId, {
    String? query,
  });
  Future<String> createThread({
    required String contextId,
    required String type,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  });
  Future<void> addParticipants({
    required String threadId,
    required List<String> profileIds,
    required String idempotencyKey,
  });
  Future<String> createAnnouncement({
    required String contextId,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  });
  Future<void> markAllRead(List<String> contextIds, String idempotencyKey);
  Future<void> send({
    required String threadId,
    required String body,
    required String idempotencyKey,
    List<String> stagedFileIds = const [],
  });
  Future<void> markRead(String threadId, int revision, String idempotencyKey);
  Future<void> setMute(String threadId, bool muted, String idempotencyKey);
  Future<void> setPin(String threadId, bool pinned, String idempotencyKey);
  Future<void> setVisibility(
    String threadId,
    bool hidden,
    String idempotencyKey,
  );
  Future<void> leaveThread(String threadId, String idempotencyKey);
  Future<void> closeThread(
    String threadId,
    String reason,
    String idempotencyKey,
  );
  Future<String> requestThreadErasure(
    String threadId,
    String reason,
    String idempotencyKey,
  );
  Future<MessagingPreferences> getPreferences();
  Future<void> setPushEnabled(bool enabled, String idempotencyKey);
  Future<StagedMessageFile> stageFile(
    String threadId,
    String name,
    String mimeType,
    Uint8List bytes,
  );
  Future<List<MessageFile>> listFiles(String threadId);
  Future<String> signedFileUrl(String fileId);
  Future<void> recall(String messageId, int revision, String idempotencyKey);
  Future<void> report(String messageId, String reason, String idempotencyKey);
  Future<List<CrossClubLeader>> searchLeaders(String query);
  Future<void> requestContact(
    String profileId,
    String reason,
    String text,
    String idempotencyKey,
  );
  Future<List<ContactRequest>> listRequests();
  Future<void> decideRequest(
    String requestId,
    String decision,
    String idempotencyKey,
  );
  Future<NotificationCenter> listNotifications();
  Stream<void> watchNotificationInvalidations();
  Future<void> setNotificationState(
    String notificationId,
    String state,
    String idempotencyKey,
  );
  Future<void> markAllNotificationsRead(String idempotencyKey);
}

class UnconfiguredMessagingServices implements MessagingServices {
  const UnconfiguredMessagingServices();
  Future<T> _fail<T>() =>
      Future.error(StateError('Messaging backend is not configured.'));
  @override
  Future<List<MessageThreadSummary>> listThreads(List<String> contextIds) =>
      _fail();
  @override
  Stream<void> watchInboxInvalidations() => const Stream<void>.empty();
  @override
  Future<List<ThreadMessage>> listMessages(String threadId) => _fail();
  @override
  Future<MessagePage> listMessagePage(String threadId, {int? beforeRevision}) =>
      _fail();
  @override
  Stream<void> watchThreadInvalidations(String threadId) =>
      const Stream<void>.empty();
  @override
  Future<List<AllowedRecipient>> resolveRecipients(
    String contextId, {
    String? query,
  }) => _fail();
  @override
  Future<String> createThread({
    required String contextId,
    required String type,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> addParticipants({
    required String threadId,
    required List<String> profileIds,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<String> createAnnouncement({
    required String contextId,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> markAllRead(List<String> contextIds, String idempotencyKey) =>
      _fail();
  @override
  Future<void> send({
    required String threadId,
    required String body,
    required String idempotencyKey,
    List<String> stagedFileIds = const [],
  }) => _fail();
  @override
  Future<void> markRead(String threadId, int revision, String idempotencyKey) =>
      _fail();
  @override
  Future<void> setMute(String threadId, bool muted, String idempotencyKey) =>
      _fail();
  @override
  Future<void> setPin(String threadId, bool pinned, String idempotencyKey) =>
      _fail();
  @override
  Future<void> setVisibility(String a, bool b, String c) => _fail();
  @override
  Future<void> leaveThread(String a, String b) => _fail();
  @override
  Future<void> closeThread(String a, String b, String c) => _fail();
  @override
  Future<String> requestThreadErasure(String a, String b, String c) => _fail();
  @override
  Future<MessagingPreferences> getPreferences() => _fail();
  @override
  Future<void> setPushEnabled(bool enabled, String idempotencyKey) => _fail();
  @override
  Future<StagedMessageFile> stageFile(
    String a,
    String b,
    String c,
    Uint8List d,
  ) => _fail();
  @override
  Future<List<MessageFile>> listFiles(String a) => _fail();
  @override
  Future<String> signedFileUrl(String fileId) => _fail();
  @override
  Future<void> recall(String a, int b, String c) => _fail();
  @override
  Future<void> report(String a, String b, String c) => _fail();
  @override
  Future<List<CrossClubLeader>> searchLeaders(String a) => _fail();
  @override
  Future<void> requestContact(String a, String b, String c, String d) =>
      _fail();
  @override
  Future<List<ContactRequest>> listRequests() => _fail();
  @override
  Future<void> decideRequest(String a, String b, String c) => _fail();
  @override
  Future<NotificationCenter> listNotifications() => _fail();
  @override
  Stream<void> watchNotificationInvalidations() => const Stream<void>.empty();
  @override
  Future<void> setNotificationState(String a, String b, String c) => _fail();
  @override
  Future<void> markAllNotificationsRead(String a) => _fail();
}

class SupabaseMessagingServices implements MessagingServices {
  SupabaseMessagingServices(this._client);
  final SupabaseClient _client;
  @override
  Future<List<MessageThreadSummary>> listThreads(
    List<String> contextIds,
  ) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_threads',
          params: {'context_ids': contextIds.toSet().toList()},
        );
    return messagingRows(
      value,
      'threads',
    ).map(MessageThreadSummary.fromJson).toList(growable: false);
  }

  @override
  Stream<void> watchInboxInvalidations() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    Future<void> start() async {
      try {
        final profileId = _client.auth.currentUser?.id;
        if (profileId == null) throw StateError('Unauthenticated inbox.');
        await _client.realtime.setAuth(
          _client.auth.currentSession?.accessToken,
        );
        channel = _client.channel(
          'message:inbox:$profileId',
          opts: const RealtimeChannelConfig(private: true),
        );
        channel!
            .onBroadcast(
              event: 'invalidate',
              callback: (_) {
                if (!controller.isClosed) controller.add(null);
              },
            )
            .subscribe((status, _) {
              if (!controller.isClosed &&
                  status == RealtimeSubscribeStatus.subscribed) {
                controller.add(null);
              }
            });
      } catch (_) {
        if (!controller.isClosed) {
          controller.addError(StateError('Inbox sync unavailable.'));
        }
      }
    }

    Future<void> stop() async {
      final current = channel;
      if (current != null) await _client.removeChannel(current);
    }

    controller = StreamController<void>(onListen: start, onCancel: stop);
    return controller.stream;
  }

  @override
  Future<List<ThreadMessage>> listMessages(String threadId) async {
    return (await listMessagePage(threadId)).messages;
  }

  @override
  Future<MessagePage> listMessagePage(
    String threadId, {
    int? beforeRevision,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'list_messages',
          params: {
            'thread_id': threadId,
            'before_revision': beforeRevision,
            'page_limit': 50,
          },
        );
    return MessagePage.fromJson(value);
  }

  @override
  Stream<void> watchThreadInvalidations(String threadId) {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    Future<void> start() async {
      try {
        await _client.realtime.setAuth(
          _client.auth.currentSession?.accessToken,
        );
        channel = _client.channel(
          'message:thread:$threadId',
          opts: const RealtimeChannelConfig(private: true),
        );
        channel!
            .onBroadcast(
              event: 'invalidate',
              callback: (_) {
                if (!controller.isClosed) controller.add(null);
              },
            )
            .subscribe((status, _) {
              if (!controller.isClosed &&
                  status == RealtimeSubscribeStatus.subscribed) {
                controller.add(null);
              }
            });
      } catch (_) {
        if (!controller.isClosed) {
          controller.addError(StateError('Thread sync unavailable.'));
        }
      }
    }

    Future<void> stop() async {
      final current = channel;
      if (current != null) await _client.removeChannel(current);
    }

    controller = StreamController<void>(onListen: start, onCancel: stop);
    return controller.stream;
  }

  @override
  Future<List<AllowedRecipient>> resolveRecipients(
    String contextId, {
    String? query,
  }) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>(
          'resolve_allowed_recipients',
          params: {'context_id': contextId, 'query': query},
        );
    if (value is! List) {
      throw const FormatException('Invalid recipient response.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(AllowedRecipient.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> createThread({
    required String contextId,
    required String type,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  }) async =>
      (await measuredRpc(
            _client,
            operation: 'create_thread',
            params: {
              'context_id': contextId,
              'thread_type': type,
              'subject': subject,
              'participant_profile_ids': recipientIds,
              'idempotency_key': idempotencyKey,
            },
          ))
          as String;
  @override
  Future<void> addParticipants({
    required String threadId,
    required List<String> profileIds,
    required String idempotencyKey,
  }) async {
    await measuredRpc(
      _client,
      operation: 'add_thread_participants',
      params: {
        'thread_id': threadId,
        'participant_profile_ids': profileIds,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<String> createAnnouncement({
    required String contextId,
    required String subject,
    required List<String> recipientIds,
    required String idempotencyKey,
  }) async =>
      (await measuredRpc(
            _client,
            operation: 'create_announcement',
            params: {
              'context_id': contextId,
              'subject': subject,
              'participant_profile_ids': recipientIds,
              'idempotency_key': idempotencyKey,
            },
          ))
          as String;

  @override
  Future<void> markAllRead(
    List<String> contextIds,
    String idempotencyKey,
  ) async {
    await measuredRpc(
      _client,
      operation: 'mark_all_threads_read',
      params: {
        'context_ids': contextIds.toSet().toList(),
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> send({
    required String threadId,
    required String body,
    required String idempotencyKey,
    List<String> stagedFileIds = const [],
  }) async {
    await measuredRpc(
      _client,
      operation: 'send_message',
      params: {
        'thread_id': threadId,
        'body': body,
        'staged_file_ids': stagedFileIds,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> markRead(
    String threadId,
    int revision,
    String idempotencyKey,
  ) async {
    await measuredRpc(
      _client,
      operation: 'mark_thread_read',
      params: {
        'thread_id': threadId,
        'through_revision': revision,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> setMute(
    String threadId,
    bool muted,
    String idempotencyKey,
  ) async {
    await measuredRpc(
      _client,
      operation: 'set_thread_mute',
      params: {
        'thread_id': threadId,
        'state': muted ? 'muted' : 'unmuted',
        'muted_until': null,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> setPin(
    String threadId,
    bool pinned,
    String idempotencyKey,
  ) async {
    await measuredRpc(
      _client,
      operation: 'set_thread_pin',
      params: {
        'thread_id': threadId,
        'pinned': pinned,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> setVisibility(String threadId, bool hidden, String key) async {
    await measuredRpc(
      _client,
      operation: 'set_thread_visibility',
      params: {'thread_id': threadId, 'hidden': hidden, 'idempotency_key': key},
    );
  }

  @override
  Future<void> leaveThread(String threadId, String key) async {
    await measuredRpc(
      _client,
      operation: 'leave_thread',
      params: {'thread_id': threadId, 'idempotency_key': key},
    );
  }

  @override
  Future<void> closeThread(String threadId, String reason, String key) async {
    await measuredRpc(
      _client,
      operation: 'close_thread',
      params: {'thread_id': threadId, 'reason': reason, 'idempotency_key': key},
    );
  }

  @override
  Future<String> requestThreadErasure(
    String threadId,
    String reason,
    String key,
  ) async =>
      (await measuredRpc(
            _client,
            operation: 'request_thread_erasure',
            params: {
              'thread_id': threadId,
              'reason': reason,
              'idempotency_key': key,
            },
          ))
          as String;

  @override
  Future<MessagingPreferences> getPreferences() async =>
      MessagingPreferences.fromJson(
        await _client.schema('api').rpc<Object?>('get_messaging_preferences'),
      );

  @override
  Future<void> setPushEnabled(bool enabled, String idempotencyKey) async {
    await measuredRpc(
      _client,
      operation: 'set_messaging_push',
      params: {'enabled': enabled, 'idempotency_key': idempotencyKey},
    );
  }

  @override
  Future<StagedMessageFile> stageFile(
    String threadId,
    String name,
    String mimeType,
    Uint8List bytes,
  ) async {
    final value = await measuredRpc(
      _client,
      operation: 'stage_message_file',
      params: {
        'thread_id': threadId,
        'file_name': name,
        'mime_type': mimeType,
        'size_bytes': bytes.length,
      },
    );
    final staged = StagedMessageFile.fromJson(
      Map<String, dynamic>.from(value! as Map),
    );
    await _client.storage
        .from(staged.bucket)
        .uploadBinary(
          staged.objectKey,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return staged;
  }

  @override
  Future<List<MessageFile>> listFiles(String threadId) async =>
      (await _client
              .schema('api')
              .rpc<List<dynamic>>(
                'list_message_files',
                params: {'thread_id': threadId},
              ))
          .whereType<Map<String, dynamic>>()
          .map(MessageFile.fromJson)
          .toList();
  @override
  Future<String> signedFileUrl(String fileId) async {
    final value = await _client
        .schema('api')
        .rpc<Object?>('authorize_message_file', params: {'file_id': fileId});
    if (value is! Map ||
        value['bucket_id'] != 'message-files' ||
        value['object_key'] is! String ||
        value['expires_in_seconds'] != 120) {
      throw const FormatException('Invalid file authorization response.');
    }
    return _client.storage
        .from(value['bucket_id']! as String)
        .createSignedUrl(value['object_key']! as String, 120);
  }

  @override
  Future<void> recall(String id, int revision, String key) async {
    await measuredRpc(
      _client,
      operation: 'recall_message',
      params: {
        'message_id': id,
        'expected_revision': revision,
        'idempotency_key': key,
      },
    );
  }

  @override
  Future<void> report(String id, String reason, String key) async {
    await measuredRpc(
      _client,
      operation: 'report_message',
      params: {'message_id': id, 'reason_code': reason, 'idempotency_key': key},
    );
  }

  @override
  Future<List<CrossClubLeader>> searchLeaders(String query) async =>
      (await _client
              .schema('api')
              .rpc<List<dynamic>>(
                'list_cross_club_leaders',
                params: {'query': query},
              ))
          .whereType<Map<String, dynamic>>()
          .map(CrossClubLeader.fromJson)
          .toList();
  @override
  Future<void> requestContact(
    String id,
    String reason,
    String text,
    String key,
  ) async {
    await measuredRpc(
      _client,
      operation: 'request_cross_club_contact',
      params: {
        'target_leader_id': id,
        'reason_code': reason,
        'request_text': text,
        'idempotency_key': key,
      },
    );
  }

  @override
  Future<List<ContactRequest>> listRequests() async =>
      (await _client.schema('api').rpc<List<dynamic>>('list_contact_requests'))
          .whereType<Map<String, dynamic>>()
          .map(ContactRequest.fromJson)
          .toList();
  @override
  Future<void> decideRequest(String id, String decision, String key) async {
    await measuredRpc(
      _client,
      operation: 'decide_contact_request',
      params: {'request_id': id, 'decision': decision, 'idempotency_key': key},
    );
  }

  @override
  Future<NotificationCenter> listNotifications() async =>
      NotificationCenter.fromJson(
        await _client.schema('api').rpc<Object?>('list_notification_center'),
      );

  @override
  Stream<void> watchNotificationInvalidations() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;
    Future<void> start() async {
      try {
        final profileId = _client.auth.currentUser?.id;
        if (profileId == null) {
          throw StateError('Unauthenticated notification center.');
        }
        await _client.realtime.setAuth(
          _client.auth.currentSession?.accessToken,
        );
        channel = _client.channel(
          'notification:center:$profileId',
          opts: const RealtimeChannelConfig(private: true),
        );
        channel!
            .onBroadcast(
              event: 'invalidate',
              callback: (_) {
                if (!controller.isClosed) controller.add(null);
              },
            )
            .subscribe();
      } catch (_) {
        if (!controller.isClosed) {
          controller.addError(StateError('Notification sync unavailable.'));
        }
      }
    }

    Future<void> stop() async {
      final current = channel;
      if (current != null) await _client.removeChannel(current);
    }

    controller = StreamController<void>(onListen: start, onCancel: stop);
    return controller.stream;
  }

  @override
  Future<void> setNotificationState(String id, String state, String key) async {
    await measuredRpc(
      _client,
      operation: 'set_notification_state',
      params: {'notification_id': id, 'state': state, 'idempotency_key': key},
    );
  }

  @override
  Future<void> markAllNotificationsRead(String key) async {
    await measuredRpc(
      _client,
      operation: 'mark_all_notifications_read',
      params: {'idempotency_key': key},
    );
  }
}
