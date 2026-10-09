import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';

/// Receiver id stored in the attendance_export tables.
const lagetSeProvider = 'laget_se';

final _digits = RegExp(r'^[0-9]{1,20}$');

bool isLagetSeId(String? value) => value != null && _digits.hasMatch(value);

/// Accepts a bare activity id or a laget.se URL such as
/// `https://admin.laget.se/EksjoFotbollJ18/Calendar/Edit/30960339`.
/// Returns null when no valid id can be extracted.
String? parseLagetSeActivityId(String input) {
  final value = input.trim();
  if (_digits.hasMatch(value)) return value;
  // Also accept a pasted link without scheme ("admin.laget.se/…").
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host != 'laget.se' && !host.endsWith('.laget.se')) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty || !_digits.hasMatch(segments.last)) return null;
  return segments.last;
}

enum ExportIssueSeverity { error, warning }

class ExportIssue {
  const ExportIssue(this.code, this.message, this.severity);
  final String code, message;
  final ExportIssueSeverity severity;
  bool get isError => severity == ExportIssueSeverity.error;
  @override
  String toString() => '$code: $message';
}

/// A person who will be part of the file, with the link used for it.
class LagetSeSelectionEntry {
  const LagetSeSelectionEntry({
    required this.candidate,
    required this.role,
    this.link,
  });
  final ExportCandidate candidate;
  final ExternalMemberLink? link;

  /// The laget.se list (player/leader): the link's role, or for an unlinked
  /// person the role inferred from the team (only used for messages).
  final String role;
}

class LagetSeSelection {
  const LagetSeSelection({
    required this.included,
    required this.unknown,
    required this.excluded,
    required this.otherTeam,
  });

  /// Explicit attendance, to be written to the file.
  final List<LagetSeSelectionEntry> included;

  /// No recorded attendance — never exported, never turned into absent.
  final List<ExportCandidate> unknown;

  /// Explicitly left out by the administrator.
  final List<ExportCandidate> excluded;

  /// Members of other teams sharing the event, without a link in this team.
  final List<ExportCandidate> otherTeam;

  List<LagetSeSelectionEntry> get missingLinks =>
      included.where((entry) => entry.link == null).toList(growable: false);
}

String _inferredRole(ExportCandidate candidate) =>
    candidate.teamRoles.contains('leader') &&
        !candidate.teamRoles.contains('player')
    ? 'leader'
    : 'player';

/// Decides who is part of the export. Links are matched by Teamzone person
/// id only (never by name).
LagetSeSelection selectLagetSeParticipants({
  required AttendanceExportBasis basis,
  required ExportContext context,
  Set<String> excludedPersonIds = const {},
}) {
  final links = <String, List<ExternalMemberLink>>{};
  for (final link in context.links) {
    links.putIfAbsent(link.personId, () => []).add(link);
  }
  final included = <LagetSeSelectionEntry>[];
  final unknown = <ExportCandidate>[];
  final excluded = <ExportCandidate>[];
  final otherTeam = <ExportCandidate>[];
  for (final candidate in basis.candidates) {
    final personLinks = links[candidate.personId] ?? const [];
    if (candidate.membership == ExportMembership.otherTeam &&
        personLinks.isEmpty) {
      otherTeam.add(candidate);
      continue;
    }
    if (excludedPersonIds.contains(candidate.personId)) {
      excluded.add(candidate);
      continue;
    }
    if (candidate.attendance == ExplicitAttendance.unknown) {
      unknown.add(candidate);
      continue;
    }
    final link = personLinks.firstOrNull;
    included.add(
      LagetSeSelectionEntry(
        candidate: candidate,
        link: link,
        role: link?.externalRole ?? _inferredRole(candidate),
      ),
    );
  }
  return LagetSeSelection(
    included: included,
    unknown: unknown,
    excluded: excluded,
    otherTeam: otherTeam,
  );
}

class LagetSeSummary {
  const LagetSeSummary({
    required this.presentPlayers,
    required this.absentPlayers,
    required this.presentLeaders,
    required this.absentLeaders,
    required this.unknown,
    required this.missingLinks,
    required this.excluded,
  });
  final int presentPlayers, absentPlayers, presentLeaders, absentLeaders;
  final int unknown, missingLinks, excluded;
  int get participants =>
      presentPlayers + absentPlayers + presentLeaders + absentLeaders;

