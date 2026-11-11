part of '../../app/teamzone_app.dart';

// Mina avgifter (club-members-and-fees.md, step 4): the fees of the
// signed-in person and their children, unpaid first, with how to pay. The
// fee reminder opens it.

class _MyClubFeesPage extends StatefulWidget {
  const _MyClubFeesPage({required this.services});

  /// Null when the backend is not connected.
  final ClubFeeServices? services;

  @override
  State<_MyClubFeesPage> createState() => _MyClubFeesPageState();
}

class _MyClubFeesPageState extends State<_MyClubFeesPage> {
  late Future<List<MyClubFee>> _fees = _load();

  Future<List<MyClubFee>> _load() async =>
      await widget.services?.loadMyClubFees() ?? const [];

  void _reload() => setState(() {
    _fees = _load();
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.feature('Mina avgifter'))),
      body: FutureBuilder<List<MyClubFee>>(
        future: _fees,
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
          final fees = snapshot.data;
          if (fees == null) {
            return AppLoadingIndicator(label: strings.loading);
          }
          final open = fees.where((fee) => fee.state == 'open').toList();
          final total = open.fold(0, (sum, fee) => sum + fee.amount);
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _fees;
            },
            child: ListView(
              key: const ValueKey('my-club-fees'),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  key: const ValueKey('my-club-fees-summary'),
                  open.isEmpty
                      ? strings.feature('Du har inga obetalda avgifter.')
                      : '${strings.feature('Att betala')}: ${clubFeeKronor(total)}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final fee in fees)
                  Card(
                    key: ValueKey('my-club-fee-${fee.feeId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  fee.title,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                clubFeeKronor(fee.amount),
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                          Text(
                            [
                              fee.name,
                              fee.clubName,
                              if (fee.discountAmount > 0)
                                '${strings.feature('rabatt')} ${clubFeeKronor(fee.discountAmount)}',
                            ].join(' · '),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fee.state == 'paid'
                                ? '${strings.feature('Betald')} ${fee.paidOn == null ? '' : _feeDay(fee.paidOn!)}'
                                : '${strings.feature('Sista betalningsdag')} ${_feeDay(fee.dueOn)}',
                            style: TextStyle(
                              color: fee.state == 'paid'
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          if (fee.state == 'open' &&
                              fee.paymentInfo != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              strings.feature('Så betalar du'),
                              style: theme.textTheme.titleSmall,
                            ),
                            SelectableText(fee.paymentInfo!),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (open.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    strings.feature(
                      'Klubben markerar avgiften som betald när betalningen har kommit in.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
