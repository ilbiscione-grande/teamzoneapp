import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_runner.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_adapter.dart';
import 'package:teamzone_app/src/features/attendance_export/ui/attendance_export_page.dart';
import 'package:teamzone_app/src/features/calendar/calendar_models.dart';
import 'package:teamzone_app/src/features/calendar/calendar_services.dart';

void main() {
  testWidgets('summary, confirmation gate and created status', (tester) async {
    final services = _Services();
    final saver = _Saver();
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceExportPage(
          eventId: 'e1',
          teamId: 't1',
          calendar: _Calendar(),
          services: services,
          saver: saver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status: Inte exporterad'), findsOneWidget);
    expect(find.text('Närvarande spelare'), findsOneWidget);
    expect(
      find.textContaining('1 person har ingen registrerad närvaro'),
      findsOneWidget,
    );
    ButtonStyleButton generate() => tester.widget<ButtonStyleButton>(
      find.byKey(const Key('export-generate')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('export-generate')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(generate().onPressed, isNull);

    await tester.tap(find.byKey(const Key('export-confirm-complete')));
    await tester.pump();
    expect(generate().onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(const Key('export-generate')));
    await tester.tap(find.byKey(const Key('export-generate')));
    await tester.pumpAndSettle();
    expect(saver.fileNames, ['laget_se_e1.json']);
    expect(services.recorded, [ExportState.fileCreated]);
    expect(
      find.textContaining('Exportfil skapad', findRichText: true),
      findsWidgets,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('export-status')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('ej bekräftad i laget.se'), findsOneWidget);
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
          {'person_id': 'p3', 'name': 'Cecilia', 'status': 'unknown'},
        ],
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Services implements AttendanceExportServices {
  final recorded = <ExportState>[];
  @override
  bool get isConfigured => true;

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
    activityLink: const ExternalActivityLink(
      teamId: 't1',
      externalActivityId: '30960339',
    ),
    teamRoster: const {
      'p1': {'player'},
      'p2': {'player'},
      'p3': {'player'},
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
    exports: [
      for (final state in recorded)
        ExportRecord(
          id: 'r',
          state: state,
          createdAt: DateTime.utc(2026, 10, 8),
        ),
    ],
  );

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
    recorded.add(state);
    return 'r';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Saver implements ExportFileSaver {
  final fileNames = <String>[];
  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    fileNames.add(fileName);
    return true;
  }
}
