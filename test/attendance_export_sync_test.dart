import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/ui/attendance_export_page.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

void main() {
  test('sync job and preview parse from the server shape', () {
    final job = SyncJob.fromJson({
      'id': 'j1',
      'state': 'awaiting_approval',
      'requested_at': '2026-10-09T08:00:00Z',
      'preview_sha256': 'a' * 64,
      'preview': {
        'pageTitle': 'Träning',
        'unchanged': 3,
        'problems': ['x'],
        'changes': [
          {'name': 'Anna', 'role': 'player', 'from': 'absent', 'to': 'present'},
        ],
      },
    });
    expect(job.state, SyncJobState.awaitingApproval);
    expect(job.isRunning, isFalse);
    expect(job.preview!.changes.single.to, 'present');
    expect(job.preview!.unchanged, 3);
    expect(syncJobStateFromString('applying'), SyncJobState.applying);
    expect(
      SyncJob.fromJson({
        'id': 'j',
        'state': 'queued',
        'requested_at': '2026-10-09T08:00:00Z',
      }).isRunning,
      isTrue,
    );
    final agent = SyncAgentStatus(lastSeenAt: DateTime.utc(2026, 10, 9, 8));
    expect(agent.isOnline(DateTime.utc(2026, 10, 9, 8, 1)), isTrue);
    expect(agent.isOnline(DateTime.utc(2026, 10, 9, 8, 5)), isFalse);
  });

  testWidgets('send, see the preview and approve exactly it', (tester) async {
    final services = _Services();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceExportPage(
          eventId: 'e1',
          teamId: 't1',
          calendar: _Calendar(),
          services: services,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sync = find.byKey(const Key('export-sync'));
    await tester.scrollUntilVisible(
      sync,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    ButtonStyleButton button() => tester.widget<ButtonStyleButton>(sync);
    expect(button().onPressed, isNull, reason: 'not confirmed yet');
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('export-blockers'), skipOffstage: false),
          )
          .data,
      'Innan du kan skicka: kryssa i att närvaron är färdigregistrerad',
    );
    await tester.tap(find.byKey(const Key('export-confirm-complete')));
    await tester.pump();
    expect(button().onPressed, isNotNull);
    expect(find.byKey(const Key('export-blockers')), findsNothing);

    await tester.tap(sync);
    // An indeterminate progress bar runs while the agent works.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(services.requested.single['activityId'], '30960339');
    expect(
      (services.requested.single['participants'] as List).map(
        (p) => (p as Map)['id'],
      ),
      ['1', '2'],
    );

    // The agent has reported its preview.
    services.job = SyncJob.fromJson({
      'id': 'j1',
      'state': 'awaiting_approval',
      'requested_at': '2026-10-09T08:00:00Z',
      'preview_sha256': 'b' * 64,
      'preview': {
        'unchanged': 1,
        'problems': [],
        'changes': [
          {'name': 'Anna', 'role': 'player', 'from': 'absent', 'to': 'present'},
        ],
      },
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Anna (spelare): ? → ✓'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Anna (spelare): ? → ✓'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('sync-approve')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('sync-approve')));
    await tester.pumpAndSettle();
    expect(services.approved, ['j1:${'b' * 64}']);
  });

  test('without activity link: sync allowed, file still blocked', () {
    final basis = AttendanceExportBasis(
      eventId: 'e1',
      teamId: 't1',
      eventTitle: 'Träning',
      eventType: 'training',
      eventState: 'scheduled',
      startsAt: DateTime.utc(2026, 10, 1, 17),
      endsAt: DateTime.utc(2026, 10, 1, 18),
      eventTeamIds: const {'t1'},
      ended: true,
      candidates: const [
        ExportCandidate(
          personId: 'p1',
          name: 'Anna',
          membership: ExportMembership.team,
          teamRoles: {'player'},
          attendance: ExplicitAttendance.present,
        ),
      ],
    );
    const context = ExportContext(
      eventId: 'e1',
      teamId: 't1',
      teamName: 'P14',
      provider: lagetSeProvider,
      enabled: true,
      externalTeamRef: 'EksjoFotbollJ18',
      teamRoster: {
        'p1': {'player'},
      },
      links: [
        ExternalMemberLink(
          teamId: 't1',
          personId: 'p1',
          externalId: '1',
          externalName: 'Anna',
          externalRole: 'player',
        ),
      ],
    );
    final file = generateLagetSeExport(
      basis: basis,
      context: context,
      confirmedComplete: true,
    );
    expect(file.file, isNull);
    expect(file.errors.map((e) => e.code), ['missing_activity_id']);
    final sync = generateLagetSeExport(
      basis: basis,
      context: context,
      confirmedComplete: true,
      requireActivity: false,
    );
    expect(sync.errors, isEmpty);
    expect(sync.file!.toJson()['activityId'], '');
  });

  testWidgets('agent locates the activity, or the admin chooses', (
    tester,
  ) async {
    final services = _Services(activityId: null);
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceExportPage(
          eventId: 'e1',
          teamId: 't1',
          calendar: _Calendar(),
          services: services,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('export-confirm-complete')),
      200,
      scrollable: scrollable,
    );
    await tester.tap(find.byKey(const Key('export-confirm-complete')));
    await tester.pump();
    final sync = find.byKey(const Key('export-sync'));
    await tester.scrollUntilVisible(sync, 200, scrollable: scrollable);
    expect(tester.widget<ButtonStyleButton>(sync).onPressed, isNotNull);
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('export-generate')))
          .onPressed,
      isNull,
      reason: 'a file needs the activity link',
    );

    await tester.tap(sync);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(services.requested.single['activityId'], '');

    // The agent found two activities at the same time.
    services.job = SyncJob.fromJson({
      'id': 'j1',
      'state': 'needs_activity',
      'requested_at': '2026-10-09T08:00:00Z',
      'message': '2 aktiviteter i laget.se börjar samma tid. Välj rätt.',
      'candidates': [
        {'id': '5002', 'date': '1 okt 19:00 - 20:30', 'label': 'Match'},
        {'id': '5003', 'date': '1 okt 19:00 - 20:00', 'label': 'Träning'},
      ],
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final choose = find.descendant(
      of: find.byKey(const ValueKey('sync-candidate-5003')),
      matching: find.text('Välj'),
    );
    await tester.scrollUntilVisible(choose, 200, scrollable: scrollable);
    await tester.tap(choose);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(services.activityId, '5003');
    expect(services.requested.last['activityId'], '5003');
  });
}

