class EditorialBlock {
  const EditorialBlock({required this.type, required this.text, this.href});
  final String type;
  final String text;
  final String? href;

  Map<String, Object?> toJson() => {
    'type': type,
    'text': text,
    if (href != null) 'href': href,
  };

  factory EditorialBlock.fromJson(Map<String, dynamic> json) => EditorialBlock(
    type: json['type'] as String,
    text: json['text'] as String,
    href: json['href'] as String?,
  );
}

class EditorialArticle {
  const EditorialArticle({
    required this.id,
    required this.slug,
    required this.title,
    required this.blocks,
    required this.state,
    required this.publishToClub,
    required this.teamIds,
    required this.revision,
    required this.mediaStatus,
    this.summary,
    this.authorLabel,
    this.publishAt,
  });

  final String id, slug, title, state, mediaStatus;
  final String? summary, authorLabel;
  final List<EditorialBlock> blocks;
  final bool publishToClub;
  final Set<String> teamIds;
  final int revision;
  final DateTime? publishAt;

  factory EditorialArticle.fromJson(Map<String, dynamic> json) =>
      EditorialArticle(
        id: json['id'] as String,
        slug: json['slug'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String?,
        blocks: (json['body_blocks'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  EditorialBlock.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(growable: false),
        state: json['state'] as String,
        publishAt: DateTime.tryParse(json['publish_at'] as String? ?? ''),
        authorLabel: json['author_label'] as String?,
        publishToClub: json['publish_to_club'] as bool? ?? true,
        teamIds: (json['teams'] as List? ?? const [])
            .whereType<String>()
            .toSet(),
        revision: (json['revision'] as num).toInt(),
        mediaStatus: json['media_status'] as String? ?? 'not_configured',
      );
}

class EditorialSaveInput {
  const EditorialSaveInput({
    required this.clubId,
    required this.slug,
    required this.title,
    required this.blocks,
    required this.publishToClub,
    required this.teamIds,
    required this.idempotencyKey,
    this.articleId,
    this.summary,
    this.authorLabel,
    this.expectedRevision,
  });
  final String clubId, slug, title, idempotencyKey;
  final String? articleId, summary, authorLabel;
  final List<EditorialBlock> blocks;
  final bool publishToClub;
  final Set<String> teamIds;
  final int? expectedRevision;
}

class PublicEventItem {
  const PublicEventItem({
    required this.id,
    required this.teamName,
    required this.title,
    required this.eventType,
    required this.startsAt,
    required this.publicationState,
    required this.revision,
    this.publicTitle,
    this.publishLocation = false,
  });
  final String id, teamName, title, eventType, publicationState;
  final DateTime startsAt;
  final int revision;
  final String? publicTitle;
  final bool publishLocation;
  factory PublicEventItem.fromJson(Map<String, dynamic> json) =>
      PublicEventItem(
        id: json['id'] as String,
        teamName: json['team_name'] as String,
        title: json['title'] as String,
        eventType: json['event_type'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        publicationState: json['publication_state'] as String,
        revision: (json['revision'] as num).toInt(),
        publicTitle: json['public_title'] as String?,
        publishLocation: json['publish_location'] as bool? ?? false,
      );
}

class PublicPartnerItem {
  const PublicPartnerItem({
    required this.id,
    required this.name,
    required this.state,
    required this.sortOrder,
    required this.revision,
    required this.mediaStatus,
    this.websiteUrl,
  });
  final String id, name, state, mediaStatus;
  final String? websiteUrl;
  final int sortOrder, revision;
  factory PublicPartnerItem.fromJson(Map<String, dynamic> json) =>
      PublicPartnerItem(
        id: json['id'] as String,
        name: json['name'] as String,
        state: json['state'] as String,
        sortOrder: (json['sort_order'] as num).toInt(),
        revision: (json['revision'] as num).toInt(),
        mediaStatus: json['media_status'] as String? ?? 'not_configured',
        websiteUrl: json['website_url'] as String?,
      );
}

class PublicationManagement {
  const PublicationManagement({
    required this.events,
    required this.partners,
    required this.canManagePartners,
    required this.mediaUploadStatus,
  });
  final List<PublicEventItem> events;
  final List<PublicPartnerItem> partners;
  final bool canManagePartners;
  final String mediaUploadStatus;
  factory PublicationManagement.fromJson(Map<String, dynamic> json) =>
      PublicationManagement(
        events: (json['events'] as List? ?? const [])
            .whereType<Map>()
            .map((v) => PublicEventItem.fromJson(Map<String, dynamic>.from(v)))
            .toList(),
        partners: (json['partners'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (v) => PublicPartnerItem.fromJson(Map<String, dynamic>.from(v)),
            )
            .toList(),
        canManagePartners: json['can_manage_partners'] as bool? ?? false,
        mediaUploadStatus:
            json['media_upload_status'] as String? ?? 'not_configured',
      );
}

class PublicationDomain {
  const PublicationDomain({
    required this.id,
    required this.kind,
    required this.hostname,
    required this.state,
    required this.commercialState,
    required this.tlsState,
    required this.canonical,
    required this.verificationRecord,
    required this.revision,
    this.verificationExpiresAt,
    this.lastErrorCode,
  });
  final String id,
      kind,
      hostname,
      state,
      commercialState,
      tlsState,
      verificationRecord;
  final bool canonical;
  final int revision;
  final DateTime? verificationExpiresAt;
  final String? lastErrorCode;
  factory PublicationDomain.fromJson(Map<String, dynamic> json) =>
      PublicationDomain(
        id: json['id'] as String,
        kind: json['kind'] as String,
        hostname: json['hostname'] as String,
        state: json['state'] as String,
        commercialState: json['commercial_state'] as String,
        tlsState: json['tls_state'] as String,
        canonical: json['canonical'] as bool? ?? false,
        verificationRecord: json['verification_record'] as String,
        revision: (json['revision'] as num).toInt(),
        verificationExpiresAt: DateTime.tryParse(
          json['verification_expires_at'] as String? ?? '',
        ),
        lastErrorCode: json['last_error_code'] as String?,
      );
}

class DomainManagement {
  const DomainManagement({
    required this.pathAddress,
    required this.clubPublished,
    required this.customDomainRequestAvailable,
    required this.teamzoneSubdomainAvailable,
    required this.domains,
  });
  final String? pathAddress;
  final bool clubPublished,
      customDomainRequestAvailable,
      teamzoneSubdomainAvailable;
  final List<PublicationDomain> domains;
  factory DomainManagement.fromJson(Map<String, dynamic> json) =>
      DomainManagement(
        pathAddress: json['path_address'] as String?,
        clubPublished: json['club_published'] as bool? ?? false,
        customDomainRequestAvailable:
            json['custom_domain_request_available'] as bool? ?? false,
        teamzoneSubdomainAvailable:
            json['teamzone_subdomain_available'] as bool? ?? false,
        domains: (json['domains'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  PublicationDomain.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
      );
}

class DomainRequestResult {
  const DomainRequestResult({
    required this.hostname,
    required this.verificationRecord,
    this.verificationToken,
  });
  final String hostname, verificationRecord;
  final String? verificationToken;
  factory DomainRequestResult.fromJson(Map<String, dynamic> json) =>
      DomainRequestResult(
        hostname: json['hostname'] as String,
        verificationRecord: json['verification_record'] as String,
        verificationToken: json['verification_token'] as String?,
      );
}
