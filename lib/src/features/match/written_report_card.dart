part of '../../app/teamzone_app.dart';

class _WrittenReportDialog extends StatefulWidget {
  const _WrittenReportDialog({
    required this.eventId,
    required this.match,
    required this.report,
    this.contextLabel,
  });
  final String eventId;
  final MatchServices match;
  final WrittenMatchReport report;
  final String? contextLabel;
  @override
  State<_WrittenReportDialog> createState() => _WrittenReportDialogState();
}

class _WrittenReportDialogState extends State<_WrittenReportDialog> {
  final _form = GlobalKey<FormState>();
  late String _body = widget.report.body;
  late bool _publish = widget.report.published;
  bool _busy = false;
  String? _error, _payload, _command;

  /// Saves as a draft, or published when [publish].
  Future<void> _save({required bool publish}) async {
    if (_busy) return;
    setState(() => _publish = publish);
    if (!_form.currentState!.validate()) return;
    final payload = '$_publish/$_body';
    if (_payload != payload) {
      _payload = payload;
      _command = _newUuid();
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.match.saveReport(
        _command!,
        widget.eventId,
        widget.report.revision,
        _body,
        _publish,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      AppErrors.caught('written_report_card._save', error);

      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Kunde inte bekräfta sparandet. Försök igen. Om rapporten har ändrats, stäng dialogen och hämta matchen igen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Skriv matchrapport'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.contextLabel != null) ...[
                  Text(widget.contextLabel!),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  initialValue: _body,
                  enabled: !_busy,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 10000,
                  decoration: const InputDecoration(
                    labelText: 'Matchrapport',
                    hintText: 'Berätta kort om matchen…',
                  ),
                  onChanged: (value) => _body = value,
                  validator: (value) =>
                      _publish && (value?.trim().isEmpty ?? true)
                      ? 'Skriv en rapport innan publicering'
                      : null,
                ),
                if (widget.report.canPublish)
                  Text(
                    widget.report.published
                        ? 'Rapporten är publicerad och visas på den publika lagsidan när slutresultatet syns där.'
                        : 'Publicera visar rapporten på den publika lagsidan när slutresultatet syns där. Ett utkast ser bara ledarna.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        if (widget.report.canPublish) ...[
          OutlinedButton(
            key: const Key('written-report-draft'),
            onPressed: _busy ? null : () => _save(publish: false),
            child: Text(
              widget.report.published ? 'Avpublicera' : 'Spara utkast',
            ),
          ),
          FilledButton(
            key: const Key('written-report-publish'),
            onPressed: _busy ? null : () => _save(publish: true),
            child: Text(
              _busy
                  ? 'Sparar…'
                  : widget.report.published
                  ? 'Spara'
                  : 'Publicera',
            ),
          ),
        ] else
          FilledButton(
            key: const Key('written-report-draft'),
            onPressed: _busy ? null : () => _save(publish: false),
            child: Text(_busy ? 'Sparar…' : 'Spara utkast'),
          ),
      ],
    ),
  );
}
