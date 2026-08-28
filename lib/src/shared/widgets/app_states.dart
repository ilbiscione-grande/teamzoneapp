import 'package:flutter/material.dart';
import 'package:teamzone_app/src/shared/theme/app_theme.dart';

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label,
      liveRegion: true,
      child: const ExcludeSemantics(child: CircularProgressIndicator()),
    ),
  );
}

class AppStateCard extends StatelessWidget {
  const AppStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.liveRegion = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: liveRegion,
    child: SingleChildScrollView(
      primary: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.stateCardMaxWidth),
        child: Card(
          margin: const EdgeInsets.all(AppSpacing.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(child: Icon(icon, size: 40)),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(message, textAlign: TextAlign.center),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.lg - AppSpacing.xs),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
