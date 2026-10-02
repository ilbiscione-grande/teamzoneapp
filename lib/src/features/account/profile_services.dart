import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:teamzone_app/src/features/account/profile_models.dart';

/// Own profile, profile pictures, team members' contact details and
/// support-approved login email changes.
abstract interface class ProfileServices {
  Future<List<Map<String, dynamic>>> listPrivacySubjects();
  Future<Map<String, dynamic>> getAddressPrivacy(String profileId);
  Future<void> saveAddressPrivacyCommand(
    String command,
    Map<String, dynamic> values,
  );
  Future<List<ContactChangeRequest>> listContactChanges();
  Future<void> decideContactChange(String requestId, {required bool approve});
  Future<MyProfileDetails> getMyProfile();
  Future<int> updateMyProfile({
    required String displayName,
    required String? contactEmail,
    required String? phone,
    required String avatarAction,
    required String? street,
    required String? postalCode,
    required String? city,
    String? stagedAvatarId,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// Uploads a picture and returns its staged id for [updateMyProfile].
  Future<String> uploadAvatar({
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  });

  /// A short-lived address of a profile's picture, or null without one.
  Future<String?> avatarUrl(String profileId);

  /// Short-lived picture addresses of the team's current members, by club
  /// person id; members without a picture are left out.
  Future<Map<String, String>> teamAvatarUrls({
    required String clubId,
    required String teamId,
  });
  Future<PersonContact> getPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
  });
  Future<void> setPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
    required String? contactEmail,
    required String? phone,
  });
  Future<void> requestLoginEmailChange({
    required String newEmail,
    required String reason,
  });
  Future<void> cancelLoginEmailChange(String requestId);

  /// After support approval: starts the account's own email confirmation.
  Future<void> confirmLoginEmailChange(String newEmail);

  /// Marks an approved change done once the login email has changed.
  Future<String?> completeLoginEmailChange();
  Future<List<LoginEmailChange>> listLoginEmailChanges({String? state});
  Future<String> decideLoginEmailChange({
    required String requestId,
    required bool approve,
    required String note,
  });
  Future<void> updateMyAddress({
    required String? street,
    required String? postalCode,
    required String? city,
  });
  Future<void> setPersonAddress({
    required String clubId,
    required String teamId,
    required String personId,
    required String? street,
    required String? postalCode,
    required String? city,
  });
  Future<MemberCard> getMemberCard({
    required String clubId,
    required String teamId,
    required String personId,
  });

  /// A short-lived address of the club badge, or null without one.
  Future<String?> clubBadgeUrl(String clubId);

  /// Uploads and activates a new club badge (club administrators).
  Future<void> setClubBadge({
    required String clubId,
    required String mimeType,
    required Uint8List bytes,
  });
  Future<void> removeClubBadge(String clubId);

  /// The club's colours on its public pages (club administrators).
  Future<ClubColors> getClubColors(String clubId);
  Future<ClubColors> setClubColors({
    required String clubId,
    String? primary,
    String? accent,
  });
  Future<PersonStatistics> getPersonStatistics({
    required String clubId,
    required String teamId,
    required String personId,
  });

  /// Notes that you used the app today (for the active-day streak).
  Future<void> recordActivity();
}

