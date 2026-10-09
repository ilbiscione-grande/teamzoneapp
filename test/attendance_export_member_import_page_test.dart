import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/features/attendance_export/export_models.dart';
import 'package:teamzone_app/src/features/attendance_export/export_services.dart';
import 'package:teamzone_app/src/features/attendance_export/laget_se/laget_se_member_import.dart';
import 'package:teamzone_app/src/features/attendance_export/ui/laget_se_member_import_page.dart';

void main() {
  testWidgets('saves only approved links', (tester) async {
    final services = _Services();
    final settings = TeamIntegrationSettings(
      teamId: 't1',
      provider: 'laget_se',
      enabled: true,
      revision: 1,
      members: const [
        IntegrationTeamMember(
          personId: 'a',
          name: 'Anna Ek',
          roles: {'player'},
        ),
        IntegrationTeamMember(personId: 'b', name: 'Bo Ek', roles: {'player'}),
        IntegrationTeamMember(
          personId: 'k',
          name: 'Kalle Berg',
          roles: {'player'},
        ),
      ],
      links: const [],
    );
    final file = LagetSeMemberFile(
      teamSlug: 'Lag',
      sourceActivityId: '1',
      readAt: DateTime.utc(2026, 10, 8),
      members: const [
        LagetSeMember(id: '1', name: 'Anna Ek', role: 'player'),
        LagetSeMember(id: '2', name: 'Bo Ek', role: 'player'),
        LagetSeMember(id: '4', name: 'Karl Berg', role: 'player'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LagetSeMemberImportPage(
          settings: settings,
          file: file,
          services: services,
        ),
      ),
    );

    expect(find.text('Säkra förslag (2)'), findsOneWidget);
    expect(find.text('Spara 2 kopplingar'), findsOneWidget);
    // Unapprove Bo; Kalle (only a similar name) stays unlinked.
    await tester.tap(find.byKey(const ValueKey('import-approve-b')));
    await tester.pump();
    expect(find.text('Spara 1 kopplingar'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('import-save')));
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();
    expect(services.saved, ['a->1']);
  });
}

class _Services implements AttendanceExportServices {
  final saved = <String>[];
  @override
  bool get isConfigured => true;
  @override
  Future<TeamIntegrationSettings> saveMemberLink({
    required String teamId,
    required String provider,
    required String personId,
    required String externalId,
    required String externalName,
    required String externalRole,
    required int expectedRevision,
  }) async {
    saved.add('$personId->$externalId');
    return TeamIntegrationSettings(
      teamId: teamId,
      provider: provider,
      enabled: true,
      revision: 1,
      members: const [],
      links: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
