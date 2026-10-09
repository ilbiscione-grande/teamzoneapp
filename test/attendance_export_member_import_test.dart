import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_member_import.dart';

String memberFile(List<Map<String, Object>> members, {Object version = 1}) =>
    jsonEncode({
      'format': 'laget_se_members',
      'version': version,
      'teamSlug': 'EksjoFotbollJ18',
      'sourceActivityId': '30960339',
      'readAt': '2026-10-08T12:00:00.000Z',
      'members': members,
    });

Map<String, Object> m(String id, String name, [String role = 'player']) => {
  'id': id,
  'name': name,
  'role': role,
};

IntegrationTeamMember tz(String id, String name, [String role = 'player']) =>
    IntegrationTeamMember(personId: id, name: name, roles: {role});

TeamIntegrationSettings settings(
  List<IntegrationTeamMember> members, {
  List<ExternalMemberLink> links = const [],
}) => TeamIntegrationSettings(
  teamId: 't1',
  provider: 'laget_se',
  enabled: true,
  revision: 1,
  members: members,
  links: links,
);

MemberProposal proposalFor(MemberImportPlan plan, String personId) =>
    plan.proposals.firstWhere((p) => p.member.personId == personId);

void main() {
  group('member file', () {
    test('parses the format written by npm run members', () {
      final file = parseLagetSeMemberFile(
        '﻿${memberFile([m('4938827', ' Anna Andersson '), m('1965637', 'Lena Ledare', 'leader')])}',
      );
      expect(file.teamSlug, 'EksjoFotbollJ18');
      expect(file.members, [
        const LagetSeMember(
          id: '4938827',
          name: 'Anna Andersson',
          role: 'player',
        ),
        const LagetSeMember(id: '1965637', name: 'Lena Ledare', role: 'leader'),
      ]);
    });

    test('rejects other files with a clear message', () {
      for (final text in [
        'inte json',
        jsonEncode({'activityId': '1', 'participants': []}),
        memberFile([m('1', 'A')], version: 2),
        memberFile([m('12x', 'A')]),
        memberFile([m('1', ' ')]),
        memberFile([m('1', 'A', 'coach')]),
      ]) {
        expect(
          () => parseLagetSeMemberFile(text),
          throwsA(isA<FormatException>()),
          reason: text,
        );
      }
    });
  });

  test('name normalization ignores case, accents and hyphens, keeps åäö', () {
    expect(normalizeMemberName('  ANNA-Lena   Ek '), 'anna lena ek');
    expect(normalizeMemberName('René Öberg'), 'rene öberg');
    expect(normalizeMemberName('Åsa'), isNot(normalizeMemberName('Asa')));
  });

  group('proposals', () {
    final file = parseLagetSeMemberFile(
      memberFile([
        m('1', 'Anna Andersson'),
        m('2', 'Erik Eriksson'),
        m('3', 'Erik Eriksson'),
        m('4', 'Karl Berg'),
        m('5', 'Lena Ledare', 'leader'),
        m('6', 'Okänd Person'),
        m('7', 'Maja Maria Lind'),
      ]),
    );
    final plan = buildMemberImportPlan(
      settings: settings([
        tz('a', 'anna andersson'),
        tz('e', 'Erik Eriksson'),
        tz('k', 'Kalle Berg'),
        tz('l', 'Lena Ledare', 'leader'),
        tz('n', 'Nils Nilsson'),
        tz('ml', 'Maja Lind'),
      ]),
      file: file,
    );

    test('exact unique name is a safe, pre-selected proposal', () {
      final anna = proposalFor(plan, 'a');
      expect(anna.kind, MemberProposalKind.certain);
      expect(anna.suggested?.id, '1');
      expect(proposalFor(plan, 'l').suggested?.role, 'leader');
    });

    test('same name twice in laget.se needs a decision', () {
      final erik = proposalFor(plan, 'e');
      expect(erik.kind, MemberProposalKind.ambiguous);
      expect(erik.suggested, isNull);
      expect(erik.candidates.map((c) => c.id), ['2', '3']);
    });

    test('similar names are only offered, never pre-selected', () {
      final kalle = proposalFor(plan, 'k');
      expect(kalle.kind, MemberProposalKind.possible);
      expect(kalle.suggested, isNull);
      expect(kalle.candidates.single.id, '4');
      final maja = proposalFor(plan, 'ml');
      expect(maja.kind, MemberProposalKind.possible);
      expect(maja.candidates.single.id, '7');
    });

    test('missing on either side is reported', () {
      expect(proposalFor(plan, 'n').kind, MemberProposalKind.noMatch);
      expect(plan.unmatchedExternal.map((m) => m.id), ['6']);
    });
  });

  test('two Teamzone people with the same name are not auto-linked', () {
    final plan = buildMemberImportPlan(
      settings: settings([tz('a1', 'Anna Berg'), tz('a2', 'Anna Berg')]),
      file: parseLagetSeMemberFile(memberFile([m('1', 'Anna Berg')])),
    );
    expect(
      plan.proposals.map((p) => p.kind),
      everyElement(MemberProposalKind.ambiguous),
    );
  });

  test('existing links: unchanged, updated and missing from the file', () {
    final plan = buildMemberImportPlan(
      settings: settings(
        [tz('a', 'Anna'), tz('b', 'Bo'), tz('c', 'Cia')],
        links: const [
          ExternalMemberLink(
            teamId: 't1',
            personId: 'a',
            externalId: '1',
            externalName: 'Anna',
            externalRole: 'player',
          ),
          ExternalMemberLink(
            teamId: 't1',
            personId: 'b',
            externalId: '2',
            externalName: 'Bo',
            externalRole: 'player',
            revision: 3,
          ),
          ExternalMemberLink(
            teamId: 't1',
            personId: 'c',
            externalId: '9',
            externalName: 'Cia',
            externalRole: 'player',
          ),
        ],
      ),
      file: parseLagetSeMemberFile(
        memberFile([m('1', 'Anna'), m('2', 'Bo Ek', 'leader')]),
      ),
    );
    expect(proposalFor(plan, 'a').kind, MemberProposalKind.unchanged);
    final bo = proposalFor(plan, 'b');
    expect(bo.kind, MemberProposalKind.update);
    expect(bo.suggested?.name, 'Bo Ek');
    expect(bo.existing?.revision, 3);
    expect(proposalFor(plan, 'c').kind, MemberProposalKind.linkedNotInFile);
    // Already linked ids are never offered to someone else.
    expect(plan.unmatchedExternal, isEmpty);
  });

  test('choosing one laget.se person for two people is a conflict', () {
    const anna = LagetSeMember(id: '1', name: 'Anna', role: 'player');
    const bo = LagetSeMember(id: '2', name: 'Bo', role: 'player');
    expect(conflictingChoices({'a': anna, 'b': bo, 'c': null}), isEmpty);
    expect(conflictingChoices({'a': anna, 'b': anna}), {'1'});
  });
}
