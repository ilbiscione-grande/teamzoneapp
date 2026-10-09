import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/attendance_export/export_basis.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_runner.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';

const teamA = 'team-a';
const teamB = 'team-b';
const eventId = 'event-1';
final now = DateTime.utc(2026, 10, 8, 20);

EventDetails event({
  String state = 'scheduled',
  DateTime? endsAt,
  List<String> teams = const [teamA],
}) => EventDetails.fromJson({
  'id': eventId,
  'title': 'Träning',
  'event_type': 'training',
  'state': state,
  'starts_at': DateTime.utc(2026, 10, 8, 17).toIso8601String(),
  'ends_at': (endsAt ?? DateTime.utc(2026, 10, 8, 18, 30)).toIso8601String(),
  'timezone': 'Europe/Stockholm',
  'revision': 1,
  'teams': [
    for (final team in teams)
      {'team_id': team, 'name': team, 'relation': 'primary'},
  ],
});

/// attendance: person id -> (name, status).
SquadDetails squad(
  Map<String, (String, String)> attendance, {
  Map<String, String> rosterTeams = const {},
}) => SquadDetails.fromJson({
  'event_id': eventId,
  'squad_state': 'sent',
  'roster': [
    for (final entry in rosterTeams.entries)
      {
        'person_id': entry.key,
        'name': attendance[entry.key]?.$1 ?? entry.key,
        'team_id': entry.value,
        'team_name': entry.value,
        'role_package': 'player',
      },
  ],
  'attendance': [
    for (final entry in attendance.entries)
      {
        'person_id': entry.key,
        'name': entry.value.$1,
        'status': entry.value.$2,
        'revision': 1,
      },
  ],
});

ExternalMemberLink link(
  String personId,
  String externalId, {
  String role = 'player',
  String team = teamA,
  String? name,
}) => ExternalMemberLink(
  teamId: team,
  personId: personId,
  externalId: externalId,
  externalName: name ?? 'Namn $personId',
  externalRole: role,
);

ExportContext exportContext({
  List<ExternalMemberLink> links = const [],
  Map<String, Set<String>> roster = const {},
  String? activityId = '30960339',
  bool enabled = true,
  String team = teamA,
  String? activityTeam,
}) => ExportContext(
  eventId: eventId,
  teamId: team,
  teamName: 'Lag',
  provider: lagetSeProvider,
  enabled: enabled,
  teamRoster: roster,
  links: links,
  activityLink: activityId == null
      ? null
      : ExternalActivityLink(
          teamId: activityTeam ?? team,
          externalActivityId: activityId,
        ),
);

AttendanceExportBasis basis({
  EventDetails? eventDetails,
  required SquadDetails squadDetails,
  required Map<String, Set<String>> roster,
  String team = teamA,
}) => buildAttendanceExportBasis(
  event: eventDetails ?? event(),
  squad: squadDetails,
  teamId: team,
  teamRoster: roster,
  now: now,
);

/// Standard team: two players and one leader, all with recorded attendance.
const standardRoster = {
  'p1': {'player'},
  'p2': {'player'},
  'l1': {'leader'},
};
SquadDetails standardSquad() => squad({
  'p1': ('Anna Andersson', 'present'),
  'p2': ('Björn Berg', 'absent'),
  'l1': ('Lena Ledare', 'late'),
});
final standardLinks = [
  link('p1', '4938827', name: 'Anna Andersson'),
  link('p2', '4938828', name: 'Björn Berg'),
  link('l1', '1965637', role: 'leader', name: 'Lena Ledare'),
];

LagetSeExportResult run({
  AttendanceExportBasis? b,
  ExportContext? c,
  Set<String> excluded = const {},
  bool confirmed = true,
}) => generateLagetSeExport(
  basis: b ?? basis(squadDetails: standardSquad(), roster: standardRoster),
  context: c ?? exportContext(links: standardLinks, roster: standardRoster),
  excludedPersonIds: excluded,
  confirmedComplete: confirmed,
);

