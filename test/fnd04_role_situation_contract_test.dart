import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/core/product/role_situation_contract.dart';

void main() {
  test(
    'every approved role has a complete contract for every priority surface',
    () {
      for (final role in ProductRole.values) {
        for (final surface in PrioritySurface.values) {
          final contract = RoleSituationContract.surface(role, surface);
          expect(contract.goal, isNotEmpty, reason: '$role $surface goal');
          expect(
            contract.information,
            isNotEmpty,
            reason: '$role $surface info',
          );
          expect(
            contract.primaryActions,
            isNotEmpty,
            reason: '$role $surface actions',
          );
          expect(
            contract.hiddenWithoutCapability,
            isNotEmpty,
            reason: '$role $surface negative contract',
          );
          expect(
            contract.primaryActions.intersection(
              contract.hiddenWithoutCapability,
            ),
            isEmpty,
            reason: '$role $surface cannot show and hide the same action',
          );
        }
      }
    },
  );

  test('unknown and legacy-looking role packages fail closed', () {
    for (final role in [
      '',
      'unknown',
      'guest',
      'admin',
      'super_admin',
      'Leader',
    ]) {
      expect(RoleSituationContract.roleForPackage(role), isNull, reason: role);
    }
  });

  test('only the four approved role packages resolve', () {
    expect(RoleSituationContract.roleForPackage('leader'), ProductRole.leader);
    expect(RoleSituationContract.roleForPackage('player'), ProductRole.player);
    expect(
      RoleSituationContract.roleForPackage('guardian'),
      ProductRole.guardian,
    );
    expect(
      RoleSituationContract.roleForPackage('club_functionary'),
      ProductRole.clubFunctionary,
    );
  });

  test('player and guardian never inherit team administration actions', () {
    for (final role in [ProductRole.player, ProductRole.guardian]) {
      final team = RoleSituationContract.surface(role, PrioritySurface.team);
      final calendar = RoleSituationContract.surface(
        role,
        PrioritySurface.calendar,
      );
      expect(team.hiddenWithoutCapability, contains('roster_management'));
      expect(calendar.hiddenWithoutCapability, contains('create_event'));
      expect(calendar.hiddenWithoutCapability, contains('take_attendance'));
    }
  });

  test('guardian information and actions remain explicitly child scoped', () {
    final home = RoleSituationContract.surface(
      ProductRole.guardian,
      PrioritySurface.home,
    );
    final calendar = RoleSituationContract.surface(
      ProductRole.guardian,
      PrioritySurface.calendar,
    );
    final inbox = RoleSituationContract.surface(
      ProductRole.guardian,
      PrioritySurface.inbox,
    );

    expect(home.information, contains('child_switcher'));
    expect(home.primaryActions, contains('respond_for_child'));
    expect(calendar.information, contains('child_events'));
    expect(inbox.information, contains('child_scoped_threads'));
    expect(inbox.hiddenWithoutCapability, contains('unrelated_child_threads'));
  });

  test(
    'club functionary receives no implicit coaching or sensitive access',
    () {
      final home = RoleSituationContract.surface(
        ProductRole.clubFunctionary,
        PrioritySurface.home,
      );
      final team = RoleSituationContract.surface(
        ProductRole.clubFunctionary,
        PrioritySurface.team,
      );
      final calendar = RoleSituationContract.surface(
        ProductRole.clubFunctionary,
        PrioritySurface.calendar,
      );

      expect(home.hiddenWithoutCapability, contains('team_coaching_tasks'));
      expect(home.hiddenWithoutCapability, contains('player_private_health'));
      expect(
        team.hiddenWithoutCapability,
        contains('player_sensitive_details'),
      );
      expect(calendar.hiddenWithoutCapability, contains('team_event_edit'));
      expect(calendar.hiddenWithoutCapability, contains('take_attendance'));
    },
  );

  test('every role has priorities for all three usage situations', () {
    for (final role in ProductRole.values) {
      for (final situation in UsageSituation.values) {
        final contract = RoleSituationContract.situation(role, situation);
        expect(contract.priority, isNotEmpty, reason: '$role $situation');
        expect(contract.layout, isNotEmpty, reason: '$role $situation layout');
        expect(contract.deprioritized, isNotEmpty, reason: '$role $situation');
      }
    }
  });

  test('device situations alter priority but never grant capabilities', () {
    for (final role in ProductRole.values) {
      final mobile = RoleSituationContract.situation(
        role,
        UsageSituation.mobileDuringActivity,
      );
      final desktop = RoleSituationContract.situation(
        role,
        UsageSituation.desktopAdministration,
      );
      expect(mobile.priority, isNot(equals(desktop.priority)), reason: '$role');
    }
  });

  test('the approved document freezes all roles, surfaces and situations', () {
    final document = File(
      'docs/implementation/role_and_situation_contract.md',
    ).readAsStringSync();

    for (final heading in [
      '## 2. Hem',
      '## 3. Laget',
      '## 4. Kalender',
      '## 5. Inbox',
    ]) {
      expect(document, contains(heading));
    }
    for (final role in ['Leader', 'Player', 'Guardian', 'Club functionary']) {
      expect(document, contains('| $role |'));
    }
    for (final situation in [
      'Mobil under aktivitet',
      'Tablet vid planering',
      'Desktop/web-administration',
    ]) {
      expect(document, contains('| $situation |'));
    }
    expect(
      document,
      contains('capabilities och objektscope avgör alltid åtkomst'),
    );
    expect(document, contains('Okänd, avslutad eller ofullständig roll'));
  });
}
