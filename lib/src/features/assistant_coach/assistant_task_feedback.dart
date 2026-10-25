import '../../core/localization/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/observability/app_errors.dart';
import 'package:teamzone_app/src/features/assistant_coach/assistant_task_preferences.dart';

/// "Inte till hjälp" on an assistant card (decided 2026-10-15): four fixed
/// reasons, no free text.
const assistantFeedbackReasons = <String, String>{
  'incorrect': 'Stämmer inte',
  'already_handled': 'Redan hanterat',
  'not_my_responsibility': 'Inte mitt ansvar',
  'too_often': 'Visas för ofta',
};

abstract interface class AssistantTaskFeedbackServices {
  /// Archives the card and stores the reason. True when the app should offer
  /// to hide the task type ("Visas för ofta" three times in 30 days).
  Future<bool> giveAssistantTaskFeedback({
    required String contextId,
    required String kind,
    required String route,
    required String reason,
  });
}

/// One task type as TeamZone support sees it.
class AssistantTaskKindStatus {
  const AssistantTaskKindStatus({
    required this.kind,
    required this.disabled,
    this.reason,
    this.changedAt,
    this.feedback = const {},
    this.feedbackPeople = 0,
  });
  factory AssistantTaskKindStatus.fromJson(Map<String, dynamic> json) =>
      AssistantTaskKindStatus(
        kind: json['kind'] as String,
        disabled: json['disabled'] == true,
        reason: json['reason'] as String?,
        changedAt: DateTime.tryParse(json['changed_at'] as String? ?? ''),
        feedback: {
          for (final entry in ((json['feedback'] as Map?) ?? const {}).entries)
            '${entry.key}': (entry.value as num).toInt(),
        },
        feedbackPeople: (json['feedback_people'] as num?)?.toInt() ?? 0,
      );
  final String kind;
  final bool disabled;
  final String? reason;
  final DateTime? changedAt;

  /// Feedback in the last 30 days, per reason.
  final Map<String, int> feedback;
  final int feedbackPeople;
}

/// TeamZone support only: switch a task type off or on for everyone.
abstract interface class AssistantTaskSupportServices {
  Future<List<AssistantTaskKindStatus>> listAssistantTaskKinds();
  Future<void> setAssistantTaskKindSwitch({
    required String kind,
    required bool disabled,
    required String reason,
  });
}

/// The reason sheet for "Inte till hjälp". Null when closed without a choice.
Future<String?> showAssistantFeedbackReasons(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  AppStrings.of(
                    context,
                  ).feature('Varför var detta inte till hjälp?'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  AppStrings.of(context).feature(
                    'Kortet arkiveras i din lista. Svaret sparas utan namn och '
                    'hjälper TeamZone att rätta regler som visar fel.',
                  ),
                ),
              ),
              for (final entry in assistantFeedbackReasons.entries)
                ListTile(
                  key: ValueKey('assistant-feedback-${entry.key}'),
                  title: Text(AppStrings.of(context).feature(entry.value)),
                  onTap: () => Navigator.pop(sheetContext, entry.key),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

/// Support view: every task type, whether it is on, and what people said
/// about it in the last 30 days. Switching off asks for a reason.
class AssistantTaskKindSwitches extends StatefulWidget {
  const AssistantTaskKindSwitches({super.key, required this.services});
  final AssistantTaskSupportServices services;

  @override
  State<AssistantTaskKindSwitches> createState() =>
      _AssistantTaskKindSwitchesState();
}

class _AssistantTaskKindSwitchesState extends State<AssistantTaskKindSwitches> {
  late Future<List<AssistantTaskKindStatus>> _kinds = widget.services
      .listAssistantTaskKinds();
  bool _saving = false;

  Future<void> _toggle(AssistantTaskKindStatus kind) async {
    final disabling = !kind.disabled;
    var typed = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            disabling
                ? 'Stäng av för alla användare?'
                : 'Slå på för alla användare?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(assistantTaskTypes[kind.kind] ?? kind.kind),
              const SizedBox(height: 8),
              Text(
                disabling
                    ? 'Korten försvinner direkt för alla. Användarnas egna val finns kvar när typen slås på igen.'
                    : 'Korten kommer tillbaka för alla som har typen påslagen.',
              ),
              TextField(
                key: const ValueKey('assistant-switch-reason'),
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).feature('Skäl'),
                ),
                onChanged: (value) => update(() => typed = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppStrings.of(context).feature('Avbryt')),
            ),
            FilledButton(
              onPressed: typed.trim().length < 3
                  ? null
                  : () => Navigator.pop(dialogContext, typed.trim()),
              child: Text(disabling ? 'Stäng av' : 'Slå på'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.services.setAssistantTaskKindSwitch(
        kind: kind.kind,
        disabled: disabling,
        reason: reason,
      );
    } catch (error) {
      AppErrors.caught('assistant_task_feedback._toggle', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(
                context,
              ).feature('Ändringen kunde inte sparas. Försök igen.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _kinds = widget.services.listAssistantTaskKinds();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return FutureBuilder<List<AssistantTaskKindStatus>>(
      future: _kinds,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.of(
                    context,
                  ).feature('Uppgiftstyperna kunde inte hämtas.'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _kinds = widget.services.listAssistantTaskKinds(),
                  ),
                  child: Text(AppStrings.of(context).feature('Försök igen')),
                ),
              ],
            ),
          );
        }
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              AppStrings.of(context).feature('Min assistents uppgiftstyper'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                AppStrings.of(context).feature(
                  'Stäng av en typ för alla om regeln visar fel. Feedback gäller '
                  'de senaste 30 dagarna och visas utan namn.',
                ),
              ),
            ),
            for (final kind in snapshot.requireData)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: SwitchListTile(
                  key: ValueKey('assistant-switch-${kind.kind}'),
                  value: !kind.disabled,
                  onChanged: _saving ? null : (_) => _toggle(kind),
                  title: Text(assistantTaskTypes[kind.kind] ?? kind.kind),
                  subtitle: Text(
                    [
                      if (kind.disabled && kind.reason != null)
                        'Avstängd: ${kind.reason}'
                            '${kind.changedAt == null ? '' : ' (${material.formatShortDate(kind.changedAt!.toLocal())})'}',
                      kind.feedback.isEmpty
                          ? 'Ingen feedback'
                          : '${[for (final entry in assistantFeedbackReasons.entries)
                                  if ((kind.feedback[entry.key] ?? 0) > 0) '${entry.value} ${kind.feedback[entry.key]}'].join(' · ')} '
                                '(${kind.feedbackPeople} ${kind.feedbackPeople == 1 ? 'person' : 'personer'})',
                    ].join('\n'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