void main() {
  group('activity id', () {
    test('accepts a bare id and the admin URL', () {
      expect(parseLagetSeActivityId('30960339'), '30960339');
      expect(parseLagetSeActivityId(' 30960339 '), '30960339');
      expect(
        parseLagetSeActivityId(
          'https://admin.laget.se/EksjoFotbollJ18/Calendar/Edit/30960339',
        ),
        '30960339',
      );
      expect(
        parseLagetSeActivityId(
          'admin.laget.se/EksjoFotbollJ18/Calendar/Edit/30960339/',
        ),
        '30960339',
      );
    });

    test('rejects invalid input', () {
      for (final input in [
        '',
        'abc',
        '12a',
        '-5',
        'https://example.com/Calendar/Edit/30960339',
        'https://admin.laget.se/EksjoFotbollJ18/Calendar',
        'https://evil-laget.se/Calendar/Edit/1',
      ]) {
        expect(parseLagetSeActivityId(input), isNull, reason: input);
      }
    });
  });

  test('only explicit attendance maps to present/absent', () {
    expect(explicitAttendanceFromStatus('present'), ExplicitAttendance.present);
    expect(explicitAttendanceFromStatus('late'), ExplicitAttendance.present);
    expect(explicitAttendanceFromStatus('partial'), ExplicitAttendance.present);
    expect(explicitAttendanceFromStatus('absent'), ExplicitAttendance.absent);
    expect(explicitAttendanceFromStatus('unknown'), ExplicitAttendance.unknown);
    expect(explicitAttendanceFromStatus(null), ExplicitAttendance.unknown);
    // Callup answers are not attendance.
    expect(
      explicitAttendanceFromStatus('accepted'),
      ExplicitAttendance.unknown,
    );
    expect(
      explicitAttendanceFromStatus('declined'),
      ExplicitAttendance.unknown,
    );
  });

  group('JSON file', () {
    test('matches the verified contract exactly', () {
      final result = run();
      expect(result.errors, isEmpty);
      final file = result.file!;
      final decoded = jsonDecode(utf8.decode(file.bytes())) as Map;
      expect(lagetSeContractErrors(decoded), isEmpty);
      expect(decoded.keys.toList(), ['activityId', 'participants']);
      expect(decoded['activityId'], '30960339');
      final participants = decoded['participants'] as List;
      for (final p in participants.cast<Map>()) {
        expect(p.keys.toList(), ['name', 'role', 'present', 'id']);
      }
      expect(participants, [
        {
          'name': 'Anna Andersson',
          'role': 'player',
          'present': true,
          'id': '4938827',
        },
        {
          'name': 'Björn Berg',
          'role': 'player',
          'present': false,
          'id': '4938828',
        },
        {
          'name': 'Lena Ledare',
          'role': 'leader',
          'present': true,
          'id': '1965637',
        },
      ]);
    });

    test('is UTF-8 without BOM and keeps Swedish characters', () {
      final bytes = run().file!.bytes();
      expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
      expect(utf8.decode(bytes), contains('Björn Berg'));
    });

    test('uses the laget.se name and id, never Teamzone ids', () {
      final text = run(
        c: exportContext(
          roster: standardRoster,
          links: [
            link('p1', '4938827', name: 'Anna A. (laget)'),
            standardLinks[1],
            standardLinks[2],
          ],
        ),
      ).file!.encode();
      expect(text, contains('Anna A. (laget)'));
      expect(text, isNot(contains('Anna Andersson')));
      expect(text, isNot(contains('p1')));
      expect(text, isNot(contains(eventId)));
    });

    test('contract check rejects extra or wrong fields', () {
      expect(
        lagetSeContractErrors({
          'activityId': '1',
          'participants': [],
          'teamzoneId': 'x',
        }),
        isNotEmpty,
      );
      expect(
        lagetSeContractErrors({'activityId': 1, 'participants': []}),
        isNotEmpty,
      );
      expect(
        lagetSeContractErrors({
          'activityId': '1',
          'participants': [
            {'name': 'A', 'role': 'coach', 'present': 'yes', 'id': 'x'},
          ],
        }),
        hasLength(3),
      );
      expect(
        lagetSeContractErrors({'activityId': '1', 'participants': []}),
        isEmpty,
      );
    });
  });

  test('players and leaders are counted separately', () {
    final summary = run().summary;
    expect(summary.presentPlayers, 1);
    expect(summary.absentPlayers, 1);
    expect(summary.presentLeaders, 1);
    expect(summary.absentLeaders, 0);
    expect(summary.participants, 3);
  });

  test('leaders only, all absent', () {
    final result = run(
      b: basis(
        squadDetails: squad({
          'l1': ('Lena', 'absent'),
          'l2': ('Leif', 'absent'),
        }),
        roster: {
          'l1': {'leader'},
          'l2': {'leader'},
        },
      ),
      c: exportContext(
        roster: {
          'l1': {'leader'},
          'l2': {'leader'},
        },
        links: [
          link('l1', '1', role: 'leader'),
          link('l2', '2', role: 'leader'),
        ],
      ),
    );
    expect(result.errors, isEmpty);
    expect(result.summary.absentLeaders, 2);
    expect(
      result.file!.participants.every((p) => p.role == 'leader' && !p.present),
      isTrue,
    );
  });

  test('unknown attendance is never exported as absent', () {
    final result = run(
      b: basis(
        squadDetails: squad({
          'p1': ('Anna', 'present'),
          'p2': ('Björn', 'unknown'),
          'l1': ('Lena', 'unknown'),
        }),
        roster: standardRoster,
      ),
    );
    expect(result.errors, isEmpty);
    expect(result.file!.participants.map((p) => p.id), ['4938827']);
    expect(result.summary.unknown, 2);
    expect(result.warnings.map((w) => w.code), contains('unknown_attendance'));
  });

  test('an empty participant list is a valid file', () {
    final result = run(
      b: basis(
        squadDetails: squad({'p1': ('Anna', 'unknown')}),
        roster: standardRoster,
      ),
    );
    expect(result.errors, isEmpty);
    expect(result.file!.toJson()['participants'], isEmpty);
    expect(lagetSeContractErrors(jsonDecode(result.file!.encode())), isEmpty);
  });

  group('blocks the export', () {
    void expectBlocked(LagetSeExportResult result, String code) {
      expect(result.file, isNull);
      expect(result.errors.map((e) => e.code), contains(code));
    }

    test('when players and leaders lack links', () {
      final result = run(
        c: exportContext(roster: standardRoster, links: [standardLinks[2]]),
      );
      expectBlocked(result, 'missing_member_links');
      expect(
        result.errors.map((e) => e.message),
        contains('Kan inte exportera: 2 spelare saknar laget.se-ID.'),
      );
    });

    test('when the activity id is missing or invalid', () {
      expectBlocked(
        run(
          c: exportContext(
            links: standardLinks,
            roster: standardRoster,
            activityId: null,
          ),
        ),
        'missing_activity_id',
      );
      expectBlocked(
        run(
          c: exportContext(
            links: standardLinks,
            roster: standardRoster,
            activityId: '30960339x',
          ),
        ),
        'invalid_activity_id',
      );
    });

    test('when member ids, names or roles are invalid', () {
      final result = run(
        c: exportContext(
          roster: standardRoster,
          links: [
            link('p1', '49388x7'),
            link('p2', '4938828', name: '  '),
            link('l1', '1965637', role: 'coach'),
          ],
        ),
      );
      expect(result.file, isNull);
      expect(
        result.errors.map((e) => e.code),
        containsAll([
          'invalid_member_id',
          'missing_member_name',
          'invalid_member_role',
        ]),
      );
    });

    test('on duplicate external ids', () {
      expectBlocked(
        run(
          c: exportContext(
            roster: standardRoster,
            links: [
              link('p1', '4938827'),
              link('p2', '4938827'),
              standardLinks[2],
            ],
          ),
        ),
        'duplicate_external_id',
      );
    });

    test('on conflicting links for one person', () {
      expectBlocked(
        run(
          c: exportContext(
            roster: standardRoster,
            links: [
              ...standardLinks,
              link('p1', '999', role: 'leader'),
            ],
          ),
        ),
        'conflicting_links',
      );
    });

    test('when the event has not ended or was cancelled', () {
      expectBlocked(
        run(
          b: basis(
            eventDetails: event(endsAt: now.add(const Duration(hours: 1))),
            squadDetails: standardSquad(),
            roster: standardRoster,
          ),
        ),
        'event_not_ended',
      );
      expectBlocked(
        run(
          b: basis(
            eventDetails: event(state: 'cancelled'),
            squadDetails: standardSquad(),
            roster: standardRoster,
          ),
        ),
        'event_not_ended',
      );
    });

    test('when the event or activity link belongs to another team', () {
      expectBlocked(
        run(
          b: basis(
            eventDetails: event(teams: [teamB]),
            squadDetails: standardSquad(),
            roster: standardRoster,
          ),
        ),
        'event_not_in_team',
      );
      expectBlocked(
        run(
          c: exportContext(
            links: standardLinks,
            roster: standardRoster,
            activityTeam: teamB,
          ),
        ),
        'activity_link_wrong_team',
      );
    });

    test('when the integration is disabled or not confirmed', () {
      expectBlocked(
        run(
          c: exportContext(
            links: standardLinks,
            roster: standardRoster,
            enabled: false,
          ),
        ),
        'integration_disabled',
      );
      expectBlocked(run(confirmed: false), 'not_confirmed');
    });
  });

  group('members in several teams', () {
    test('links of another team are rejected', () {
      final result = run(
        c: exportContext(
          roster: standardRoster,
          links: [
            standardLinks[0],
            standardLinks[1],
            link('l1', '1965637', role: 'leader', team: teamB),
          ],
        ),
      );
      expect(result.file, isNull);
      expect(result.errors.map((e) => e.code), contains('link_wrong_team'));
    });

    test('a shared event exports each team with its own links', () {
      // p1 plays in both teams with different laget.se ids; p3 only in B.
      final shared = event(teams: [teamA, teamB]);
      final squadDetails = squad(
        {'p1': ('Anna', 'present'), 'p3': ('Cecilia', 'absent')},
        rosterTeams: {'p1': teamA, 'p3': teamB},
      );
      final forA = run(
        b: basis(
          eventDetails: shared,
          squadDetails: squadDetails,
          roster: {
            'p1': {'player'},
          },
        ),
        c: exportContext(
          roster: {
            'p1': {'player'},
          },
          links: [link('p1', '111')],
        ),
      );
      expect(forA.errors, isEmpty);
      expect(forA.file!.participants.map((p) => p.id), ['111']);
      expect(forA.selection.otherTeam.map((c) => c.personId), ['p3']);

      final forB = run(
        b: basis(
          eventDetails: shared,
          squadDetails: squadDetails,
          team: teamB,
          roster: {
            'p1': {'player'},
            'p3': {'player'},
          },
        ),
        c: exportContext(
          team: teamB,
          activityId: '222000',
          roster: {
            'p1': {'player'},
            'p3': {'player'},
          },
          links: [
            link('p1', '222', team: teamB),
            link('p3', '333', team: teamB),
          ],
        ),
      );
      expect(forB.errors, isEmpty);
      expect(forB.file!.activityId, '222000');
      expect(forB.file!.participants.map((p) => p.id).toSet(), {'222', '333'});
    });
  });

  test('a guest without link must be linked or explicitly left out', () {
    final b = basis(
      squadDetails: squad({
        'p1': ('Anna', 'present'),
        'g1': ('Gäst Gästsson', 'present'),
      }),
      roster: {
        'p1': {'player'},
      },
    );
    final c = exportContext(
      roster: {
        'p1': {'player'},
      },
      links: [link('p1', '4938827')],
    );
    final blocked = run(b: b, c: c);
    expect(blocked.file, isNull);
    expect(
      blocked.errors.single.message,
      contains('1 gäst utanför laget saknar laget.se-ID'),
    );
    final excluded = run(b: b, c: c, excluded: {'g1'});
    expect(excluded.errors, isEmpty);
    expect(excluded.file!.participants.map((p) => p.id), ['4938827']);
    expect(excluded.summary.excluded, 1);
  });

  test('repeated export of an unchanged basis gives an identical file', () {
    final first = run().file!;
    final second = run().file!;
    expect(second.encode(), first.encode());
    expect(second.sha256Hex(), first.sha256Hex());
    expect(first.sha256Hex(), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  group('runner', () {
    test(
      'saves the file and logs it as created (twice when repeated)',
      () async {
        final services = _FakeServices();
        final saver = _FakeSaver();
        final runner = AttendanceExportRunner(services: services, saver: saver);
        for (var i = 0; i < 2; i++) {
          final outcome = await runner.exportToLagetSe(
            basis: basis(squadDetails: standardSquad(), roster: standardRoster),
            context: exportContext(
              links: standardLinks,
              roster: standardRoster,
            ),
            confirmedComplete: true,
          );
          expect(outcome.kind, ExportOutcomeKind.fileCreated);
        }
        expect(saver.saved.keys.single, 'laget_se_event-1.json');
        expect(services.records, hasLength(2));
        expect(services.records.map((r) => r.state).toSet(), {
          ExportState.fileCreated,
        });
        expect(services.records[0].sha, services.records[1].sha);
        // The log holds counts only.
        expect(services.records[0].summary.toString(), isNot(contains('Anna')));
      },
    );

    test('creates nothing when validation fails', () async {
      final services = _FakeServices();
      final saver = _FakeSaver();
      final outcome =
          await AttendanceExportRunner(
            services: services,
            saver: saver,
          ).exportToLagetSe(
            basis: basis(squadDetails: standardSquad(), roster: standardRoster),
            context: exportContext(roster: standardRoster),
            confirmedComplete: true,
          );
      expect(outcome.kind, ExportOutcomeKind.blocked);
      expect(saver.saved, isEmpty);
      expect(services.records, isEmpty);
    });

    test('logs a failure when the file cannot be saved', () async {
      final services = _FakeServices();
      final outcome =
          await AttendanceExportRunner(
            services: services,
            saver: _FakeSaver(fail: true),
          ).exportToLagetSe(
            basis: basis(squadDetails: standardSquad(), roster: standardRoster),
            context: exportContext(
              links: standardLinks,
              roster: standardRoster,
            ),
            confirmedComplete: true,
          );
      expect(outcome.kind, ExportOutcomeKind.failed);
      expect(services.records.single.state, ExportState.failed);
      expect(services.records.single.sha, isNull);
    });

    test('a cancelled save is neither created nor failed', () async {
      final services = _FakeServices();
      final outcome =
          await AttendanceExportRunner(
            services: services,
            saver: _FakeSaver(cancel: true),
          ).exportToLagetSe(
            basis: basis(squadDetails: standardSquad(), roster: standardRoster),
            context: exportContext(
              links: standardLinks,
              roster: standardRoster,
            ),
            confirmedComplete: true,
          );
      expect(outcome.kind, ExportOutcomeKind.cancelled);
      expect(services.records, isEmpty);
    });
  });

  test('export state distinguishes not exported, created and failed', () {
    final created = ExportRecord(
      id: '1',
      state: ExportState.fileCreated,
      createdAt: now,
    );
    final failed = ExportRecord(
      id: '2',
      state: ExportState.failed,
      createdAt: now,
    );
    expect(exportContext().state, ExportState.notExported);
    ExportContext withExports(List<ExportRecord> exports) => ExportContext(
      eventId: eventId,
      teamId: teamA,
      teamName: 'Lag',
      provider: lagetSeProvider,
      enabled: true,
      teamRoster: const {},
      links: const [],
      exports: exports,
    );
    expect(withExports([created]).state, ExportState.fileCreated);
    expect(withExports([failed, created]).state, ExportState.failed);
    expect(withExports([failed, created]).lastFileCreated, created);
    // A created file is never reported as synchronized.
    expect(withExports([created]).state, isNot(ExportState.verified));
  });
}

class _Record {
  _Record(this.state, this.sha, this.summary);
  final ExportState state;
  final String? sha;
  final Map<String, dynamic> summary;
}

class _FakeServices implements AttendanceExportServices {
  final records = <_Record>[];
  @override
  bool get isConfigured => true;
  @override
  Future<String> recordExport({
    required String eventId,
    required String teamId,
    required String provider,
    required ExportState state,
    String? externalActivityId,
    Map<String, dynamic> summary = const {},
    bool confirmedComplete = false,
    String? payloadSha256,
    String? errorCode,
  }) async {
    records.add(_Record(state, payloadSha256, summary));
    return 'record-${records.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeSaver implements ExportFileSaver {
  _FakeSaver({this.fail = false, this.cancel = false});
  final bool fail, cancel;
  final saved = <String, Uint8List>{};
  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (fail) throw StateError('disk full');
    if (cancel) return false;
    saved[fileName] = bytes;
    return true;
  }
}
