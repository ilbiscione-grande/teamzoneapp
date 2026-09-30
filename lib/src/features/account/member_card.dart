part of '../../app/teamzone_app.dart';

/// PROF-04: the virtual member card, shaped like an ID card. Full screen on
/// phones, a dialog on wider screens. The back holds address and contact
/// details, shown only to the person and the team's leaders.

Future<void> _openMemberCard(
  BuildContext context, {
  required ProfileServices profile,
  required String clubId,
  required String teamId,
  required String personId,
}) => showDialog<void>(
  context: context,
  useRootNavigator: true,
  barrierColor: Colors.black87,
  builder: (_) => _MemberCardDialog(
    profile: profile,
    clubId: clubId,
    teamId: teamId,
    personId: personId,
  ),
);

String _cardRoleLabel(AppStrings strings, String role) => switch (role) {
  'leader' => strings.feature('Ledare'),
  'club_functionary' => strings.feature('Klubbfunktionär'),
  'guardian' => strings.feature('Vårdnadshavare'),
  _ => strings.feature('Spelare'),
};

class _MemberCardData {
  const _MemberCardData(this.card, this.photo, this.badge);
  final MemberCard card;
  final String? photo, badge;
}

class _MemberCardDialog extends StatefulWidget {
  const _MemberCardDialog({
    required this.profile,
    required this.clubId,
    required this.teamId,
    required this.personId,
  });
  final ProfileServices profile;
  final String clubId, teamId, personId;

  @override
  State<_MemberCardDialog> createState() => _MemberCardDialogState();
}

class _MemberCardDialogState extends State<_MemberCardDialog>
    with SingleTickerProviderStateMixin {
  late final Future<_MemberCardData> _load = _reload();
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  Future<_MemberCardData> _reload() async {
    final card = await widget.profile
        .getMemberCard(
          clubId: widget.clubId,
          teamId: widget.teamId,
          personId: widget.personId,
        )
        .timeout(const Duration(seconds: 15));
    String? photo;
    String? badge;
    final photoProfile = card.contact.avatarProfileId;
    if (photoProfile != null) {
      try {
        photo = await widget.profile.avatarUrl(photoProfile);
      } catch (_) {}
    }
    if (card.hasBadge) {
      try {
        badge = await widget.profile.clubBadgeUrl(card.clubId);
      } catch (_) {}
    }
    return _MemberCardData(card, photo, badge);
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _turn() =>
      _flip.status == AnimationStatus.completed ||
          _flip.status == AnimationStatus.forward
      ? _flip.reverse()
      : _flip.forward();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final fullScreen = MediaQuery.sizeOf(context).width < 600;
    final body = FutureBuilder<_MemberCardData>(
      future: _load,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return Center(
            child: snapshot.hasError
                ? Text(
                    strings.feature('Medlemskortet kunde inte laddas.'),
                    style: const TextStyle(color: Colors.white),
                  )
                : const CircularProgressIndicator(),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GestureDetector(
                onTap: _turn,
                child: AnimatedBuilder(
                  animation: _flip,
                  builder: (context, _) {
                    final angle = _flip.value * pi;
                    final showBack = angle > pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(angle),
                      child: showBack
                          ? Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(pi),
                              child: _MemberCardBack(data: data),
                            )
                          : _MemberCardFront(data: data),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _flip,
              builder: (context, _) => FilledButton.tonalIcon(
                key: const ValueKey('member-card-flip'),
                onPressed: _turn,
                icon: const Icon(Icons.flip_outlined),
                label: Text(
                  strings.feature(
                    _flip.value > .5 ? 'Visa framsidan' : 'Visa baksidan',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    final content = Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
            child: body,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            key: const ValueKey('member-card-close'),
            tooltip: strings.feature('Stäng'),
            color: Colors.white,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
    return fullScreen
        ? Dialog.fullscreen(
            backgroundColor: const Color(0xFF101418),
            child: SafeArea(child: content),
          )
        : Dialog(
            backgroundColor: const Color(0xFF101418),
            insetPadding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: content,
            ),
          );
  }
}

/// Card surface in the ID-1 shape (85.6 × 54 mm), laid out at a fixed size
/// and scaled to the available width.
class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child, this.back = false});
  final Widget child;
  final bool back;

  static const width = 428.0;
  static const height = 270.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: width / height,
      child: FittedBox(
        child: Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: back
                  ? [const Color(0xFF263238), const Color(0xFF101418)]
                  : [
                      colors.primary,
                      Color.lerp(colors.primary, Colors.black, .55)!,
                    ],
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ClubBadge extends StatelessWidget {
  const _ClubBadge({required this.name, this.url, this.size = 44});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(size * .22),
    ),
    clipBehavior: Clip.antiAlias,
    padding: EdgeInsets.all(url == null ? 0 : size * .08),
    child: url != null
        ? Image.network(
            url!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _initials(context),
          )
        : _initials(context),
  );

  Widget _initials(BuildContext context) => Center(
    child: Text(
      _initialsOf(name.isEmpty ? '?' : name),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
        fontSize: size * .38,
      ),
    ),
  );
}

class _CardField extends StatelessWidget {
  const _CardField(this.label, this.value, {this.large = false});
  final String label, value;
  final bool large;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            letterSpacing: 1.1,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          maxLines: large ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: large ? 20 : 13,
            fontWeight: large ? FontWeight.w800 : FontWeight.w600,
            height: 1.15,
          ),
        ),
      ],
    ),
  );
}