class UnconfiguredProfileServices implements ProfileServices {
  @override
  Future<List<Map<String, dynamic>>> listPrivacySubjects() async => [];
  @override
  Future<Map<String, dynamic>> getAddressPrivacy(String profileId) => _fail();
  @override
  Future<void> saveAddressPrivacyCommand(
    String command,
    Map<String, dynamic> values,
  ) => _fail();
  @override
  Future<List<ContactChangeRequest>> listContactChanges() async => const [];
  @override
  Future<void> decideContactChange(String requestId, {required bool approve}) =>
      _fail();
  const UnconfiguredProfileServices();
  static Future<T> _fail<T>() =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<MyProfileDetails> getMyProfile() => _fail();
  @override
  Future<int> updateMyProfile({
    required String displayName,
    required String? contactEmail,
    required String? phone,
    required String avatarAction,
    required String? street,
    required String? postalCode,
    required String? city,
    String? stagedAvatarId,
    required int expectedRevision,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<String> uploadAvatar({
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  }) => _fail();
  @override
  Future<String?> avatarUrl(String profileId) async => null;
  @override
  Future<Map<String, String>> teamAvatarUrls({
    required String clubId,
    required String teamId,
  }) async => const {};
  @override
  Future<PersonContact> getPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => const PersonContact();
  @override
  Future<void> setPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
    required String? contactEmail,
    required String? phone,
  }) => _fail();
  @override
  Future<void> requestLoginEmailChange({
    required String newEmail,
    required String reason,
  }) => _fail();
  @override
  Future<void> cancelLoginEmailChange(String requestId) => _fail();
  @override
  Future<void> confirmLoginEmailChange(String newEmail) => _fail();
  @override
  Future<String?> completeLoginEmailChange() async => null;
  @override
  Future<List<LoginEmailChange>> listLoginEmailChanges({String? state}) =>
      _fail();
  @override
  Future<String> decideLoginEmailChange({
    required String requestId,
    required bool approve,
    required String note,
  }) => _fail();
  @override
  Future<void> updateMyAddress({
    required String? street,
    required String? postalCode,
    required String? city,
  }) => _fail();
  @override
  Future<void> setPersonAddress({
    required String clubId,
    required String teamId,
    required String personId,
    required String? street,
    required String? postalCode,
    required String? city,
  }) => _fail();
  @override
  Future<MemberCard> getMemberCard({
    required String clubId,
    required String teamId,
    required String personId,
  }) => _fail();
  @override
  Future<String?> clubBadgeUrl(String clubId) async => null;
  @override
  Future<void> setClubBadge({
    required String clubId,
    required String mimeType,
    required Uint8List bytes,
  }) => _fail();
  @override
  Future<void> removeClubBadge(String clubId) => _fail();
  @override
  Future<ClubColors> getClubColors(String clubId) async => const ClubColors();
  @override
  Future<ClubColors> setClubColors({
    required String clubId,
    String? primary,
    String? accent,
  }) => _fail();
  @override
  Future<PersonStatistics> getPersonStatistics({
    required String clubId,
    required String teamId,
    required String personId,
  }) => _fail();
  @override
  Future<void> recordActivity() async {}
}

class SupabaseProfileServices implements ProfileServices {
  @override
  Future<List<Map<String, dynamic>>> listPrivacySubjects() async =>
      ((await _rpc('list_address_privacy_subjects')) as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  @override
  Future<Map<String, dynamic>> getAddressPrivacy(String profileId) async =>
      Map<String, dynamic>.from(
        (await _rpc('get_address_privacy', {'target': profileId})) as Map,
      );
  @override
  Future<void> saveAddressPrivacyCommand(
    String command,
    Map<String, dynamic> values,
  ) async {
    if (!const {
      'save_profile_address',
      'delete_profile_address',
      'choose_club_address',
      'save_profile_privacy',
      'set_private_contact_grant',
    }.contains(command)) {
      throw ArgumentError.value(command);
    }
    await _rpc(command, values);
  }

  @override
  Future<List<ContactChangeRequest>> listContactChanges() async {
    final data = await _rpc('list_contact_change_requests', {});
    if (data is! List) throw const FormatException('Invalid contact requests.');
    return data
        .map(
          (item) => ContactChangeRequest.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> decideContactChange(
    String requestId, {
    required bool approve,
  }) async {
    await _rpc('decide_contact_change', {
      'target_request_id': requestId,
      'approve': approve,
    });
  }

  const SupabaseProfileServices(this._client);
  final SupabaseClient _client;

  static const _codes = [
    'invalid_email',
    'invalid_phone',
    'invalid_profile',
    'stale_revision',
    'avatar_not_uploaded',
    'invalid_avatar',
    'request_open',
    'same_email',
    'invalid_request',
    'invalid_note',
    'stale_request',
    'invalid_address',
    'invalid_badge',
    'badge_not_uploaded',
    'invalid_color',
    'club_admin_required',
  ];

  Future<T> _call<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      for (final code in _codes) {
        if (error.message.contains(code)) throw ProfileException(code);
      }
      rethrow;
    }
  }

  Future<Object?> _rpc(String name, [Map<String, dynamic>? params]) =>
      _call(() => _client.schema('api').rpc<Object?>(name, params: params));

  @override
  Future<MyProfileDetails> getMyProfile() async {
    final value = await _rpc('get_my_profile_details');
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Profile response is invalid.');
    }
    return MyProfileDetails.fromJson(value);
  }

