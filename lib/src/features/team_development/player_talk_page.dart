import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/app_strings.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_editor.dart';
import 'package:teamzone_app/src/features/team_development/player_talk_services.dart';
import 'package:teamzone_app/src/features/team_development/team_survey_services.dart';

/// Shows a survey answer beside the talk.
typedef TalkAnswerView = Widget Function(PlayerSurveyAnswer answer);

/// Reads a talk and the player's survey answers, then opens the editor: the
/// talk [talkId], the talk that starts from [responseId], or a new one.
class PlayerTalkPage extends StatefulWidget {
  const PlayerTalkPage({
    super.key,
    required this.teamId,
    required this.personId,
    required this.answerView,
    this.talkId,
    this.responseId,
  });
  final String teamId, personId;
  final String? talkId, responseId;
  final TalkAnswerView answerView;

  static Future<void> open(
    BuildContext context, {
    required String teamId,
    required String personId,
    required TalkAnswerView answerView,
    String? talkId,
    String? responseId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PlayerTalkPage(
        teamId: teamId,
        personId: personId,
        answerView: answerView,
        talkId: talkId,
        responseId: responseId,
      ),
    ),
  );

  @override
  State<PlayerTalkPage> createState() => _PlayerTalkPageState();
}

class _PlayerTalkPageState extends State<PlayerTalkPage> {
  late Future<(PlayerTalks, List<PlayerSurveyAnswer>)> _load = _read();

  Future<(PlayerTalks, List<PlayerSurveyAnswer>)> _read() async {
    try {
      return await (
        PlayerTalksFeature.services.list(widget.teamId, widget.personId),
        TeamSurveysFeature.services.playerAnswers(
          widget.teamId,
          widget.personId,
        ),
      ).wait;
    } on ParallelWaitError<Object?, (AsyncError?, AsyncError?)> catch (failed) {
      final error = failed.errors.$1?.error ?? failed.errors.$2!.error;
      AppErrors.caught('player_talks.open', error);
      throw error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final swedish = AppStrings.of(context).isSwedish;
    return FutureBuilder(
      future: _load,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data != null) {
          final (talks, answers) = data;
          final talk = talks.talks
              .where(
                (talk) => widget.talkId != null
                    ? talk.id == widget.talkId
                    : widget.responseId != null &&
                          talk.responseId == widget.responseId,
              )
              .firstOrNull;
          if (talk != null || (talks.canEdit && talks.isPlayer)) {
            return PlayerTalkEditor(
              teamId: widget.teamId,
              personId: widget.personId,
              talks: talks,
              talk: talk,
              answers: answers,
              responseId: widget.responseId,
              answerView: widget.answerView,
            );
          }
        }
        final error = snapshot.error;
        return Scaffold(
          appBar: AppBar(
            title: Text(swedish ? 'Spelarsamtal' : 'Player talk'),
          ),
          body: data == null && error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          switch (error) {
                            final PlayerTalkException refused =>
                              refused.message(swedish),
                            null => PlayerTalkException(
                              data!.$1.canEdit
                                  ? 'talk_needs_player_role'
                                  : 'read_only',
                            ).message(swedish),
                            _ =>
                              swedish
                                  ? 'Samtalet kunde inte läsas.'
                                  : 'The talk could not be read.',
                          },
                          textAlign: TextAlign.center,
                        ),
                        if (error != null && error is! PlayerTalkException)
                          TextButton(
                            onPressed: () => setState(() => _load = _read()),
                            child: Text(swedish ? 'Försök igen' : 'Retry'),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
