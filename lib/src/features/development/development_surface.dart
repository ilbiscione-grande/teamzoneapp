part of '../../app/teamzone_app.dart';

class _DevelopmentSurface extends StatefulWidget {
  const _DevelopmentSurface({
    required this.contextValue,
    required this.development,
  });

  final TeamZoneContext contextValue;
  final DevelopmentServices development;

  @override
  State<_DevelopmentSurface> createState() => _DevelopmentSurfaceState();
}

class _DevelopmentSurfaceState extends State<_DevelopmentSurface> {
  late Future<List<DevelopmentPlan>> _load = _reload();

  Future<List<DevelopmentPlan>> _reload() {
    final teamId = widget.contextValue.teamId;
    if (teamId == null) return Future.value(const []);
    return widget.development.listPlans(
      clubId: widget.contextValue.clubId,
      teamId: teamId,
    );
  }

  Future<void> _createPlan() async {
    final title = TextEditingController();
    final focus = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Ny lagplan')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Titel'),
              ),
            ),
            TextField(
              controller: focus,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Fokus'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).feature('Skapa')),
          ),
        ],
      ),
    );
    final planTitle = title.text.trim();
    final planFocus = focus.text.trim();
    if (submitted != true || planTitle.length < 2) return;
    try {
      await widget.development.createPlan(
        clubId: widget.contextValue.clubId,
        teamId: widget.contextValue.teamId!,
        planType: 'team',
        title: planTitle,
        focus: planFocus,
        idempotencyKey: _newUuid(),
      );
    } catch (error, stackTrace) {
      debugPrint('Create development plan failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Planen kunde inte skapas. Försök igen.'),
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      final refreshed = _reload();
      setState(() {
        _load = refreshed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).feature('Planen har skapats.')),
        ),
      );
    }
  }

  Future<void> _addAction(DevelopmentPlan plan) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).feature('Ny åtgärd')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Åtgärd'),
              ),
            ),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: AppStrings.of(context).feature('Beskrivning'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).feature('Avbryt')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).feature('Lägg till')),
          ),
        ],
      ),
    );
    final actionTitle = title.text.trim();
    final actionDescription = description.text.trim();
    if (submitted != true || actionTitle.length < 2) return;
    try {
      await widget.development.addAction(
        planId: plan.id,
        title: actionTitle,
        description: actionDescription,
        expectedPlanRevision: plan.revision,
        idempotencyKey: _newUuid(),
      );
    } catch (error, stackTrace) {
      debugPrint('Add development action failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Åtgärden kunde inte sparas. Försök igen.'),
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      final refreshed = _reload();
      setState(() {
        _load = refreshed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.of(context).feature('Åtgärden har lagts till.'),
          ),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _DevelopmentSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextValue.id != widget.contextValue.id) {
      _load = _reload();
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => setState(() {
      _load = _reload();
    }),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Utveckling', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (widget.contextValue.can('development.manage')) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _createPlan,
              icon: const Icon(Icons.add),
              label: Text(AppStrings.of(context).feature('Ny lagplan')),
            ),
          ),
          const SizedBox(height: 8),
        ],
        FutureBuilder<List<DevelopmentPlan>>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppLoadingIndicator(
                  label: AppStrings.of(context).loading,
                ),
              );
            }
            if (snapshot.hasError) {
              return _StateCard(
                icon: Icons.lock_outline,
                title: AppStrings.of(
                  context,
                ).feature('Utvecklingsplaner är inte tillgängliga'),
                message: AppStrings.of(context).feature(
                  'Den här rollen saknar behörighet i aktuell lagkontext.',
                ),
              );
            }
            final plans = snapshot.requireData;
            if (plans.isEmpty) {
              return _StateCard(
                icon: Icons.flag_outlined,
                title: AppStrings.of(
                  context,
                ).feature('Inga utvecklingsplaner ännu'),
                message: AppStrings.of(context).feature(
                  'Grunden är klar. Nya planer skapas av behörig ledare.',
                ),
              );
            }
            return Column(
              children: [
                for (final plan in plans)
                  Card(
                    child: ExpansionTile(
                      title: Text(plan.title),
                      subtitle: Text(
                        '${AppStrings.of(context).domainValue(plan.planType)} · ${AppStrings.of(context).domainValue(plan.state)}',
                      ),
                      children: [
                        if (plan.focus.isNotEmpty)
                          ListTile(title: Text(plan.focus)),
                        for (final action in plan.actions)
                          ListTile(
                            leading: const Icon(Icons.check_circle_outline),
                            title: Text(action.title),
                            subtitle: action.description.isEmpty
                                ? null
                                : Text(action.description),
                            trailing: Text(
                              AppStrings.of(context).domainValue(action.state),
                            ),
                          ),
                        if (widget.contextValue.can('development.manage'))
                          ListTile(
                            leading: const Icon(Icons.add_task),
                            title: Text(
                              AppStrings.of(
                                context,
                              ).feature('Lägg till åtgärd'),
                            ),
                            onTap: () => _addAction(plan),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