  @override
  Future<int> updateMyProfile({
    required String displayName,
    required String? contactEmail,
    required String? phone,
    required String avatarAction,
    required String? street,
    required String? postalCode,
    required String? city,
    String? stagedAvatarId,
    required int expectedRevision,
    required String idempotencyKey,
  }) async {
    final value = await _rpc('update_my_profile_details_v2', {
      'new_display_name': displayName,
      'new_contact_email': contactEmail,
      'new_phone': phone,
      'new_street': street,
      'new_postal': postalCode,
      'new_city': city,
      'avatar_action': avatarAction,
      'staged_avatar_id': stagedAvatarId,
      'expected_revision': expectedRevision,
      'idempotency_key': idempotencyKey,
    });
    if (value is! num) throw const FormatException('Invalid revision.');
    return value.toInt();
  }

  @override
  Future<String> uploadAvatar({
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  }) async {
    final value = await _rpc('stage_profile_avatar', {
      'target_mime_type': mimeType,
      'target_size_bytes': bytes.length,
      'idempotency_key': idempotencyKey,
    });
    if (value is! Map<String, dynamic> ||
        value['bucket_id'] != 'profile-avatars' ||
        value['object_key'] is! String ||
        value['avatar_id'] is! String) {
      throw const FormatException('Invalid staged avatar.');
    }
    await _client.storage
        .from('profile-avatars')
        .uploadBinary(
          value['object_key'] as String,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    return value['avatar_id'] as String;
  }

  @override
  Future<Map<String, String>> teamAvatarUrls({
    required String clubId,
    required String teamId,
  }) async {
    final value = await _rpc('list_team_avatars', {
      'target_club_id': clubId,
      'target_team_id': teamId,
    });
    final keyByPerson = <String, String>{
      if (value is List)
        for (final item in value.whereType<Map<String, dynamic>>())
          if (item['person_id'] is String && item['object_key'] is String)
            item['person_id'] as String: item['object_key'] as String,
    };
    if (keyByPerson.isEmpty) return const {};
    final signed = await _client.storage
        .from('profile-avatars')
        .createSignedUrlsResult(keyByPerson.values.toSet().toList(), 3600);
    // A picture that cannot be signed is left out; the list shows initials.
    final urlByKey = {
      for (final item in signed.whereType<SignedUrlSuccess>())
        item.path: item.signedUrl,
    };
    return {
      for (final entry in keyByPerson.entries)
        entry.key: ?urlByKey[entry.value],
    };
  }

  @override
  Future<String?> avatarUrl(String profileId) async {
    final value = await _rpc('authorize_profile_avatar', {
      'target_profile_id': profileId,
    });
    if (value is! Map<String, dynamic> ||
        value['bucket_id'] != 'profile-avatars' ||
        value['object_key'] is! String) {
      return null;
    }
    return _client.storage
        .from('profile-avatars')
        .createSignedUrl(value['object_key'] as String, 3600);
  }

  @override
  Future<PersonContact> getPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    final value = await _rpc('get_person_contact', {
      'target_club_id': clubId,
      'target_team_id': teamId,
      'target_person_id': personId,
    });
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Contact response is invalid.');
    }
    return PersonContact.fromJson(value);
  }

  @override
  Future<void> setPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
    required String? contactEmail,
    required String? phone,
  }) => _rpc('set_person_contact', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'target_person_id': personId,
    'new_contact_email': contactEmail,
    'new_phone': phone,
  });

  @override
  Future<void> requestLoginEmailChange({
    required String newEmail,
    required String reason,
  }) => _rpc('request_login_email_change', {
    'new_email': newEmail,
    'new_reason': reason,
  });

  @override
  Future<void> cancelLoginEmailChange(String requestId) =>
      _rpc('cancel_login_email_change', {'target_request_id': requestId});

  @override
  Future<void> confirmLoginEmailChange(String newEmail) async {
    await _client.auth.updateUser(UserAttributes(email: newEmail));
  }

  @override
  Future<String?> completeLoginEmailChange() async =>
      await _rpc('complete_login_email_change') as String?;

  @override
  Future<List<LoginEmailChange>> listLoginEmailChanges({String? state}) async {
    final value = await _rpc('list_login_email_change_requests', {
      'target_state': state,
    });
    if (value is! List) {
      throw const FormatException('Email change list is invalid.');
    }
    return value
        .whereType<Map<String, dynamic>>()
        .map(LoginEmailChange.fromJson)
        .toList(growable: false);
  }

  @override
  Future<String> decideLoginEmailChange({
    required String requestId,
    required bool approve,
    required String note,
  }) async {
    final value = await _rpc('decide_login_email_change', {
      'target_request_id': requestId,
      'approve': approve,
      'note': note,
    });
    return value as String? ?? (approve ? 'approved' : 'rejected');
  }

  @override
  Future<void> updateMyAddress({
    required String? street,
    required String? postalCode,
    required String? city,
  }) => _rpc('update_my_address', {
    'new_street': street,
    'new_postal': postalCode,
    'new_city': city,
  });

  @override
  Future<void> setPersonAddress({
    required String clubId,
    required String teamId,
    required String personId,
    required String? street,
    required String? postalCode,
    required String? city,
  }) => _rpc('set_person_address', {
    'target_club_id': clubId,
    'target_team_id': teamId,
    'target_person_id': personId,
    'new_street': street,
    'new_postal': postalCode,
    'new_city': city,
  });

  @override
  Future<MemberCard> getMemberCard({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    final value = await _rpc('get_member_card', {
      'target_club_id': clubId,
      'target_team_id': teamId,
      'target_person_id': personId,
    });
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Member card response is invalid.');
    }
    return MemberCard.fromJson(value);
  }

  @override
  Future<String?> clubBadgeUrl(String clubId) async {
    final value = await _rpc('authorize_club_badge', {
      'target_club_id': clubId,
    });
    if (value is! Map<String, dynamic> ||
        value['bucket_id'] != 'club-badges' ||
        value['object_key'] is! String) {
      return null;
    }
    return _client.storage
        .from('club-badges')
        .createSignedUrl(value['object_key'] as String, 3600);
  }

  @override
  Future<void> setClubBadge({
    required String clubId,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final staged = await _rpc('stage_club_badge', {
      'target_club_id': clubId,
      'target_mime_type': mimeType,
      'target_size_bytes': bytes.length,
    });
    if (staged is! Map<String, dynamic> ||
        staged['bucket_id'] != 'club-badges' ||
        staged['object_key'] is! String ||
        staged['badge_id'] is! String) {
      throw const FormatException('Invalid staged badge.');
    }
    await _client.storage
        .from('club-badges')
        .uploadBinary(
          staged['object_key'] as String,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    await _rpc('set_club_badge', {
      'target_club_id': clubId,
      'badge_action': 'replace',
      'staged_badge_id': staged['badge_id'],
    });
  }

  @override
  Future<PersonStatistics> getPersonStatistics({
    required String clubId,
    required String teamId,
    required String personId,
  }) async {
    final value = await _rpc('get_person_statistics', {
      'target_club_id': clubId,
      'target_team_id': teamId,
      'target_person_id': personId,
    });
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Statistics response is invalid.');
    }
    return PersonStatistics.fromJson(value);
  }

  @override
  Future<void> recordActivity() => _rpc('record_activity');

  @override
  Future<ClubColors> getClubColors(String clubId) async {
    final value = await _rpc('get_club_colors', {'target_club_id': clubId});
    return value is Map<String, dynamic>
        ? ClubColors.fromJson(value)
        : const ClubColors();
  }

  @override
  Future<ClubColors> setClubColors({
    required String clubId,
    String? primary,
    String? accent,
  }) async {
    final value = await _rpc('set_club_colors', {
      'target_club_id': clubId,
      'new_primary': primary,
      'new_accent': accent,
    });
    return value is Map<String, dynamic>
        ? ClubColors.fromJson(value)
        : const ClubColors();
  }

  @override
  Future<void> removeClubBadge(String clubId) => _rpc('set_club_badge', {
    'target_club_id': clubId,
    'badge_action': 'remove',
    'staged_badge_id': null,
  });
}
