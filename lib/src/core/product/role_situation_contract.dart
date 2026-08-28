enum ProductRole { leader, player, guardian, clubFunctionary }

enum PrioritySurface { home, team, calendar, inbox }

enum UsageSituation {
  mobileDuringActivity,
  tabletPlanning,
  desktopAdministration,
}

class RoleSurfaceContract {
  const RoleSurfaceContract({
    required this.goal,
    required this.information,
    required this.primaryActions,
    required this.hiddenWithoutCapability,
  });

  final String goal;
  final Set<String> information;
  final Set<String> primaryActions;
  final Set<String> hiddenWithoutCapability;
}

class SituationContract {
  const SituationContract({
    required this.priority,
    required this.layout,
    required this.deprioritized,
  });

  final Set<String> priority;
  final String layout;
  final Set<String> deprioritized;
}

abstract final class RoleSituationContract {
  static ProductRole? roleForPackage(String rolePackage) =>
      switch (rolePackage) {
        'leader' => ProductRole.leader,
        'player' => ProductRole.player,
        'guardian' => ProductRole.guardian,
        'club_functionary' => ProductRole.clubFunctionary,
        _ => null,
      };

  static RoleSurfaceContract surface(
    ProductRole role,
    PrioritySurface surface,
  ) => switch ((role, surface)) {
    (ProductRole.leader, PrioritySurface.home) => _leaderHome,
    (ProductRole.leader, PrioritySurface.team) => _leaderTeam,
    (ProductRole.leader, PrioritySurface.calendar) => _leaderCalendar,
    (ProductRole.leader, PrioritySurface.inbox) => _leaderInbox,
    (ProductRole.player, PrioritySurface.home) => _playerHome,
    (ProductRole.player, PrioritySurface.team) => _playerTeam,
    (ProductRole.player, PrioritySurface.calendar) => _playerCalendar,
    (ProductRole.player, PrioritySurface.inbox) => _playerInbox,
    (ProductRole.guardian, PrioritySurface.home) => _guardianHome,
    (ProductRole.guardian, PrioritySurface.team) => _guardianTeam,
    (ProductRole.guardian, PrioritySurface.calendar) => _guardianCalendar,
    (ProductRole.guardian, PrioritySurface.inbox) => _guardianInbox,
    (ProductRole.clubFunctionary, PrioritySurface.home) => _functionaryHome,
    (ProductRole.clubFunctionary, PrioritySurface.team) => _functionaryTeam,
    (ProductRole.clubFunctionary, PrioritySurface.calendar) =>
      _functionaryCalendar,
    (ProductRole.clubFunctionary, PrioritySurface.inbox) => _functionaryInbox,
  };

  static SituationContract situation(
    ProductRole role,
    UsageSituation situation,
  ) => switch (situation) {
    UsageSituation.mobileDuringActivity => SituationContract(
      priority: switch (role) {
        ProductRole.leader => const {
          'current_event',
          'attendance',
          'urgent_messages',
        },
        ProductRole.player => const {
          'next_action',
          'callup_response',
          'event_details',
        },
        ProductRole.guardian => const {
          'child_switcher',
          'callup_response',
          'event_details',
        },
        ProductRole.clubFunctionary => const {
          'urgent_club_tasks',
          'approvals',
          'urgent_messages',
        },
      },
      layout: 'single_column_quick_actions',
      deprioritized: const {'bulk_edit', 'complex_planning', 'dense_reports'},
    ),
    UsageSituation.tabletPlanning => SituationContract(
      priority: switch (role) {
        ProductRole.leader => const {
          'event_planning',
          'participant_selection',
          'training_plan',
        },
        ProductRole.player => const {
          'schedule_overview',
          'preparations',
          'team_information',
        },
        ProductRole.guardian => const {
          'children_schedule',
          'responses',
          'team_information',
        },
        ProductRole.clubFunctionary => const {
          'club_schedule',
          'applications',
          'content_planning',
        },
      },
      layout: 'master_detail_planning',
      deprioritized: const {'dense_financial_reports', 'system_configuration'},
    ),
    UsageSituation.desktopAdministration => SituationContract(
      priority: switch (role) {
        ProductRole.leader => const {
          'roster_administration',
          'series_planning',
          'communication_overview',
        },
        ProductRole.player => const {
          'history',
          'schedule_overview',
          'personal_information',
        },
        ProductRole.guardian => const {
          'children_overview',
          'history',
          'contact_settings',
        },
        ProductRole.clubFunctionary => const {
          'club_administration',
          'applications',
          'publishing',
          'audit_overview',
        },
      },
      layout: 'dense_multi_column_administration',
      deprioritized: const {'sideline_quick_actions'},
    ),
  };

  static const _leaderHome = RoleSurfaceContract(
    goal: 'Planera laget och agera på det som kräver ledarens uppmärksamhet.',
    information: {
      'next_event',
      'pending_callups',
      'attendance_gaps',
      'active_invites_applications',
      'urgent_messages',
    },
    primaryActions: {'create_event', 'take_attendance', 'message_team'},
    hiddenWithoutCapability: {
      'club_finance',
      'board_cases',
      'unrelated_team_data',
    },
  );
  static const _leaderTeam = RoleSurfaceContract(
    goal: 'Förstå och administrera det egna lagets vardag.',
    information: {
      'team_photo',
      'team_information',
      'roster',
      'active_invites_applications',
      'event_list',
    },
    primaryActions: {'manage_roster', 'review_application', 'create_event'},
    hiddenWithoutCapability: {
      'global_person_delete',
      'other_team_private_data',
    },
  );
  static const _leaderCalendar = RoleSurfaceContract(
    goal: 'Planera, kalla och genomföra lagets aktiviteter.',
    information: {
      'team_events',
      'responses',
      'participant_status',
      'attendance_status',
    },
    primaryActions: {'create_event', 'manage_participants', 'take_attendance'},
    hiddenWithoutCapability: {'other_team_event_edit', 'private_player_health'},
  );
  static const _leaderInbox = RoleSurfaceContract(
    goal: 'Kommunicera med laget och hantera relevanta svar.',
    information: {'team_threads', 'leader_threads', 'unread', 'announcements'},
    primaryActions: {'message_team', 'message_leaders', 'create_announcement'},
    hiddenWithoutCapability: {
      'club_wide_broadcast',
      'unrelated_private_threads',
    },
  );

