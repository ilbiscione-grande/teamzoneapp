import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Medlemsregister (docs/implementation/club-members-and-fees.md, step 1):
// everyone active in the club, their teams and guardians, and who is a
// member in which category.

/// youth: barn och ungdom (through the year one turns 20), adult, supporter.
const clubMemberCategories = ['youth', 'adult', 'supporter'];

/// The category the birth year gives, as the server derives it.
String? clubMemberCategoryFor(int? birthYear, {DateTime? now}) {
  if (birthYear == null) return null;
  return (now ?? DateTime.now()).year - birthYear <= 20 ? 'youth' : 'adult';
}

class ClubRegisterTeamRole {
  const ClubRegisterTeamRole({
    required this.teamId,
    required this.teamName,
    required this.role,
  });
  factory ClubRegisterTeamRole.fromJson(Map<String, dynamic> json) =>
      ClubRegisterTeamRole(
        teamId: json['team_id'] as String,
        teamName: json['name'] as String? ?? '',
        role: json['role'] as String? ?? 'player',
      );
  final String teamId;
  final String teamName;

  /// player, leader, guardian or club_functionary.
  final String role;
}

class ClubRegisterPerson {
  const ClubRegisterPerson({
    required this.personId,
    required this.name,
    required this.birthYear,
    required this.hasAccount,
    required this.clubRole,
    required this.teams,
    required this.guardians,
    required this.children,
    required this.isMember,
    required this.memberSet,
    required this.category,
    required this.categorySet,
    required this.revision,
    this.email,
    this.emailEditable = false,
  });

  factory ClubRegisterPerson.fromJson(Map<String, dynamic> json) {
    List<String> names(Object? value) =>
        (value as List? ?? const []).whereType<String>().toList()..sort();
    return ClubRegisterPerson(
      personId: json['person_id'] as String,
      name: json['name'] as String? ?? '',
      birthYear: (json['birth_year'] as num?)?.toInt(),
      hasAccount: json['has_account'] as bool? ?? false,
      clubRole: json['club_role'] as bool? ?? false,
      teams:
          (json['teams'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ClubRegisterTeamRole.fromJson)
              .toList()
            ..sort((a, b) => a.teamName.compareTo(b.teamName)),
      guardians: names(json['guardians']),
      children: names(json['children']),
      isMember: json['is_member'] as bool? ?? false,
      memberSet: json['member_set'] as bool? ?? false,
      category: json['category'] as String?,
      categorySet: json['category_set'] as bool? ?? false,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      email: json['email'] as String?,
      emailEditable: json['email_editable'] as bool? ?? false,
    );
  }

  final String personId;
  final String name;
  final int? birthYear;
  final bool hasAccount;

  /// Holds a club-wide assignment (functionary, board, treasurer …).
  final bool clubRole;
  final List<ClubRegisterTeamRole> teams;
  final List<String> guardians;
  final List<String> children;
  final bool isMember;

  /// The club has said whether this person is a member; otherwise it
  /// follows the roles (players, leaders and functionaries are).
  final bool memberSet;

  /// youth, adult, supporter or null when unknown (no birth year).
  final String? category;

  /// A guardian who does not play is the same member as the child: no fee
  /// of their own, the payer of the child's (decided 2026-11-10).
  bool get coveredByChild =>
      !isMember &&
      !memberSet &&
      !clubRole &&
      children.isNotEmpty &&
      teams.every((team) => team.role == 'guardian');

  /// The category is set by the club; otherwise it follows the birth year.
  final bool categorySet;
  final int revision;

  /// The address fee reminders go to (2026-11-11): only for someone without
  /// an account, never for a protected person.
  final String? email;
  final bool emailEditable;
}

class ClubRegister {
  const ClubRegister(this.people);
  factory ClubRegister.fromJson(Map<String, dynamic> json) => ClubRegister(
    (json['people'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ClubRegisterPerson.fromJson)
        .toList(growable: false),
  );
  final List<ClubRegisterPerson> people;
}

/// The register's conflict: someone else changed the person meanwhile.
class ClubRegisterConflict implements Exception {
  const ClubRegisterConflict();
}

abstract interface class ClubRegisterServices {
  Future<ClubRegister> loadClubRegister(String clubId);

