import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamzone_app/src/app/teamzone_app.dart';
import 'package:teamzone_app/src/core/config/app_environment.dart';
import 'package:teamzone_app/src/core/identity/identity_models.dart';
import 'package:teamzone_app/src/core/identity/identity_services.dart';
import 'package:teamzone_app/src/core/preferences/theme_persistence.dart';
import 'package:teamzone_app/src/core/supabase/supabase_bootstrap.dart';
import 'package:teamzone_app/src/features/account/profile_models.dart';
import 'package:teamzone_app/src/features/account/profile_services.dart';
import 'package:teamzone_app/src/features/roster/roster_models.dart';
import 'package:teamzone_app/src/features/roster/roster_services.dart';

void main() {
  testWidgets('multiple addresses and club choice use the new settings', (
    tester,
  ) async {
    final profile = _Profile();
    await _openSettingsProfile(tester, profile);
    await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('edit-profile-addresses'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('privacy-add-address')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('privacy-address_label')),
      'Hos pappa',
    );
    await tester.enterText(
      find.byKey(const ValueKey('privacy-new_street')),
      'Andra gatan 2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('privacy-new_postal')),
      '12345',
    );
    await tester.enterText(
      find.byKey(const ValueKey('privacy-new_city')),
      'Vetlanda',
    );
    await tester.tap(find.byKey(const ValueKey('privacy-save-fields')));
    await tester.pumpAndSettle();
    expect(profile.privacyCommands.single.$1, 'save_profile_address');
    expect(profile.privacyCommands.single.$2['address_label'], 'Hos pappa');
    expect(profile.privacyCommands.single.$2['target'], 'profile');
    expect(find.text('Hos mamma'), findsWidgets);
    expect(find.text('Hos pappa'), findsOneWidget);
    final clubChoice = find.byKey(const ValueKey('club-address-club-null'));
    await tester.ensureVisible(clubChoice);
    await tester.tap(clubChoice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hos pappa').last);
    await tester.pumpAndSettle();
    expect(profile.privacyCommands.last.$1, 'choose_club_address');
    expect(profile.privacyCommands.last.$2['club'], 'club');
    expect(profile.privacyCommands.last.$2['address_id'], isNotNull);
  });
  testWidgets(
    'protection requires deliberate alias and save, cancellation writes nothing',
    (tester) async {
      final profile = _Profile();
      await _openSettingsProfile(tester, profile);
      await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('edit-profile-addresses'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('privacy-protection'));
      await tester.scrollUntilVisible(
        toggle,
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('privacy-settings-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('privacy-new_alias')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.tap(find.text('Avbryt'));
      await tester.pumpAndSettle();
      expect(profile.privacyCommands, isEmpty);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('privacy-new_alias')),
        'Spelare A',
      );
      await tester.enterText(
        find.byKey(const ValueKey('privacy-new_safe_email')),
        'safe@example.se',
      );
      await tester.tap(find.byKey(const ValueKey('privacy-save-fields')));
      await tester.pumpAndSettle();
      expect(profile.privacyCommands.single.$1, 'save_profile_privacy');
      expect(profile.privacyCommands.single.$2['enable_protection'], true);
      expect(profile.privacyCommands.single.$2['new_alias'], 'Spelare A');
      final subject = find.byKey(const ValueKey('privacy-subject-profile'));
      final privacyScroll = find.descendant(
        of: find.byKey(const ValueKey('privacy-settings-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(subject, -200, scrollable: privacyScroll);
      expect(
        find.descendant(of: subject, matching: find.text('Spelare A')),
        findsWidgets,
      );
      await tester.scrollUntilVisible(toggle, 200, scrollable: privacyScroll);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('privacy-save-fields')));
      await tester.pumpAndSettle();
      expect(profile.privacyCommands.last.$2['enable_protection'], false);
      await tester.scrollUntilVisible(subject, -200, scrollable: privacyScroll);
      expect(
        find.descendant(of: subject, matching: find.text('Ada Andersson')),
        findsWidgets,
      );
    },
  );
  for (final conflict in [false, true]) {
    testWidgets('contact proposal approval, conflict=$conflict', (
      tester,
    ) async {
      final profile = _Profile()
        ..changes = [
          ContactChangeRequest(
            id: 'change',
            name: 'Barn Spelare',
            clubName: 'Testklubben',
            before: {'email': 'old@example.se'},
            proposed: {'email': 'new@example.se'},
            conflict: conflict,
          ),
        ];
      await _openSettingsProfile(tester, profile);
      await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('approve-contact-change'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(find.text('Nuvarande: old@example.se'), findsOneWidget);
      expect(find.text('Föreslaget: new@example.se'), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed == null, conflict);
      await tester.tap(conflict ? find.text('Avvisa') : button);
      await tester.pumpAndSettle();
      expect(profile.decisions, [('change', !conflict)]);
      expect(
        find.byKey(const ValueKey('contact-request-change')),
        findsNothing,
      );
    });
  }
  testWidgets('lost profile response retries the same complete save once', (
    tester,
  ) async {
    final profile = _Profile()..loseResponse = true;
    await _openSettingsProfile(tester, profile);
    await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('my-profile-phone')),
      '0701234567',
    );
    await tester.tap(find.byKey(const ValueKey('save-my-profile')));
    await tester.pumpAndSettle();
    expect(profile.revision, 2);
    await tester.tap(find.byKey(const ValueKey('save-my-profile')));
    await tester.pumpAndSettle();
    expect(profile.revision, 2);
    expect(profile.saveKeys.length, 2);
    expect(profile.saveKeys.toSet().length, 1);
    expect(find.byKey(const ValueKey('save-my-profile')), findsNothing);
  });
  testWidgets('own details are edited from the profile app bar', (
    tester,
  ) async {
    final profile = _Profile();
    await _openSettingsProfile(tester, profile);
    await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('my-profile-email')),
      'inte-en-adress',
    );
    profile.failWith = const ProfileException('invalid_email');
    await tester.tap(find.byKey(const ValueKey('save-my-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Kontrollera e-postadressen.'), findsOneWidget);
    profile.failWith = null;
    await tester.enterText(
      find.byKey(const ValueKey('my-profile-email')),
      'ada@mail.se',
    );
    await tester.enterText(
      find.byKey(const ValueKey('my-profile-phone')),
      '070-123 45 67',
    );
    await tester.tap(find.byKey(const ValueKey('save-my-profile')));
    await tester.pumpAndSettle();
    expect(profile.saved, ('Ada Andersson', 'ada@mail.se', '070-123 45 67'));
    // A new name shows in the menu straight away.
    await _openSettingsProfile(tester, profile);
    await tester.enterText(
      find.byKey(const ValueKey('my-profile-name')),
      'Ada Nyberg',
    );
    await tester.tap(find.byKey(const ValueKey('save-my-profile')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('drawer-own-name'))).data,
      'Ada Nyberg',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new picture can come from the camera or the photos', (
    tester,
  ) async {
    await _openSettingsProfile(tester, _Profile());
    await tester.tap(find.byKey(const ValueKey('pick-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('avatar-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('avatar-gallery')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('avatar-camera')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('club administrators choose the club colours', (tester) async {
    final profile = _Profile();
    await tester.pumpWidget(_app(profile, clubAdmin: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trupp'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hantera'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('club-colors')),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('club-colors')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-colors-preview')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('club-accent-hex')))
          .controller!
          .text,
      '#c6f04d',
    );
    await tester.tap(find.byKey(const ValueKey('club-primary-#00843d')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('club-accent-hex')),
      'not a colour',
    );
    await tester.pump();
    expect(find.text('Ogiltig färg'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('club-accent-hex')),
      'FFD100',
    );
    await tester.tap(find.byKey(const ValueKey('club-colors-save')));
    await tester.pumpAndSettle();
    expect(profile.colors.primary, '#00843d');
    expect(profile.colors.accent, '#ffd100');
    expect(find.byKey(const ValueKey('club-colors-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light, dark or system is chosen in personal settings', (
    tester,
  ) async {
    final persistence = MemoryThemePersistence();
    await tester.pumpWidget(_app(_Profile(), themePersistence: persistence));
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
    expect(brightness(), Brightness.light);
    await tester.scrollUntilVisible(
      find.text('Inställningar').last,
      250,
      scrollable: find.descendant(
        of: find.byKey(const Key('app-navigation-panel-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Inställningar').last);
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('setting-theme-mode'));
    expect(selector, findsOneWidget);
    await tester.tap(
      find.descendant(of: selector, matching: find.text('Mörkt')),
    );
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    expect(await persistence.readBrightnessMode(), 'dark');
    await tester.tap(
      find.descendant(of: selector, matching: find.text('Ljust')),
    );
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    expect(await persistence.readBrightnessMode(), 'light');
  });

  testWidgets('club settings are a tab for club administrators only', (
    tester,
  ) async {
    final profile = _Profile();
    await _openSettings(tester, profile);
    expect(find.widgetWithText(Tab, 'Klubb'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _openSettings(tester, profile, clubAdmin: true);
    await tester.tap(find.widgetWithText(Tab, 'Klubb'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('club-settings-club')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('club-settings-club')),
        matching: find.text('Testklubben'),
      ),
      findsOneWidget,
    );
    // Public pages have their own settings tab.
    expect(find.byKey(const ValueKey('club-public-club')), findsNothing);
    expect(
      find.byKey(const ValueKey('club-badge-upload-club')),
      findsOneWidget,
    );
    expect(find.text('Ladda upp klubbmärke'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('club-verification-club')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('club-colors-club')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('club-primary-#0b1f3a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('club-colors-save')));
    await tester.pumpAndSettle();
    expect(profile.colors.primary, '#0b1f3a');
    expect(tester.takeException(), isNull);
  });

  testWidgets('login address change goes through support', (tester) async {
    final profile = _Profile();
    await _openSettingsProfile(tester, profile);
    await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
    await tester.pumpAndSettle();
    final request = find.byKey(const ValueKey('request-login-email'));
    await tester.scrollUntilVisible(
      request,
      200,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(request);
    await tester.pumpAndSettle();
    await tester.tap(request);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('login-email-new')),
      'ny@mail.se',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-email-reason')),
      'Bytt jobb',
    );
    await tester.tap(find.byKey(const ValueKey('send-login-email-request')));
    await tester.pumpAndSettle();
    expect(profile.requested, ('ny@mail.se', 'Bytt jobb'));
    expect(
      find.text('Väntar på support: byte till ny@mail.se.'),
      findsOneWidget,
    );
    // Support approves; the person then confirms through the email link.
    profile.change = const LoginEmailChange(
      id: 'request',
      requestedEmail: 'ny@mail.se',
      state: 'approved',
    );
    await tester.tap(find.byTooltip('Stäng'));
    await tester.pumpAndSettle();
    await _openSettingsProfile(tester, profile);
    await tester.tap(find.widgetWithText(Tab, 'Kontakt'));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm-login-email'));
    await tester.scrollUntilVisible(
      confirm,
      200,
      scrollable: find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(profile.confirmed, 'ny@mail.se');
    expect(find.text('Kolla din e-post'), findsOneWidget);
  });

  testWidgets('leader sees and keeps contact details on a member profile', (
    tester,
  ) async {
    final profile = _Profile()
      ..contact = const PersonContact(
        canSeeContact: true,
        canEditClubContact: true,
        contactEmail: 'forälder@mail.se',
        contactSource: 'club',
      );
    await _openMember(tester, profile);
    expect(find.byKey(const ValueKey('person-contact')), findsOneWidget);
    expect(find.text('forälder@mail.se'), findsOneWidget);
    expect(find.text('Ifyllt av klubben.'), findsOneWidget);
    // Contact details are edited with the rest, from the top bar.
    expect(find.byKey(const ValueKey('edit-club-contact')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('edit-member')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('club-contact-phone')),
      '0701234567',
    );
    await tester.ensureVisible(find.text('Spara person'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spara person'));
    await tester.pumpAndSettle();
    expect(profile.clubContact, ('ada', 'forälder@mail.se', '0701234567'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('member card flips to show the address', (tester) async {
    final profile = _Profile()
      ..card = const MemberCard(
        personId: 'ada',
        name: 'Ada Spelare',
        clubId: 'club',
        clubName: 'Testklubben',
        teamName: 'F2012',
        memberNumber: 'AB12CD34',
        roles: ['player'],
        birthYear: 2012,
        contact: PersonContact(
          canSeeContact: true,
          streetAddress: 'Storgatan 1',
          postalCode: '123 45',
          city: 'Alby',
          phone: '0701234567',
        ),
      );
    await _openMember(tester, profile);
    await tester.ensureVisible(find.byKey(const ValueKey('open-member-card')));
    await tester.tap(find.byKey(const ValueKey('open-member-card')));
    await tester.pumpAndSettle();
    expect(find.text('MEDLEMSKORT'), findsOneWidget);
    expect(find.text('Testklubben'), findsWidgets);
    expect(find.text('AB12CD34'), findsOneWidget);
    expect(find.text('Spelare'), findsWidgets);
    expect(find.text('Storgatan 1\n123 45 Alby'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('member-card-flip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('member-card-back')), findsOneWidget);
    expect(find.text('Storgatan 1\n123 45 Alby'), findsOneWidget);
    expect(find.text('Visa framsidan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('member-card-close')));
    await tester.pumpAndSettle();
    expect(find.text('MEDLEMSKORT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card back is locked for others; full screen on phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = _Profile()
      ..card = const MemberCard(
        personId: 'ada',
        name: 'Ada Spelare',
        clubId: 'club',
        clubName: 'Testklubben',
        teamName: 'F2012',
        memberNumber: 'AB12CD34',
      );
    await _openMember(tester, profile);
    await tester.ensureVisible(find.byKey(const ValueKey('open-member-card')));
    await tester.tap(find.byKey(const ValueKey('open-member-card')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Dialog)).width, 390);
    await tester.tap(find.byKey(const ValueKey('member-card-flip')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('member-card-back-locked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a leader sees info and statistics on a player profile', (
    tester,
  ) async {
    final profile = _Profile()
      ..statistics = const PersonStatistics(
        trainingsTotal: 10,
        trainingsAttended: 8,
        goals: 3,
        averageResponseMinutes: 95,
        app: AppUsage(
          messagesSent: 5,
          activeDays30: 3,
          currentStreak: 2,
          longestStreak: 6,
        ),
      );
    await _openMember(tester, profile);
    expect(find.widgetWithText(Tab, 'Medlemsinfo'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Statistik'), findsOneWidget);
    // Settings are only on your own profile.
    expect(find.widgetWithText(Tab, 'Inställningar'), findsNothing);
    await tester.tap(find.widgetWithText(Tab, 'Statistik'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stat-goals')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('80 %'), findsOneWidget);
    expect(find.text('1 h 35 min'), findsOneWidget);
    // App use is the player's own, also when a leader looks.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('stat-messages')),
      find.byKey(const ValueKey('person-statistics')),
      const Offset(0, -200),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stat-messages')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('own profile adds app statistics and personal settings', (
    tester,
  ) async {
    final profile = _Profile()
      ..statistics = const PersonStatistics(
        isSelf: true,
        app: AppUsage(
          messagesSent: 12,
          activeDays30: 9,
          currentStreak: 4,
          longestStreak: 7,
        ),
      );
    await _openMember(tester, profile, self: true);
    await tester.tap(find.widgetWithText(Tab, 'Statistik'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('stat-messages')),
      find.byKey(const ValueKey('person-statistics')),
      const Offset(0, -200),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stat-streak')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stat-messages')),
        matching: find.text('12'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('edit-own-profile-appbar')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Inställningar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('personal-settings')), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('setting-week-numbers')),
      find.byKey(const ValueKey('personal-settings')),
      const Offset(0, -200),
    );
    expect(find.text('Standardvy för kalendern'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teammates see no contact details', (tester) async {
    final profile = _Profile()..contact = const PersonContact();
    await _openMember(tester, profile);
    expect(find.text('Ada Spelare'), findsWidgets);
    expect(find.byKey(const ValueKey('person-contact')), findsNothing);
  });
}

Future<void> _openSettings(
  WidgetTester tester,
  _Profile profile, {
  bool clubAdmin = false,
}) async {
  await tester.pumpWidget(_app(profile, clubAdmin: clubAdmin));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Inställningar').last,
    250,
    scrollable: find.descendant(
      of: find.byKey(const Key('app-navigation-panel-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(find.text('Inställningar').last);
  await tester.pumpAndSettle();
}

Future<void> _openSettingsProfile(WidgetTester tester, _Profile profile) async {
  await tester.pumpWidget(_app(profile, roster: const _Roster(self: true)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Laget'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Trupp'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ada Spelare'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('edit-own-profile-appbar')));
  await tester.pumpAndSettle();
}

Future<void> _openMember(
  WidgetTester tester,
  _Profile profile, {
  bool self = false,
}) async {
  await tester.pumpWidget(_app(profile, roster: _Roster(self: self)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Laget'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Trupp'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ada Spelare'));
  await tester.pumpAndSettle();
}

Widget _app(
  _Profile profile, {
  _Roster roster = const _Roster(),
  bool clubAdmin = false,
  ThemePersistence themePersistence = const StatelessThemePersistence(),
}) => TeamZoneApp(
  environment: const AppEnvironment(name: 'prof01'),
  locale: const Locale('sv'),
  services: AppServices(
    identity: _Identity(clubAdmin: clubAdmin),
    roster: roster,
    profile: profile,
    themePersistence: themePersistence,
    isConfigured: true,
  ),
);

class _Profile extends UnconfiguredProfileServices {
  final List<(String, Map<String, dynamic>)> privacyCommands = [];
  final List<Map<String, dynamic>> addresses = [
    {
      'id': 'address-1',
      'label': 'Hos mamma',
      'street': 'Första gatan 1',
      'postal': '12345',
      'city': 'Vetlanda',
      'revision': 1,
    },
  ];
  String? clubAddress;
  bool privacyEnabled = false;
  @override
  Future<List<Map<String, dynamic>>> listPrivacySubjects() async => [
    {'id': 'profile', 'name': 'Ada Andersson'},
  ];
  @override
  Future<Map<String, dynamic>> getAddressPrivacy(String profileId) async => {
    'profile_id': 'profile',
    'name': privacyEnabled ? 'Spelare A' : 'Ada Andersson',
    'protected': privacyEnabled,
    'alias': privacyEnabled ? 'Spelare A' : 'Ada Andersson',
    'revision': 0,
    'addresses': List.of(addresses),
    'clubs': [
      {'id': 'club', 'name': 'Testklubben', 'address_id': clubAddress},
    ],
    'grants': [],
    'candidates': [],
  };
  @override
  Future<void> saveAddressPrivacyCommand(
    String command,
    Map<String, dynamic> values,
  ) async {
    privacyCommands.add((command, values));
    if (command == 'save_profile_address') {
      addresses.add({
        'id': values['address_id'],
        'label': values['address_label'],
        'street': values['new_street'],
        'postal': values['new_postal'],
        'city': values['new_city'],
        'revision': 1,
      });
    }
    if (command == 'choose_club_address') {
      clubAddress = values['address_id'] as String?;
    }
    if (command == 'save_profile_privacy') {
      privacyEnabled = values['enable_protection'] == true;
    }
  }

  List<ContactChangeRequest> changes = [];
  final List<(String, bool)> decisions = [];
  @override
  Future<List<ContactChangeRequest>> listContactChanges() async =>
      List.of(changes);
  @override
  Future<void> decideContactChange(String id, {required bool approve}) async {
    decisions.add((id, approve));
    changes.removeWhere((item) => item.id == id);
  }

  Object? failWith;
  (String, String?, String?)? saved;
  (String, String)? requested;
  String? confirmed;
  (String, String?, String?)? clubContact;
  LoginEmailChange? change;
  PersonContact contact = const PersonContact();
  MemberCard? card;
  PersonStatistics statistics = const PersonStatistics();
  ClubColors colors = const ClubColors(accent: '#c6f04d');

  @override
  Future<ClubColors> getClubColors(String clubId) async => colors;

  @override
  Future<ClubColors> setClubColors({
    required String clubId,
    String? primary,
    String? accent,
  }) async => colors = ClubColors(primary: primary, accent: accent);

  @override
  Future<PersonStatistics> getPersonStatistics({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => statistics;

  @override
  Future<MemberCard> getMemberCard({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => card!;
  String name = 'Ada Andersson';
  String? email;
  String? phone;
  int revision = 1;
  String? postal;
  bool loseResponse = false;
  final saveKeys = <String>[];
  final receipts = <String, int>{};

  @override
  Future<MyProfileDetails> getMyProfile() async => MyProfileDetails(
    profileId: 'profile',
    displayName: name,
    contactEmail: email,
    phone: phone,
    loginEmail: 'ada@x.se',
    revision: revision,
    emailChange: change,
  );

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
    saveKeys.add(idempotencyKey);
    if (receipts.containsKey(idempotencyKey)) return receipts[idempotencyKey]!;
    if (failWith != null) throw failWith!;
    if (postalCode == '!') throw const ProfileException('invalid_address');
    if (expectedRevision != revision) {
      throw const ProfileException('stale_revision');
    }
    saved = (displayName, contactEmail, phone);
    name = displayName;
    email = contactEmail;
    this.phone = phone;
    postal = postalCode;
    receipts[idempotencyKey] = ++revision;
    if (loseResponse) {
      loseResponse = false;
      throw StateError('lost response');
    }
    return revision;
  }

  @override
  Future<String> uploadAvatar({
    required String mimeType,
    required Uint8List bytes,
    required String idempotencyKey,
  }) async => 'avatar';

  @override
  Future<void> requestLoginEmailChange({
    required String newEmail,
    required String reason,
  }) async {
    requested = (newEmail, reason);
    change = LoginEmailChange(
      id: 'request',
      requestedEmail: newEmail,
      state: 'pending',
    );
  }

  @override
  Future<void> confirmLoginEmailChange(String newEmail) async =>
      confirmed = newEmail;

  @override
  Future<PersonContact> getPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => contact;

  @override
  Future<void> setPersonContact({
    required String clubId,
    required String teamId,
    required String personId,
    required String? contactEmail,
    required String? phone,
  }) async => clubContact = (personId, contactEmail, phone);
}

class _Roster extends UnconfiguredRosterServices {
  const _Roster({this.self = false});
  final bool self;
  @override
  Future<List<RosterPersonSummary>> listPeople({
    required String clubId,
    String? teamId,
  }) async => const [
    RosterPersonSummary(
      id: 'ada',
      displayName: 'Ada Spelare',
      teamId: 'team',
      teamName: 'F2012',
      assignmentState: 'active',
      safeguardingRequired: false,
    ),
  ];
  @override
  Future<RosterPersonDetails> getPersonDetails({
    required String clubId,
    required String teamId,
    required String personId,
  }) async => RosterPersonDetails(
    id: 'ada',
    displayName: 'Ada Spelare',
    teamId: 'team',
    teamName: 'F2012',
    assignmentState: 'active',
    isSelf: self,
    personRevision: 1,
    birthYear: 2012,
  );
  @override
  Future<TeamRoles> listTeamRoles({
    required String clubId,
    required String teamId,
  }) async => const TeamRoles(
    canManage: true,
    roles: [TeamRole(personId: 'ada', name: 'Ada Spelare', role: 'player')],
  );
}

class _Identity implements IdentityServices {
  const _Identity({this.clubAdmin = false});
  final bool clubAdmin;
  @override
  SessionStatus get sessionStatus => SessionStatus.authenticated;
  @override
  Stream<SessionStatus> get sessionChanges => const Stream.empty();
  @override
  Future<TeamZoneProfile> getProfile() async =>
      const TeamZoneProfile(id: 'profile', displayName: 'Ada', locale: 'sv');
  @override
  Future<List<TeamZoneContext>> getContexts() async => mergeTeamContexts([
    TeamZoneContext(
      id: 'context',
      clubId: 'club',
      clubName: 'Testklubben',
      teamId: 'team',
      teamName: 'F2012',
      rolePackage: 'leader',
      capabilities: {'team.read', 'team.roster.view', 'team.roster.manage'},
    ),
    // A club administrator's club-wide role in the same team, merged into
    // the leader context like a real account with both assignments.
    if (clubAdmin)
      const TeamZoneContext(
        id: 'context-admin',
        clubId: 'club',
        clubName: 'Testklubben',
        teamId: 'team',
        teamName: 'F2012',
        rolePackage: 'club_functionary',
        capabilities: {'team.read', 'club.memberships.manage'},
      ),
  ]);
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> signOut() async {}
}
