part of '../../app/teamzone_app.dart';

// Avgifter (club-members-and-fees.md, step 2): fee rounds for membership
// fees (an amount per category with the family rule) and team fees (per
// player). A round is a draft until its fees are created; nobody is told
// yet. Opened from the Klubb page by club admin and treasurer.

String _feeDay(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

String _feeRoundKindLine(AppStrings strings, ClubFeeRound round) =>
    round.isMembership
    ? strings.feature('Medlemsavgift')
    : '${strings.feature('Lagavgift')} ${round.teamName ?? ''}'.trim();

/// Team choices for a team fee: id → name.
typedef _FeeTeams = List<({String id, String name})>;

class _ClubFeeRoundsPage extends StatefulWidget {
  const _ClubFeeRoundsPage({
    required this.clubId,
    required this.teams,
    required this.services,
  });
  final String clubId;
  final _FeeTeams teams;
  final ClubFeeServices services;

  @override
  State<_ClubFeeRoundsPage> createState() => _ClubFeeRoundsPageState();
}

class _ClubFeeRoundsPageState extends State<_ClubFeeRoundsPage> {
  late Future<List<ClubFeeRound>> _rounds = _load();

  Future<List<ClubFeeRound>> _load() =>
      widget.services.loadClubFeeRounds(widget.clubId);

  void _reload() => setState(() {
    _rounds = _load();
  });

  Future<void> _openRound(String roundId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ClubFeeRoundPage(
          clubId: widget.clubId,
          roundId: roundId,
          teams: widget.teams,
          services: widget.services,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _create() async {
    final roundId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _ClubFeeRoundEditor(
          clubId: widget.clubId,
          teams: widget.teams,
          services: widget.services,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
    if (roundId != null) await _openRound(roundId);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Avgifter'))),
      body: FutureBuilder<List<ClubFeeRound>>(
        future: _rounds,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: _StateCard(
                icon: Icons.sync_problem,
                title: strings.couldNotLoad,
                message: strings.safeError,
                action: FilledButton(
                  onPressed: _reload,
                  child: Text(strings.retry),
                ),
              ),
            );
          }
          final rounds = snapshot.data;
          if (rounds == null) {
            return AppLoadingIndicator(label: strings.loading);
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _rounds;
            },
            child: ListView(
              key: const ValueKey('club-fees'),
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('club-fees-new'),
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                      label: Text(strings.feature('Ny avgiftsomgång')),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('club-fees-families'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _ClubFamiliesPage(
                            clubId: widget.clubId,
                            services: widget.services,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.family_restroom_outlined),
                      label: Text(strings.feature('Familjer')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (rounds.isEmpty)
                  Text(
                    strings.feature(
                      'Inga avgiftsomgångar än. Skapa till exempel årets medlemsavgift eller en lagavgift.',
                    ),
                  ),
                for (final round in rounds)
                  Card(
                    child: ListTile(
                      key: ValueKey('club-fee-round-${round.roundId}'),
                      title: Text(round.title),
                      subtitle: Text(
                        '${_feeRoundKindLine(strings, round)} · '
                        '${strings.feature('förfaller')} ${_feeDay(round.dueOn)}',
                      ),
                      trailing: Text(
                        round.isDraft
                            ? strings.feature('Utkast')
                            : '${round.openCount} ${strings.feature('obetalda')}\n'
                                  '${clubFeeKronor(round.paidTotal)} ${strings.feature('av')} ${clubFeeKronor(round.total)}',
                        textAlign: TextAlign.end,
                      ),
                      onTap: () => _openRound(round.roundId),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One round: its terms and the fees it gives (computed while a draft).
class _ClubFeeRoundPage extends StatefulWidget {
  const _ClubFeeRoundPage({
    required this.clubId,
    required this.roundId,
    required this.teams,
    required this.services,
  });
  final String clubId;
  final String roundId;
  final _FeeTeams teams;
  final ClubFeeServices services;

  @override
  State<_ClubFeeRoundPage> createState() => _ClubFeeRoundPageState();
}

class _ClubFeeRoundPageState extends State<_ClubFeeRoundPage> {
  late Future<ClubFeeRoundDetail> _detail = _load();
  bool _busy = false;

  Future<ClubFeeRoundDetail> _load() =>
      widget.services.loadClubFeeRound(widget.clubId, widget.roundId);

  void _reload() => setState(() {
    _detail = _load();
  });

  Future<void> _edit(ClubFeeRound round) async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _ClubFeeRoundEditor(
          clubId: widget.clubId,
          teams: widget.teams,
          services: widget.services,
          round: round,
        ),
      ),
    );
    if (saved != null && mounted) _reload();
  }

  Future<void> _editPaymentInfo(ClubFeeRound round) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final info = await showDialog<String>(
      context: context,
      builder: (_) => _FeePaymentInfoDialog(initial: round.paymentInfo ?? ''),
    );
    if (info == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.services.setClubFeeRoundPaymentInfo(
        clubId: widget.clubId,
        roundId: round.roundId,
        paymentInfo: info.isEmpty ? null : info,
      );
    } catch (error) {
      AppErrors.caught('club_fees._editPaymentInfo', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Det gick inte. Försök igen.'))),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  Future<void> _decide(ClubFeeRoundDetail detail, String decision) async {
    final strings = AppStrings.of(context);
    final issue = decision == 'issue';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.feature(issue ? 'Skapa avgifterna?' : 'Ta bort utkastet?'),
        ),
        content: Text(
          issue
              ? '${detail.fees.length} ${strings.feature(detail.fees.length == 1 ? 'avgift' : 'avgifter')}, '
                    '${clubFeeKronor(detail.total)}. '
                    '${strings.feature('Beloppen låses. Ingen får något meddelande än.')}'
              : strings.feature('Utkastet tas bort.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            key: const ValueKey('club-fee-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              strings.feature(issue ? 'Skapa avgifterna' : 'Ta bort'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await widget.services.decideClubFeeRound(
        clubId: widget.clubId,
        roundId: widget.roundId,
        decision: decision,
        expectedRevision: detail.round.revision,
        idempotencyKey: _newUuid(),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (issue) {
        messenger.showSnackBar(
          SnackBar(content: Text(strings.feature('Avgifterna är skapade.'))),
        );
        _reload();
      } else {
        navigator.pop();
      }
    } catch (error) {
      AppErrors.caught('club_fees._decide', error);
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              error is ClubRegisterConflict
                  ? 'Någon annan har ändrat omgången. Öppna den igen.'
                  : 'Det gick inte. Försök igen.',
            ),
          ),
        ),
      );
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<ClubFeeRoundDetail>(
      future: _detail,
      builder: (context, snapshot) {
        final detail = snapshot.data;
        final round = detail?.round;
        return Scaffold(
          appBar: AppBar(
            title: Text(round?.title ?? strings.feature('Avgiftsomgång')),
            actions: [
              if (round != null && round.isDraft)
                IconButton(
                  key: const ValueKey('club-fee-edit'),
                  tooltip: strings.feature('Ändra'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _busy ? null : () => _edit(round),
                ),
              if (detail != null && round != null && !round.isDraft)
                IconButton(
                  key: const ValueKey('club-fee-export'),
                  tooltip: strings.feature('Exportera som CSV'),
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => _exportClubFees(context, round, detail.fees),
                ),
            ],
          ),
          body: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: _StateCard(
                    icon: Icons.sync_problem,
                    title: strings.couldNotLoad,
                    message: strings.safeError,
                    action: FilledButton(
                      onPressed: _reload,
                      child: Text(strings.retry),
                    ),
                  ),
                )
              : detail == null || round == null
              ? AppLoadingIndicator(label: strings.loading)
              : ListView(
                  key: const ValueKey('club-fee-round'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${_feeRoundKindLine(strings, round)} · '
                      '${strings.feature('förfaller')} ${_feeDay(round.dueOn)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(_feeTermsLine(strings, round)),
                    const SizedBox(height: 8),
                    _FeePaymentInfoCard(
                      info: round.paymentInfo,
                      onEdit: _busy ? null : () => _editPaymentInfo(round),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      key: const ValueKey('club-fee-summary'),
                      [
                        '${detail.fees.where((fee) => fee.amount > 0).length} '
                            '${strings.feature('att betala')}',
                        clubFeeKronor(detail.total),
                        if (detail.discount > 0)
                          '${strings.feature('familjerabatt')} ${clubFeeKronor(detail.discount)}',
                      ].join(' · '),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (round.isDraft) ...[
                      const SizedBox(height: 12),
                      _FeeNotice(
                        icon: Icons.edit_note_outlined,
                        text: strings.feature(
                          'Utkast. Avgifterna räknas om tills de skapas. Ingen får något meddelande än.',
                        ),
                      ),
                    ],
                    if (detail.missing.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _FeeNotice(
                        key: const ValueKey('club-fee-missing'),
                        icon: Icons.warning_amber_outlined,
                        text:
                            '${strings.feature('Får ingen avgift, kategori saknas (inget födelseår)')}: '
                            '${detail.missing.join(', ')}. '
                            '${strings.feature('Ange kategori i medlemsregistret.')}',
                      ),
                    ],
                    if (round.isDraft) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            key: const ValueKey('club-fee-issue'),
                            onPressed: _busy || detail.fees.isEmpty
                                ? null
                                : () => _decide(detail, 'issue'),
                            child: Text(strings.feature('Skapa avgifterna')),
                          ),
                          OutlinedButton(
                            key: const ValueKey('club-fee-cancel'),
                            onPressed: _busy
                                ? null
                                : () => _decide(detail, 'cancel'),
                            child: Text(strings.feature('Ta bort utkastet')),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 32),
                    if (detail.fees.isEmpty)
                      Text(strings.feature('Omgången ger inga avgifter.'))
                    else if (round.isDraft)
                      for (final fee in detail.fees)
                        _ClubFeeRow(fee: fee, all: detail.fees)
                    else
                      _ClubFeePayments(
                        clubId: widget.clubId,
                        roundId: widget.roundId,
                        fees: detail.fees,
                        services: widget.services,
                        onChanged: _reload,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// "Barn och ungdom 300 kr, Vuxen 500 kr · 50 % från andra syskonet ·
/// högst 800 kr per familj".
String _feeTermsLine(AppStrings strings, ClubFeeRound round) {
  final amounts = round.isMembership
      ? [
          for (final category in clubMemberCategories)
            if (round.amounts[category] case final amount?)
              '${_memberCategoryLabel(strings, category)} ${clubFeeKronor(amount)}',
        ].join(', ')
      : '${clubFeeKronor(round.amounts['player'] ?? 0)} ${strings.feature('per spelare')}';
  return [
    amounts,
    if (round.siblingDiscountPercent case final percent?)
      '$percent % ${strings.feature('rabatt från andra syskonet')}',
    if (round.familyCap case final cap?)
      '${strings.feature('högst')} ${clubFeeKronor(cap)} ${strings.feature('per familj')}',
  ].join(' · ');
}

class _FeeNotice extends StatelessWidget {
  const _FeeNotice({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ClubFeeRow extends StatelessWidget {
  const _ClubFeeRow({required this.fee, required this.all});
  final ClubFee fee;
  final List<ClubFee> all;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final siblings = [
      for (final other in all)
        if (other.personId != fee.personId &&
            other.familyKey != null &&
            other.familyKey == fee.familyKey)
          other.name,
    ];
    final details = [
      if (fee.category != null) _memberCategoryLabel(strings, fee.category),
      if (fee.guardians.isNotEmpty)
        '${strings.feature('betalas av')} ${fee.guardians.join(', ')}',
      if (siblings.isNotEmpty)
        '${strings.feature('familj med')} ${siblings.join(', ')}',
    ];
    return ListTile(
      key: ValueKey('club-fee-${fee.personId}'),
      contentPadding: EdgeInsets.zero,
      title: Text(fee.name),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            clubFeeKronor(fee.amount),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (fee.amount == 0)
            Text(
              strings.feature('täcks av familjetaket'),
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          else if (fee.discountAmount > 0)
            Text(
              '${strings.feature('rabatt')} ${clubFeeKronor(fee.discountAmount)}',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// How to pay, as the payers see it in Mina avgifter.
class _FeePaymentInfoCard extends StatelessWidget {
  const _FeePaymentInfoCard({required this.info, required this.onEdit});
  final String? info;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: const ValueKey('club-fee-payment-info'),
        leading: const Icon(Icons.info_outline),
        title: Text(strings.feature('Så betalar man')),
        subtitle: Text(
          info ??
              strings.feature(
                'Inte angivet. Skriv till exempel Swish-nummer och vad betalningen ska märkas med.',
              ),
          style: info == null
              ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
        trailing: IconButton(
          key: const ValueKey('club-fee-payment-info-edit'),
          tooltip: strings.feature('Ändra'),
          icon: const Icon(Icons.edit_outlined),
          onPressed: onEdit,
        ),
      ),
    );
  }
}

class _FeePaymentInfoDialog extends StatefulWidget {
  const _FeePaymentInfoDialog({required this.initial});
  final String initial;

  @override
  State<_FeePaymentInfoDialog> createState() => _FeePaymentInfoDialogState();
}

class _FeePaymentInfoDialogState extends State<_FeePaymentInfoDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Så betalar man')),
      content: TextField(
        key: const ValueKey('club-fee-payment-info-text'),
        controller: _text,
        maxLength: 500,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: strings.feature(
            'Swish 123 456 78 90. Märk betalningen med namn och avgift.',
          ),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const ValueKey('club-fee-payment-info-save'),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(strings.feature('Spara')),
        ),
      ],
    );
  }
}
