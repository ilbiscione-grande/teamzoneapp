import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_page.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_services.dart';

/// The Samtal tab on a player's profile, for the team's leaders with
/// Säsongsplanering: the talks with the player, newest first.
class PlayerTalksView extends StatefulWidget {
  const PlayerTalksView({
    super.key,
    required this.teamId,
    required this.personId,
    required this.answerView,
    this.header,
  });
  final String teamId, personId;
  final TalkAnswerView answerView;
  final Widget? header;

  @override
  State<PlayerTalksView> createState() => _PlayerTalksViewState();
}

class _PlayerTalksViewState extends State<PlayerTalksView> {
  late Future<PlayerTalks> _load = _read();

  Future<PlayerTalks> _read() async {
    try {
      return await PlayerTalksFeature.services.list(
        widget.teamId,
        widget.personId,
      );
    } catch (error) {
      if (error is! PlayerTalkException) {
        AppErrors.caught('player_talks.list', error);
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final next = _read();
    setState(() {
      _load = next;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  Future<void> _open([PlayerTalk? talk]) async {
    await PlayerTalkPage.open(
      context,
      teamId: widget.teamId,
      personId: widget.personId,
      answerView: widget.answerView,
      talkId: talk?.id,
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swedish = AppStrings.of(context).isSwedish;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return FutureBuilder<PlayerTalks>(
      future: _load,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final error = snapshot.error;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 16),
              ],
              Text(
                swedish ? 'Spelarsamtal' : 'Player talks',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (error is PlayerTalkException)
                Text(error.message(swedish), style: muted)
              else if (error != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        swedish
                            ? 'Samtalen kunde inte läsas.'
                            : 'The talks could not be read.',
                      ),
                    ),
                    TextButton(
                      onPressed: _refresh,
                      child: Text(swedish ? 'Försök igen' : 'Retry'),
                    ),
                  ],
                )
              else if (data == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text(
                  swedish
                      ? 'Syns bara för lagets ledare med Säsongsplanering.'
                      : 'Only the team\'s leaders with Season planning see this.',
                  style: muted,
                ),
                if (data.canEdit && data.isPlayer)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: FilledButton.icon(
                        key: const Key('talk-new'),
                        onPressed: _open,
                        icon: const Icon(Icons.add),
                        label: Text(swedish ? 'Nytt samtal' : 'New talk'),
                      ),
                    ),
                  ),
                if (data.talks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      swedish
                          ? 'Inga samtal ännu. Ett samtal kan också startas från ett enkätsvar.'
                          : 'No talks yet. A talk can also start from a survey answer.',
                    ),
                  ),
                for (final talk in data.talks) _card(context, talk, swedish),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, PlayerTalk talk, bool swedish) {
    final text = talk.agreed.trim().isNotEmpty
        ? '${swedish ? 'Överens om' : 'Agreed'}: ${talk.agreed.trim()}'
        : talk.leaderNotes.trim();
    final about = [
      for (final leader in talk.leaders) leader.name,
      ?talk.surveyTitle,
    ].join(' · ');
    return Card(
      key: Key('talk-${talk.id}'),
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: const Icon(Icons.forum_outlined),
        title: Text(
          MaterialLocalizations.of(context).formatCompactDate(talk.talkedOn),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (about.isNotEmpty) Text(about),
            if (text.isNotEmpty)
              Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(talk),
      ),
    );
  }
}
