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
Future<void> openMatchPoolOnWeb(
  MessagingServices services, {
  String? listingId,
}) async {
  var url = '$_publicSiteOrigin/matchpool';
  if (listingId != null) url = '$url?annons=$listingId';
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
  'cancelled': 'Avbokad',
};

const _genderLabels = {
  'boys': 'Pojkar',
  'girls': 'Flickor',
  'mixed': 'Mixat',
  'men': 'Herrar',
  'women': 'Damer',
};
const _levelLabels = {
  'beginner': 'Nybörjare',
  'intermediate': 'Medel',
  'advanced': 'Stark',
};

String _formatLabel(String format) => format.replaceFirst('v', ' mot ');

/// The database's reason in Swedish, or a general message.
String matchPoolErrorText(Object error) {
  final text = error.toString();
  const known = {
    'match_started': 'Matchen har redan börjat och kan inte avbokas.',
    'cancellation_pending': 'Det finns redan en begäran om avbokning.',
    'no_cancellation': 'Det finns ingen begäran om avbokning längre.',
    'conversation_closed': 'Konversationen är avslutad.',
    'listing_closed': 'Annonsen är inte längre öppen.',
    'cannot_republish':
        'Annonsen kan inte läggas ut igen, datumet har passerat.',
    'not_booked': 'Matchen är inte bokad.',
    'rate_limited': 'Många ändringar på kort tid. Försök igen senare.',
  };
  for (final entry in known.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'Det gick inte att spara. Försök igen.';
}

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
  const MatchPoolPage({
    super.key,
    required this.services,
    this.embedded = false,
  });
  final MessagingServices services;

  /// Inside the inbox's Matchpool tab: the list without its own app bar.
  final bool embedded;

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
    final body = _body(context);
    if (widget.embedded) {
      return RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _items.catchError(
            (_) => const <MatchPoolConversationSummary>[],
          );
        },
        child: body,
      );
    }
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
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return FutureBuilder<List<MatchPoolConversationSummary>>(
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
                          '${item.listing.homeSlot ? 'söker hemmamatch' : 'söker bortamatch'} · '
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
  String? _republishKey;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(matchPoolErrorText(error))));
        _reload();
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
                          ..._cancellation(data),
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
              '${listing.teamName} ${listing.homeSlot ? 'söker hemmamatch' : 'söker bortamatch'} · '
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

  Future<String?> _askReason() async {
    var text = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Begär avbokning'),
        content: TextField(
          key: const ValueKey('match-pool-cancel-reason'),
          onChanged: (value) => text = value,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Varför? (valfritt)',
            helperText: 'Det andra laget behöver godkänna avbokningen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, text),
            child: const Text('Begär avbokning'),
          ),
        ],
      ),
    );
    return reason;
  }

  /// POOL-02: cancellation needs both teams; the listing's team may then
  /// put the same listing out again.
  List<Widget> _cancellation(MatchPoolConversation data) {
    final requested = data.cancelRequestedSide;
    if (data.state == 'accepted' && requested == null) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('match-pool-request-cancel'),
            onPressed: _busy
                ? null
                : () async {
                    final reason = await _askReason();
                    if (reason == null) return;
                    await _run(
                      'request_cancel',
                      () => widget.services.requestMatchPoolCancellation(
                        widget.interestId,
                        reason.trim().isEmpty ? null : reason.trim(),
                      ),
                      done: 'Begäran om avbokning är skickad.',
                    );
                  },
            child: const Text('Begär avbokning'),
          ),
        ),
      ];
    }
    if (data.state == 'accepted' && requested == data.mySide) {
      return [
        Card(
          color: const Color(0xFFFFFAF0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ni har begärt avbokning'
                  '${data.cancelReason != null ? ': ${data.cancelReason}' : ''}. '
                  'Väntar på att ${data.otherTeamName} godkänner.',
                ),
                TextButton(
                  key: const ValueKey('match-pool-withdraw-cancel'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          'withdraw_cancel',
                          () => widget.services.withdrawMatchPoolCancellation(
                            widget.interestId,
                          ),
                        ),
                  child: const Text('Ta tillbaka begäran'),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (data.state == 'accepted' && requested != null) {
      return [
        Card(
          key: const ValueKey('match-pool-cancel-request'),
          color: const Color(0xFFFFFAF0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${data.cancelRequestedTeamName ?? data.otherTeamName} vill avboka matchen'
                  '${data.cancelReason != null ? ': ${data.cancelReason}' : '.'} '
                  'Godkänner ni ställs matchen in i båda lagens kalendrar.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('match-pool-keep'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              'decline_cancel',
                              () =>
                                  widget.services.respondMatchPoolCancellation(
                                    widget.interestId,
                                    false,
                                  ),
                            ),
                      child: const Text('Matchen gäller'),
                    ),
                    FilledButton(
                      key: const ValueKey('match-pool-approve-cancel'),
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirm(
                                'Godkänn avbokningen? Matchen ställs in i båda kalendrarna.',
                                'Godkänn',
                              )) {
                                await _run(
                                  'accept_cancel',
                                  () => widget.services
                                      .respondMatchPoolCancellation(
                                        widget.interestId,
                                        true,
                                      ),
                                  done: 'Matchen är avbokad.',
                                );
                              }
                            },
                      child: const Text('Godkänn avbokning'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (data.state == 'cancelled' &&
        data.fromListingSide &&
        data.listing.canRepublish) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vill ni hitta ett annat lag till samma tid? Lägg ut annonsen igen som den var.',
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('match-pool-republish'),
                  onPressed: _busy
                      ? null
                      : () {
                          _republishKey ??= _newKey();
                          _run(
                            'republish',
                            () => widget.services.republishMatchPoolListing(
                              data.listing.id,
                              _republishKey!,
                            ),
                            done: 'Annonsen är utlagd igen.',
                          );
                        },
                  child: const Text('Lägg ut annonsen igen'),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return const [];
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

/// POOL-02: a listing a watch found, opened from its notification. Showing
/// interest happens on the web, signed in with the same account.
class MatchPoolListingPage extends StatefulWidget {
  const MatchPoolListingPage({
    super.key,
    required this.services,
    required this.listingId,
  });
  final MessagingServices services;
  final String listingId;

  @override
  State<MatchPoolListingPage> createState() => _MatchPoolListingPageState();
}

class _MatchPoolListingPageState extends State<MatchPoolListingPage> {
  late final Future<MatchPoolListing> _listing = widget.services
      .getMatchPoolListing(widget.listingId);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ny annons i matchpoolen')),
    body: FutureBuilder<MatchPoolListing>(
      future: _listing,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Annonsen finns inte längre.'));
        }
        final listing = snapshot.data;
        if (listing == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final details = [
          listing.ageClass,
          if (listing.gender != null)
            _genderLabels[listing.gender] ?? listing.gender!,
          _formatLabel(listing.matchFormat),
          if (listing.level != null)
            _levelLabels[listing.level] ?? listing.level!,
        ].join(' · ');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _VerifiedBadge(verified: listing.verified),
                        Chip(
                          label: Text(
                            listing.homeSlot
                                ? 'Söker hemmamatch'
                                : 'Söker bortamatch',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${listing.teamName} · ${listing.clubName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (!listing.verified)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Klubben är inte verifierad av TeamZone. Stäm gärna av med klubben innan ni bokar.',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(_when(context, listing)),
                    Text(listing.placeLabel),
                    if (listing.maxDistanceKm != null)
                      Text('Reser upp till ${listing.maxDistanceKm} km'),
                    Text(details),
                    if (listing.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(listing.note!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!listing.current)
              const Text('Annonsen är inte längre öppen.')
            else if (listing.myInterestId != null)
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => MatchPoolConversationPage(
                      services: widget.services,
                      interestId: listing.myInterestId!,
                    ),
                  ),
                ),
                child: const Text('Öppna konversationen'),
              )
            else if (!listing.own)
              FilledButton.icon(
                key: const ValueKey('match-pool-interest-web'),
                onPressed: () =>
                    openMatchPoolOnWeb(widget.services, listingId: listing.id),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Visa intresse'),
              ),
            if (listing.current && listing.myInterestId == null && !listing.own)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Öppnas på teamzoneapp.se, inloggad med samma konto. Där väljer ni lag och skriver ett meddelande.',
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// POOL-04: reported match pool listings, for support administrators.
/// Support hides a listing or dismisses its reports; a listing hidden
/// automatically after three reports opens again when they are dismissed.
class MatchPoolReportsQueue extends StatefulWidget {
  const MatchPoolReportsQueue({super.key, required this.services});
  final MessagingServices services;

  @override
  State<MatchPoolReportsQueue> createState() => _MatchPoolReportsQueueState();
}

class _MatchPoolReportsQueueState extends State<MatchPoolReportsQueue> {
  bool _onlyOpen = true;
  bool _busy = false;
  late Future<List<MatchPoolReportedListing>> _items = widget.services
      .listMatchPoolReports();

  void _reload() {
    final next = widget.services.listMatchPoolReports(onlyOpen: _onlyOpen);
    setState(() {
      _items = next;
    });
  }

  Future<void> _decide(MatchPoolReportedListing item, bool hide) async {
    var text = '';
    final formKey = GlobalKey<FormState>();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(hide ? 'Dölj annonsen' : 'Rapporterna är ogrundade'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const ValueKey('match-pool-report-note'),
            onChanged: (value) => text = value,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Motivering',
              helperText: hide
                  ? 'Lag som väntar på svar får beskedet att annonsen är borttagen.'
                  : 'En annons som dolts automatiskt blir synlig igen.',
            ),
            validator: (value) =>
                (value?.trim().length ?? 0) < 5 ? 'Ange minst 5 tecken.' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, text.trim());
              }
            },
            child: Text(hide ? 'Dölj' : 'Avfärda rapporterna'),
          ),
        ],
      ),
    );
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.services.decideMatchPoolReports(
        item.listing.id,
        hide: hide,
        note: note,
      );
      if (mounted) _reload();
    } catch (error) {
      AppErrors.caught('match_pool.decideReports', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beslutet kunde inte sparas.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Rapporterade annonser i matchpoolen',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            key: const ValueKey('match-pool-reports-open'),
            contentPadding: EdgeInsets.zero,
            value: _onlyOpen,
            onChanged: (value) {
              _onlyOpen = value;
              _reload();
            },
            title: const Text('Bara obehandlade rapporter'),
          ),
          Flexible(
            child: FutureBuilder<List<MatchPoolReportedListing>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Rapporterna kunde inte hämtas.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.requireData;
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Inga rapporterade annonser.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in items)
                      Card(
                        key: ValueKey('match-pool-report-${item.listing.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _VerifiedBadge(
                                    verified: item.listing.verified,
                                  ),
                                  Chip(
                                    label: Text(switch (item.listing.state) {
                                      'hidden' when item.hiddenBySupport =>
                                        'Dold av support',
                                      'hidden' => 'Dold automatiskt',
                                      'open' => 'Synlig',
                                      'matched' => 'Bokad',
                                      _ => 'Avslutad',
                                    }),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  if (item.openReports > 0)
                                    Chip(
                                      label: Text(
                                        '${item.openReports} obehandlade',
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item.listing.teamName} · ${item.listing.clubName}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                [
                                  item.listing.homeSlot
                                      ? 'Söker hemmamatch'
                                      : 'Söker bortamatch',
                                  _when(context, item.listing),
                                  ?item.listing.venueName,
                                  item.listing.placeLabel,
                                  item.listing.ageClass,
                                ].where((part) => part.isNotEmpty).join(' · '),
                              ),
                              if (item.listing.note != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Kommentar: ${item.listing.note}',
                                  ),
                                ),
                              const Divider(),
                              for (final report in item.reports)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    '${report.clubName} · ${material.formatShortDate(report.createdAt.toLocal())}'
                                    '${report.resolution == null
                                        ? ''
                                        : report.resolution == 'hidden'
                                        ? ' · dold'
                                        : ' · avfärdad'}'
                                    ': ${report.reason}',
                                  ),
                                ),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    key: ValueKey(
                                      'match-pool-dismiss-${item.listing.id}',
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _decide(item, false),
                                    child: const Text('Ogrundade'),
                                  ),
                                  FilledButton(
                                    key: ValueKey(
                                      'match-pool-hide-${item.listing.id}',
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => _decide(item, true),
                                    child: const Text('Dölj annonsen'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
