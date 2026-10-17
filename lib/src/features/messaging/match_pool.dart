import 'dart:math';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';
import 'package:url_launcher/url_launcher.dart';

/// POOL-01: the match pool's conversations in the app. Listings are found
/// and posted on teamzoneapp.se; the leaders of the two teams talk, book and
/// decline here as well. Every conversation shows whether the other club is
/// officially verified.

const _publicSiteOrigin = String.fromEnvironment(
  'PUBLIC_SITE_URL',
  defaultValue: 'https://teamzoneapp.se',
);

/// Opens the match pool on the web, signed in as the same account when a
/// one-time code can be had (otherwise the page asks to sign in).
Future<void> openMatchPoolOnWeb(MessagingServices services) async {
  var url = '$_publicSiteOrigin/matchpool';
  try {
    final code = await services.createWebHandoff().timeout(
      const Duration(seconds: 10),
    );
    url = '$url#handoff=$code';
  } catch (error) {
    AppErrors.caught('match_pool.openMatchPoolOnWeb', error);
  }
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

const _stateLabels = {
  'pending': 'Väntar på svar',
  'accepted': 'Bokad',
  'declined': 'Nej tack',
  'withdrawn': 'Återkallad',
  'closed': 'Avslutad',
};

String _formatLabel(String format) => format.replaceFirst('v', ' mot ');

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final colors = verified
        ? (const Color(0xFFE2F5E9), const Color(0xFF10592F))
        : (const Color(0xFFFFF4D6), const Color(0xFF7A4F00));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        verified ? '✓ Officiellt verifierad klubb' : '! Ej verifierad klubb',
        style: TextStyle(
          color: colors.$2,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _when(
  BuildContext context,
  MatchPoolListing listing, {
  DateTime? proposedStart,
  DateTime? proposedEnd,
}) {
  final material = MaterialLocalizations.of(context);
  String slot(DateTime start, DateTime end) =>
      '${material.formatMediumDate(start.toLocal())} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(start.toLocal()))}–'
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(end.toLocal()))}';
  if (listing.homeSlot && listing.startsAt != null && listing.endsAt != null) {
    return slot(listing.startsAt!, listing.endsAt!);
  }
  if (proposedStart != null && proposedEnd != null) {
    return slot(proposedStart, proposedEnd);
  }
  if (listing.dateFrom != null && listing.dateTo != null) {
    return '${material.formatShortMonthDay(listing.dateFrom!)} – '
        '${material.formatShortMonthDay(listing.dateTo!)}';
  }
  return '';
}

class MatchPoolPage extends StatefulWidget {
  const MatchPoolPage({super.key, required this.services});
  final MessagingServices services;

  @override
  State<MatchPoolPage> createState() => _MatchPoolPageState();
}

class _MatchPoolPageState extends State<MatchPoolPage> {
  late Future<List<MatchPoolConversationSummary>> _items = widget.services
      .listMatchPoolConversations();

  void _reload() {
    final next = widget.services.listMatchPoolConversations();
    setState(() {
      _items = next;
    });
  }

