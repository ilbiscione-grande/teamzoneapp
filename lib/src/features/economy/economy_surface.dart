part of '../../app/teamzone_app.dart';

bool _hasEconomyCapability(TeamZoneContext value) => const [
  'economy.read',
  'economy.manage',
  'economy.post',
  'economy.approve',
  'economy.reverse',
].any(value.can);

class _EconomySurface extends StatefulWidget {
  const _EconomySurface({required this.contextValue, required this.economy});
  final TeamZoneContext contextValue;
  final EconomyServices economy;
  @override
  State<_EconomySurface> createState() => _EconomySurfaceState();
}

class _EconomySurfaceState extends State<_EconomySurface> {
  late Future<EconomyOverview> _load = _reload();
  bool _busy = false;
  Future<EconomyOverview> _reload() =>
      widget.economy.getOverview(widget.contextValue.clubId);
  void _refresh() => setState(() => _load = _reload());

  @override
  void didUpdateWidget(covariant _EconomySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.clubId != widget.contextValue.clubId) {
      _load = _reload();
    }
  }

  Future<String?> _reason(String title) async {
    final controller = TextEditingController();
    final strings = AppStrings.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: InputDecoration(labelText: strings.reason),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(strings.continueAction),
          ),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.length < 3 ? null : result;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(EconomyStrings.of(context).error(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    final controller = TextEditingController();
    final copy = EconomyStrings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(copy.newAccount),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: copy.accountName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppStrings.of(context).create),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _run(
      () => widget.economy.createAccount(
        clubId: widget.contextValue.clubId,
        name: name,
        idempotencyKey: _newUuid(),
      ),
    );
  }

  Future<void> _createEntry(List<EconomyAccount> accounts) async {
    if (accounts.isEmpty) return;
    final copy = EconomyStrings.of(context);
    final amount = TextEditingController();
    final reason = TextEditingController();
    var accountId = accounts.first.id;
    var direction = 'inflow';
    final value = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(copy.newEntry),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: InputDecoration(labelText: copy.account),
                  items: [
                    for (final item in accounts)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: (v) => setDialogState(() => accountId = v!),
                ),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  decoration: InputDecoration(labelText: copy.type),
                  items: [
                    DropdownMenuItem(value: 'inflow', child: Text(copy.inflow)),
                    DropdownMenuItem(
                      value: 'outflow',
                      child: Text(copy.outflow),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => direction = v!),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: copy.amountSek),
                ),
                TextField(
                  controller: reason,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: AppStrings.of(context).reason,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context).cancel),
            ),
            FilledButton(
              onPressed: () {
                final kronor = int.tryParse(amount.text.trim());
                if (kronor != null &&
                    kronor > 0 &&
                    reason.text.trim().length >= 3) {
                  Navigator.pop(context, {
                    'account': accountId,
                    'direction': direction,
                    'amount': kronor * 100,
                    'reason': reason.text.trim(),
                  });
                }
              },
              child: Text(AppStrings.of(context).create),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reason.dispose();
    if (value == null) return;
    await _run(
      () => widget.economy.createEntry(
        clubId: widget.contextValue.clubId,
        accountId: value['account']! as String,
        amountMinor: value['amount']! as int,
        direction: value['direction']! as String,
        category: 'manual_entry',
        reason: value['reason']! as String,
        idempotencyKey: _newUuid(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copy = EconomyStrings.of(context);
    if (!widget.contextValue.can('economy.read')) {
      return _StateCard(
        icon: Icons.lock_outline,
        title: copy.title,
        message: copy.noAccess,
      );
    }
    return FutureBuilder<EconomyOverview>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(label: AppStrings.of(context).loading);
        }
        if (snapshot.hasError) {
          return _StateCard(
            icon: Icons.lock_outline,
            title: copy.inactiveTitle,
            message: copy.inactiveMessage,
          );
        }
        final data = snapshot.requireData;
        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      copy.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  if (widget.contextValue.can('economy.manage'))
                    FilledButton.icon(
                      onPressed: _busy ? null : _createAccount,
                      icon: const Icon(Icons.add),
                      label: Text(copy.newAccount),
                    ),
                  const SizedBox(width: 8),
                  if (widget.contextValue.can('economy.post'))
                    FilledButton.icon(
                      onPressed: _busy || data.accounts.isEmpty
                          ? null
                          : () => _createEntry(data.accounts),
                      icon: const Icon(Icons.post_add),
                      label: Text(copy.newEntryShort),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (data.accounts.isEmpty)
                _StateCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: copy.noAccounts,
                  message: copy.noAccountsMessage,
                ),
              for (final account in data.accounts)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(account.name),
                    subtitle: Text(
                      account.teamId == null
                          ? copy.clubAccount
                          : copy.teamAccount,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(copy.entries, style: Theme.of(context).textTheme.titleLarge),
              if (data.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(copy.noEntries),
                ),
              for (final entry in data.entries) _entryTile(entry, copy),
            ],
          ),
        );
      },
    );
  }

  Widget _entryTile(EconomyEntry entry, EconomyStrings copy) => Card(
    child: ListTile(
      leading: Icon(
        entry.direction == 'inflow' ? Icons.south_west : Icons.north_east,
      ),
      title: Text(
        '${entry.direction == 'inflow' ? '+' : '−'}${_sek(entry.amountMinor)}',
      ),
      subtitle: Text(
        [
          '${copy.category(entry.category)} · ${copy.state(entry.state)}',
          if (entry.riskLevel == 'high')
            copy.approvals(entry.approvalCount, entry.requiredApprovals),
          if (entry.approvers.isNotEmpty)
            entry.approvers.map((item) => item.displayName).join(', '),
          if (entry.reversalState != null)
            '${copy.reversal}: ${copy.state(entry.reversalState!)}',
        ].join(' · '),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (entry.state == 'pending' &&
              entry.riskLevel == 'high' &&
              widget.contextValue.can('economy.approve'))
            IconButton(
              tooltip: entry.currentActorApproved
                  ? copy.alreadyApproved
                  : copy.approve,
              onPressed: _busy || entry.currentActorApproved
                  ? null
                  : () async {
                      final reason = await _reason(copy.approveEntry);
                      if (reason != null) {
                        await _run(
                          () => widget.economy.approve(
                            entryId: entry.id,
                            decision: 'approved',
                            reason: reason,
                            idempotencyKey: _newUuid(),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.approval_outlined),
            ),
          if (entry.state == 'pending' &&
              widget.contextValue.can('economy.post'))
            IconButton(
              tooltip: copy.post,
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => widget.economy.post(
                        entryId: entry.id,
                        idempotencyKey: _newUuid(),
                      ),
                    ),
              icon: const Icon(Icons.check_circle_outline),
            ),
          if (entry.state == 'posted' &&
              entry.reversalState == null &&
              widget.contextValue.can('economy.reverse'))
            IconButton(
              tooltip: copy.reverse,
              onPressed: _busy
                  ? null
                  : () async {
                      final reason = await _reason(copy.requestReversal);
                      if (reason != null) {
                        await _run(
                          () => widget.economy.reverse(
                            entryId: entry.id,
                            reason: reason,
                            idempotencyKey: _newUuid(),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.undo),
            ),
        ],
      ),
    ),
  );
}
