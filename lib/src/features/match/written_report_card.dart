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
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
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
    } catch (_) {
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Publicera matchrapport'),
                    subtitle: const Text(
                      'Visas för alla när slutresultatet är synligt på den publika lagsidan. Avstängt sparar ett internt utkast.',
                    ),
                    value: _publish,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _publish = value;
                          }),
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
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Sparar…'
                : _publish
                ? 'Spara och publicera'
                : 'Spara utkast',
          ),
        ),
      ],
    ),
  );
}
