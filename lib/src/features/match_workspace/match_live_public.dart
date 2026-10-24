part of '../../app/teamzone_app.dart';

/// Decision package 12 in Live: whether this match is reported live on the
/// team's public page — following the team's choice, or switched on or off
/// for this match (PLM-03). Only a published match in a published team can
/// be reported.
mixin _LivePublicState on State<_MatchLiveView> {
  LiveReporting? _publicLive;

  String get _eventId;

  Future<void> _loadPublicLive() async {
    try {
      final value = await widget.calendar.matchPlans.getLiveReporting(_eventId);
      if (mounted) setState(() => _publicLive = value);
    } catch (error) {
      AppErrors.caught('match_live_public._loadPublicLive', error);
    }
  }

  /// "Live publikt", "Inte publikt" or why it cannot be.
  String get _publicLiveLabel {
    final value = _publicLive;
    if (value == null) return 'Publikt';
    if (!value.published) return 'Inte publicerad';
    return value.chosen ? 'Live publikt' : 'Inte publikt';
  }

  Future<void> _choosePublicLive() async {
    final value = _publicLive;
    if (value == null) return;
    final chosen = await showDialog<(bool?,)>(
      context: context,
      builder: (_) => _PublicLiveDialog(reporting: value),
    );
    if (chosen == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.calendar.matchPlans.setLiveReporting(
        _eventId,
        chosen.$1,
      );
      if (mounted) setState(() => _publicLive = saved);
    } catch (error) {
      AppErrors.caught('match_live_public._choosePublicLive', error);
      messenger.showSnackBar(
        const SnackBar(content: Text('Valet kunde inte sparas.')),
      );
    }
  }
}

class _PublicLiveDialog extends StatefulWidget {
  const _PublicLiveDialog({required this.reporting});
  final LiveReporting reporting;

  @override
  State<_PublicLiveDialog> createState() => _PublicLiveDialogState();
}

class _PublicLiveDialogState extends State<_PublicLiveDialog> {
  late bool? _choice = widget.reporting.matchChoice;

  @override
  Widget build(BuildContext context) {
    final reporting = widget.reporting;
    if (!reporting.published) {
      return AlertDialog(
        title: const Text('Live på lagsidan'),
        content: const Text(
          'Matchen eller laget är inte publicerat. Publicera laget under '
          'Publika sidor och matchen under Publicering för att kunna '
          'rapportera den live.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stäng'),
          ),
        ],
      );
    }
    Widget option(bool? value, String title, String subtitle) =>
        RadioListTile<bool?>(
          key: Key('public-live-${value ?? 'team'}'),
          contentPadding: EdgeInsets.zero,
          value: value,
          title: Text(title),
          subtitle: Text(subtitle),
        );
    return AlertDialog(
      title: const Text('Live på lagsidan'),
      content: SizedBox(
        width: 380,
        child: RadioGroup<bool?>(
          groupValue: _choice,
          onChanged: (value) => setState(() => _choice = value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                null,
                'Följ lagets val (${reporting.teamDefault ? 'på' : 'av'})',
                'Laget väljer under Publika sidor.',
              ),
              option(
                true,
                'Rapportera live',
                'Ställning, klocka och matchens gång visas på lagsidan. '
                    'Spelare nämns bara med namnsamtycke.',
              ),
              option(false, 'Rapportera inte', 'Matchen visas inte live.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          key: const Key('public-live-save'),
          onPressed: () => Navigator.pop(context, (_choice,)),
          child: const Text('Spara'),
        ),
      ],
    );
  }
}
