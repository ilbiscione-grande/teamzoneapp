part of '../../app/teamzone_app.dart';

enum _RosterPlayerAction {
  profile,
  edit,
  details,
  represent,
  move,
  invite,
  archive,
}

/// The menu button on a player in the squad list: the common actions for
/// a player without opening the profile first. Tapping the row itself
/// still opens the profile.
class _RosterPlayerMenu extends StatelessWidget {
  const _RosterPlayerMenu({
    required this.contextValue,
    required this.roster,
    required this.profileServices,
    required this.person,
    required this.roles,
    required this.onOpenProfile,
    required this.onChanged,
  });

  final TeamZoneContext contextValue;
  final RosterServices roster;
  final ProfileServices profileServices;
  final RosterPersonSummary person;

  /// The team's roles; null while they load, which hides the position item.
  final TeamRoles? roles;
  final VoidCallback onOpenProfile;

  /// The squad reloads after an action that may have changed it.
  final VoidCallback onChanged;

  /// An active player of this team: representing, moving and ending apply.
  bool get _homePlayer =>
      person.assignmentState == 'active' &&
      (person.teamId == null || person.teamId == contextValue.teamId);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    PopupMenuItem<_RosterPlayerAction> item(
      _RosterPlayerAction action,
      IconData icon,
      String label,
    ) => PopupMenuItem(
      key: ValueKey('roster-player-action-${action.name}'),
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(child: Text(strings.feature(label))),
        ],
      ),
    );
    return PopupMenuButton<_RosterPlayerAction>(
      key: ValueKey('roster-player-menu-${person.id}'),
      tooltip: strings.feature('Åtgärder'),
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _run(context, action),
      itemBuilder: (_) => [
        item(_RosterPlayerAction.profile, Icons.person_outline, 'Visa profil'),
        item(
          _RosterPlayerAction.edit,
          Icons.edit_outlined,
          'Redigera uppgifter',
        ),
        if (roles?.canEditDetails == true)
          item(
            _RosterPlayerAction.details,
            Icons.sports_soccer_outlined,
            'Position och titel',
          ),
        if (_homePlayer) ...[
          item(
            _RosterPlayerAction.represent,
            Icons.compare_arrows,
            'Representera annat lag',
          ),
          item(
            _RosterPlayerAction.move,
            Icons.swap_horiz,
            'Flytta till ett annat lag',
          ),
        ],
        if (!person.accountLinked)
          item(_RosterPlayerAction.invite, Icons.mail_outline, 'Bjud in'),
        if (_homePlayer)
          item(
            _RosterPlayerAction.archive,
            Icons.archive_outlined,
            'Avsluta i laget',
          ),
      ],
    );
  }

  Future<void> _run(BuildContext context, _RosterPlayerAction action) async {
    final teamId = contextValue.teamId;
    if (teamId == null) return;
    switch (action) {
      case _RosterPlayerAction.profile:
        onOpenProfile();
      case _RosterPlayerAction.edit:
        await _openRosterPersonEditor(
          context,
          contextValue: contextValue,
          roster: roster,
          personId: person.id,
          profileServices: profileServices,
          onSaved: () async => onChanged(),
        );
      case _RosterPlayerAction.details:
        final data = roles;
        if (data == null) return;
        final saved = await _editTeamPersonDetails(
          context,
          roster: roster,
          clubId: contextValue.clubId,
          teamId: teamId,
          data: data,
          personId: person.id,
        );
        if (saved) onChanged();
      case _RosterPlayerAction.move:
        await showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _IntraClubMoveSheet(
            contextValue: contextValue,
            roster: roster,
            initialPersonId: person.id,
          ),
        );
        onChanged();
      case _RosterPlayerAction.archive:
        await _archivePersonFromDetails(
          context: context,
          contextValue: contextValue,
          roster: roster,
          personId: person.id,
          onArchived: onChanged,
        );
      case _RosterPlayerAction.represent:
      case _RosterPlayerAction.invite:
        // Both need the person's details (revision, account state).
        final details = await _loadDetails(context, teamId);
        if (details == null || !context.mounted) return;
        if (action == _RosterPlayerAction.represent) {
          await _representFromProfile(
            context: context,
            contextValue: contextValue,
            roster: roster,
            person: details,
          );
        } else {
          await _inviteFromProfile(
            context: context,
            contextValue: contextValue,
            roster: roster,
            person: details,
          );
        }
        onChanged();
    }
  }

  Future<RosterPersonDetails?> _loadDetails(
    BuildContext context,
    String teamId,
  ) async {
    try {
      return await roster
          .getPersonDetails(
            clubId: contextValue.clubId,
            teamId: teamId,
            personId: person.id,
          )
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      AppErrors.caught('roster_player_menu._loadDetails', error);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Spelaren kunde inte laddas. Försök igen.'),
            ),
          ),
        );
      }
      return null;
    }
  }
}
