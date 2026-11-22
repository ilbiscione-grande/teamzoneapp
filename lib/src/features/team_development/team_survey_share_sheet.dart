part of '../../app/teamzone_app.dart';

/// Sends a survey link with WhatsApp, a text message, email or any app the
/// device's share sheet offers, or copies it. A personal link goes straight
/// to the player's phone or email when TeamZone has it.
class _SurveyShareSheet extends StatelessWidget {
  const _SurveyShareSheet({
    required this.title,
    required this.message,
    required this.url,
    required this.subject,
    this.phone,
    this.email,
    this.note,
  });
  final String title, message, url, subject;
  final String? phone, email, note;

  /// A player's personal link.
  static Future<void> personal(
    BuildContext context, {
    required TeamSurvey survey,
    required SurveyInvite invite,
  }) {
    final swedish = AppStrings.of(context).isSwedish;
    return _show(
      context,
      _SurveyShareSheet(
        title: swedish
            ? 'Skicka länken till ${invite.name}'
            : 'Send the link to ${invite.name}',
        message: surveyInviteMessage(
          name: invite.name,
          title: survey.title,
          url: invite.url,
          swedish: swedish,
        ),
        url: invite.url,
        subject: survey.title,
        phone: invite.phone,
        email: invite.email,
        note: invite.hasAccount
            ? (swedish
                  ? '${invite.name} har ett konto och får också en notis i appen när enkäten är öppen.'
                  : '${invite.name} has an account and is also notified in the app.')
            : null,
      ),
    );
  }

  /// The open link, which may go to a group chat.
  static Future<void> open(BuildContext context, TeamSurvey survey) {
    final swedish = AppStrings.of(context).isSwedish;
    final url = survey.openUrl!;
    return _show(
      context,
      _SurveyShareSheet(
        title: swedish ? 'Dela den öppna länken' : 'Share the open link',
        message: swedish
            ? 'Svara gärna på ledarnas enkät "${survey.title}". Skriv ditt namn först: $url'
            : 'Please answer your coaches\' survey "${survey.title}". Write your name first: $url',
        url: url,
        subject: survey.title,
        note: swedish
            ? 'Den öppna länken går bra att dela i lagets gruppchatt.'
            : 'The open link can go to the team\'s group chat.',
      ),
    );
  }

  static Future<void> _show(BuildContext context, Widget sheet) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => sheet,
      );

  Future<void> _launch(BuildContext context, Uri uri) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failed = _tdpText(
      context,
      'Appen kunde inte öppnas. Kopiera meddelandet i stället.',
      'The app could not be opened. Copy the message instead.',
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('not opened');
      navigator.pop();
    } catch (error) {
      AppErrors.caught('survey_share.launch', error);
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _copy(BuildContext context, String text, String done) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _shareMore(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (await shareText(message, subject: subject)) {
      navigator.pop();
    } else if (context.mounted) {
      await _copy(
        context,
        message,
        _tdpText(context, 'Meddelandet är kopierat.', 'Message copied.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasPhone = whatsAppNumber(phone) != null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(message),
              ),
            ),
            const SizedBox(height: 8),
            if (note != null) Text(note!, style: muted),
            ListTile(
              key: const Key('survey-share-whatsapp'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp'),
              subtitle: Text(
                hasPhone
                    ? phone!
                    : _tdpText(
                        context,
                        'Du väljer mottagare i WhatsApp',
                        'Choose the recipient in WhatsApp',
                      ),
              ),
              onTap: () =>
                  _launch(context, whatsAppUri(message, phone: phone)),
            ),
            ListTile(
              key: const Key('survey-share-sms'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sms_outlined),
              title: Text(_tdpText(context, 'Sms', 'Text message')),
              subtitle: Text(
                hasPhone
                    ? phone!
                    : _tdpText(
                        context,
                        'Inget nummer i TeamZone, du väljer mottagare',
                        'No number in TeamZone: choose the recipient',
                      ),
              ),
              onTap: () => _launch(context, smsUri(message, phone: phone)),
            ),
            ListTile(
              key: const Key('survey-share-email'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline),
              title: Text(_tdpText(context, 'E-post', 'Email')),
              subtitle: email == null
                  ? Text(
                      _tdpText(
                        context,
                        'Ingen e-post i TeamZone, du väljer mottagare',
                        'No email in TeamZone: choose the recipient',
                      ),
                    )
                  : Text(email!),
              onTap: () => _launch(
                context,
                emailUri(message, email: email, subject: subject),
              ),
            ),
            if (canShareText)
              ListTile(
                key: const Key('survey-share-more'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.ios_share),
                title: Text(_tdpText(context, 'Fler appar', 'More apps')),
                subtitle: Text(
                  _tdpText(
                    context,
                    'Messenger, Signal, Telegram och andra',
                    'Messenger, Signal, Telegram and others',
                  ),
                ),
                onTap: () => _shareMore(context),
              ),
            ListTile(
              key: const Key('survey-share-copy'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy),
              title: Text(
                _tdpText(context, 'Kopiera meddelandet', 'Copy the message'),
              ),
              onTap: () => _copy(
                context,
                message,
                _tdpText(context, 'Meddelandet är kopierat.', 'Message copied.'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text(
                _tdpText(context, 'Kopiera bara länken', 'Copy the link only'),
              ),
              onTap: () => _copy(
                context,
                url,
                _tdpText(context, 'Länken är kopierad.', 'Link copied.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
