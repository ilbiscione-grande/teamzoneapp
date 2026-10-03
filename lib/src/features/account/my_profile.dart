part of '../../app/teamzone_app.dart';

/// PROF-01: your own details (name, contact email, phone, picture) and the
/// support-approved change of login email. Contact details are shown only to
/// you and your teams' leaders; the picture to members of your clubs.

String _profileErrorMessage(
  AppStrings strings,
  Object error,
) => switch (error) {
  ProfileException(code: 'invalid_email') => strings.feature(
    'Kontrollera e-postadressen.',
  ),
  ProfileException(code: 'invalid_phone') => strings.feature(
    'Telefonnumret får bara innehålla siffror, mellanslag, bindestreck och +.',
  ),
  ProfileException(code: 'stale_revision') => strings.feature(
    'Profilen har ändrats någon annanstans. Öppna den igen.',
  ),
  ProfileException(code: 'request_open') => strings.feature(
    'Du har redan en begäran som inte är klar.',
  ),
  ProfileException(code: 'invalid_address') => strings.feature(
    'Kontrollera adressen och postnumret.',
  ),
  ProfileException(code: 'same_email') => strings.feature(
    'Det är redan din inloggningsadress.',
  ),
  ProfileException(code: 'use_privacy_settings') => strings.feature(
    'Ändra uppgifterna under Kontakt.',
  ),
  ProfileException(code: 'use_address_settings') => strings.feature(
    'Ändra adressen under Kontakt.',
  ),
  _ => strings.feature('Det gick inte att spara. Försök igen.'),
};

Future<bool> _openMyProfileEditor(
  BuildContext context,
  ProfileServices profile, {
  Widget? teamDetails,
  Widget? settings,
  VoidCallback? onProfileChanged,
}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _MyProfileEditor(
        profile: profile,
        teamDetails: teamDetails,
        settings: settings,
        onProfileChanged: onProfileChanged,
      ),
    ) ??
    false;

/// Round picture with initials as fallback.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    super.key,
    required this.name,
    this.url,
    this.bytes,
    this.radius = 20,
  });
  final String name;
  final String? url;
  final Uint8List? bytes;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? image = bytes != null
        ? MemoryImage(bytes!)
        : url != null
        ? NetworkImage(url!)
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      child: image == null
          ? Text(
              _initialsOf(name.isEmpty ? '?' : name),
              style: TextStyle(fontSize: radius * .7),
            )
          : null,
    );
  }
}

class _MyProfileEditor extends StatefulWidget {
  const _MyProfileEditor({
    required this.profile,
    this.teamDetails,
    this.settings,
    this.onProfileChanged,
  });
  final ProfileServices profile;
  final Widget? teamDetails;
  final Widget? settings;
  final VoidCallback? onProfileChanged;
  @override
  State<_MyProfileEditor> createState() => _MyProfileEditorState();
}

