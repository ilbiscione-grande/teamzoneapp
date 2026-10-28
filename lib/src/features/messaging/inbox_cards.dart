part of '../../app/teamzone_app.dart';

/// The quick filters under the inbox search: all, important notices,
/// unread and read (archived) notices. The sheet keeps the rest.
class _InboxQuickFilters extends StatelessWidget {
  const _InboxQuickFilters({
    required this.selected,
    required this.total,
    required this.important,
    required this.onSelected,
  });
  final String selected;
  final int total, important;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final palette = AppPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    Widget chip(String key, String label, {Widget? before, int? count}) {
      final active = selected == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          key: ValueKey('inbox-quick-$key'),
          color: active ? palette.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
            side: active
                ? BorderSide.none
                : BorderSide(color: colors.outlineVariant),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => onSelected(active && key != 'all' ? 'all' : key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?before,
                  Text(
                    strings.feature(label),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: active ? palette.accent : null,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 6),
                    _InboxCountBadge(
                      count: count,
                      color: key == 'important' ? palette.danger : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          chip('all', 'Alla', count: total),
          chip(
            'important',
            'Viktigt',
            count: important,
            before: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.circle, size: 8, color: palette.danger),
            ),
          ),
          chip('unread', 'Olästa'),
          chip('archived', 'Arkiverade'),
        ],
      ),
    );
  }
}

/// A count in a small filled circle: accent by default, red for notices.
class _InboxCountBadge extends StatelessWidget {
  const _InboxCountBadge({required this.count, this.color});
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = color ?? colors.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color == null ? colors.onPrimary : Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A notice in the inbox: a megaphone in a soft circle, the subject, the
/// start of the text and the time; unread ones on an accent-tinted card
/// with a red count.
class _InboxAnnouncementCard extends StatelessWidget {
  const _InboxAnnouncementCard({required this.thread, required this.onTap});
  final MessageThreadSummary thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final unread = thread.unreadCount > 0;
    return Card(
      key: ValueKey('inbox-announcement-${thread.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: unread
          ? Color.alphaBlend(
              palette.accentSoft.withValues(alpha: .45),
              theme.cardTheme.color ?? theme.colorScheme.surface,
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: palette.accentSoft,
                child: Icon(
                  unread ? Icons.campaign : Icons.campaign_outlined,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.subject ?? strings.feature('Anslag'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.preview ?? strings.noMessages,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inboxShortTime(context, thread.lastAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: palette.muted,
                    ),
                  ),
                  if (unread) ...[
                    const SizedBox(height: 8),
                    _InboxCountBadge(
                      count: thread.unreadCount,
                      color: palette.danger,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A conversation in the inbox: who it is with, the subject, the last
/// message, the time and an unread count.
class _InboxThreadRow extends StatelessWidget {
  const _InboxThreadRow({
    required this.thread,
    required this.avatars,
    required this.onTap,
  });
  final MessageThreadSummary thread;
  final ThreadAvatars? avatars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final people = avatars?.people ?? const <ThreadAvatarPerson>[];
    final unread = thread.unreadCount > 0;
    final sender = (thread.senderName ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Center(
                  child: people.isNotEmpty
                      ? _ThreadAvatarStack(
                          key: ValueKey('inbox-avatars-${thread.id}'),
                          avatars: avatars!,
                        )
                      : CircleAvatar(
                          radius: 22,
                          backgroundColor: palette.accentSoft,
                          child: Icon(
                            thread.type == 'group'
                                ? Icons.groups_outlined
                                : Icons.forum_outlined,
                            color: palette.accent,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.subject ?? strings.directMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${sender.isEmpty || thread.type == 'direct' ? '' : '$sender: '}'
                      '${thread.preview ?? strings.noMessages}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: unread
                            ? theme.colorScheme.onSurface
                            : palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inboxShortTime(context, thread.lastAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: unread ? palette.accent : palette.muted,
                      fontWeight: unread ? FontWeight.w700 : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (thread.muted)
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 16,
                          color: palette.muted,
                        ),
                      if (thread.pinned)
                        Icon(Icons.push_pin, size: 16, color: palette.muted),
                      if (unread) ...[
                        const SizedBox(width: 4),
                        _InboxCountBadge(count: thread.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The time on an inbox row: the clock today, "igår", the weekday within
/// a week, else the date.
String _inboxShortTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(local);
  final material = MaterialLocalizations.of(context);
  final days = today.difference(day).inDays;
  if (days <= 0) {
    return material.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  }
  if (days == 1) return AppStrings.of(context).feature('igår');
  if (days < 7) return _capitalized(_homeShortWeekday(material, local));
  return material.formatShortMonthDay(local);
}

/// A soft colour per person for initials, the same name always the same.
({Color background, Color foreground}) _avatarTint(
  BuildContext context,
  String name,
) {
  const hues = [145.0, 210.0, 275.0, 30.0, 180.0, 340.0];
  final dark = Theme.of(context).brightness == Brightness.dark;
  final hue = hues[name.codeUnits.fold(0, (a, b) => a + b) % hues.length];
  return (
    background: HSLColor.fromAHSL(1, hue, .45, dark ? .28 : .9).toColor(),
    foreground: HSLColor.fromAHSL(1, hue, .55, dark ? .85 : .32).toColor(),
  );
}

/// A day between messages: the date centred between two hairlines.
class _ThreadDateDivider extends StatelessWidget {
  const _ThreadDateDivider({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final line = Expanded(
      child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              MaterialLocalizations.of(context).formatMediumDate(day),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: palette.muted),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// One message as a bubble: your own on the right in soft accent, the
/// others' on the left in grey, with the time in the corner.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.files,
    required this.messaging,
    required this.onLongPress,
  });
  final ThreadMessage message;
  final List<MessageFile> files;
  final MessagingServices messaging;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final mine = message.mine;
    final dark = theme.brightness == Brightness.dark;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt.toLocal()));
    return Card(
      key: ValueKey('message-bubble-${message.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      // The theme's surfaces lean green; the others' bubbles are a neutral
      // grey so the two sides stay apart.
      color: mine
          ? palette.accentSoft
          : Color.alphaBlend(
              theme.colorScheme.onSurface.withValues(alpha: dark ? .1 : .06),
              theme.colorScheme.surface,
            ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 6),
          bottomRight: Radius.circular(mine ? 6 : 18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  message.body ?? strings.recalledMessage,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontStyle: message.body == null ? FontStyle.italic : null,
                  ),
                ),
              ),
              for (final file in files) ...[
                const SizedBox(height: 6),
                _InlineMessageFile(file: file, messaging: messaging),
              ],
              const SizedBox(height: 4),
              Text(
                time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: mine ? palette.accent : palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The writing row under a conversation: attach, the text in a pill and
/// a round send button.
class _ThreadComposer extends StatelessWidget {
  const _ThreadComposer({
    required this.controller,
    required this.sending,
    required this.stagedName,
    required this.onAttach,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final String? stagedName;
  final VoidCallback onAttach, onSend;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stagedName != null)
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.attach_file, size: 16, color: palette.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${strings.feature('Bilaga')}: $stagedName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  key: const ValueKey('thread-attach'),
                  onPressed: sending ? null : onAttach,
                  tooltip: strings.feature('Bifoga fil'),
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('thread-message-field'),
                    controller: controller,
                    maxLength: 4000,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: strings.feature('Skriv ett meddelande …'),
                      counterText: '',
                      filled: true,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: palette.accent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('thread-send'),
                  onPressed: sending ? null : onSend,
                  tooltip: strings.sendMessage,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