  Future<void> _open(MatchPoolConversationSummary item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MatchPoolConversationPage(
          services: widget.services,
          interestId: item.id,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matchpoolen'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Uppdatera',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<MatchPoolConversationSummary>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Konversationerna kunde inte hämtas.'),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Försök igen'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Card(
                key: const ValueKey('match-pool-web'),
                child: ListTile(
                  leading: const Icon(Icons.travel_explore),
                  title: const Text('Hitta matcher och lägg in annonser'),
                  subtitle: const Text(
                    'Öppnas på teamzoneapp.se, inloggad med samma konto.',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openMatchPoolOnWeb(widget.services),
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Inga konversationer än. När ett lag visar intresse för er annons, eller ni för deras, dyker konversationen upp här.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final item in items)
                Card(
                  key: ValueKey('match-pool-${item.id}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open(item),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.otherTeamName} · ${item.otherClubName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: item.unread
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (item.unread)
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(left: 8),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _VerifiedBadge(verified: item.otherVerified),
                              Chip(
                                label: Text(
                                  _stateLabels[item.state] ?? item.state,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.fromListingSide ? 'Er annons' : 'Deras annons'}: '
                            '${item.listing.homeSlot ? 'har hemmatid' : 'söker bortamatch'} · '
                            '${item.listing.ageClass} · ${_formatLabel(item.listing.matchFormat)} · '
                            '${_when(context, item.listing)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (item.lastMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                item.lastMessage!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (item.lastActivityAt != null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                material.formatShortDate(
                                  item.lastActivityAt!.toLocal(),
                                ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class MatchPoolConversationPage extends StatefulWidget {
  const MatchPoolConversationPage({
    super.key,
    required this.services,
    required this.interestId,
  });
  final MessagingServices services;
  final String interestId;

  @override
  State<MatchPoolConversationPage> createState() =>
      _MatchPoolConversationPageState();
}

class _MatchPoolConversationPageState extends State<MatchPoolConversationPage> {
  late Future<MatchPoolConversation> _conversation = widget.services
      .getMatchPoolConversation(widget.interestId);
  final _reply = TextEditingController();
  String? _replyKey;
  bool _busy = false;
  bool _addToCalendar = true;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _reload() {
    final next = widget.services.getMatchPoolConversation(widget.interestId);
    setState(() {
      _conversation = next;
    });
  }

  Future<void> _run(
    String where,
    Future<void> Function() action, {
    String? done,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
      if (mounted) _reload();
    } catch (error) {
      AppErrors.caught('match_pool.$where', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Det gick inte att spara. Försök igen.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    _replyKey ??= _newKey();
    await _run('send', () async {
      await widget.services.sendMatchPoolMessage(
        interestId: widget.interestId,
        body: body,
        idempotencyKey: _replyKey!,
      );
      _reply.clear();
      _replyKey = null;
    });
  }

  Future<bool> _confirm(String question, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<MatchPoolConversation>(
      future: _conversation,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              data == null
                  ? 'Matchpoolen'
                  : '${data.otherTeamName} · ${data.otherClubName}',
            ),
          ),
          body: snapshot.hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Konversationen kunde inte hämtas.'),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Försök igen'),
                      ),
                    ],
                  ),
                )
              : data == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _summary(context, data),
                          const SizedBox(height: 16),
                          for (final message in data.messages)
                            _message(context, data, message, material, colors),
                          if (data.fromListingSide &&
                              data.state == 'pending' &&
                              data.listing.current)
                            _decide(data),
                          if (!data.fromListingSide && data.state == 'pending')
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const ValueKey('match-pool-withdraw'),
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        if (await _confirm(
                                          'Återkalla ert intresse?',
                                          'Återkalla',
                                        )) {
                                          await _run(
                                            'withdraw',
                                            () => widget.services
                                                .withdrawMatchPoolInterest(
                                                  widget.interestId,
                                                ),
                                          );
                                        }
                                      },
                                child: const Text('Återkalla intresset'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (data.state == 'pending' || data.state == 'accepted')
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('match-pool-reply'),
                                  controller: _reply,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: 2000,
                                  enabled: !_busy,
                                  decoration: InputDecoration(
                                    labelText:
                                        'Skriv till ${data.otherTeamName}',
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                key: const ValueKey('match-pool-send'),
                                onPressed: _busy ? null : _send,
                                tooltip: 'Skicka',
                                icon: const Icon(Icons.send),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _summary(BuildContext context, MatchPoolConversation data) {
    final listing = data.listing;
    final venue = listing.homeSlot ? listing.venueName : data.proposedVenue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _VerifiedBadge(verified: data.otherVerified),
                Chip(
                  label: Text(_stateLabels[data.state] ?? data.state),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (!data.otherVerified)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Klubben är inte verifierad av TeamZone. Stäm gärna av med klubben innan ni bokar.',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${listing.teamName} ${listing.homeSlot ? 'har hemmatid' : 'söker bortamatch'} · '
              '${listing.ageClass} · ${_formatLabel(listing.matchFormat)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              [
                _when(
                  context,
                  listing,
                  proposedStart: data.proposedStartsAt,
                  proposedEnd: data.proposedEndsAt,
                ),
                ?venue,
                listing.placeLabel,
              ].where((part) => part.isNotEmpty).join(' · '),
            ),
            if (data.state == 'accepted')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  data.myEventId != null
                      ? 'Matchen är bokad och ligger som utkast i er kalender – publicera den när ni är redo.'
                      : 'Matchen är bokad. Den är inte inlagd i er kalender.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(
    BuildContext context,
    MatchPoolConversation data,
    MatchPoolMessage message,
    MaterialLocalizations material,
    ColorScheme colors,
  ) {
    if (message.side == 'system') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    final mine = message.side == data.mySide;
    final team = message.side == 'listing'
        ? data.listing.teamName
        : data.interestTeamName;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          color: mine ? colors.primaryContainer : null,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${mine ? 'Ni' : team}'
                  '${message.authorName != null ? ' · ${message.authorName}' : ''}'
                  ' · ${material.formatShortDate(message.createdAt.toLocal())} '
                  '${material.formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt.toLocal()))}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 4),
                SelectableText(message.body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _decide(MatchPoolConversation data) => Card(
    key: const ValueKey('match-pool-decide'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('match-pool-calendar'),
            contentPadding: EdgeInsets.zero,
            value: _addToCalendar,
            onChanged: _busy
                ? null
                : (value) => setState(() => _addToCalendar = value),
            title: const Text('Lägg in matchen i vår kalender (som utkast)'),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('match-pool-decline'),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm(
                          'Tacka nej till ${data.otherTeamName}?',
                          'Tacka nej',
                        )) {
                          await _run(
                            'decline',
                            () => widget.services.declineMatchPoolInterest(
                              widget.interestId,
                            ),
                          );
                        }
                      },
                child: const Text('Tacka nej'),
              ),
              FilledButton(
                key: const ValueKey('match-pool-accept'),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _confirm(
                          'Boka matchen med ${data.otherTeamName}? Övriga intresserade får besked.',
                          'Boka',
                        )) {
                          await _run(
                            'accept',
                            () => widget.services.acceptMatchPoolInterest(
                              widget.interestId,
                              _addToCalendar,
                            ),
                            done: 'Matchen är bokad.',
                          );
                        }
                      },
                child: const Text('Acceptera och boka'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _newKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
