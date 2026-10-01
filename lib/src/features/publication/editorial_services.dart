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
  Future<void> saveArticle(EditorialSaveInput input);
  Future<void> transition({
    required String articleId,
    required String state,
    DateTime? publishAt,
    required int expectedRevision,
    required String idempotencyKey,
  });
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
  Future<void> saveArticle(EditorialSaveInput input) => _fail();
  @override
  Future<void> transition({
    required String articleId,
    required String state,
    DateTime? publishAt,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
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
  Future<void> saveArticle(EditorialSaveInput input) async => measuredRpc(
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
