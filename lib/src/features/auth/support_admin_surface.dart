part of '../../app/teamzone_app.dart';

class _SupportAdminSurface extends StatefulWidget {
  const _SupportAdminSurface({required this.membership, required this.profile});

  final MembershipServices membership;
  final ProfileServices profile;

  @override
  State<_SupportAdminSurface> createState() => _SupportAdminSurfaceState();
}

class _SupportAdminSurfaceState extends State<_SupportAdminSurface> {
  Future<List<ProtectedNameSupportCase>>? _cases;
  Future<List<GlobalPersonErasureCase>>? _erasures;
  Future<List<ClubVerificationRequest>>? _verifications;
  String? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _cases = widget.membership
          .listProtectedNameSupportCases(status: _status)
          .timeout(const Duration(seconds: 15));
      _erasures = widget.membership.listGlobalPersonErasureCases().timeout(
        const Duration(seconds: 15),
      );
      _verifications = widget.membership
          .listClubVerificationRequests(
            status: switch (_status) {
              'pending' => 'pending',
              'resolved' => 'approved',
              'rejected' => 'rejected',
              _ => null,
            },
          )
          .timeout(const Duration(seconds: 15));
    });
  }

  bool _showErasure(GlobalPersonErasureCase item) => switch (_status) {
    null => true,
    'pending' => item.state == 'requested',
    'resolved' => item.state == 'completed',
    'rejected' => item.state == 'rejected',
    _ => false,
  };

  bool _showVerification(ClubVerificationRequest item) => switch (_status) {
    null => true,
    'pending' => item.status == 'pending',
    'resolved' => item.status == 'approved',
    'rejected' => item.status == 'rejected',
    _ => false,
  };

  Future<void> _decideVerification(
    ClubVerificationRequest item, {
    required bool approve,
  }) async {
    final strings = AppStrings.of(context);
    var reason = '';
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          strings.feature(
            approve ? 'Godkänn officiell klubb' : 'Avslå klubbverifiering',
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: strings.feature('Beslutsmotivering'),
            ),
            onChanged: (value) => reason = value,
            validator: (value) => (value?.trim().length ?? 0) < 5
                ? strings.feature('Ange minst 5 tecken.')
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(strings.feature(approve ? 'Godkänn' : 'Avslå')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.membership.decideClubVerificationRequest(
        requestId: item.id,
        approve: approve,
        decisionReason: reason.trim(),
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Verifieringen kunde inte uppdateras. Läs om kön och försök igen.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _decideErasure(
    GlobalPersonErasureCase item, {
    required bool approve,
  }) async {
    final strings = AppStrings.of(context);
    var reason = '';
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          strings.feature(
            approve ? 'Godkänn global radering' : 'Avslå global radering',
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (approve) ...[
                Text(
                  strings.feature(
                    'Kontot tas bort från Auth och kan inte längre användas för inloggning. Neutral historik och audit bevaras.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: strings.feature('Beslutsanteckning'),
                ),
                onChanged: (value) => reason = value,
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? strings.feature('Ange minst 2 tecken.')
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(
              strings.feature(approve ? 'Godkänn och radera' : 'Avslå'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final state = await widget.membership.decideGlobalPersonErasure(
        requestId: item.id,
        approve: approve,
        reason: reason.trim(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Personradering')),
          content: Text(
            strings.feature(
              state == 'completed'
                  ? 'Kontot är raderat och ärendet är slutfört.'
                  : 'Ärendet är avslaget.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Personradering')),
          content: Text(
            strings.feature(
              'Åtgärden kunde inte slutföras. Ärendet ligger kvar för säkert återförsök.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _update(ProtectedNameSupportCase item, String status) async {
    final strings = AppStrings.of(context);
    var note = '';
    if (status != 'in_review') {
      final approvesRegistration = status == 'approved';
      final formKey = GlobalKey<FormState>();
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            strings.feature(
              approvesRegistration ? 'Godkänn och registrera' : 'Avslå ärende',
            ),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (approvesRegistration) ...[
                  Text(
                    strings.feature(
                      'Klubben och laget skapas eller kopplas till en befintlig officiell klubb. Sökanden blir klubbfunktionär och får administrativ behörighet.',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  autofocus: true,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: strings.feature('Beslutsanteckning'),
                  ),
                  onChanged: (value) => note = value,
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? strings.feature('Ange minst 5 tecken.')
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, note.trim());
                }
              },
              child: Text(
                strings.feature(
                  approvesRegistration ? 'Godkänn och registrera' : 'Avslå',
                ),
              ),
            ),
          ],
        ),
      );
      if (value == null) return;
      note = value;
    }
    try {
      await widget.membership.updateProtectedNameSupportCase(
        caseId: item.id,
        status: status,
        resolutionNote: note,
        expectedRevision: item.revision,
        idempotencyKey: _newUuid(),
      );
      if (mounted) _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Ärendet kunde inte uppdateras. Läs om kön och försök igen.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openConversation(ProtectedNameSupportCase item) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProtectedNameSupportConversationSheet(
        membership: widget.membership,
        supportCase: item,
        asSupport: true,
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.feature('Supportärenden')),
        actions: [
          IconButton(
            key: const ValueKey('support-email-changes'),
            tooltip: strings.feature('Byte av inloggningsadress'),
            icon: const Icon(Icons.alternate_email),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => _LoginEmailChangeQueue(profile: widget.profile),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String?>(
              initialValue: _status,
              decoration: InputDecoration(labelText: strings.feature('Status')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(strings.feature('Alla')),
                ),
                for (final value in const [
                  'pending',
                  'in_review',
                  'resolved',
                  'rejected',
                ])
                  DropdownMenuItem(
                    value: value,
                    child: Text(strings.domainValue(value)),
                  ),
              ],
              onChanged: (value) {
                _status = value;
                _reload();
              },
            ),
          ),
          FutureBuilder<List<ClubVerificationRequest>>(
            future: _verifications,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              strings.feature(
                                'Klubbverifieringarna kunde inte laddas.',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _reload,
                            child: Text(strings.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final items = (snapshot.data ?? const [])
                  .where(_showVerification)
                  .toList(growable: false);
              if (items.isEmpty) return const SizedBox.shrink();
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 310),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Chip(
                              avatar: const Icon(
                                Icons.verified_outlined,
                                size: 18,
                              ),
                              label: Text(strings.feature('Officiell klubb')),
                            ),
                            Text(
                              item.clubName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${item.requesterName} · ${strings.domainValue(item.status)}',
                            ),
                            const SizedBox(height: 10),
                            SelectableText(item.evidenceSummary),
                            if (item.decisionReason != null) ...[
                              const SizedBox(height: 10),
                              Text(item.decisionReason!),
                            ],
                            if (item.status == 'pending') ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => _decideVerification(
                                      item,
                                      approve: true,
                                    ),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: Text(strings.feature('Godkänn')),
                                  ),
                                  TextButton(
                                    onPressed: () => _decideVerification(
                                      item,
                                      approve: false,
                                    ),
                                    child: Text(strings.feature('Avslå')),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<ProtectedNameSupportCase>>(
              future: _cases,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            strings.feature('Supportkön är inte tillgänglig'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            strings.feature(
                              'Du saknar supportbehörighet eller så kunde kön inte laddas.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _reload,
                            child: Text(strings.retry),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final items = snapshot.data ?? const [];
                return FutureBuilder<List<GlobalPersonErasureCase>>(
                  future: _erasures,
                  builder: (context, erasureSnapshot) {
                    if (erasureSnapshot.connectionState !=
                        ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (erasureSnapshot.hasError) {
                      return Center(
                        child: OutlinedButton(
                          onPressed: _reload,
                          child: Text(strings.retry),
                        ),
                      );
                    }
                    final erasures = (erasureSnapshot.data ?? const [])
                        .where(_showErasure)
                        .toList(growable: false);
                    if (items.isEmpty && erasures.isEmpty) {
                      return Center(
                        child: Text(
                          strings.feature('Inga supportärenden i vald status.'),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async {
                        _reload();
                        await Future.wait([
                          _cases!,
                          _erasures!,
                          _verifications!,
                        ]);
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: erasures.length + items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index < erasures.length) {
                            final item = erasures[index];
                            final actionable = item.state == 'requested';
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Chip(
                                      avatar: const Icon(
                                        Icons.person_remove_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        strings.feature(
                                          'Kontoradering · hög risk',
                                        ),
                                      ),
                                    ),
                                    Text(
                                      item.requesterName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(strings.domainValue(item.state)),
                                    const SizedBox(height: 8),
                                    SelectableText(item.reason),
                                    if (actionable) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton(
                                            onPressed: () => _decideErasure(
                                              item,
                                              approve: true,
                                            ),
                                            child: Text(
                                              strings.feature(
                                                'Godkänn och radera',
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => _decideErasure(
                                              item,
                                              approve: false,
                                            ),
                                            child: Text(
                                              strings.feature('Avslå'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }
                          final item = items[index - erasures.length];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Chip(
                                    avatar: const Icon(
                                      Icons.domain_verification_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      strings.feature('Skyddat klubbnamn'),
                                    ),
                                  ),
                                  Text(
                                    item.clubName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${item.teamName} · ${strings.domainValue(item.status)}',
                                  ),
                                  const SizedBox(height: 12),
                                  SelectableText(item.message),
                                  if (item.resolutionNote != null) ...[
                                    const SizedBox(height: 12),
                                    Text(item.resolutionNote!),
                                  ],
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: () => _openConversation(item),
                                    icon: Badge.count(
                                      count: item.unreadCount,
                                      isLabelVisible: item.unreadCount > 0,
                                      child: const Icon(Icons.forum_outlined),
                                    ),
                                    label: Text(
                                      strings.feature(
                                        item.status == 'pending' ||
                                                item.status == 'in_review'
                                            ? 'Svara eller be om uppgifter'
                                            : 'Visa meddelanden',
                                      ),
                                    ),
                                  ),
                                  if (item.status == 'pending' ||
                                      item.status == 'in_review') ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (item.status == 'pending')
                                          OutlinedButton(
                                            onPressed: () =>
                                                _update(item, 'in_review'),
                                            child: Text(
                                              strings.feature(
                                                'Påbörja granskning',
                                              ),
                                            ),
                                          ),
                                        FilledButton.icon(
                                          onPressed: () =>
                                              _update(item, 'approved'),
                                          icon: const Icon(
                                            Icons.domain_add_outlined,
                                          ),
                                          label: Text(
                                            strings.feature(
                                              'Godkänn och registrera',
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _update(item, 'rejected'),
                                          child: Text(
                                            strings.feature('Avslå ärende'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtectedNameSupportConversationSheet extends StatefulWidget {
  const _ProtectedNameSupportConversationSheet({
    required this.membership,
    required this.supportCase,
    required this.asSupport,
  });

  final MembershipServices membership;
  final ProtectedNameSupportCase supportCase;
  final bool asSupport;

  @override
  State<_ProtectedNameSupportConversationSheet> createState() =>
      _ProtectedNameSupportConversationSheetState();
}

class _ProtectedNameSupportConversationSheetState
    extends State<_ProtectedNameSupportConversationSheet> {
  final _message = TextEditingController();
  late Future<List<ProtectedNameSupportMessage>> _messages = _load();
  final List<StagedProtectedNameSupportFile> _stagedFiles = [];
  bool _sending = false;
  bool _uploading = false;
  String? _error;

  bool get _isOpen =>
      widget.supportCase.status == 'pending' ||
      widget.supportCase.status == 'in_review';

  Future<List<ProtectedNameSupportMessage>> _load() async {
    final messages = await widget.membership
        .listProtectedNameSupportMessages(caseId: widget.supportCase.id)
        .timeout(const Duration(seconds: 15));
    await widget.membership
        .markProtectedNameSupportCaseRead(caseId: widget.supportCase.id)
        .timeout(const Duration(seconds: 15));
    return messages;
  }

  void _reload() => setState(() => _messages = _load());

  Future<void> _send() async {
    final body = _message.text.trim();
    if (_sending || _uploading || body.length > 2000) return;
    if (body.isNotEmpty && body.length < 2) return;
    if (body.isEmpty && _stagedFiles.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.membership
          .sendProtectedNameSupportMessage(
            caseId: widget.supportCase.id,
            body: body,
            asSupport: widget.asSupport,
            idempotencyKey: _newUuid(),
            stagedFileIds: _stagedFiles.map((file) => file.id).toList(),
          )
          .timeout(const Duration(seconds: 15));
      _message.clear();
      _stagedFiles.clear();
      _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Meddelandet kunde inte skickas. Försök igen.'),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _mimeTypeFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'odt' => 'application/vnd.oasis.opendocument.text',
      'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
      _ => null,
    };
  }

  Future<void> _pickFiles() async {
    if (_uploading || _sending || _stagedFiles.length >= 5) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
        'txt',
        'csv',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
        'odt',
        'ods',
      ],
    );
    if (!mounted || result == null) return;
    final selected = result.files.take(5 - _stagedFiles.length).toList();
    if (selected.any((file) => file.size > 10 * 1024 * 1024)) {
      setState(
        () => _error = AppStrings.of(
          context,
        ).feature('En bilaga får vara högst 10 MB.'),
      );
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      for (final file in selected) {
        final bytes = file.bytes;
        final mimeType = _mimeTypeFor(file.name);
        if (bytes == null || mimeType == null) {
          throw const FormatException('Unsupported support attachment.');
        }
        final staged = await widget.membership
            .stageProtectedNameSupportFile(
              caseId: widget.supportCase.id,
              name: file.name,
              mimeType: mimeType,
              bytes: bytes,
            )
            .timeout(const Duration(seconds: 45));
        if (mounted) setState(() => _stagedFiles.add(staged));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Bilagan kunde inte laddas upp. Försök igen.'),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openAttachment(ProtectedNameSupportAttachment file) async {
    try {
      final url = await widget.membership
          .protectedNameSupportFileUrl(fileId: file.id)
          .timeout(const Duration(seconds: 15));
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Could not open support attachment.');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).safeError)),
        );
      }
    }
  }

  String _timestamp(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: const Duration(milliseconds: 150),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.supportCase.clubName,
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    '${widget.supportCase.teamName} · ${strings.domainValue(widget.supportCase.status)}',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ProtectedNameSupportMessage>>(
                future: _messages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: OutlinedButton(
                        onPressed: _reload,
                        child: Text(strings.retry),
                      ),
                    );
                  }
                  final messages = snapshot.data ?? const [];
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Align(
                        alignment: widget.asSupport
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Card(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    strings.feature(
                                      widget.asSupport
                                          ? 'Sökandens ursprungliga meddelande'
                                          : 'Ditt ursprungliga meddelande',
                                    ),
                                    style: theme.textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(widget.supportCase.message),
                                  const SizedBox(height: 6),
                                  Text(
                                    _timestamp(
                                      context,
                                      widget.supportCase.createdAt,
                                    ),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final message in messages) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment:
                              (widget.asSupport && message.isFromSupport) ||
                                  (!widget.asSupport && !message.isFromSupport)
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Card(
                              color:
                                  (widget.asSupport && message.isFromSupport) ||
                                      (!widget.asSupport &&
                                          !message.isFromSupport)
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.senderName,
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 4),
                                    if (message.body.isNotEmpty)
                                      SelectableText(message.body),
                                    for (final file in message.attachments)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: ActionChip(
                                          avatar: Icon(
                                            file.mimeType.startsWith('image/')
                                                ? Icons.image_outlined
                                                : Icons.attach_file,
                                            size: 18,
                                          ),
                                          label: Text(
                                            file.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          onPressed: () =>
                                              _openAttachment(file),
                                        ),
                                      ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _timestamp(context, message.createdAt),
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (_isOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_stagedFiles.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final file in _stagedFiles)
                            InputChip(
                              avatar: const Icon(Icons.attach_file, size: 18),
                              label: Text(file.name),
                              onDeleted: _sending || _uploading
                                  ? null
                                  : () => setState(
                                      () => _stagedFiles.remove(file),
                                    ),
                            ),
                        ],
                      ),
                    TextField(
                      controller: _message,
                      enabled: !_sending && !_uploading,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: strings.feature('Skriv ett svar'),
                        errorText: _error,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: strings.feature('Bifoga fil'),
                              onPressed:
                                  _sending ||
                                      _uploading ||
                                      _stagedFiles.length >= 5
                                  ? null
                                  : _pickFiles,
                              icon: _uploading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.attach_file),
                            ),
                            IconButton(
                              tooltip: strings.feature('Skicka svar'),
                              onPressed: _sending || _uploading ? null : _send,
                              icon: _sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_outlined),
                            ),
                          ],
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  strings.feature(
                    'Ärendet är avslutat och kan inte få fler meddelanden.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MyProtectedNameSupportCasesSheet extends StatefulWidget {
  const _MyProtectedNameSupportCasesSheet({required this.membership});

  final MembershipServices membership;

  @override
  State<_MyProtectedNameSupportCasesSheet> createState() =>
      _MyProtectedNameSupportCasesSheetState();
}

class _MyProtectedNameSupportCasesSheetState
    extends State<_MyProtectedNameSupportCasesSheet> {
  late Future<List<ProtectedNameSupportCase>> _cases = _load();

  Future<List<ProtectedNameSupportCase>> _load() => widget.membership
      .listMyProtectedNameSupportCases()
      .timeout(const Duration(seconds: 15));

  void _reload() => setState(() => _cases = _load());

  Future<void> _open(ProtectedNameSupportCase item) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProtectedNameSupportConversationSheet(
        membership: widget.membership,
        supportCase: item,
        asSupport: false,
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              strings.feature('Mina supportärenden'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<ProtectedNameSupportCase>>(
              future: _cases,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: OutlinedButton(
                      onPressed: _reload,
                      child: Text(strings.retry),
                    ),
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return Center(
                    child: Text(strings.feature('Du har inga supportärenden.')),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await _cases;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.support_agent_outlined),
                          title: Text(item.clubName),
                          subtitle: Text(
                            '${item.teamName} · ${strings.domainValue(item.status)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.unreadCount > 0)
                                Badge.count(count: item.unreadCount),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => _open(item),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Kept temporarily as a compatibility surface while older routes are phased
// out; the primary support UI now renders these cases in the unified queue.
// ignore: unused_element
class _GlobalPersonErasureAdminSheet extends StatefulWidget {
  const _GlobalPersonErasureAdminSheet({required this.membership});

  final MembershipServices membership;

  @override
  State<_GlobalPersonErasureAdminSheet> createState() =>
      _GlobalPersonErasureAdminSheetState();
}

class _GlobalPersonErasureAdminSheetState
    extends State<_GlobalPersonErasureAdminSheet> {
  late Future<List<GlobalPersonErasureCase>> _load = _reload();
  bool _pending = false;

  Future<List<GlobalPersonErasureCase>> _reload() => widget.membership
      .listGlobalPersonErasureCases()
      .timeout(const Duration(seconds: 15));

  Future<void> _decide(
    GlobalPersonErasureCase item, {
    required bool approve,
  }) async {
    final strings = AppStrings.of(context);
    var reason = '';
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          strings.feature(
            approve ? 'Godkänn global radering' : 'Avslå global radering',
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (approve) ...[
                Text(
                  strings.feature(
                    'Kontot tas bort från Auth och kan inte längre användas för inloggning. Neutral historik och audit bevaras.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: strings.feature('Beslutsanteckning'),
                ),
                onChanged: (value) => reason = value,
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? strings.feature('Ange minst 2 tecken.')
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(
              strings.feature(approve ? 'Godkänn och radera' : 'Avslå'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _pending = true);
    try {
      final state = await widget.membership.decideGlobalPersonErasure(
        requestId: item.id,
        approve: approve,
        reason: reason.trim(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Personradering')),
          content: Text(
            strings.feature(
              state == 'completed'
                  ? 'Kontot är raderat och ärendet är slutfört.'
                  : 'Ärendet är avslaget.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _load = _reload());
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Personradering')),
          content: Text(
            strings.feature(
              'Åtgärden kunde inte slutföras. Ärendet ligger kvar för säkert återförsök.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: Text(strings.feature('Globala personraderingar')),
            subtitle: Text(
              strings.feature(
                'Endast separata support-admins kan granska. Godkännande tar bort användarens inloggningskonto.',
              ),
            ),
            trailing: IconButton(
              tooltip: strings.feature('Stäng'),
              onPressed: _pending ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<GlobalPersonErasureCase>>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _load = _reload()),
                      child: Text(strings.retry),
                    ),
                  );
                }
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      strings.feature('Inga globala raderingsärenden.'),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _load = _reload());
                    await _load;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final actionable = item.state == 'requested';
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.requesterName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(strings.domainValue(item.state)),
                              const SizedBox(height: 8),
                              SelectableText(item.reason),
                              if (actionable) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: _pending
                                          ? null
                                          : () => _decide(item, approve: true),
                                      child: Text(
                                        strings.feature('Godkänn och radera'),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _pending
                                          ? null
                                          : () => _decide(item, approve: false),
                                      child: Text(strings.feature('Avslå')),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
