import 'dart:math';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/messaging/messaging_models.dart';
import 'package:teamzone_app/src/features/messaging/messaging_services.dart';

/// PUB-14: messages that came in through the club's or a team's page on the
/// public site. Club administrators see the club's and its teams' threads,
/// a team's leaders the team's. Answers are e-mailed from a TeamZone address
/// with the club's name; the sender's e-mail replies come back into the
/// thread.
class ContactThreadsPage extends StatefulWidget {
  const ContactThreadsPage({super.key, required this.services});
  final MessagingServices services;

  @override
  State<ContactThreadsPage> createState() => _ContactThreadsPageState();
}

class _ContactThreadsPageState extends State<ContactThreadsPage> {
  late Future<List<ContactThreadSummary>> _threads = widget.services
      .listContactThreads();
  bool _showHandled = false;

  void _reload() {
    final next = widget.services.listContactThreads();
    setState(() {
      _threads = next;
    });
  }

  Future<void> _open(ContactThreadSummary thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ContactThreadPage(services: widget.services, threadId: thread.id),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meddelanden från klubbsajten'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: 'Uppdatera',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<ContactThreadSummary>>(
        future: _threads,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Meddelandena kunde inte hämtas.'),
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
          final all = snapshot.requireData;
          final open = all.where((t) => !t.handled).toList();
          final handled = all.where((t) => t.handled).toList();
          final shown = _showHandled ? handled : open;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text('Att hantera (${open.length})'),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Hanterade (${handled.length})'),
                  ),
                ],
                selected: {_showHandled},
                onSelectionChanged: (value) =>
                    setState(() => _showHandled = value.first),
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _showHandled
                        ? 'Inga hanterade meddelanden.'
                        : 'Inga meddelanden att hantera. När någon skriver via klubbens eller lagets sida dyker det upp här.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final thread in shown)
                Card(
                  key: ValueKey('contact-thread-${thread.id}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      thread.unread
                          ? Icons.mark_email_unread_outlined
                          : Icons.mail_outline,
                      color: thread.unread
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      '${thread.senderName} · ${thread.subject}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: thread.unread
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
                    subtitle: Text(
                      '${thread.recipientLabel}\n'
                      '${thread.latestFromSender ? '' : 'Du: '}${thread.preview}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      material.formatShortDate(thread.lastActivityAt.toLocal()),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    onTap: () => _open(thread),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ContactThreadPage extends StatefulWidget {
  const ContactThreadPage({
    super.key,
    required this.services,
    required this.threadId,
  });
  final MessagingServices services;
  final String threadId;

  @override
  State<ContactThreadPage> createState() => _ContactThreadPageState();
}

class _ContactThreadPageState extends State<ContactThreadPage> {
  late Future<ContactThread> _thread = widget.services.getContactThread(
    widget.threadId,
  );
  final _reply = TextEditingController();
  // Kept until the answer is saved, so a retry never sends it twice.
  String? _replyKey;
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _reload() {
    final next = widget.services.getContactThread(widget.threadId);
    setState(() {
      _thread = next;
    });
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    _replyKey ??= _newKey();
    try {
      await widget.services.replyContactThread(
        threadId: widget.threadId,
        body: body,
        idempotencyKey: _replyKey!,
      );
      _reply.clear();
      _replyKey = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Svaret skickas till avsändaren via e-post.'),
          ),
        );
        _reload();
      }
    } catch (error) {
      AppErrors.caught('contact_threads._send', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Svaret kunde inte sparas. Försök igen.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setHandled(bool handled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.services.setContactThreadHandled(widget.threadId, handled);
      if (!mounted) return;
      if (handled) {
        Navigator.of(context).pop();
      } else {
        _reload();
      }
    } catch (error) {
      AppErrors.caught('contact_threads._setHandled', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ändringen kunde inte sparas. Försök igen.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<ContactThread>(
      future: _thread,
      builder: (context, snapshot) {
        final thread = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(thread?.subject ?? 'Meddelande'),
            actions: [
              if (thread != null)
                TextButton(
                  key: const ValueKey('contact-thread-handled'),
                  onPressed: _busy ? null : () => _setHandled(!thread.handled),
                  child: Text(
                    thread.handled ? 'Öppna igen' : 'Markera som hanterad',
                  ),
                ),
            ],
          ),
          body: snapshot.hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Meddelandet kunde inte hämtas.'),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Försök igen'),
                      ),
                    ],
                  ),
                )
              : thread == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          SelectableText(
                            '${thread.senderName} <${thread.senderEmail}>',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            'Till ${thread.teamName == null ? thread.clubName : '${thread.teamName} · ${thread.clubName}'}'
                            ' · raderas ${material.formatShortDate(thread.expiresAt.toLocal())} om inget nytt händer',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          for (final message in thread.messages)
                            Align(
                              alignment: message.fromSender
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Card(
                                  color: message.fromSender
                                      ? null
                                      : colors.primaryContainer,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${message.fromSender ? thread.senderName : (message.authorName ?? 'Ledare')}'
                                          ' · ${material.formatShortDate(message.createdAt.toLocal())} '
                                          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt.toLocal()))}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(message.body),
                                        if (!message.fromSender)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              switch (message.emailState) {
                                                'sent' => 'Skickat via e-post',
                                                'failed' =>
                                                  'Kunde inte skickas ännu – försöker igen',
                                                _ => 'Skickas…',
                                              },
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey('contact-reply-field'),
                                controller: _reply,
                                minLines: 1,
                                maxLines: 6,
                                maxLength: 5000,
                                enabled: !_busy,
                                decoration: const InputDecoration(
                                  labelText: 'Svara via e-post',
                                  helperText:
                                      'Skickas från TeamZone med klubbens namn. Din e-postadress visas inte.',
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              key: const ValueKey('contact-reply-send'),
                              onPressed: _busy ? null : _send,
                              tooltip: 'Skicka svar',
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
