part of '../../app/teamzone_app.dart';

// Betalstatus (club-members-and-fees.md, step 3): an issued round's fees,
// filtered to the unpaid ones, marked paid by hand one or many at a time,
// waived with a note or opened again; exported as CSV for the treasurer.

String _feeStateLabel(AppStrings strings, ClubFee fee) =>
    strings.feature(switch (fee.state) {
      'paid' => 'Betald',
      'waived' when fee.amount == 0 => 'Täcks av familjetaket',
      'waived' => 'Efterskänkt',
      'cancelled' => 'Makulerad',
      _ => 'Obetald',
    });

String _feeMethodLabel(AppStrings strings, String? method) =>
    strings.feature(switch (method) {
      'swish' => 'Swish',
      'bank' => 'Bank',
      'cash' => 'Kontant',
      _ => 'Annat',
    });

const _feeMethods = ['swish', 'bank', 'cash', 'other'];

Future<void> _exportClubFees(
  BuildContext context,
  ClubFeeRound round,
  List<ClubFee> fees,
) async {
  final strings = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final name = round.title
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9åäö]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  try {
    final saved = await saveClubRegisterCsv(
      '${name.isEmpty ? 'avgifter' : name}.csv',
      clubFeesCsv(
        fees,
        categoryLabel: (category) => _memberCategoryLabel(strings, category),
        stateLabel: (fee) => _feeStateLabel(strings, fee),
        methodLabel: (method) => _feeMethodLabel(strings, method),
      ),
    );
    if (saved) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Avgifterna är exporterade.'))),
      );
    }
  } catch (error) {
    AppErrors.caught('club_fees._export', error);
    messenger.showSnackBar(
      SnackBar(
        content: Text(strings.feature('Avgifterna kunde inte exporteras.')),
      ),
    );
  }
}

enum _FeeFilter { all, open, paid, waived }

class _ClubFeePayments extends StatefulWidget {
  const _ClubFeePayments({
    required this.clubId,
    required this.roundId,
    required this.fees,
    required this.services,
    required this.onChanged,
  });
  final String clubId;
  final String roundId;
  final List<ClubFee> fees;
  final ClubFeeServices services;
  final VoidCallback onChanged;

  @override
  State<_ClubFeePayments> createState() => _ClubFeePaymentsState();
}

