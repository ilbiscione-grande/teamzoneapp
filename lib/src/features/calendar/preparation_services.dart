import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/calendar/preparation_models.dart';

abstract interface class EventPreparationServices {
  Future<EventPreparation> getPreparation(String eventId);

  /// Creates ([expectedRevision] 0) or edits an item. [itemId] is generated
  /// by the caller, so a retry after a lost response never duplicates it.
  Future<PreparationItem> saveItem({
    required String eventId,
    required String itemId,
    required String kind,
    required String label,
    String? assigneePersonId,
    required int expectedRevision,
  });
  Future<PreparationItem> setItemDone(String itemId, bool done);
  Future<void> deleteItem(String eventId, String itemId);
  Future<void> reorderItems(String eventId, String kind, List<String> itemIds);
  Future<PreparationNote> saveNote(
    String eventId,
    String body,
    int expectedRevision,
  );
  Future<List<String>> listSuggestions(String eventId, String kind);

  /// Stages, uploads and finalizes a file. Safe to call again with the same
  /// [fileId] after a failure.
  Future<void> uploadFile({
    required String eventId,
    required String fileId,
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String visibility,
    List<String> personIds,
  });
  Future<void> setFileVisibility({
    required String fileId,
    required String visibility,
    List<String> personIds,
    required int expectedRevision,
  });
  Future<void> deleteFile(String fileId);
  Future<String> signedFileUrl(String fileId);

  /// Invalidations for one event's preparation and match data (several
  /// leaders may work on the same event). Carries no data; refetch on event.
  Stream<void> watchEventLive(String eventId);
}

class UnconfiguredEventPreparationServices implements EventPreparationServices {
  const UnconfiguredEventPreparationServices();

  Future<T> _fail<T>() =>
      Future.error(StateError('Supabase is not configured.'));

  @override
  Future<EventPreparation> getPreparation(String eventId) => _fail();
  @override
  Future<PreparationItem> saveItem({
    required String eventId,
    required String itemId,
    required String kind,
    required String label,
    String? assigneePersonId,
    required int expectedRevision,
  }) => _fail();
  @override
  Future<PreparationItem> setItemDone(String itemId, bool done) => _fail();
  @override
  Future<void> deleteItem(String eventId, String itemId) => _fail();
  @override
  Future<void> reorderItems(
    String eventId,
    String kind,
    List<String> itemIds,
  ) => _fail();
  @override
  Future<PreparationNote> saveNote(
    String eventId,
    String body,
    int expectedRevision,
  ) => _fail();
  @override
  Future<List<String>> listSuggestions(String eventId, String kind) => _fail();
  @override
  Future<void> uploadFile({
    required String eventId,
    required String fileId,
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String visibility,
    List<String> personIds = const [],
  }) => _fail();
  @override
  Future<void> setFileVisibility({
    required String fileId,
    required String visibility,
    List<String> personIds = const [],
    required int expectedRevision,
  }) => _fail();
  @override
  Future<void> deleteFile(String fileId) => _fail();
  @override
  Future<String> signedFileUrl(String fileId) => _fail();
  @override
  Stream<void> watchEventLive(String eventId) => const Stream.empty();
}