class _Calendar implements CalendarServices {
  @override
  Future<EventDetails> getEventDetails(String eventId) async =>
      EventDetails.fromJson({
        'id': 'e1',
        'title': 'Träning',
        'event_type': 'training',
        'state': 'scheduled',
        'starts_at': '2026-10-01T17:00:00Z',
        'ends_at': '2026-10-01T18:30:00Z',
        'timezone': 'Europe/Stockholm',
        'revision': 1,
        'teams': [
          {'team_id': 't1', 'name': 'P14', 'relation': 'primary'},
        ],
      });

  @override
  Future<SquadDetails> getEventSquad(String eventId) async =>
      SquadDetails.fromJson({
        'event_id': 'e1',
        'attendance': [
          {'person_id': 'p1', 'name': 'Anna', 'status': 'present'},
          {'person_id': 'p2', 'name': 'Björn', 'status': 'absent'},
        ],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Services implements AttendanceExportServices {
  _Services({this.activityId = '30960339'});
  final requested = <Map<String, Object>>[];
  final approved = <String>[];
  SyncJob? job;

  /// null = the event has no laget.se activity link yet.
  String? activityId;

  @override
  bool get isConfigured => true;

  @override
  Future<ExportContext> setActivityLink({
    required String eventId,
    required String teamId,
    required String provider,
    required String? externalActivityId,
    required int expectedRevision,
  }) async {
    activityId = externalActivityId;
    return getExportContext(
      eventId: eventId,
      teamId: teamId,
      provider: provider,
    );
  }

  @override
  Future<ExportContext> getExportContext({
    required String eventId,
    required String teamId,
    required String provider,
  }) async => ExportContext(
    eventId: 'e1',
    teamId: 't1',
    teamName: 'P14',
    provider: lagetSeProvider,
    enabled: true,
    externalTeamRef: 'EksjoFotbollJ18',
    agent: SyncAgentStatus(lastSeenAt: DateTime.now(), lagetSessionOk: true),
    activityLink: activityId == null
        ? null
        : ExternalActivityLink(teamId: 't1', externalActivityId: activityId!),
    teamRoster: const {
      'p1': {'player'},
      'p2': {'player'},
    },
    links: const [
      ExternalMemberLink(
        teamId: 't1',
        personId: 'p1',
        externalId: '1',
        externalName: 'Anna',
        externalRole: 'player',
      ),
      ExternalMemberLink(
        teamId: 't1',
        personId: 'p2',
        externalId: '2',
        externalName: 'Björn',
        externalRole: 'player',
      ),
    ],
    syncJobs: [?job],
  );

  @override
  Future<SyncJob> requestSync({
    required String eventId,
    required String teamId,
    required String provider,
    required Map<String, Object> payload,
    Map<String, dynamic> summary = const {},
    required bool confirmedComplete,
  }) async {
    requested.add(payload);
    return job = SyncJob(
      id: 'j1',
      state: SyncJobState.queued,
      requestedAt: DateTime.now(),
    );
  }

  @override
  Future<SyncJob> approveSync({
    required String jobId,
    required String previewSha256,
  }) async {
    approved.add('$jobId:$previewSha256');
    return job = SyncJob(
      id: jobId,
      state: SyncJobState.verified,
      requestedAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