  /// [category] null: follow the birth year.
  Future<void> setClubMembership({
    required String clubId,
    required String personId,
    required bool isMember,
    required String? category,
    required int expectedRevision,
    required String idempotencyKey,
  });

  /// [email] empty: no address. Throws [ClubRegisterInvalidEmail].
  Future<String?> setClubPersonEmail({
    required String clubId,
    required String personId,
    required String email,
  });
}

/// The address is not an e-mail address.
class ClubRegisterInvalidEmail implements Exception {
  const ClubRegisterInvalidEmail();
}

Future<String?> setClubPersonEmailWith(
  SupabaseClient client, {
  required String clubId,
  required String personId,
  required String email,
}) async {
  try {
    final value = await client
        .schema('api')
        .rpc<Object?>(
          'set_club_person_email',
          params: {
            'target_club_id': clubId,
            'target_person_id': personId,
            'new_email': email,
          },
        )
        .timeout(const Duration(seconds: 15));
    return value is Map ? value['email'] as String? : null;
  } on PostgrestException catch (error) {
    if (error.message.contains('invalid_email')) {
      throw const ClubRegisterInvalidEmail();
    }
    rethrow;
  }
}

Future<ClubRegister> loadClubRegisterFrom(
  SupabaseClient client,
  String clubId,
) async {
  final value = await client
      .schema('api')
      .rpc<Object?>(
        'get_club_member_register',
        params: {'target_club_id': clubId},
      )
      .timeout(const Duration(seconds: 20));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid member register.');
  }
  return ClubRegister.fromJson(value);
}

Future<void> setClubMembershipWith(
  SupabaseClient client, {
  required String clubId,
  required String personId,
  required bool isMember,
  required String? category,
  required int expectedRevision,
  required String idempotencyKey,
}) async {
  try {
    await client
        .schema('api')
        .rpc<Object?>(
          'set_club_membership',
          params: {
            'target_club_id': clubId,
            'target_person_id': personId,
            'new_is_member': isMember,
            'new_category': category,
            'expected_revision': expectedRevision,
            'idempotency_key': idempotencyKey,
          },
        )
        .timeout(const Duration(seconds: 15));
  } on PostgrestException catch (error) {
    if (error.code == 'PT409') throw const ClubRegisterConflict();
    rethrow;
  }
}

/// The register as CSV: semicolons and a BOM, so Excel opens it in Swedish.
String clubRegisterCsv(
  List<ClubRegisterPerson> people, {
  required String Function(String role) roleLabel,
  required String Function(String? category) categoryLabel,
}) {
  String cell(Object? value) {
    final text = '${value ?? ''}';
    return text.contains(RegExp('[;"\n]'))
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  final lines = <List<Object?>>[
    [
      'Namn',
      'Födelseår',
      'Medlem',
      'Kategori',
      'Lag och roll',
      'Vårdnadshavare',
      'Barn',
      'Konto i TeamZone',
    ],
    for (final person in people)
      [
        person.name,
        person.birthYear,
        person.isMember
            ? 'Ja'
            : person.coveredByChild
            ? 'Via barnet'
            : 'Nej',
        person.isMember ? categoryLabel(person.category) : null,
        person.teams
            .map((team) => '${team.teamName} (${roleLabel(team.role)})')
            .join(', '),
        person.guardians.join(', '),
        person.children.join(', '),
        person.hasAccount ? 'Ja' : 'Nej',
      ],
  ];
  return '﻿${lines.map((line) => line.map(cell).join(';')).join('\r\n')}\r\n';
}

/// Saves the export; tests replace it. True when saved.
Future<bool> Function(String fileName, String csv) saveClubRegisterCsv =
    (fileName, csv) async {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara medlemsregistret',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );
      // The web download has no path to report.
      return kIsWeb || path != null;
    };
