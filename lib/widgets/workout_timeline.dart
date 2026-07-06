import 'package:flutter/material.dart';
import 'package:my_app/models/workout_models.dart';

class WorkoutTimeline extends StatelessWidget {
  const WorkoutTimeline({
    super.key,
    required this.timeline,
    required this.currentIndex,
  });

  final List<WorkoutPhase> timeline;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: timeline.length,
        separatorBuilder: (_, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final phase = timeline[index];
          final isDone = index < currentIndex;
          final isActive = index == currentIndex;

          return _TimelineItem(
            label: phase.label,
            seconds: phase.durationSeconds,
            set: phase.setNumber,
            color: _phaseColor(phase.type),
            isDone: isDone,
            isActive: isActive,
          );
        },
      ),
    );
  }

  Color _phaseColor(WorkoutPhaseType type) {
    switch (type) {
      case WorkoutPhaseType.warmup:
        return const Color(0xFFF7A531);
      case WorkoutPhaseType.work:
        return const Color(0xFFFF5A5F);
      case WorkoutPhaseType.rest:
        return const Color(0xFF2AB7CA);
      case WorkoutPhaseType.cooldown:
        return const Color(0xFF6BCB77);
      case WorkoutPhaseType.complete:
        return Colors.white38;
    }
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.label,
    required this.seconds,
    required this.color,
    required this.isDone,
    required this.isActive,
    this.set,
  });

  final String label;
  final int seconds;
  final int? set;
  final Color color;
  final bool isDone;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final statusColor = isDone
        ? color.withValues(alpha: 0.45)
        : isActive
            ? color
            : Colors.white24;

    return Container(
      width: 128,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: statusColor, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${seconds}s${set == null ? '' : '  | Set $set'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
