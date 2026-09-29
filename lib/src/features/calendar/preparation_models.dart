/// Förberedelser v1: the small per-event workspace behind the
/// "Förberedelser" tab. Deliberately flat — focus, material, tasks and
/// agenda are all [PreparationItem]s distinguished by [PreparationItem.kind].
library;

abstract final class PreparationKind {
  static const focus = 'focus';
  static const material = 'material';
  static const task = 'task';
  static const agenda = 'agenda';
}

abstract final class FileVisibility {
  static const participants = 'participants';
  static const leaders = 'leaders';
  static const selected = 'selected';
}

class PreparationItem {
  const PreparationItem({
    required this.id,
    required this.kind,
    required this.label,
    this.done = false,
    this.assigneePersonId,
    this.assigneeName,
    this.position = 0,
    this.source = 'manual',
    this.sourceRef,
    this.revision = 1,
  });

  final String id, kind, label, source;
  final bool done;
  final String? assigneePersonId, assigneeName;

  /// Set when an entry was contributed by a future training/match module
  /// rather than typed here; v1 only ever writes `manual`.
  final String? sourceRef;
  final int position, revision;

  PreparationItem copyWith({bool? done}) => PreparationItem(
    id: id,
    kind: kind,
    label: label,
    done: done ?? this.done,
    assigneePersonId: assigneePersonId,
    assigneeName: assigneeName,
    position: position,
    source: source,
    sourceRef: sourceRef,
    revision: revision,
  );

  factory PreparationItem.fromJson(Map<String, dynamic> json) =>
      PreparationItem(
        id: json['id'] as String,
        kind: json['kind'] as String,
        label: json['label'] as String? ?? '',
        done: json['done'] == true,
        assigneePersonId: json['assignee_person_id'] as String?,
        assigneeName: json['assignee_name'] as String?,
        position: (json['position'] as num? ?? 0).toInt(),
        source: json['source'] as String? ?? 'manual',
        sourceRef: json['source_ref'] as String?,
        revision: (json['revision'] as num? ?? 1).toInt(),
      );
}

class PreparationNote {
  const PreparationNote({this.body = '', this.revision = 0});
  final String body;
  final int revision;

  factory PreparationNote.fromJson(Map<String, dynamic> json) =>
      PreparationNote(
        body: json['body'] as String? ?? '',
        revision: (json['revision'] as num? ?? 0).toInt(),
      );
}

class EventFile {
  const EventFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.visibility,
    required this.revision,
    required this.createdAt,
    this.viewerCount = 0,
    this.viewerIds = const [],
  });

  final String id, name, mimeType, visibility;
  final int sizeBytes, revision, viewerCount;
  final DateTime createdAt;

  /// Only filled for leaders; other viewers never learn who else a file
  /// was shared with.
  final List<String> viewerIds;

  factory EventFile.fromJson(Map<String, dynamic> json) => EventFile(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    mimeType: json['mime_type'] as String? ?? '',
    sizeBytes: (json['size_bytes'] as num? ?? 0).toInt(),
    visibility: json['visibility'] as String? ?? FileVisibility.participants,
    revision: (json['revision'] as num? ?? 1).toInt(),
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    viewerCount: (json['viewer_count'] as num? ?? 0).toInt(),
    viewerIds: (json['viewer_ids'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
  );
}

/// Which Förberedelser areas the viewer may edit. Each follows its own
/// capability: logistics (material, tasks, agenda, files, other notes),
/// training (focus, training notes) and match (match preparation note).
class PreparationPermissions {
  const PreparationPermissions({
    this.logistics = false,
    this.training = false,
    this.match = false,
  });
  const PreparationPermissions.all()
    : logistics = true,
      training = true,
      match = true;
  final bool logistics, training, match;

  factory PreparationPermissions.fromJson(Map<String, dynamic> json) =>
      PreparationPermissions(
        logistics: json['logistics'] == true,
        training: json['training'] == true,
        match: json['match'] == true,
      );
}

class EventPreparation {
  const EventPreparation({
    required this.eventId,
    required this.canEdit,
    this.items = const [],
    this.note = const PreparationNote(),
    this.files = const [],
    PreparationPermissions? permissions,
  }) : permissions =
           permissions ??
           (canEdit
               ? const PreparationPermissions.all()
               : const PreparationPermissions());

  final String eventId;
  final bool canEdit;
  final PreparationPermissions permissions;
  final List<PreparationItem> items;
  final PreparationNote note;
  final List<EventFile> files;

  List<PreparationItem> itemsOf(String kind) =>
      items.where((item) => item.kind == kind).toList()
        ..sort((a, b) => a.position.compareTo(b.position));

  EventPreparation copyWith({
    List<PreparationItem>? items,
    PreparationNote? note,
    List<EventFile>? files,
  }) => EventPreparation(
    eventId: eventId,
    canEdit: canEdit,
    items: items ?? this.items,
    note: note ?? this.note,
    files: files ?? this.files,
    permissions: permissions,
  );

  factory EventPreparation.fromJson(Map<String, dynamic> json) =>
      EventPreparation(
        eventId: json['event_id'] as String,
        canEdit: json['can_edit'] == true,
        permissions: json['permissions'] is Map<String, dynamic>
            ? PreparationPermissions.fromJson(
                json['permissions'] as Map<String, dynamic>,
              )
            : null,
        items: (json['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PreparationItem.fromJson)
            .toList(growable: false),
        note: json['note'] is Map<String, dynamic>
            ? PreparationNote.fromJson(json['note'] as Map<String, dynamic>)
            : const PreparationNote(),
        files: (json['files'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EventFile.fromJson)
            .toList(growable: false),
      );
}

/// Thrown when another leader changed the same item, note or file first.
class PreparationConflict implements Exception {
  const PreparationConflict();
}
