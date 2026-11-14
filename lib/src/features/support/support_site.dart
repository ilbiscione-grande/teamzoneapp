part of '../../app/teamzone_app.dart';

/// The support site's address. The page is split from the app (decided
/// 2026-11-14) so support is done from an account of its own.
const supportSiteUrl = 'https://support.teamzoneapp.se';

/// Whether this web page is the support site: support.teamzoneapp.se, or
/// its Firebase address before the domain is connected.
bool isSupportSiteHost(String host) =>
    host.startsWith('support.') || host.startsWith('teamzoneapp-support.');

/// After sign-in on the support site: the support page for support
/// administrators, nothing of clubs and teams. Other accounts are told the
/// site is not for them and can sign out.
class _SupportSiteShell extends StatefulWidget {
  const _SupportSiteShell({required this.services, required this.onSignOut});
  final AppServices services;
  final Future<void> Function() onSignOut;

  @override
  State<_SupportSiteShell> createState() => _SupportSiteShellState();
}

class _SupportSiteShellState extends State<_SupportSiteShell> {
  late Future<bool> _access = widget.services.membership
      .isSupportAdmin()
      .timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    return FutureBuilder<bool>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          AppErrors.caught('support_site.access', snapshot.error!);
          return _SupportSiteMessage(
            title: strings.notSupportTitle,
            body: strings.adminsFailed,
            actions: [
              OutlinedButton(
                onPressed: () => setState(
                  () => _access = widget.services.membership.isSupportAdmin(),
                ),
                child: Text(strings.retry),
              ),
              FilledButton(
                onPressed: widget.onSignOut,
                child: Text(strings.signOut),
              ),
            ],
          );
        }
        if (snapshot.data != true) {
          return _SupportSiteMessage(
            key: const ValueKey('support-site-not-support'),
            title: strings.notSupportTitle,
            body: strings.notSupportBody,
            actions: [
              FilledButton(
                key: const ValueKey('support-site-sign-out'),
                onPressed: widget.onSignOut,
                child: Text(strings.signOut),
              ),
            ],
          );
        }
        final services = widget.services;
        return _SupportAdminSurface(
          membership: services.membership,
          profile: services.profile,
          messaging: services.messaging,
          assistant: services.overview is AssistantTaskSupportServices
              ? services.overview as AssistantTaskSupportServices
              : null,
          onSignOut: widget.onSignOut,
        );
      },
    );
  }
}

class _SupportSiteMessage extends StatelessWidget {
  const _SupportSiteMessage({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
  });
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.support_agent, size: 48),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
        ),
      ),
    ),
  );
}

/// In the app: support has moved to its own site. Shown on /support and
/// opened from the Supportkö card.
class _SupportMovedSurface extends StatelessWidget {
  const _SupportMovedSurface();

  @override
  Widget build(BuildContext context) {
    final strings = SupportStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.siteTitle)),
      body: _SupportSiteMessage(
        key: const ValueKey('support-moved'),
        title: strings.movedTitle,
        body: strings.movedBody,
        actions: [
          FilledButton.icon(
            key: const ValueKey('support-moved-open'),
            onPressed: () => openSupportSite(),
            icon: const Icon(Icons.open_in_new),
            label: Text(strings.openSupport),
          ),
        ],
      ),
    );
  }
}

Future<void> openSupportSite() async {
  try {
    await launchUrl(
      Uri.parse(supportSiteUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (error) {
    AppErrors.caught('support_site.open', error);
  }
}