  /// Counts only; stored in the export log (no personal data).
  Map<String, dynamic> toJson() => {
    'participants': participants,
    'present_players': presentPlayers,
    'absent_players': absentPlayers,
    'present_leaders': presentLeaders,
    'absent_leaders': absentLeaders,
    'unknown': unknown,
    'missing_links': missingLinks,
    'excluded': excluded,
  };
}

LagetSeSummary summarizeLagetSeSelection(LagetSeSelection selection) {
  int count(String role, ExplicitAttendance attendance) => selection.included
      .where(
        (entry) =>
            entry.role == role && entry.candidate.attendance == attendance,
      )
      .length;
  return LagetSeSummary(
    presentPlayers: count('player', ExplicitAttendance.present),
    absentPlayers: count('player', ExplicitAttendance.absent),
    presentLeaders: count('leader', ExplicitAttendance.present),
    absentLeaders: count('leader', ExplicitAttendance.absent),
    unknown: selection.unknown.length,
    missingLinks: selection.missingLinks.length,
    excluded: selection.excluded.length,
  );
}

String _people(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

/// Validation run before any file is generated. Any error stops the export.
/// It does not replace the sync tool's own check against laget.se.
List<ExportIssue> validateLagetSeExport({
  required AttendanceExportBasis basis,
  required ExportContext context,
  required LagetSeSelection selection,
  required bool confirmedComplete,

  /// False for a direct sync, where the sync agent locates the activity in
  /// the team's laget.se calendar when no link exists yet.
  bool requireActivity = true,
}) {
  final issues = <ExportIssue>[];
  void error(String code, String message) =>
      issues.add(ExportIssue(code, message, ExportIssueSeverity.error));
  void warning(String code, String message) =>
      issues.add(ExportIssue(code, message, ExportIssueSeverity.warning));
  const prefix = 'Kan inte exportera: ';

  if (!context.enabled) {
    error(
      'integration_disabled',
      '${prefix}laget.se-exporten är inte aktiverad för laget.',
    );
  }
  if (context.teamId != basis.teamId ||
      context.eventId != basis.eventId ||
      !basis.belongsToTeam) {
    error('event_not_in_team', '${prefix}aktiviteten tillhör inte laget.');
  }
  if (!basis.ended) {
    error('event_not_ended', '${prefix}aktiviteten är inte avslutad.');
  }

  final activity = context.activityLink;
  if (activity == null) {
    if (requireActivity) {
      error(
        'missing_activity_id',
        '${prefix}aktiviteten saknar laget.se-ID. Ange ID eller länk till aktiviteten i laget.se.',
      );
    }
  } else {
    if (!isLagetSeId(activity.externalActivityId)) {
      error(
        'invalid_activity_id',
        '${prefix}laget.se-ID för aktiviteten är ogiltigt (endast siffror).',
      );
    }
    if (activity.teamId != basis.teamId) {
      error(
        'activity_link_wrong_team',
        '${prefix}aktivitetskopplingen tillhör ett annat lag.',
      );
    }
  }

  // Missing member links, grouped the way the administrator thinks of them.
  final missing = selection.missingLinks;
  final missingPlayers = missing
      .where(
        (e) =>
            e.candidate.membership == ExportMembership.team &&
            e.role == 'player',
      )
      .length;
  final missingLeaders = missing
      .where(
        (e) =>
            e.candidate.membership == ExportMembership.team &&
            e.role == 'leader',
      )
      .length;
  final missingGuests = missing
      .where((e) => e.candidate.membership != ExportMembership.team)
      .length;
  if (missingPlayers > 0) {
    error(
      'missing_member_links',
      '$prefix${_people(missingPlayers, 'spelare', 'spelare')} saknar laget.se-ID.',
    );
  }
  if (missingLeaders > 0) {
    error(
      'missing_member_links',
      '$prefix${_people(missingLeaders, 'ledare', 'ledare')} saknar laget.se-ID.',
    );
  }
  if (missingGuests > 0) {
    error(
      'missing_member_links',
      '$prefix${_people(missingGuests, 'gäst', 'gäster')} utanför laget saknar laget.se-ID. Koppla dem eller ta inte med dem.',
    );
  }

  // Link integrity across the team's links (not only those in this file):
  // one link per person, one person per external id, right team.
  final byPerson = <String, int>{};
  final byExternal = <String, Set<String>>{};
  for (final link in context.links) {
    byPerson.update(link.personId, (n) => n + 1, ifAbsent: () => 1);
    byExternal.putIfAbsent(link.externalId, () => {}).add(link.personId);
  }
  final conflicting = byPerson.values.where((n) => n > 1).length;
  if (conflicting > 0) {
    error(
      'conflicting_links',
      '$prefix${_people(conflicting, 'person', 'personer')} har flera motstridiga laget.se-kopplingar.',
    );
  }
  final duplicates = byExternal.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toList();
  if (duplicates.isNotEmpty) {
    error(
      'duplicate_external_id',
      '${prefix}samma laget.se-ID är kopplat till flera personer (${duplicates.join(', ')}).',
    );
  }
  final wrongTeam = context.links
      .where((link) => link.teamId != basis.teamId)
      .length;
  if (wrongTeam > 0) {
    error(
      'link_wrong_team',
      '$prefix${_people(wrongTeam, 'koppling', 'kopplingar')} tillhör ett annat lag.',
    );
  }

  // Field contract for the people in the file.
  final used = <String>{};
  var invalidIds = 0, missingNames = 0, invalidRoles = 0, repeated = 0;
  for (final entry in selection.included) {
    final link = entry.link;
    if (link == null) continue;
    if (!isLagetSeId(link.externalId)) invalidIds++;
    if (link.externalName.trim().isEmpty) missingNames++;
    if (link.externalRole != 'player' && link.externalRole != 'leader') {
      invalidRoles++;
    }
    if (!used.add('${link.externalId}:${link.externalRole}')) repeated++;
  }
  if (invalidIds > 0) {
    error(
      'invalid_member_id',
      '$prefix${_people(invalidIds, 'person', 'personer')} har ett ogiltigt laget.se-ID (endast siffror).',
    );
  }
  if (missingNames > 0) {
    error(
      'missing_member_name',
      '$prefix${_people(missingNames, 'person', 'personer')} saknar namn i laget.se.',
    );
  }
  if (invalidRoles > 0) {
    error(
      'invalid_member_role',
      '$prefix${_people(invalidRoles, 'person', 'personer')} har en ogiltig roll (spelare eller ledare).',
    );
  }
  if (repeated > 0) {
    error(
      'duplicate_participant',
      '${prefix}samma laget.se-person förekommer flera gånger i exporten.',
    );
  }
  // Defensive: unknown attendance must never reach the file as absent.
  if (selection.included.any(
    (e) => e.candidate.attendance == ExplicitAttendance.unknown,
  )) {
    error(
      'unknown_attendance_included',
      '${prefix}okänd närvaro kan inte exporteras som frånvaro.',
    );
  }
  if (!confirmedComplete) {
    error(
      'not_confirmed',
      '${prefix}bekräfta att närvaron är färdigregistrerad.',
    );
  }

  if (selection.unknown.isNotEmpty) {
    warning(
      'unknown_attendance',
      '${_people(selection.unknown.length, 'person', 'personer')} har ingen registrerad närvaro och tas inte med i filen.',
    );
  }
  final roleMismatch = selection.included
      .where(
        (e) =>
            e.link != null &&
            e.candidate.teamRoles.isNotEmpty &&
            !e.candidate.teamRoles.contains(e.link!.externalRole),
      )
      .length;
  if (roleMismatch > 0) {
    warning(
      'role_mismatch',
      '${_people(roleMismatch, 'person', 'personer')} har en annan roll i laget.se än i Teamzone.',
    );
  }
  return issues;
}

class LagetSeParticipant {
  const LagetSeParticipant({
    required this.name,
    required this.role,
    required this.present,
    required this.id,
  });
  final String name, role, id;
  final bool present;

  /// Exactly the verified contract; no Teamzone fields.
  Map<String, Object> toJson() => {
    'name': name,
    'role': role,
    'present': present,
    'id': id,
  };
}

class LagetSeExportFile {
  const LagetSeExportFile({
    required this.activityId,
    required this.participants,
  });
  final String activityId;
  final List<LagetSeParticipant> participants;

  Map<String, Object> toJson() => {
    'activityId': activityId,
    'participants': [for (final p in participants) p.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// UTF-8 bytes of [encode] (no BOM).
  Uint8List bytes() => Uint8List.fromList(utf8.encode(encode()));

  String sha256Hex() => sha256.convert(bytes()).toString();
}

/// Builds the file from a validated selection. Throws when any entry lacks a
/// link — call [generateLagetSeExport] rather than this directly.
LagetSeExportFile buildLagetSeFile({
  required ExportContext context,
  required LagetSeSelection selection,
}) {
  final participants = [
    for (final entry in selection.included)
      LagetSeParticipant(
        name: entry.link!.externalName.trim(),
        role: entry.link!.externalRole,
        present: switch (entry.candidate.attendance) {
          ExplicitAttendance.present => true,
          ExplicitAttendance.absent => false,
          ExplicitAttendance.unknown => throw StateError('unknown attendance'),
        },
        id: entry.link!.externalId,
      ),
  ];
  // Deterministic order so an unchanged basis gives an identical file.
  participants.sort((a, b) {
    final role = a.role == b.role ? 0 : (a.role == 'player' ? -1 : 1);
    if (role != 0) return role;
    final name = a.name.compareTo(b.name);
    return name != 0 ? name : a.id.compareTo(b.id);
  });
  return LagetSeExportFile(
    // '' only for a direct sync without link; the agent fills it in.
    activityId: context.activityLink?.externalActivityId ?? '',
    participants: participants,
  );
}

class LagetSeExportResult {
  const LagetSeExportResult({
    required this.selection,
    required this.summary,
    required this.issues,
    this.file,
  });
  final LagetSeSelection selection;
  final LagetSeSummary summary;
  final List<ExportIssue> issues;

  /// Null whenever any error was found.
  final LagetSeExportFile? file;

  List<ExportIssue> get errors =>
      issues.where((issue) => issue.isError).toList(growable: false);
  List<ExportIssue> get warnings =>
      issues.where((issue) => !issue.isError).toList(growable: false);
}

/// Select → validate → generate. No file is produced if validation fails.
LagetSeExportResult generateLagetSeExport({
  required AttendanceExportBasis basis,
  required ExportContext context,
  Set<String> excludedPersonIds = const {},
  required bool confirmedComplete,

  /// See [validateLagetSeExport]. The resulting payload then carries
  /// activityId '' and must only be sent to the sync agent, never saved.
  bool requireActivity = true,
}) {
  final selection = selectLagetSeParticipants(
    basis: basis,
    context: context,
    excludedPersonIds: excludedPersonIds,
  );
  final issues = validateLagetSeExport(
    basis: basis,
    context: context,
    selection: selection,
    confirmedComplete: confirmedComplete,
    requireActivity: requireActivity,
  );
  LagetSeExportFile? file;
  if (!issues.any((issue) => issue.isError)) {
    file = buildLagetSeFile(context: context, selection: selection);
    final contractErrors = lagetSeContractErrors(
      jsonDecode(file.encode()),
      allowMissingActivityId: !requireActivity && context.activityLink == null,
    );
    if (contractErrors.isNotEmpty) {
      issues.add(
        ExportIssue(
          'contract_violation',
          'Kan inte exportera: filen följer inte formatet (${contractErrors.first}).',
          ExportIssueSeverity.error,
        ),
      );
      file = null;
    }
  }
  return LagetSeExportResult(
    selection: selection,
    summary: summarizeLagetSeSelection(selection),
    issues: issues,
    file: file,
  );
}

/// Checks decoded JSON against the verified file contract. Empty = valid.
List<String> lagetSeContractErrors(
  Object? json, {
  bool allowMissingActivityId = false,
}) {
  final errors = <String>[];
  if (json is! Map) return ['roten är inte ett objekt'];
  if ((json.keys.toSet()..removeAll(['activityId', 'participants']))
      .isNotEmpty) {
    errors.add('okända fält i roten');
  }
  final activityId = json['activityId'];
  if (activityId is! String ||
      !(isLagetSeId(activityId) ||
          (allowMissingActivityId && activityId.isEmpty))) {
    errors.add('activityId måste vara en sträng med siffror');
  }
  final participants = json['participants'];
  if (participants is! List) {
    errors.add('participants måste vara en lista');
    return errors;
  }
  for (final (index, p) in participants.indexed) {
    if (p is! Map) {
      errors.add('deltagare $index är inte ett objekt');
      continue;
    }
    if ((p.keys.toSet()..removeAll(['name', 'role', 'present', 'id']))
        .isNotEmpty) {
      errors.add('deltagare $index har okända fält');
    }
    final name = p['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.add('deltagare $index saknar namn');
    }
    if (p['role'] != 'player' && p['role'] != 'leader') {
      errors.add('deltagare $index har ogiltig roll');
    }
    if (p['present'] is! bool) {
      errors.add('deltagare $index saknar booleskt present');
    }
    final id = p['id'];
    if (id is! String || !isLagetSeId(id)) {
      errors.add('deltagare $index har ogiltigt id');
    }
  }
  return errors;
}
