import 'package:flutter/material.dart';
import 'package:teamzone_app/src/core/localization/support_strings.dart';

/// Ärenden on the support admin page: club verifications and the case
/// queue (account erasures, protected club names). Side by side in columns
/// on a wide screen, each scrolling on its own; on a narrow one, a tab each.
class SupportCasesLayout extends StatelessWidget {
  const SupportCasesLayout({
    super.key,
    required this.verifications,
    required this.cases,
  });

  final Widget verifications;
  final Widget cases;

  /// From this width the blocks stand side by side.
  static const wideFrom = 900.0;

  @override
  Widget build(BuildContext context) {
    final support = SupportStrings.of(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideFrom) {
          Widget column(String key, String title, Widget child) => Expanded(
            key: ValueKey(key),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Expanded(child: child),
              ],
            ),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              column(
                'support-cases-column-cases',
                support.casesQueueHeading,
                cases,
              ),
              VerticalDivider(
                width: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              column(
                'support-cases-column-verifications',
                support.verificationsHeading,
                verifications,
              ),
            ],
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                key: const ValueKey('support-cases-tabs'),
                tabs: [
                  Tab(
                    key: const ValueKey('support-cases-tab-cases'),
                    text: support.casesQueueHeading,
                  ),
                  Tab(
                    key: const ValueKey('support-cases-tab-verifications'),
                    text: support.verificationsHeading,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: TabBarView(children: [cases, verifications])),
            ],
          ),
        );
      },
    );
  }
}