class _MemberCardFront extends StatelessWidget {
  const _MemberCardFront({required this.data});
  final _MemberCardData data;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final card = data.card;
    final localizations = MaterialLocalizations.of(context);
    final titles = [
      ...card.titles.map((key) => _titleLabel(strings, key)),
      ...card.customTitles,
    ];
    final roles = [
      ...card.roles.map((role) => _cardRoleLabel(strings, role)),
      ...titles,
    ].join(' · ');
    return _CardSurface(
      child: Stack(
        children: [
          // Faded watermark.
          Positioned(
            right: -30,
            bottom: -40,
            child: Icon(
              Icons.shield,
              size: 220,
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _ClubBadge(name: card.clubName, url: data.badge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        card.clubName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      strings.feature('MEDLEMSKORT'),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: const ValueKey('member-card-photo'),
                        width: 104,
                        height: 136,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white54, width: 2),
                          image: data.photo == null
                              ? null
                              : DecorationImage(
                                  image: NetworkImage(data.photo!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: data.photo == null
                            ? Center(
                                child: Text(
                                  _initialsOf(
                                    card.name.isEmpty ? '?' : card.name,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CardField(
                              strings.feature('Namn'),
                              card.name,
                              large: true,
                            ),
                            _CardField(strings.feature('Lag'), card.teamName),
                            if (roles.isNotEmpty)
                              _CardField(strings.feature('Roll'), roles),
                            if (card.guardianOf.isNotEmpty)
                              _CardField(
                                strings.feature('Vårdnadshavare till'),
                                card.guardianOf.join(', '),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _CardField(
                        strings.feature('Medlems-ID'),
                        card.memberNumber,
                      ),
                    ),
                    if (card.birthYear != null)
                      Expanded(
                        child: _CardField(
                          strings.feature('Född'),
                          '${card.birthYear}',
                        ),
                      ),
                    if (card.memberSince != null)
                      Expanded(
                        child: _CardField(
                          strings.feature('Medlem sedan'),
                          localizations.formatShortDate(
                            card.memberSince!.toLocal(),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberCardBack extends StatelessWidget {
  const _MemberCardBack({required this.data});
  final _MemberCardData data;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final card = data.card;
    final contact = card.contact;
    final postal = [
      contact.postalCode,
      contact.city,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
    return _CardSurface(
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stripe, like the back of a card.
          Container(
            height: 34,
            margin: const EdgeInsets.only(top: 18),
            color: Colors.black87,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: !contact.canSeeContact
                  ? Row(
                      key: const ValueKey('member-card-back-locked'),
                      children: [
                        const Icon(Icons.lock_outline, color: Colors.white70),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            strings.feature(
                              'Adress och kontaktuppgifter visas bara för personen och lagets ledare.',
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('member-card-back'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CardField(
                          strings.feature('Adress'),
                          contact.hasAddress
                              ? [contact.streetAddress, postal]
                                    .whereType<String>()
                                    .where((p) => p.isNotEmpty)
                                    .join('\n')
                              : strings.feature('Ingen adress angiven'),
                          large: false,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _CardField(
                                strings.feature('E-post'),
                                contact.contactEmail ?? '–',
                              ),
                            ),
                            Expanded(
                              child: _CardField(
                                strings.feature('Telefon'),
                                contact.phone ?? '–',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                _ClubBadge(name: card.clubName, url: data.badge, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${card.clubName} · ${card.memberNumber}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ),
                const Text(
                  'TeamZone',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Club administrators set the club badge from the team's manage menu.
class _ClubBadgeDialog extends StatefulWidget {
  const _ClubBadgeDialog({
    required this.profile,
    required this.clubId,
    required this.clubName,
  });
  final ProfileServices profile;
  final String clubId, clubName;
  @override
  State<_ClubBadgeDialog> createState() => _ClubBadgeDialogState();
}

class _ClubBadgeDialogState extends State<_ClubBadgeDialog> {
  late Future<String?> _current = widget.profile.clubBadgeUrl(widget.clubId);
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    final strings = AppStrings.of(context);
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    final file = pick?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    if (bytes.length > 1048576) {
      setState(
        () => _error = strings.feature('Klubbmärket får vara högst 1 MB.'),
      );
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.profile.setClubBadge(
        clubId: widget.clubId,
        mimeType: extension == 'png'
            ? 'image/png'
            : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg',
        bytes: bytes,
      );
      if (mounted) {
        setState(() {
          _current = widget.profile.clubBadgeUrl(widget.clubId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = strings.feature('Klubbmärket kunde inte sparas.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await widget.profile.removeClubBadge(widget.clubId);
      if (mounted) {
        setState(() {
          _current = Future.value(null);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppStrings.of(
            context,
          ).feature('Klubbmärket kunde inte tas bort.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.feature('Klubbmärke')),
      content: FutureBuilder<String?>(
        future: _current,
        builder: (context, snapshot) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ClubBadge(name: widget.clubName, url: snapshot.data, size: 96),
            const SizedBox(height: 12),
            Text(
              strings.feature(
                'Visas på medlemskorten för alla i klubben. PNG, JPG eller WebP, högst 1 MB.',
              ),
              textAlign: TextAlign.center,
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _remove,
          child: Text(strings.feature('Ta bort')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.upload_outlined),
          label: Text(strings.feature('Välj bild')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.feature('Stäng')),
        ),
      ],
    );
  }
}
