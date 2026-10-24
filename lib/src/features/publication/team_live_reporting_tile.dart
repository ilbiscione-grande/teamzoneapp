part of '../../app/teamzone_app.dart';

/// Decision package 12 (PLM-03): whether a published team's matches are
/// reported live on its public page. Shown only to those who may change it
/// (the read is refused for others); off by default, and each match can
/// still be switched on or off in Live.
class _TeamLiveReportingTile extends StatefulWidget {
  const _TeamLiveReportingTile({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.editorial,
  });
  final String teamId, teamName;
  final EditorialServices editorial;

  @override
  State<_TeamLiveReportingTile> createState() => _TeamLiveReportingTileState();
}

class _TeamLiveReportingTileState extends State<_TeamLiveReportingTile> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final value = await widget.editorial.getTeamLiveReporting(widget.teamId);
      if (mounted) setState(() => _enabled = value.enabled);
    } catch (_) {
      // Not this viewer's to change: nothing shows.
    }
  }

  Future<void> _set(bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.editorial.setTeamLiveReporting(
        teamId: widget.teamId,
        enabled: enabled,
      );
      if (mounted) setState(() => _enabled = enabled);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Lagets publicerade matcher rapporteras live på lagsidan.'
                : 'Lagets matcher rapporteras inte live längre.',
          ),
        ),
      );
    } catch (error) {
      AppErrors.caught('team_live_reporting_tile._set', error);
      messenger.showSnackBar(
        const SnackBar(content: Text('Inställningen kunde inte sparas.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    if (enabled == null) return const SizedBox.shrink();
    return SwitchListTile(
      key: ValueKey('team-live-reporting-${widget.teamId}'),
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      title: Text('Rapportera ${widget.teamName}s matcher live'),
      subtitle: const Text(
        'Publicerade matcher visas live på lagsidan med ställning, klocka och '
        'matchens gång. Spelare nämns bara med namnsamtycke. Det går att '
        'ändra för en enskild match i Live.',
      ),
      value: enabled,
      onChanged: _busy ? null : _set,
    );
  }
}
