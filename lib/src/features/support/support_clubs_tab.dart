import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/board_strings.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/support/support_club_actions.dart';
import 'package:teamzone_app/src/features/support/support_club_services.dart';

/// Klubbar on the support admin page: every club, those needing support
/// first (no club admin with an account, board changes waiting). Opening a
/// club shows names and is logged on the server.
class SupportClubsTab extends StatefulWidget {
  const SupportClubsTab({super.key, required this.services});
  final SupportClubServices services;

  @override
  State<SupportClubsTab> createState() => _SupportClubsTabState();
}

class _SupportClubsTabState extends State<SupportClubsTab> {
  late Future<List<SupportClubSummary>> _clubs = _load();
  String _query = '';
  bool _onlyAttention = false;

  Future<List<SupportClubSummary>> _load() => widget.services
      .listClubsForSupport()
      .timeout(const Duration(seconds: 15));

  void _reload() => setState(() => _clubs = _load());

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    return FutureBuilder<List<SupportClubSummary>>(
      future: _clubs,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          AppErrors.caught('support_clubs_tab.load', snapshot.error!);
          return _Retry(message: strings.clubsFailed, onRetry: _reload);
        }
        final all = snapshot.data ?? const <SupportClubSummary>[];
        final attention = all.where((club) => club.needsAttention).length;
        final query = _query.trim().toLowerCase();
        final shown = all
            .where((club) => !_onlyAttention || club.needsAttention)
            .where((club) => club.name.toLowerCase().contains(query))
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            await _clubs.catchError((_) => const <SupportClubSummary>[]);
          },
          child: ListView(
            key: const ValueKey('support-clubs-list'),
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const ValueKey('support-clubs-search'),
                decoration: InputDecoration(
                  labelText: strings.searchClubs,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(strings.clubsSummary(all.length, attention)),
                  FilterChip(
                    key: const ValueKey('support-clubs-attention'),
                    label: Text(strings.onlyAttention),
                    selected: _onlyAttention,
                    onSelected: (value) =>
                        setState(() => _onlyAttention = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _onlyAttention ? strings.noAttention : strings.noClubs,
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final club in shown) ...[
                _ClubCard(
                  club: club,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (_) => SupportClubDetailSheet(
                      services: widget.services,
                      actions: widget.services is SupportClubActionServices
                          ? widget.services as SupportClubActionServices
                          : null,
                      clubId: club.clubId,
                      name: club.name,
                      onChanged: _reload,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.onTap});
  final SupportClubSummary club;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final facts = [
      if (!club.isActive) strings.clubStatus(club.status),
      strings.verification(club.verificationStatus),
      strings.teams(club.teamCount),
      strings.people(club.peopleCount),
      strings.accounts(club.accountCount),
      if (!club.lacksAdmin) strings.admins(club.adminCount),
      if (club.boardForming) strings.boardForming,
    ];
    final oldest = club.oldestPendingBoardChange;
    return Card(
      key: ValueKey('support-club-${club.clubId}'),
      color: club.lacksAdmin ? scheme.errorContainer : null,
      child: ListTile(
        title: Text(club.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (club.lacksAdmin)
              Text(
                strings.noAdmin,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (club.pendingBoardChanges > 0)
              Text(
                [
                  strings.pendingChanges(club.pendingBoardChanges),
                  if (oldest != null) strings.oldestSince(supportDate(oldest)),
                ].join(', '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            Text(facts.join(' · ')),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// A club's admins, board, pending board changes and teams, with names.
/// With [actions], support can appoint or remove a club admin and apply or
/// cancel a stuck board change (part 3), each with a logged reason.
class SupportClubDetailSheet extends StatefulWidget {
  const SupportClubDetailSheet({
    super.key,
    required this.services,
    required this.clubId,
    required this.name,
    this.actions,
    this.onChanged,
  });
  final SupportClubServices services;
  final SupportClubActionServices? actions;
  final String clubId;
  final String name;

  /// Called after an action, so the club list is fresh.
  final VoidCallback? onChanged;

  @override
  State<SupportClubDetailSheet> createState() => _SupportClubDetailSheetState();
}

class _SupportClubDetailSheetState extends State<SupportClubDetailSheet> {
  late Future<SupportClubDetail> _detail = _load();

  bool _saving = false;

  Future<SupportClubDetail> _load() => widget.services
      .getClubForSupport(clubId: widget.clubId)
      .timeout(const Duration(seconds: 15));

  Future<void> _run(Future<String> Function() action) async {
    final strings = SupportStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final done = await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      widget.onChanged?.call();
      if (mounted) setState(() => _detail = _load());
    } catch (error) {
      final code = supportClubActionRefusal(error);
      if (code == null) AppErrors.caught('support_clubs_tab.action', error);
      messenger.showSnackBar(SnackBar(content: Text(strings.refusal(code))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _grant(SupportClubDetail club) async {
    final actions = widget.actions!;
    final strings = SupportStrings.of(context);
    final candidates = club.peopleWithAccount
        .where((person) => !person.isAdmin)
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.noCandidates)));
      return;
    }
    final input = await askNewClubAdmin(context, candidates);
    if (input == null || !mounted) return;
    await _run(() async {
      await actions.grantClubAdmin(
        clubId: club.clubId,
        personId: input.personId,
        reason: input.reason,
      );
      return strings.clubAdminGranted;
    });
  }

  Future<void> _remove(SupportClubDetail club, SupportClubPerson admin) async {
    final actions = widget.actions!;
    final strings = SupportStrings.of(context);
    final counts = admin.hasAccount && admin.endsAt == null;
    final reason = await askSupportReason(
      context,
      title: strings.removeClubAdminTitle,
      body: strings.removeClubAdminBody(admin.name),
      confirm: strings.removeClubAdmin,
      warning: counts && club.countingAdmins <= 1
          ? strings.lastAdminWarning
          : null,
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      final leftWithout = await actions.removeClubAdmin(
        clubId: club.clubId,
        personId: admin.personId!,
        reason: reason,
      );
      return leftWithout
          ? strings.clubLeftWithoutAdmin
          : strings.clubAdminRemoved;
    });
  }

  Future<void> _resolve(
    SupportBoardChange change, {
    required bool apply,
  }) async {
    final actions = widget.actions!;
    final strings = SupportStrings.of(context);
    final reason = await askSupportReason(
      context,
      title: apply ? strings.applyChangeTitle : strings.cancelChangeTitle,
      body: apply ? strings.applyChangeBody : strings.cancelChangeBody,
      confirm: apply ? strings.applyChange : strings.cancelChange,
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      await actions.resolveBoardChange(
        changeId: change.id,
        apply: apply,
        reason: reason,
      );
      return apply ? strings.changeApplied : strings.changeCancelled;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    final board = BoardStrings.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<SupportClubDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          AppErrors.caught('support_clubs_tab.detail', snapshot.error!);
          return _Retry(
            message: strings.clubFailed,
            onRetry: () => setState(() => _detail = _load()),
          );
        }
        final club = snapshot.requireData;
        final canAct = widget.actions != null && !_saving;
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
        Widget person(
          SupportClubPerson item, {
          String? title,
          Widget? trailing,
        }) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            item.hasAccount ? Icons.person_outline : Icons.person_off_outlined,
          ),
          title: Text(title ?? item.name),
          subtitle: Text(
            [
              if (!item.hasAccount) strings.noAccount,
              if (item.endsAt != null)
                strings.endsOn(supportDate(item.endsAt!)),
            ].join(' · '),
          ),
          trailing: trailing,
        );
        return ListView(
          key: const ValueKey('support-club-detail'),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(club.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              [
                strings.clubStatus(club.status),
                strings.verification(club.verificationStatus),
                if (club.boardForming) strings.boardForming,
              ].join(' · '),
            ),
            if (!club.hasAdminWithAccount && club.status == 'active')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(strings.noAdmin),
                  ),
                ),
              ),
            heading(strings.adminsHeading),
            Text(strings.adminsExplained, style: theme.textTheme.bodySmall),
            if (club.admins.isEmpty) Text(strings.none),
            for (final admin in club.admins)
              person(
                admin,
                trailing: widget.actions != null && admin.personId != null
                    ? TextButton(
                        key: ValueKey(
                          'support-club-admin-remove-${admin.personId}',
                        ),
                        onPressed: canAct ? () => _remove(club, admin) : null,
                        child: Text(strings.removeClubAdmin),
                      )
                    : null,
              ),
            if (widget.actions != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey('support-club-admin-grant'),
                  onPressed: canAct ? () => _grant(club) : null,
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(strings.grantClubAdmin),
                ),
              ),
            heading(strings.boardHeading),
            if (club.board.isEmpty) Text(strings.none),
            for (final member in club.board)
              person(
                member,
                title: '${board.office(member.office ?? '')}: ${member.name}',
              ),
            if (club.pendingBoardChanges.isNotEmpty) ...[
              heading(strings.pendingHeading),
              for (final change in club.pendingBoardChanges)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.hourglass_empty),
                  title: Text(
                    strings.change(
                      change.action,
                      board.office(change.office),
                      change.name,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.approvals(
                          change.approvals,
                          supportDate(change.createdAt),
                        ),
                      ),
                      if (widget.actions != null && change.id.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              key: ValueKey('support-board-apply-${change.id}'),
                              onPressed: canAct
                                  ? () => _resolve(change, apply: true)
                                  : null,
                              child: Text(strings.applyChange),
                            ),
                            TextButton(
                              key: ValueKey(
                                'support-board-cancel-${change.id}',
                              ),
                              onPressed: canAct
                                  ? () => _resolve(change, apply: false)
                                  : null,
                              child: Text(strings.cancelChange),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
            heading(strings.teamsHeading),
            if (club.teams.isEmpty) Text(strings.none),
            for (final team in club.teams)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.groups_outlined),
                title: Text(team.name),
                subtitle: Text(strings.people(team.people)),
              ),
            const SizedBox(height: 12),
            Text(strings.viewLogged, style: theme.textTheme.bodySmall),
            if (widget.actions != null)
              Text(strings.actionsLogged, style: theme.textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(SupportStrings.of(context).retry),
          ),
        ],
      ),
    ),
  );
}

/// 2026-11-14 in local time.
String supportDate(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