class _MyProfileEditorState extends State<_MyProfileEditor>
    with SingleTickerProviderStateMixin {
  late Future<MyProfileDetails> _load = _reload();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _postal = TextEditingController();
  final _city = TextEditingController();
  String? _avatarUrl;
  Uint8List? _pickedBytes;
  String? _pickedMime;
  bool _removeAvatar = false;
  bool _busy = false;
  String? _error;
  MyProfileDetails? _details;
  // Kept for a retry of the same save.
  String? _saveKey;
  Object? _saveInput;
  String? _stagedAvatarId;
  Uint8List? _stagedAvatarBytes;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs =
        TabController(
          length:
              2 +
              (widget.teamDetails == null ? 0 : 1) +
              (widget.settings == null ? 0 : 1),
          vsync: this,
        )..addListener(() {
          if (!_tabs.indexIsChanging && mounted) setState(() {});
        });
  }

  Future<MyProfileDetails> _reload() async {
    // An approved change is finished once the login email has changed.
    try {
      await widget.profile.completeLoginEmailChange();
    } catch (_) {}
    final details = await widget.profile.getMyProfile().timeout(
      const Duration(seconds: 15),
    );
    String? url;
    if (details.hasAvatar) {
      try {
        url = await widget.profile.avatarUrl(details.profileId);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _details = details;
        _avatarUrl = url;
        _name.text = details.displayName;
        _email.text = details.contactEmail ?? '';
        _phone.text = details.phone ?? '';
        _street.text = details.streetAddress ?? '';
        _postal.text = details.postalCode ?? '';
        _city.text = details.city ?? '';
      });
    }
    return details;
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _street.dispose();
    _postal.dispose();
    _city.dispose();
    super.dispose();
  }

  String? _text(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  /// Phones and mobile browsers can take the picture with the camera.
  static bool get _cameraAvailable =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _pickAvatar() async {
    final strings = AppStrings.of(context);
    var useCamera = false;
    if (_cameraAvailable) {
      final source = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('avatar-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(strings.feature('Ta ett foto')),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              ListTile(
                key: const ValueKey('avatar-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(strings.feature('Välj från bilder')),
                onTap: () => Navigator.pop(sheetContext, false),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      useCamera = source;
    }
    if (useCamera) {
      final XFile? photo;
      try {
        photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
      } catch (_) {
        if (mounted) {
          setState(
            () => _error = strings.feature('Kameran kunde inte öppnas.'),
          );
        }
        return;
      }
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      _useAvatar(bytes, 'jpg');
      return;
    }
    final XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 82,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = strings.feature('Bilden kunde inte öppnas.'));
      }
      return;
    }
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    _useAvatar(
      bytes,
      image.mimeType?.split('/').last ?? image.name.split('.').last,
    );
  }

  void _useAvatar(Uint8List bytes, String? fileExtension) {
    if (bytes.length > 2097152) {
      setState(
        () => _error = AppStrings.of(context).feature(
          'Bilden kunde inte komprimeras till rätt storlek. Välj en annan bild.',
        ),
      );
      return;
    }
    final extension = (fileExtension ?? '').toLowerCase();
    setState(() {
      _pickedBytes = bytes;
      _pickedMime = extension == 'png'
          ? 'image/png'
          : extension == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      _removeAvatar = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    final details = _details;
    if (details == null || _busy) return;
    final strings = AppStrings.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = strings.feature('Ange ditt namn.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final input = (
        _name.text.trim(),
        _text(_email),
        _text(_phone),
        _text(_street),
        _text(_postal),
        _text(_city),
        _pickedBytes,
        _removeAvatar,
      );
      if (_saveInput != input) {
        _saveInput = input;
        _saveKey = _newUuid();
      }
      if (_pickedBytes != null &&
          (_stagedAvatarId == null ||
              !identical(_stagedAvatarBytes, _pickedBytes))) {
        _stagedAvatarId = await widget.profile.uploadAvatar(
          mimeType: _pickedMime!,
          bytes: _pickedBytes!,
          idempotencyKey: _newUuid(),
        );
      }
      if (_pickedBytes != null) _stagedAvatarBytes = _pickedBytes;
      final stagedId = _pickedBytes == null ? null : _stagedAvatarId;
      await widget.profile.updateMyProfile(
        displayName: _name.text.trim(),
        contactEmail: _email.text.trim().isEmpty ? null : _email.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        street: _text(_street),
        postalCode: _text(_postal),
        city: _text(_city),
        avatarAction: stagedId != null
            ? 'replace'
            : _removeAvatar
            ? 'remove'
            : 'keep',
        stagedAvatarId: stagedId,
        expectedRevision: details.revision,
        idempotencyKey: _saveKey!,
      );
      widget.onProfileChanged?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _profileErrorMessage(strings, error);
        });
      }
    }
  }

  Future<void> _requestEmailChange() async {
    final strings = AppStrings.of(context);
    final request = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _LoginEmailRequestDialog(),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.profile.requestLoginEmailChange(
        newEmail: request.$1,
        reason: request.$2,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.feature(
              'Begäran är skickad. Supporten återkommer innan något ändras.',
            ),
          ),
        ),
      );
      setState(() {
        _load = _reload();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _profileErrorMessage(strings, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelEmailChange(LoginEmailChange change) async {
    setState(() => _busy = true);
    try {
      await widget.profile.cancelLoginEmailChange(change.id);
      if (mounted) {
        setState(() {
          _load = _reload();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _profileErrorMessage(AppStrings.of(context), error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEmailChange(LoginEmailChange change) async {
    final strings = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      await widget.profile.confirmLoginEmailChange(change.requestedEmail);
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.feature('Kolla din e-post')),
          content: Text(
            strings
                .feature(
                  'Vi har skickat en bekräftelselänk till {email}. Bytet gäller när du har bekräftat.',
                )
                .replaceFirst('{email}', change.requestedEmail),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.feature('Stäng')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = strings.feature(
            'Bekräftelsen kunde inte skickas. Försök igen om en stund.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _loginSection(AppStrings strings, MyProfileDetails details) {
    final change = details.emailChange;
    final theme = Theme.of(context);
    final status = switch (change?.state) {
      'pending' =>
        strings
            .feature('Väntar på support: byte till {email}.')
            .replaceFirst('{email}', change!.requestedEmail),
      'approved' =>
        strings
            .feature('Godkänt: bekräfta bytet till {email}.')
            .replaceFirst('{email}', change!.requestedEmail),
      'rejected' => [
        strings.feature('Den senaste begäran avslogs.'),
        if (change!.decisionNote != null) change.decisionNote!,
      ].join(' '),
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: Text(strings.feature('Inloggningsadress')),
          subtitle: Text(details.loginEmail ?? '–'),
        ),
        if (status != null)
          Container(
            key: const ValueKey('login-email-status'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(status),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (change?.state == 'approved')
              FilledButton.icon(
                key: const ValueKey('confirm-login-email'),
                onPressed: _busy ? null : () => _confirmEmailChange(change!),
                icon: const Icon(Icons.mark_email_read_outlined),
                label: Text(strings.feature('Bekräfta bytet')),
              ),
            if (change?.isOpen == true)
              TextButton(
                onPressed: _busy ? null : () => _cancelEmailChange(change!),
                child: Text(strings.feature('Avbryt begäran')),
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('request-login-email'),
                onPressed: _busy ? null : _requestEmailChange,
                icon: const Icon(Icons.support_agent_outlined),
                label: Text(strings.feature('Begär byte av inloggningsadress')),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          strings.feature(
            'Av säkerhetsskäl granskar supporten varje byte. Därefter bekräftar du via en länk i e-posten.',
          ),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final fullScreen = MediaQuery.sizeOf(context).width < 600;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: strings.feature('Stäng'),
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              strings.feature('Redigera profil'),
              style: theme.textTheme.titleLarge,
            ),
          ),
          if (_tabs.index < 2)
            FilledButton(
              key: const ValueKey('save-my-profile'),
              onPressed: _busy || _details == null || _details!.protected
                  ? null
                  : _save,
              child: Text(strings.feature('Spara')),
            ),
        ],
      ),
    );
    final body = FutureBuilder<MyProfileDetails>(
      future: _load,
      builder: (context, snapshot) {
        final details = _details;
        if (details == null) {
          return snapshot.hasError
              ? _StateCard(
                  icon: Icons.sync_problem,
                  title: strings.feature('Profilen kunde inte laddas'),
                  message: strings.feature('Försök igen om en stund.'),
                )
              : AppLoadingIndicator(label: strings.loading);
        }
        final hasPicture =
            _pickedBytes != null || (_avatarUrl != null && !_removeAvatar);
        if (details.protected) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(strings.feature('Ändra uppgifterna under Kontakt.')),
              _loginSection(strings, details),
            ],
          );
        }
        final profile = ListView(
          key: const ValueKey('edit-profile-tab'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: _ProfileAvatar(
                name: _name.text,
                url: _removeAvatar ? null : _avatarUrl,
                bytes: _pickedBytes,
                radius: 44,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('pick-avatar'),
                  onPressed: _busy ? null : _pickAvatar,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    strings.feature(hasPicture ? 'Byt bild' : 'Lägg till bild'),
                  ),
                ),
                if (hasPicture)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _pickedBytes = null;
                            _pickedMime = null;
                            _removeAvatar = true;
                          }),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(strings.feature('Ta bort bild')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('my-profile-name'),
              controller: _name,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: strings.feature('Namn'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        );
        final contact = ListView(
          key: const ValueKey('edit-contact-tab'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            TextField(
              key: const ValueKey('my-profile-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: strings.feature('Kontakt-e-post'),
                prefixIcon: const Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('my-profile-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: strings.feature('Telefon'),
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: const ValueKey('edit-profile-addresses'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.home_outlined),
              title: Text(strings.feature('Adresser')),
              subtitle: Text(
                strings.feature(
                  'Hantera adresser och välj kontaktadress per klubb.',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                useRootNavigator: true,
                builder: (_) => _AddressPrivacySettings(
                  profile: widget.profile,
                  onChanged: widget.onProfileChanged,
                ),
              ),
            ),
            _ContactChangeRequests(
              profile: widget.profile,
              onChanged: widget.onProfileChanged,
            ),
            const SizedBox(height: 8),
            Text(
              strings.feature(
                'Kontaktuppgifterna visas bara för dig och ledarna i dina lag. Profilbilden syns för alla i dina klubbar.',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 32),
            _loginSection(strings, details),
          ],
        );
        return TabBarView(
          controller: _tabs,
          children: [
            profile,
            contact,
            if (widget.teamDetails != null) widget.teamDetails!,
            if (widget.settings != null) widget.settings!,
          ],
        );
      },
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const Divider(height: 1),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: strings.feature('Profil')),
            Tab(text: strings.feature('Kontakt')),
            if (widget.teamDetails != null)
              Tab(text: strings.feature('Roll/titel')),
            if (widget.settings != null)
              Tab(text: strings.feature('Inställningar')),
          ],
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Container(
            key: const ValueKey('profile-edit-error'),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: theme.colorScheme.errorContainer,
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        Expanded(child: body),
      ],
    );
    return fullScreen
        ? Dialog.fullscreen(child: SafeArea(child: content))
        : Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 720,
                maxHeight: MediaQuery.sizeOf(context).height * .9,
              ),
              child: content,
            ),
          );
  }
}

class _LoginEmailRequestDialog extends StatefulWidget {
  const _LoginEmailRequestDialog();
  @override
  State<_LoginEmailRequestDialog> createState() =>
      _LoginEmailRequestDialogState();
}

class _LoginEmailRequestDialogState extends State<_LoginEmailRequestDialog> {
  final _email = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final strings = AppStrings.of(context);
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = strings.feature('Kontrollera e-postadressen.'));
      return;
    }
    if (_reason.text.trim().length < 5) {
      setState(
        () => _error = strings.feature('Beskriv varför med minst 5 tecken.'),
      );
      return;
    }
    Navigator.pop(context, (email, _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Byt inloggningsadress')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.feature(
                'Supporten granskar begäran. När den är godkänd bekräftar du bytet via en länk som skickas till den nya adressen.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('login-email-new'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: strings.feature('Ny inloggningsadress'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('login-email-reason'),
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: strings.feature('Varför vill du byta?'),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.feature('Avbryt')),
        ),
        FilledButton(
          key: const ValueKey('send-login-email-request'),
          onPressed: _submit,
          child: Text(strings.feature('Skicka till support')),
        ),
      ],
    );
  }
}
