import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/training/training_models.dart';

/// Where a pass comes from: your own training projects, your clubs'
/// library, TeamZone's library, or a link someone sent.
enum TrainingPassSource {
  mine('Mina pass'),
  club('Klubbens'),
  teamzone('TeamZone'),
  link('Delad länk');

  const TrainingPassSource(this.label);
  final String label;

  static TrainingPassSource from(Object? value) => switch (value) {
    'club' => club,
    'teamzone' => teamzone,
    'link' => link,
    _ => mine,
  };
}

/// A pass or a single exercise in Tacticsboard's library, in the form the
/// training session takes it in: its exercises in order.
class TrainingPass {
  const TrainingPass({
    required this.source,
    required this.id,
    required this.title,
    required this.exercises,
    this.single = false,
    this.theme = '',
    this.goal = '',
    this.author,
    this.updatedAt,
    this.mine = false,
  });
  factory TrainingPass.fromJson(Map<String, dynamic> json) {
    final source = TrainingPassSource.from(json['source']);
    final id = json['id'] as String? ?? '';
    return TrainingPass(
      source: source,
      id: id,
      title: json['title'] as String? ?? '',
      single: json['kind'] == 'exercise',
      theme: json['theme'] as String? ?? '',
      goal: json['goal'] as String? ?? '',
      author: json['author'] as String?,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      mine: json['mine'] == true,
      exercises: [
        for (final exercise
            in (json['exercises'] as List? ?? const []).whereType<Map>())
          TrainingBlock.fromJson({
            ...Map<String, dynamic>.from(exercise),
            // Taken from the library, the block keeps its origin; a link's
            // pass is copied into your library first.
            'source_kind': source == TrainingPassSource.link
                ? 'own'
                : 'library',
            'source_id': source == TrainingPassSource.link ? null : id,
          }),
      ],
    );
  }
  final TrainingPassSource source;
  final String id, title, theme, goal;
  final String? author;
  final DateTime? updatedAt;
  final List<TrainingBlock> exercises;

  /// A single exercise rather than a whole pass.
  final bool single;

  /// Behind a link: whether you sent it yourself.
  final bool mine;

  int get minutes => exercises.fold(0, (sum, block) => sum + block.minutes);
}

/// What a session is saved as for you: your pass, whether it is shared with
/// a club, and its link.
class TrainingPassState {
  const TrainingPassState({
    required this.title,
    this.updatedAt,
    this.version,
    this.clubName,
    this.link,
  });
  factory TrainingPassState.fromJson(Map<String, dynamic> json) =>
      TrainingPassState(
        title: json['title'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
        version: (json['version'] as num?)?.toInt(),
        clubName: json['club_name'] as String?,
        link: json['link'] as String?,
      );
  final String title;
  final DateTime? updatedAt;
  final int? version;
  final String? clubName, link;

  /// The address to send: the app opens the pass from it.
  static Uri linkUri(String token) =>
      Uri.parse('https://app.teamzoneapp.se/pass/$token');
}

/// Saving a session as a pass in Tacticsboard's library, sharing it with
/// the club or by link, and taking passes into a session.
abstract interface class TrainingPassServices {
  /// The session's pass, or null when you have not saved it.
  Future<TrainingPassState?> passState(String eventId);

  /// Saves the session as last saved as your pass; with [club] it is shared
  /// with the event's club, with [link] it gets a link.
  Future<TrainingPassState> savePass({
    required String eventId,
    required String title,
    bool club = false,
    bool link = false,
  });

  /// Withdraws the session's pass link.
  Future<TrainingPassState?> deleteLink(String eventId);

  Future<List<TrainingPass>> listPasses(
    TrainingPassSource source, {
    String search = '',
  });

  /// The pass behind a link.
  Future<TrainingPass> openLink(String token);

  /// Copies the pass behind a link into your library.
  Future<TrainingPass> copyLink(String token);

  /// A short link of your own to the board linked to a saved block.
  Future<String> openBlockBoard(String blockId);
}

/// Training services that also handle passes.
abstract interface class TrainingPassSourceServices {
  TrainingPassServices get passes;
}

class SupabaseTrainingPassServices implements TrainingPassServices {
  SupabaseTrainingPassServices(this._client);
  final SupabaseClient _client;

  Future<Object?> _rpc(String name, Map<String, Object?> params) => _client
      .schema('api')
      .rpc<Object?>(name, params: params)
      .timeout(const Duration(seconds: 15));

  static TrainingPassState? _state(Object? value) =>
      value is Map<String, dynamic> ? TrainingPassState.fromJson(value) : null;

  static TrainingPass _pass(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid training pass.');
    }
    return TrainingPass.fromJson(value);
  }

  @override
  Future<TrainingPassState?> passState(String eventId) async => _state(
    await _rpc('get_training_pass_state', {'target_event_id': eventId}),
  );

  @override
  Future<TrainingPassState> savePass({
    required String eventId,
    required String title,
    bool club = false,
    bool link = false,
  }) async {
    final state = _state(
      await _rpc('save_training_pass', {
        'target_event_id': eventId,
        'pass_title': title,
        'to_club': club,
        'with_link': link,
      }),
    );
    if (state == null) throw const FormatException('Invalid training pass.');
    return state;
  }

  @override
  Future<TrainingPassState?> deleteLink(String eventId) async => _state(
    await _rpc('delete_training_pass_link', {'target_event_id': eventId}),
  );

  @override
  Future<List<TrainingPass>> listPasses(
    TrainingPassSource source, {
    String search = '',
  }) async {
    final value = await _rpc('list_training_passes', {
      'pass_source': source.name,
      'search_text': search,
    });
    return [
      for (final item in (value as List? ?? const []).whereType<Map>())
        TrainingPass.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  @override
  Future<TrainingPass> openLink(String token) async =>
      _pass(await _rpc('get_training_pass_link', {'link_token': token}));

  @override
  Future<TrainingPass> copyLink(String token) async =>
      _pass(await _rpc('copy_training_pass_link', {'link_token': token}));

  @override
  Future<String> openBlockBoard(String blockId) async {
    final path = await _rpc('open_training_block_board', {
      'target_block_id': blockId,
    });
    if (path is! String) throw const FormatException('Invalid board link.');
    return path;
  }
}
