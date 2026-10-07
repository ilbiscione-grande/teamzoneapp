import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/core/supabase/measured_rpc.dart';
import 'package:teamzone_app/src/features/publication/editorial_models.dart';

abstract interface class EditorialServices {
  Future<Map<String, dynamic>> getTeamEventVisibility(String teamId);
  Future<void> setTeamEventVisibility({
    required String teamId,
    required bool showResults,
    required bool showTraining,
    required bool showMatches,
    required int expectedRevision,
  });
  Future<Map<String, dynamic>> getPublicationSelfService(String clubId);
  Future<void> configurePublication({
    required String clubId,
    required String aggregateType,
    required String aggregateId,
    required String mode,
    required String slug,
    required List<String> fields,
    String? locality,
    String? description,
    String? ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<void> requestTeamPublication({
    required String clubId,
    required String teamId,
    required String message,
  });
  Future<void> decideTeamPublication({
    required String requestId,
    required bool approve,
  });
  Future<DomainManagement> getDomainManagement(String clubId);
  Future<DomainRequestResult> requestDomain({
    required String clubId,
    required String kind,
    required String hostname,
    required String idempotencyKey,
  });
  Future<void> setCanonicalDomain({required String clubId, String? domainId});
  Future<PublicationManagement> getPublicationManagement(String clubId);
  Future<void> configureEvent({
    required String eventId,
    required String state,
    String? publicTitle,
    required bool publishLocation,
    bool publishResult = false,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<void> savePartner({
    required String clubId,
    String? partnerId,
    required String name,
    String? websiteUrl,
    required String state,
    required int sortOrder,
    required int expectedRevision,
    required String idempotencyKey,
  });
  Future<List<EditorialArticle>> listArticles(String clubId);
  Future<EditorialArticle> getArticle(String articleId);

  /// The saved article's id and revision; null if the server did not say.
  Future<EditorialSaveResult?> saveArticle(EditorialSaveInput input);
  Future<void> transition({
    required String articleId,
    required String state,
    DateTime? publishAt,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// Uploads a news image privately (JPEG, PNG or WebP); returns its asset
  /// id. It is published only after public-media-worker has processed it.
  Future<String> uploadNewsImage({
    required String clubId,
    required Uint8List bytes,
    required String mimeType,
  });

  /// Sets (or with a null [assetId] removes) the hero image; returns the new
  /// article revision.
  Future<int> setArticleHero({
    required String articleId,
    required String? assetId,
    required String? alt,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// Asks the worker to process pending images now; a missed call is picked
  /// up by the next one.
  Future<void> startImageProcessing();
}

class UnconfiguredEditorialServices implements EditorialServices {
  const UnconfiguredEditorialServices();
  Future<T> _fail<T>() =>
      Future.error(StateError('Editorial backend is not configured.'));
  @override
  Future<Map<String, dynamic>> getTeamEventVisibility(String teamId) => _fail();
  @override
  Future<void> setTeamEventVisibility({
    required String teamId,
    required bool showResults,
    required bool showTraining,
    required bool showMatches,
    required int expectedRevision,
  }) => _fail();
  @override
  Future<Map<String, dynamic>> getPublicationSelfService(String clubId) =>
      _fail();
  @override
  Future<void> configurePublication({
    required String clubId,
    required String aggregateType,
    required String aggregateId,
    required String mode,
    required String slug,
    required List<String> fields,
    String? locality,
    String? description,
    String? ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> requestTeamPublication({
    required String clubId,
    required String teamId,
    required String message,
  }) => _fail();
  @override
  Future<void> decideTeamPublication({
    required String requestId,
    required bool approve,
  }) => _fail();
  @override
  Future<List<EditorialArticle>> listArticles(String clubId) => _fail();
  @override
  Future<DomainManagement> getDomainManagement(String clubId) => _fail();
  @override
  Future<DomainRequestResult> requestDomain({
    required String clubId,
    required String kind,
    required String hostname,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> setCanonicalDomain({required String clubId, String? domainId}) =>
      _fail();
  @override
  Future<PublicationManagement> getPublicationManagement(String clubId) =>
      _fail();
  @override
  Future<void> configureEvent({
    required String eventId,
    required String state,
    String? publicTitle,
    required bool publishLocation,
    bool publishResult = false,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> savePartner({
    required String clubId,
    String? partnerId,
    required String name,
    String? websiteUrl,
    required String state,
    required int sortOrder,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<EditorialArticle> getArticle(String articleId) => _fail();
  @override
  Future<EditorialSaveResult?> saveArticle(EditorialSaveInput input) => _fail();
  @override
  Future<void> transition({
    required String articleId,
    required String state,
    DateTime? publishAt,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<String> uploadNewsImage({
    required String clubId,
    required Uint8List bytes,
    required String mimeType,
  }) => _fail();
  @override
  Future<int> setArticleHero({
    required String articleId,
    required String? assetId,
    required String? alt,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<void> startImageProcessing() async {}
}

class SupabaseEditorialServices implements EditorialServices {
  SupabaseEditorialServices(this._client);
  final SupabaseClient _client;
  @override
  Future<Map<String, dynamic>> getTeamEventVisibility(String teamId) async =>
      Map<String, dynamic>.from(
        await _client
                .schema('api')
                .rpc('get_team_event_visibility', params: {'team_id': teamId})
            as Map,
      );
  @override
  Future<void> setTeamEventVisibility({
    required String teamId,
    required bool showResults,
    required bool showTraining,
    required bool showMatches,
    required int expectedRevision,
  }) async {
    await _client
        .schema('api')
        .rpc(
          'set_team_event_visibility_v2',
          params: {
            'team_id': teamId,
            'show_results': showResults,
            'show_training': showTraining,
            'show_matches': showMatches,
            'expected_revision': expectedRevision,
          },
        );
  }

  Future<Object?> _query(String name, Map<String, Object?> params) =>
      _client.schema('api').rpc<Object?>(name, params: params);

  @override
  Future<Map<String, dynamic>> getPublicationSelfService(String clubId) async {
    final value = await _query('get_publication_self_service', {
      'club_id': clubId,
    });
    if (value is! Map) {
      throw const FormatException('Invalid publication settings.');
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> configurePublication({
    required String clubId,
    required String aggregateType,
    required String aggregateId,
    required String mode,
    required String slug,
    required List<String> fields,
    String? locality,
    String? description,
    String? ageClass,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    await measuredRpc(
      _client,
      operation: 'configure_publication_v2',
      params: {
        'club_id': clubId,
        'aggregate_type': aggregateType,
        'aggregate_id': aggregateId,
        'mode': mode,
        'slug': slug,
        'fields': fields,
        'locality': locality,
        'description': description,
        'age_class': ageClass,
        'policy_version': 'pub02-self-service-v1',
        'confirmation_expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 365))
            .toIso8601String(),
        'expected_revision': expectedRevision,
        'idempotency_key': idempotencyKey,
      },
    );
  }

  @override
  Future<void> requestTeamPublication({
    required String clubId,
    required String teamId,
    required String message,
  }) async {
    await measuredRpc(
      _client,
      operation: 'request_team_publication',
      params: {'club_id': clubId, 'team_id': teamId, 'message': message},
    );
  }

  @override
  Future<void> decideTeamPublication({
    required String requestId,
    required bool approve,
  }) async {
    await measuredRpc(
      _client,
      operation: 'decide_team_publication',
      params: {'request_id': requestId, 'approve': approve, 'note': ''},
    );
  }

  @override
  Future<List<EditorialArticle>> listArticles(String clubId) async {
    final value = await _query('list_editorial_articles', {'club_id': clubId});
    if (value is! List) throw const FormatException('Invalid editorial list.');
    return value
        .whereType<Map>()
        .map((row) => EditorialArticle.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  @override
  Future<DomainManagement> getDomainManagement(String clubId) async {
    final value = await _query('get_publication_domains', {'club_id': clubId});
    if (value is! Map) {
      throw const FormatException('Invalid domain management.');
    }
    return DomainManagement.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<DomainRequestResult> requestDomain({
    required String clubId,
    required String kind,
    required String hostname,
    required String idempotencyKey,
  }) async {
    final value = await measuredRpc(
      _client,
      operation: 'request_publication_domain',
      params: {
        'club_id': clubId,
        'kind': kind,
        'hostname': hostname,
        'idempotency_key': idempotencyKey,
      },
    );
    if (value is! Map) throw const FormatException('Invalid domain request.');
    return DomainRequestResult.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> setCanonicalDomain({required String clubId, String? domainId}) =>
      measuredRpc(
        _client,
        operation: 'set_canonical_publication_domain',
        params: {'club_id': clubId, 'domain_id': domainId},
      );

  @override
  Future<PublicationManagement> getPublicationManagement(String clubId) async {
    final value = await _query('get_publication_management', {
      'club_id': clubId,
    });
    if (value is! Map) {
      throw const FormatException('Invalid publication management.');
    }
    return PublicationManagement.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> configureEvent({
    required String eventId,
    required String state,
    String? publicTitle,
    required bool publishLocation,
    bool publishResult = false,
    required int expectedRevision,
    required String idempotencyKey,
  }) => measuredRpc(
    _client,
    operation: 'configure_event_publication',
    params: {
      'event_id': eventId,
      'state': state,
      'public_title': publicTitle,
      'publish_location': publishLocation,
      if (publishResult) 'publish_result': true,
      'expected_revision': expectedRevision,
      'idempotency_key': idempotencyKey,
    },
  );

  @override
  Future<void> savePartner({
    required String clubId,
    String? partnerId,
    required String name,
    String? websiteUrl,
    required String state,
    required int sortOrder,
    required int expectedRevision,
    required String idempotencyKey,
  }) => measuredRpc(
    _client,
    operation: 'save_public_partner',
    params: {
      'club_id': clubId,
      'partner_id': partnerId,
      'name': name,
      'website_url': websiteUrl,
      'logo_asset_id': null,
      'state': state,
      'sort_order': sortOrder,
      'expected_revision': expectedRevision,
      'idempotency_key': idempotencyKey,
    },
  );

  @override
  Future<EditorialArticle> getArticle(String articleId) async {
    final value = await _query('get_editorial_article', {
      'article_id': articleId,
    });
    if (value is! Map) {
      throw const FormatException('Invalid editorial article.');
    }
    return EditorialArticle.fromJson(Map<String, dynamic>.from(value));
  }

  @override
  Future<EditorialSaveResult?> saveArticle(EditorialSaveInput input) async {
    final value = await measuredRpc(
      _client,
      operation: 'save_editorial_article',
      params: {
        'club_id': input.clubId,
        'article_id': input.articleId,
        'slug': input.slug,
        'title': input.title,
        'summary': input.summary,
        'blocks': input.blocks.map((block) => block.toJson()).toList(),
        'author_label': input.authorLabel,
        'publish_to_club': input.publishToClub,
        'team_ids': input.teamIds.toList(),
        'expected_revision': input.expectedRevision,
        'idempotency_key': input.idempotencyKey,
      },
    );
    if (value is! Map ||
        value['article_id'] is! String ||
        value['revision'] is! num) {
      return null;
    }
    return EditorialSaveResult(
      articleId: value['article_id'] as String,
      revision: (value['revision'] as num).toInt(),
    );
  }

  @override
  Future<String> uploadNewsImage({
    required String clubId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final staged = await _query('stage_public_media', {
      'club_id': clubId,
      'purpose': 'editorial_hero',
      'content_type': mimeType,
      'size_bytes': bytes.length,
    });
    if (staged is! Map ||
        staged['bucket_id'] != 'public-media-source' ||
        staged['object_key'] is! String ||
        staged['asset_id'] is! String) {
      throw const FormatException('Invalid staged news image.');
    }
    await _client.storage
        .from('public-media-source')
        .uploadBinary(
          staged['object_key'] as String,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return staged['asset_id'] as String;
  }

  @override
  Future<int> setArticleHero({
    required String articleId,
    required String? assetId,
    required String? alt,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _query('set_editorial_article_hero', {
      'article_id': articleId,
      'asset_id': assetId,
      'alt': alt,
      'expected_revision': expectedRevision,
      'idempotency_key': idempotencyKey,
    });
    if (value is! Map || value['revision'] is! num) {
      throw const FormatException('Invalid hero image response.');
    }
    return (value['revision'] as num).toInt();
  }

  @override
  Future<void> startImageProcessing() async {
    try {
      await _client.functions.invoke('public-media-worker', body: {});
    } catch (_) {
      // Processed by a later call; the image stays private until then.
    }
  }

  @override
  Future<void> transition({
    required String articleId,
    required String state,
    DateTime? publishAt,
    required int expectedRevision,
    required String idempotencyKey,
  }) async => measuredRpc(
    _client,
    operation: 'transition_editorial_article',
    params: {
      'article_id': articleId,
      'state': state,
      'publish_at': publishAt?.toUtc().toIso8601String(),
      'expected_revision': expectedRevision,
      'idempotency_key': idempotencyKey,
    },
  );
}