  static const _playerHome = RoleSurfaceContract(
    goal: 'Förstå vad som händer härnäst och vad spelaren behöver göra.',
    information: {'next_event', 'my_callups', 'my_responses', 'preparations'},
    primaryActions: {'respond_callup', 'open_event', 'contact_leader'},
    hiddenWithoutCapability: {
      'admin_queue',
      'other_player_attendance',
      'roster_management',
    },
  );
  static const _playerTeam = RoleSurfaceContract(
    goal: 'Se det egna laget och tillåten laginformation.',
    information: {
      'team_photo',
      'team_information',
      'limited_roster',
      'event_list',
    },
    primaryActions: {'open_teammate', 'open_event'},
    hiddenWithoutCapability: {
      'contact_details_without_scope',
      'invites_applications',
      'roster_management',
    },
  );
  static const _playerCalendar = RoleSurfaceContract(
    goal: 'Se egna aktiviteter, svara och förbereda sig.',
    information: {'my_events', 'my_callups', 'event_preparations'},
    primaryActions: {'respond_callup', 'open_event'},
    hiddenWithoutCapability: {'create_event', 'edit_event', 'take_attendance'},
  );
  static const _playerInbox = RoleSurfaceContract(
    goal: 'Ta emot laginformation och kontakta tillåtna mottagare.',
    information: {'my_threads', 'announcements', 'unread'},
    primaryActions: {'contact_leader', 'reply_allowed_thread'},
    hiddenWithoutCapability: {
      'player_to_player_direct',
      'leader_threads',
      'broadcast',
    },
  );

  static const _guardianHome = RoleSurfaceContract(
    goal: 'Hantera rätt barns närmaste aktiviteter och åtgärder.',
    information: {
      'child_switcher',
      'child_next_event',
      'child_callups',
      'urgent_messages',
    },
    primaryActions: {'respond_for_child', 'open_event', 'contact_leader'},
    hiddenWithoutCapability: {
      'unrelated_child_data',
      'team_admin_queue',
      'player_private_development',
    },
  );
  static const _guardianTeam = RoleSurfaceContract(
    goal: 'Se barnets lag och tillåten praktisk information.',
    information: {
      'team_photo',
      'team_information',
      'limited_roster',
      'event_list',
    },
    primaryActions: {'open_event', 'contact_leader'},
    hiddenWithoutCapability: {
      'roster_management',
      'invites_applications',
      'other_child_contact_details',
    },
  );
  static const _guardianCalendar = RoleSurfaceContract(
    goal: 'Se och svara på aktiviteter uttryckligen för rätt barn.',
    information: {'child_switcher', 'child_events', 'child_callups'},
    primaryActions: {'respond_for_child', 'open_event'},
    hiddenWithoutCapability: {'create_event', 'edit_event', 'take_attendance'},
  );
  static const _guardianInbox = RoleSurfaceContract(
    goal: 'Ta emot barnrelaterad information och kontakta ledare.',
    information: {'child_scoped_threads', 'announcements', 'unread'},
    primaryActions: {'contact_leader', 'reply_allowed_thread'},
    hiddenWithoutCapability: {
      'player_to_player_direct',
      'leader_threads',
      'unrelated_child_threads',
    },
  );

  static const _functionaryHome = RoleSurfaceContract(
    goal: 'Se klubbens operativa läge och egna tilldelade ärenden.',
    information: {
      'club_tasks',
      'applications',
      'official_status',
      'publishing_status',
      'urgent_messages',
    },
    primaryActions: {'review_application', 'publish_news', 'open_club_admin'},
    hiddenWithoutCapability: {
      'team_coaching_tasks',
      'player_private_health',
      'unassigned_finance_board',
    },
  );
  static const _functionaryTeam = RoleSurfaceContract(
    goal: 'Överblicka klubbens lag inom uttryckligt tilldelat scope.',
    information: {
      'team_photo',
      'team_information',
      'roster_summary',
      'active_invites_applications',
      'event_list',
    },
    primaryActions: {'review_application', 'manage_team_if_capable'},
    hiddenWithoutCapability: {
      'player_sensitive_details',
      'team_coaching_notes',
    },
  );
  static const _functionaryCalendar = RoleSurfaceContract(
    goal: 'Överblicka klubbaktiviteter utan implicit lagledarbehörighet.',
    information: {'club_events', 'meeting_events', 'publication_state'},
    primaryActions: {'create_club_event_if_capable', 'open_event'},
    hiddenWithoutCapability: {
      'team_event_edit',
      'participant_selection',
      'take_attendance',
    },
  );
  static const _functionaryInbox = RoleSurfaceContract(
    goal: 'Hantera klubbkommunikation inom tilldelat mandat.',
    information: {
      'club_threads',
      'contact_requests',
      'announcements',
      'unread',
    },
    primaryActions: {'publish_announcement', 'reply_contact_request'},
    hiddenWithoutCapability: {
      'leader_threads',
      'team_private_threads',
      'player_direct',
    },
  );
}