class _ClubFeePaymentsState extends State<_ClubFeePayments> {
  _FeeFilter _filter = _FeeFilter.all;
  final _selected = <String>{};
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _ClubFeePayments oldWidget) {
    super.didUpdateWidget(oldWidget);
    final open = {
      for (final fee in widget.fees)
        if (fee.isOpen) fee.feeId,
    };
    _selected.removeWhere((id) => !open.contains(id));
  }

  List<ClubFee> get _visible => [
    for (final fee in widget.fees)
      if (switch (_filter) {
        _FeeFilter.all => true,
        _FeeFilter.open => fee.isOpen,
        _FeeFilter.paid => fee.state == 'paid',
        _FeeFilter.waived => fee.state == 'waived',
      })
        fee,
  ];

  Future<void> _mark(
    List<ClubFee> fees,
    String decision, {
    DateTime? paidOn,
    String? method,
    String? note,
  }) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.services.markClubFees(
        clubId: widget.clubId,
        fees: fees,
        decision: decision,
        paidOn: paidOn,
        method: method,
        note: note,
        idempotencyKey: _newUuid(),
      );
      _selected.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            decision == 'paid'
                ? '${fees.length} ${strings.feature(fees.length == 1 ? 'markerad som betald' : 'markerade som betalda')}'
                : strings.feature(
                    decision == 'waived'
                        ? 'Avgiften är efterskänkt.'
                        : 'Avgiften är obetald igen.',
                  ),
          ),
        ),
      );
    } catch (error) {
      AppErrors.caught('club_fees._mark', error);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              error is ClubRegisterConflict
                  ? 'Någon annan har ändrat avgiften. Listan är uppdaterad.'
                  : 'Det gick inte. Försök igen.',
            ),
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
  }

  Future<void> _remind(List<ClubFee> fees) async {
    final strings = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final all = fees.length == widget.fees.where((fee) => fee.isOpen).length;
    final unreachable = fees.where((fee) => fee.reachable == false).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.feature('Skicka påminnelse?')),
        content: Text(
          [
            '${fees.length} ${strings.feature(fees.length == 1 ? 'obetald avgift' : 'obetalda avgifter')}. '
                '${strings.feature('Personen och vårdnadshavarna får en notis i inkorgen och en push.')}',
            if (unreachable > 0)
              '$unreachable ${strings.feature('kan inte nås, de saknar konto i TeamZone.')}',
            strings.feature(
              'En avgift som påmints senaste dygnet hoppas över.',
            ),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.feature('Avbryt')),
          ),
          FilledButton(
            key: const ValueKey('club-fee-remind-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.feature('Skicka')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await widget.services.sendClubFeeReminders(
        clubId: widget.clubId,
        roundId: widget.roundId,
        feeIds: all ? null : [for (final fee in fees) fee.feeId!],
        idempotencyKey: _newUuid(),
      );
      _selected.clear();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [
              '${strings.feature('Påminnelse om')} ${result.reminded} ${strings.feature(result.reminded == 1 ? 'avgift' : 'avgifter')} '
                  '${strings.feature('till')} ${result.notifications} ${strings.feature('mottagare')}.',
              if (result.skippedRecent > 0)
                '${result.skippedRecent} ${strings.feature('påmindes nyss och hoppades över.')}',
              if (result.unreachable.isNotEmpty)
                '${strings.feature('Kan inte nås')}: ${result.unreachable.join(', ')}.',
            ].join(' '),
          ),
        ),
      );
    } catch (error) {
      AppErrors.caught('club_fees._remind', error);
      messenger.showSnackBar(
        SnackBar(content: Text(strings.feature('Det gick inte. Försök igen.'))),
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
  }

  Future<void> _markPaid(List<ClubFee> fees) async {
    final payment = await showDialog<_FeePayment>(
      context: context,
      builder: (_) => _FeePaymentDialog(count: fees.length),
    );
    if (payment == null || !mounted) return;
    await _mark(
      fees,
      'paid',
      paidOn: payment.day,
      method: payment.method,
      note: payment.note,
    );
  }

  Future<void> _open(ClubFee fee) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ClubFeeSheet(fee: fee),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'paid':
        await _markPaid([fee]);
      case 'waived':
        final note = await showDialog<String>(
          context: context,
          builder: (_) => const _FeeWaiveDialog(),
        );
        if (note != null && mounted) await _mark([fee], 'waived', note: note);
      case 'open':
        await _mark([fee], 'open');
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final fees = widget.fees;
    final paid = fees.where((fee) => fee.state == 'paid');
    final open = fees.where((fee) => fee.isOpen).toList();
    int sum(Iterable<ClubFee> items) =>
        items.fold(0, (total, fee) => total + fee.amount);
    final visible = _visible;
    final selected = [
      for (final fee in open)
        if (_selected.contains(fee.feeId)) fee,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: const ValueKey('club-fee-payment-summary'),
          '${strings.feature('Betalt')} ${paid.length} · ${clubFeeKronor(sum(paid))}   '
          '${strings.feature('Obetalt')} ${open.length} · ${clubFeeKronor(sum(open))}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (filter, label) in [
              (_FeeFilter.all, 'Alla'),
              (_FeeFilter.open, 'Obetalda'),
              (_FeeFilter.paid, 'Betalda'),
              (_FeeFilter.waived, 'Efterskänkta'),
            ])
              ChoiceChip(
                key: ValueKey('club-fee-filter-${filter.name}'),
                label: Text(strings.feature(label)),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              key: const ValueKey('club-fee-select-open'),
              onPressed: _busy || open.isEmpty
                  ? null
                  : () => setState(() {
                      if (selected.length == open.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll([for (final fee in open) fee.feeId!]);
                      }
                    }),
              child: Text(
                strings.feature(
                  open.isNotEmpty && selected.length == open.length
                      ? 'Avmarkera alla'
                      : 'Välj alla obetalda',
                ),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('club-fee-mark-paid'),
              onPressed: _busy || selected.isEmpty
                  ? null
                  : () => _markPaid(selected),
              icon: const Icon(Icons.check),
              label: Text(
                selected.isEmpty
                    ? strings.feature('Markera betalda')
                    : '${strings.feature('Markera betalda')} (${selected.length})',
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('club-fee-remind'),
              onPressed: _busy || open.isEmpty
                  ? null
                  : () => _remind(selected.isEmpty ? open : selected),
              icon: const Icon(Icons.notifications_outlined),
              label: Text(
                selected.isEmpty
                    ? strings.feature('Påminn obetalda')
                    : '${strings.feature('Påminn valda')} (${selected.length})',
              ),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              strings.feature('Inga avgifter här.'),
              textAlign: TextAlign.center,
            ),
          ),
        for (final fee in visible)
          _ClubFeePaymentRow(
            fee: fee,
            selected: _selected.contains(fee.feeId),
            onSelected: fee.isOpen && !_busy
                ? (value) => setState(() {
                    if (value) {
                      _selected.add(fee.feeId!);
                    } else {
                      _selected.remove(fee.feeId);
                    }
                  })
                : null,
            onTap: _busy ? null : () => _open(fee),
          ),
      ],
    );
  }
}

