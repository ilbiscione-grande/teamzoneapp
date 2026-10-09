import 'dart:convert';

import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';

/// One person from the member file written by the sync tool
/// (`npm run members`, format laget_se_members v1).
class LagetSeMember {
  const LagetSeMember({
    required this.id,
    required this.name,
    required this.role,
  });
  final String id, name, role;

  @override
  bool operator ==(Object other) =>
      other is LagetSeMember &&
      other.id == id &&
      other.role == role &&
      other.name == name;
  @override
  int get hashCode => Object.hash(id, name, role);
}

class LagetSeMemberFile {
  const LagetSeMemberFile({
    required this.teamSlug,
    required this.sourceActivityId,
    required this.readAt,
    required this.members,
  });
  final String teamSlug, sourceActivityId;
  final DateTime readAt;
  final List<LagetSeMember> members;
}

/// Parses and validates the member file. Throws [FormatException] with a
/// message meant for the administrator.
LagetSeMemberFile parseLagetSeMemberFile(String text) {
  Object? json;
  try {
    json = jsonDecode(text.startsWith('﻿') ? text.substring(1) : text);
  } on FormatException {
    throw const FormatException('Filen är inte giltig JSON.');
  }
  if (json is! Map || json['format'] != 'laget_se_members') {
    throw const FormatException(
      'Filen är ingen medlemslista från laget.se. Skapa den med "npm run members".',
    );
  }
  if (json['version'] != 1) {
    throw const FormatException(
      'Medlemslistan har en version som Teamzone inte känner till.',
    );
  }
  final rows = json['members'];
  if (rows is! List) {
    throw const FormatException('Medlemslistan saknar medlemmar.');
  }
  final members = <LagetSeMember>[];
  final seen = <String>{};
  for (final (index, row) in rows.indexed) {
    final id = row is Map ? row['id'] : null;
    final name = row is Map ? row['name'] : null;
    final role = row is Map ? row['role'] : null;
    if (id is! String ||
        !isLagetSeId(id) ||
        name is! String ||
        name.trim().isEmpty ||
        (role != 'player' && role != 'leader')) {
      throw FormatException('Rad ${index + 1} i medlemslistan är ogiltig.');
    }
    if (!seen.add('$id:$role')) continue;
    members.add(LagetSeMember(id: id, name: name.trim(), role: role as String));
  }
  return LagetSeMemberFile(
    teamSlug: json['teamSlug'] is String ? json['teamSlug'] as String : '',
    sourceActivityId: json['sourceActivityId'] is String
        ? json['sourceActivityId'] as String
        : '',
    readAt:
        DateTime.tryParse(json['readAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    members: members,
  );
}

const _foldMap = {
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'á': 'a', 'à': 'a', 'â': 'a', //
  'ü': 'u', 'ú': 'u', 'ï': 'i', 'í': 'i', 'ó': 'o', 'ø': 'ö', 'æ': 'ä',
};

/// Lower case, folded accents (keeping å/ä/ö), hyphens as spaces and
/// collapsed whitespace. Used only to propose links, never for export.
String normalizeMemberName(String name) {
  final lower = name.toLowerCase().replaceAll(RegExp(r'[-‐–_.,]'), ' ');
  final folded = StringBuffer();
  for (final char in lower.split('')) {
    folded.write(_foldMap[char] ?? char);
  }
  return folded.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// First + last name only, so "Anna Maria Berg" ~ "Anna Berg".
String _firstLast(String normalized) {
  final parts = normalized.split(' ');
  return parts.length < 2 ? normalized : '${parts.first} ${parts.last}';
}

enum MemberProposalKind {
  /// Already linked and the file agrees.
  unchanged,

  /// Already linked to an id in the file whose name or role differs.
  update,

  /// Already linked to an id that is not in the file.
  linkedNotInFile,

  /// Exactly one person on both sides with the same name.
  certain,

  /// Same name, but several possible people — the administrator chooses.
  ambiguous,

  /// Similar name only — the administrator chooses.
  possible,

  /// Nothing in the file resembles the person.
  noMatch,
}

class MemberProposal {
  const MemberProposal({
    required this.member,
    required this.kind,
    this.candidates = const [],
    this.existing,
  });
  final IntegrationTeamMember member;
  final MemberProposalKind kind;

  /// Possible laget.se people, best first. For [certain]/[update] exactly one.
  final List<LagetSeMember> candidates;
  final ExternalMemberLink? existing;

  /// Pre-selected when the proposal is safe; the administrator still saves.
  LagetSeMember? get suggested =>
      kind == MemberProposalKind.certain || kind == MemberProposalKind.update
      ? candidates.single
      : null;

  bool get needsDecision =>
      kind == MemberProposalKind.ambiguous ||
      kind == MemberProposalKind.possible;
}

class MemberImportPlan {
  const MemberImportPlan({
    required this.proposals,
    required this.unmatchedExternal,
  });
  final List<MemberProposal> proposals;

  /// laget.se people that matched nobody in the team and are not linked.
  final List<LagetSeMember> unmatchedExternal;

  Iterable<MemberProposal> ofKind(MemberProposalKind kind) =>
      proposals.where((proposal) => proposal.kind == kind);
}

/// Prefers the laget.se entry in the person's Teamzone role when a laget.se
/// person is listed both as player and leader.
List<LagetSeMember> _rolePreferred(
  List<LagetSeMember> members,
  Set<String> roles,
) {
  final byId = <String, List<LagetSeMember>>{};
  for (final member in members) {
    byId.putIfAbsent(member.id, () => []).add(member);
  }
  return [
    for (final entries in byId.values)
      entries.firstWhere(
        (entry) => roles.contains(entry.role),
        orElse: () => entries.first,
      ),
  ];
}

/// Compares the member file with the team. Names are only used to propose
/// links; every link is saved by an explicit administrator action.
MemberImportPlan buildMemberImportPlan({
  required TeamIntegrationSettings settings,
  required LagetSeMemberFile file,
}) {
  final linkedIds = {for (final link in settings.links) link.externalId};
  final available = file.members
      .where((member) => !linkedIds.contains(member.id))
      .toList();
  final unlinked = settings.members
      .where((member) => settings.linkFor(member.personId) == null)
      .toList();

  // Exact-name index on both sides, to detect ambiguity in either direction.
  final externalByName = <String, List<LagetSeMember>>{};
  for (final member in available) {
    externalByName
        .putIfAbsent(normalizeMemberName(member.name), () => [])
        .add(member);
  }
  final teamByName = <String, int>{};
  for (final member in unlinked) {
    teamByName.update(
      normalizeMemberName(member.name),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }

  final proposals = <MemberProposal>[];
  final proposedIds = <String>{};
  for (final member in settings.members) {
    final existing = settings.linkFor(member.personId);
    if (existing != null) {
      final inFile = file.members
          .where((m) => m.id == existing.externalId)
          .toList();
      if (inFile.isEmpty) {
        proposals.add(
          MemberProposal(
            member: member,
            kind: MemberProposalKind.linkedNotInFile,
            existing: existing,
          ),
        );
        continue;
      }
      final match = inFile.firstWhere(
        (m) => m.role == existing.externalRole,
        orElse: () => inFile.first,
      );
      final same =
          match.name == existing.externalName &&
          match.role == existing.externalRole;
      proposals.add(
        MemberProposal(
          member: member,
          kind: same ? MemberProposalKind.unchanged : MemberProposalKind.update,
          candidates: [match],
          existing: existing,
        ),
      );
      continue;
    }
    final name = normalizeMemberName(member.name);
    final exact = _rolePreferred(
      externalByName[name] ?? const [],
      member.roles,
    );
    if (exact.length == 1 && teamByName[name] == 1) {
      proposals.add(
        MemberProposal(
          member: member,
          kind: MemberProposalKind.certain,
          candidates: exact,
        ),
      );
      proposedIds.add(exact.single.id);
      continue;
    }
    if (exact.isNotEmpty) {
      proposals.add(
        MemberProposal(
          member: member,
          kind: MemberProposalKind.ambiguous,
          candidates: exact,
        ),
      );
      proposedIds.addAll(exact.map((m) => m.id));
      continue;
    }
    final short = _firstLast(name);
    final lastName = name.split(' ').last;
    final similar = _rolePreferred([
      for (final external in available)
        if (_firstLast(normalizeMemberName(external.name)) == short) external,
    ], member.roles);
    // Same last name and first initial ("Kalle Berg" ~ "Karl Berg").
    final sameLastName = similar.isNotEmpty || name.isEmpty
        ? const <LagetSeMember>[]
        : _rolePreferred([
            for (final external in available)
              if (normalizeMemberName(external.name).split(' ').last ==
                      lastName &&
                  normalizeMemberName(external.name).startsWith(name[0]))
                external,
          ], member.roles);
    final candidates = [...similar, ...sameLastName];
    if (candidates.isNotEmpty) {
      proposals.add(
        MemberProposal(
          member: member,
          kind: MemberProposalKind.possible,
          candidates: candidates,
        ),
      );
      proposedIds.addAll(candidates.map((m) => m.id));
    } else {
      proposals.add(
        MemberProposal(member: member, kind: MemberProposalKind.noMatch),
      );
    }
  }
  final seen = <String>{};
  return MemberImportPlan(
    proposals: proposals,
    unmatchedExternal: [
      for (final member in available)
        if (!proposedIds.contains(member.id) && seen.add(member.id)) member,
    ],
  );
}

/// The ids chosen for more than one Teamzone person in [choices]
/// (person id -> laget.se member). Saving is blocked while non-empty.
Set<String> conflictingChoices(Map<String, LagetSeMember?> choices) {
  final counts = <String, int>{};
  for (final choice in choices.values) {
    if (choice == null) continue;
    counts.update(choice.id, (n) => n + 1, ifAbsent: () => 1);
  }
  return {
    for (final entry in counts.entries)
      if (entry.value > 1) entry.key,
  };
}
