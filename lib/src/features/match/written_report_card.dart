part of '../../app/teamzone_app.dart';

class _WrittenReportCard extends StatefulWidget {
  const _WrittenReportCard({
    required this.eventId,
    required this.match,
    required this.canManage,
  });
  final String eventId;
  final MatchServices match;
  final bool canManage;
  @override
  State<_WrittenReportCard> createState() => _WrittenReportCardState();
}

class _WrittenReportCardState extends State<_WrittenReportCard> {
  late Future<WrittenMatchReport> _load = widget.match.getReport(
    widget.eventId,
  );
  void _reload() => setState(() {
    _load = widget.match.getReport(widget.eventId);
  });
  Future<void> _edit(WrittenMatchReport report) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WrittenReportDialog(
        eventId: widget.eventId,
        match: widget.match,
        report: report,
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Matchrapporten är sparad.')));
    _reload();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: FutureBuilder<WrittenMatchReport>(
      future: _load,
      builder: (context, value) {
        if (value.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        if (value.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Matchrapporten kunde inte laddas.'),
              TextButton(
                onPressed: _reload,
                child: const Text('Hämta matchrapport igen'),
              ),
            ],
          );
        }
        final report = value.requireData;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Matchrapport',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              report.body.isEmpty
                  ? 'Ingen matchrapport skriven ännu.'
                  : report.body,
            ),
            if (report.body.isNotEmpty)
              Text(
                report.published
                    ? 'Publiceras tillsammans med synligt slutresultat'
                    : 'Internt utkast',
              ),
            if (widget.canManage && report.canEdit)
              TextButton.icon(
                onPressed: () => _edit(report),
                icon: const Icon(Icons.edit_note),
                label: Text(
                  report.body.isEmpty
                      ? 'Skriv matchrapport'
                      : 'Redigera matchrapport',
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _WrittenReportDialog extends StatefulWidget {
  const _WrittenReportDialog({
    required this.eventId,
    required this.match,
    required this.report,
  });
  final String eventId;
  final MatchServices match;
  final WrittenMatchReport report;
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