class _ClubFeePaymentRow extends StatelessWidget {
  const _ClubFeePaymentRow({
    required this.fee,
    required this.selected,
    required this.onSelected,
    required this.onTap,
  });
  final ClubFee fee;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final status = switch (fee.state) {
      'paid' => [
        _feeStateLabel(strings, fee),
        if (fee.paidOn case final day?) _feeDay(day),
        _feeMethodLabel(strings, fee.paymentMethod),
      ].join(' '),
      _ => _feeStateLabel(strings, fee),
    };
    return ListTile(
      key: ValueKey('club-fee-${fee.personId}'),
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        key: ValueKey('club-fee-check-${fee.personId}'),
        value: selected,
        onChanged: onSelected == null
            ? null
            : (value) => onSelected!(value ?? false),
      ),
      title: Text(fee.name),
      subtitle: Text(
        [
          status,
          if (fee.guardians.isNotEmpty)
            '${strings.feature('betalas av')} ${fee.guardians.join(', ')}',
          if (fee.isOpen && fee.reachable == false)
            strings.feature('kan inte nås')
          else if (fee.remindedAt case final at?)
            '${strings.feature('påmind')} ${_feeDay(at.toLocal())}',
          ?fee.note,
        ].join(' · '),
      ),
      trailing: Text(
        clubFeeKronor(fee.amount),
        style: TextStyle(
          color: fee.isOpen ? colors.onSurface : colors.onSurfaceVariant,
          fontWeight: fee.isOpen ? FontWeight.w600 : null,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// One fee: what it is and what can be done with it; pops the decision.
class _ClubFeeSheet extends StatelessWidget {
  const _ClubFeeSheet({required this.fee});
  final ClubFee fee;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        key: const ValueKey('club-fee-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(fee.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            [
              clubFeeKronor(fee.amount),
              if (fee.discountAmount > 0)
                '${strings.feature('rabatt')} ${clubFeeKronor(fee.discountAmount)}',
              _feeStateLabel(strings, fee),
            ].join(' · '),
          ),
          if (fee.state == 'paid')
            Text(
              '${strings.feature('Betald')} '
              '${fee.paidOn == null ? '' : _feeDay(fee.paidOn!)} '
              '${_feeMethodLabel(strings, fee.paymentMethod)}',
            ),
          if (fee.guardians.isNotEmpty)
            Text(
              '${strings.feature('Betalas av')} ${fee.guardians.join(', ')}',
            ),
          if (fee.note case final note?)
            Text('${strings.feature('Anteckning')}: $note'),
          const SizedBox(height: 16),
          if (fee.isOpen) ...[
            FilledButton(
              key: const ValueKey('club-fee-sheet-paid'),
              onPressed: () => Navigator.of(context).pop('paid'),
              child: Text(strings.feature('Markera betald')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('club-fee-sheet-waive'),
              onPressed: () => Navigator.of(context).pop('waived'),
              child: Text(strings.feature('Efterskänk')),
            ),
          ],
          if (fee.canReopen)
            OutlinedButton(
              key: const ValueKey('club-fee-sheet-reopen'),
              onPressed: () => Navigator.of(context).pop('open'),
              child: Text(strings.feature('Ändra till obetald')),
            ),
        ],
      ),
    );
  }
}

typedef _FeePayment = ({DateTime day, String method, String? note});

class _FeePaymentDialog extends StatefulWidget {
  const _FeePaymentDialog({required this.count});
  final int count;

  @override
  State<_FeePaymentDialog> createState() => _FeePaymentDialogState();
}

class _FeePaymentDialogState extends State<_FeePaymentDialog> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  String _method = 'swish';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(
        widget.count == 1
            ? strings.feature('Markera betald')
            : '${strings.feature('Markera betalda')} (${widget.count})',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: const ValueKey('club-fee-paid-day'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(strings.feature('Betalningsdag')),
              subtitle: Text(_feeDay(_day)),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: DateTime(now.year - 2),
                  lastDate: now,
                );
                if (picked != null && mounted) setState(() => _day = picked);
              },
            ),
            RadioGroup<String>(
              groupValue: _method,
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
              child: Column(
                children: [
                  for (final method in _feeMethods)
                    RadioListTile<String>(
                      key: ValueKey('club-fee-method-$method'),
                      contentPadding: EdgeInsets.zero,
                      value: method,
                      title: Text(_feeMethodLabel(strings, method)),
                    ),
                ],
              ),
            ),
            TextField(
              key: const ValueKey('club-fee-note'),
              controller: _note,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: strings.feature('Anteckning (valfri)'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const ValueKey('club-fee-paid-save'),
          onPressed: () => Navigator.of(context).pop<_FeePayment>((
            day: _day,
            method: _method,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          )),
          child: Text(strings.feature('Spara')),
        ),
      ],
    );
  }
}

/// Why the fee is waived; pops the note ('' for none).
class _FeeWaiveDialog extends StatefulWidget {
  const _FeeWaiveDialog();

  @override
  State<_FeeWaiveDialog> createState() => _FeeWaiveDialogState();
}

class _FeeWaiveDialogState extends State<_FeeWaiveDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Efterskänk avgiften?')),
      content: TextField(
        key: const ValueKey('club-fee-waive-note'),
        controller: _note,
        maxLength: 200,
        decoration: InputDecoration(
          labelText: strings.feature('Anledning (valfri)'),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const ValueKey('club-fee-waive-save'),
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(strings.feature('Efterskänk')),
        ),
      ],
    );
  }
}
