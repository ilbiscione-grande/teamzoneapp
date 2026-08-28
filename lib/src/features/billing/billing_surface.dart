part of '../../app/teamzone_app.dart';

class _BillingSurface extends StatefulWidget {
  const _BillingSurface({
    required this.contextValue,
    required this.billing,
    this.result,
  });

  final TeamZoneContext contextValue;
  final BillingServices billing;
  final String? result;

  @override
  State<_BillingSurface> createState() => _BillingSurfaceState();
}

class _BillingSurfaceState extends State<_BillingSurface> {
  late Future<BillingOverview> _load = _reload();
  String _interval = 'month';
  String? _busyPlan;

  Future<BillingOverview> _reload() =>
      widget.billing.getPublishedPricebook(clubId: widget.contextValue.clubId);

  @override
  void didUpdateWidget(covariant _BillingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.clubId != widget.contextValue.clubId) {
      _load = _reload();
    }
  }

  Future<void> _checkout(BillingPlan plan) async {
    if (_busyPlan != null) return;
    setState(() => _busyPlan = plan.key);
    try {
      final uri = await widget.billing.createCheckout(
        clubId: widget.contextValue.clubId,
        planKey: plan.key,
        interval: _interval,
        idempotencyKey: _newUuid(),
      );
      final opened = await launchUrl(uri, webOnlyWindowName: '_self');
      if (!opened) throw StateError('Checkout unavailable.');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Betalningen kunde inte startas. Försök igen.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.contextValue.can('club.billing.manage')) {
      return _StateCard(
        icon: Icons.lock_outline,
        title: AppStrings.of(context).feature('Abonnemang'),
        message: AppStrings.of(
          context,
        ).feature('Du saknar behörighet att hantera klubbens abonnemang.'),
      );
    }
    if (!kIsWeb) {
      return _StateCard(
        icon: Icons.receipt_long_outlined,
        title: AppStrings.of(context).feature('Abonnemang'),
        message: AppStrings.of(
          context,
        ).feature('Abonnemang hanteras av klubbadministratören på webben.'),
      );
    }
    return FutureBuilder<BillingOverview>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppLoadingIndicator(label: AppStrings.of(context).loading);
        }
        if (snapshot.hasError) {
          return _StateCard(
            icon: Icons.cloud_off_outlined,
            title: AppStrings.of(
              context,
            ).feature('Abonnemang kunde inte laddas'),
            message: AppStrings.of(context).feature('Försök igen.'),
            action: FilledButton(
              onPressed: () => setState(() => _load = _reload()),
              child: Text(AppStrings.of(context).feature('Försök igen')),
            ),
          );
        }
        final pricebook = snapshot.requireData;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Abonnemang',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (widget.result == 'success')
              Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text(
                    AppStrings.of(context).feature('Betalningen är mottagen'),
                  ),
                  subtitle: Text(
                    AppStrings.of(context).feature(
                      'Abonnemanget uppdateras när betalningen har bekräftats.',
                    ),
                  ),
                ),
              ),
            if (widget.result == 'cancelled')
              Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text(
                    AppStrings.of(context).feature('Betalningen avbröts'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'month',
                  label: Text(AppStrings.of(context).feature('Månad')),
                ),
                ButtonSegment(
                  value: 'year',
                  label: Text(AppStrings.of(context).feature('År')),
                ),
              ],
              selected: {_interval},
              onSelectionChanged: (value) =>
                  setState(() => _interval = value.single),
            ),
            const SizedBox(height: 16),
            for (final plan in pricebook.plans) _planCard(plan),
          ],
        );
      },
    );
  }

  Widget _planCard(BillingPlan plan) {
    final amount = _interval == 'month'
        ? plan.monthlyAmountMinor
        : plan.annualAmountMinor;
    final isFree = plan.key == 'plan.free';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _planName(plan.key),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.quoteRequired
                        ? AppStrings.of(context).feature('Pris enligt offert')
                        : AppStrings.of(context).pricePerInterval(
                            _sek(amount ?? 0),
                            _interval == 'month',
                          ),
                  ),
                  if (plan.maxActiveTeams != null)
                    Text(
                      AppStrings.of(context).planCapacity(
                        plan.maxActiveTeams!,
                        plan.maxBillablePeople,
                      ),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: isFree || plan.quoteRequired || _busyPlan != null
                  ? null
                  : () => _checkout(plan),
              child: Text(
                _busyPlan == plan.key
                    ? AppStrings.of(context).feature('Öppnar…')
                    : isFree
                    ? AppStrings.of(context).feature('Kostnadsfri')
                    : plan.quoteRequired
                    ? AppStrings.of(context).feature('Offert')
                    : AppStrings.of(context).feature('Välj plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _planName(String key) => switch (key) {
  'plan.free' => 'Free',
  'plan.small' => 'Small',
  'plan.medium' => 'Medium',
  'plan.large' => 'Large',
  'plan.custom_xl' => 'Custom XL',
  _ => key,
};

String _sek(int minor) {
  final digits = (minor ~/ 100).toString();
  final chunks = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    chunks.insert(0, digits.substring((end - 3).clamp(0, end), end));
  }
  return '${chunks.join(' ')} kr';
}
