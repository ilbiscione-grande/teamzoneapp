import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/board_strings.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
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
                      clubId: club.clubId,
                      name: club.name,
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
class SupportClubDetailSheet extends StatefulWidget {
  const SupportClubDetailSheet({
    super.key,
    required this.services,
    required this.clubId,
    required this.name,
  });
  final SupportClubServices services;
  final String clubId;
  final String name;

  @override
  State<SupportClubDetailSheet> createState() => _SupportClubDetailSheetState();
}

class _SupportClubDetailSheetState extends State<SupportClubDetailSheet> {
  late Future<SupportClubDetail> _detail = _load();

  Future<SupportClubDetail> _load() => widget.services
      .getClubForSupport(clubId: widget.clubId)
      .timeout(const Duration(seconds: 15));

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
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
        Widget person(SupportClubPerson item, {String? title}) => ListTile(
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
            for (final admin in club.admins) person(admin),
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
                  subtitle: Text(
                    strings.approvals(
                      change.approvals,
                      supportDate(change.createdAt),
                    ),
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