class SupabaseEventPreparationServices implements EventPreparationServices {
  SupabaseEventPreparationServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) async {
    try {
      return await _client.schema('api').rpc<Object?>(name, params: params);
    } on PostgrestException catch (error) {
      if (error.code == '40001') throw const PreparationConflict();
      rethrow;
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid preparation response.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<EventPreparation> getPreparation(String eventId) async =>
      EventPreparation.fromJson(
        _map(await _rpc('get_event_preparation', {'p_event_id': eventId})),
      );

  @override
  Future<PreparationItem> saveItem({
    required String eventId,
    required String itemId,
    required String kind,
    required String label,
    String? assigneePersonId,
    required int expectedRevision,
  }) async => PreparationItem.fromJson(
    _map(
      await _rpc('save_event_preparation_item', {
        'p_event_id': eventId,
        'p_item_id': itemId,
        'p_kind': kind,
        'p_label': label,
        'p_assignee_person_id': assigneePersonId,
        'p_expected_revision': expectedRevision,
      }),
    ),
  );

  @override
  Future<PreparationItem> setItemDone(String itemId, bool done) async =>
      PreparationItem.fromJson(
        _map(
          await _rpc('set_event_preparation_item_done', {
            'p_item_id': itemId,
            'p_done': done,
          }),
        ),
      );

  @override
  Future<void> deleteItem(String eventId, String itemId) async {
    await _rpc('delete_event_preparation_item', {
      'p_event_id': eventId,
      'p_item_id': itemId,
    });
  }

  @override
  Future<void> reorderItems(
    String eventId,
    String kind,
    List<String> itemIds,
  ) async {
    await _rpc('reorder_event_preparation_items', {
      'p_event_id': eventId,
      'p_kind': kind,
      'p_item_ids': itemIds,
    });
  }

  @override
  Future<PreparationNote> saveNote(
    String eventId,
    String body,
    int expectedRevision,
  ) async => PreparationNote.fromJson(
    _map(
      await _rpc('save_event_preparation_note', {
        'p_event_id': eventId,
        'p_body': body,
        'p_expected_revision': expectedRevision,
      }),
    ),
  );

  @override
  Future<List<String>> listSuggestions(String eventId, String kind) async {
    final value = await _rpc('list_event_preparation_suggestions', {
      'p_event_id': eventId,
      'p_kind': kind,
    });
    return (value as List? ?? const []).whereType<String>().toList();
  }

  @override
  Future<void> uploadFile({
    required String eventId,
    required String fileId,
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required String visibility,
    List<String> personIds = const [],
  }) async {
    final staged = _map(
      await _rpc('stage_event_file', {
        'p_event_id': eventId,
        'p_file_id': fileId,
        'p_file_name': name,
        'p_mime_type': mimeType,
        'p_size_bytes': bytes.length,
        'p_visibility': visibility,
        'p_person_ids': visibility == FileVisibility.selected
            ? personIds
            : null,
      }),
    );
    if (staged['state'] == 'active') return;
    try {
      await _client.storage
          .from(staged['bucket_id'] as String)
          .uploadBinary(
            staged['object_key'] as String,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    } on StorageException catch (error) {
      // A previous attempt uploaded the object but lost the response;
      // finalize verifies the stored size either way.
      if (error.statusCode != '409' && error.statusCode != '400') rethrow;
    }
    await _rpc('finalize_event_file', {'p_file_id': fileId});
  }

  @override
  Future<void> setFileVisibility({
    required String fileId,
    required String visibility,
    List<String> personIds = const [],
    required int expectedRevision,
  }) async {
    await _rpc('set_event_file_visibility', {
      'p_file_id': fileId,
      'p_visibility': visibility,
      'p_person_ids': visibility == FileVisibility.selected ? personIds : null,
      'p_expected_revision': expectedRevision,
    });
  }

  @override
  Future<void> deleteFile(String fileId) async {
    final value = _map(await _rpc('delete_event_file', {'p_file_id': fileId}));
    // The row is already unreadable; removing the object is best effort.
    try {
      await _client.storage.from(value['bucket_id'] as String).remove([
        value['object_key'] as String,
      ]);
    } catch (_) {}
  }

  @override
  Future<String> signedFileUrl(String fileId) async {
    final value = _map(
      await _rpc('authorize_event_file', {'p_file_id': fileId}),
    );
    if (value['bucket_id'] != 'event-files' ||
        value['object_key'] is! String ||
        value['expires_in_seconds'] != 120) {
      throw const FormatException('Invalid file authorization response.');
    }
    return _client.storage
        .from('event-files')
        .createSignedUrl(value['object_key'] as String, 120);
  }

  @override
  Stream<void> watchEventLive(String eventId) {
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () async {
        try {
          await _client.realtime.setAuth(
            _client.auth.currentSession?.accessToken,
          );
          if (controller.isClosed) return;
          channel = _client.channel(
            'event:live:$eventId',
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
                // A reconnect may have missed invalidations: refetch.
                if (status == RealtimeSubscribeStatus.subscribed &&
                    !controller.isClosed) {
                  controller.add(null);
                }
              });
        } catch (_) {
          // Realtime is an optimization; explicit refresh still works.
        }
      },
      onCancel: () async {
        final current = channel;
        channel = null;
        if (current != null) await _client.removeChannel(current);
      },
    );
    return controller.stream;
  }
}
