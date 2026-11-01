part of '../../app/teamzone_app.dart';

/// A phase's color on the timeline and on its chip.
Color _tdpPhaseColor(PeriodPhase phase) => switch (phase) {
  PeriodPhase.preseason => const Color(0xFF2E7D5B),
  PeriodPhase.competition => const Color(0xFF6A4C93),
  PeriodPhase.breakTime => const Color(0xFF8D99AE),
  PeriodPhase.other => const Color(0xFFB8562B),
};

class _TdpPhaseChip extends StatelessWidget {
  const _TdpPhaseChip({required this.phase});
  final PeriodPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = _tdpPhaseColor(phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        AppStrings.of(context).feature(phase.label),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
