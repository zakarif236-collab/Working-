import 'package:flutter/material.dart';
import 'package:my_app/models/workout_models.dart';

class WorkoutTimeline extends StatelessWidget {
  const WorkoutTimeline({
    super.key,
    required this.timeline,
    required this.currentIndex,
    this.currentRemainingSeconds,
    this.program = WorkoutProgram.custom,
  });

  final List<WorkoutPhase> timeline;
  final int currentIndex;
  final int? currentRemainingSeconds;
  final WorkoutProgram program;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 100,
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
            remainingSeconds: isActive ? currentRemainingSeconds : null,
            set: phase.setNumber,
            color: _phaseColor(phase.type),
            icon: _phaseIcon(phase.type),
            cue: _phaseCue(phase),
            intensity: _phaseIntensity(phase),
            isDone: isDone,
            isActive: isActive,
          );
        },
      ),
    );
  }

  IconData _phaseIcon(WorkoutPhaseType type) {
    if (program == WorkoutProgram.vo2max) {
      switch (type) {
        case WorkoutPhaseType.warmup:
          return Icons.directions_run_rounded;
        case WorkoutPhaseType.work:
          return Icons.bolt_rounded;
        case WorkoutPhaseType.rest:
          return Icons.directions_walk_rounded;
        case WorkoutPhaseType.cooldown:
          return Icons.self_improvement_rounded;
        case WorkoutPhaseType.complete:
          return Icons.check_circle_rounded;
      }
    }

    if (program == WorkoutProgram.hiitCardio) {
      switch (type) {
        case WorkoutPhaseType.warmup:
          return Icons.directions_walk_rounded;
        case WorkoutPhaseType.work:
          return Icons.bolt_rounded;
        case WorkoutPhaseType.rest:
          return Icons.pause_circle_rounded;
        case WorkoutPhaseType.cooldown:
          return Icons.self_improvement_rounded;
        case WorkoutPhaseType.complete:
          return Icons.check_circle_rounded;
      }
    }

    if (program == WorkoutProgram.tabataCardio) {
      switch (type) {
        case WorkoutPhaseType.warmup:
          return Icons.directions_run_rounded;
        case WorkoutPhaseType.work:
          return Icons.bolt_rounded;
        case WorkoutPhaseType.rest:
          return Icons.pause_circle_rounded;
        case WorkoutPhaseType.cooldown:
          return Icons.self_improvement_rounded;
        case WorkoutPhaseType.complete:
          return Icons.check_circle_rounded;
      }
    }

    switch (type) {
      case WorkoutPhaseType.warmup:
        return Icons.local_fire_department_rounded;
      case WorkoutPhaseType.work:
        return Icons.flash_on_rounded;
      case WorkoutPhaseType.rest:
        return Icons.spa_rounded;
      case WorkoutPhaseType.cooldown:
        return Icons.favorite_outline_rounded;
      case WorkoutPhaseType.complete:
        return Icons.check_circle_rounded;
    }
  }

  String? _phaseCue(WorkoutPhase phase) {
    if (program == WorkoutProgram.vo2max) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Easy pace';
        case WorkoutPhaseType.work:
          return 'Push hard';
        case WorkoutPhaseType.rest:
          return 'Recover';
        case WorkoutPhaseType.cooldown:
          return 'Cool down';
        case WorkoutPhaseType.complete:
          return null;
      }
    }

    if (program == WorkoutProgram.hiitCardio) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'March, jacks, high knees';
        case WorkoutPhaseType.work:
          return 'Pick one HIIT move';
        case WorkoutPhaseType.rest:
          return 'Walk + deep breathing';
        case WorkoutPhaseType.cooldown:
          return 'Slow walk and stretch';
        case WorkoutPhaseType.complete:
          return null;
      }
    }

    if (program == WorkoutProgram.tabataCardio) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Easy jog';
        case WorkoutPhaseType.work:
          return 'Go hard!';
        case WorkoutPhaseType.rest:
          return 'Rest now.';
        case WorkoutPhaseType.cooldown:
          return 'Stretch and walk';
        case WorkoutPhaseType.complete:
          return null;
      }
    }

    return null;
  }

  String? _phaseIntensity(WorkoutPhase phase) {
    if (program == WorkoutProgram.vo2max) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return '60-70% HRmax';
        case WorkoutPhaseType.work:
          return '85-95% HRmax';
        case WorkoutPhaseType.rest:
          return 'Easy pace';
        case WorkoutPhaseType.cooldown:
          return '60% HRmax';
        case WorkoutPhaseType.complete:
          return null;
      }
    }

    if (program == WorkoutProgram.hiitCardio) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Easy';
        case WorkoutPhaseType.work:
          return 'Intermediate';
        case WorkoutPhaseType.rest:
          return 'Recovery';
        case WorkoutPhaseType.cooldown:
          return 'Easy';
        case WorkoutPhaseType.complete:
          return null;
      }
    }

    if (program == WorkoutProgram.tabataCardio) {
      switch (phase.type) {
        case WorkoutPhaseType.warmup:
          return 'Easy';
        case WorkoutPhaseType.work:
          return 'All-out';
        case WorkoutPhaseType.rest:
          return 'Passive/light';
        case WorkoutPhaseType.cooldown:
          return 'Easy';
        case WorkoutPhaseType.complete:
          return null;
      }
    }

    return null;
  }

  Color _phaseColor(WorkoutPhaseType type) {
    if (program == WorkoutProgram.hiitCardio) {
      switch (type) {
        case WorkoutPhaseType.warmup:
        case WorkoutPhaseType.cooldown:
          return const Color(0xFF6BCB77);
        case WorkoutPhaseType.work:
          return const Color(0xFFFF5A5F);
        case WorkoutPhaseType.rest:
          return const Color(0xFF2AB7CA);
        case WorkoutPhaseType.complete:
          return Colors.white38;
      }
    }

    if (program == WorkoutProgram.tabataCardio) {
      switch (type) {
        case WorkoutPhaseType.warmup:
        case WorkoutPhaseType.cooldown:
          return const Color(0xFF6BCB77);
        case WorkoutPhaseType.work:
          return const Color(0xFFFF5A5F);
        case WorkoutPhaseType.rest:
          return const Color(0xFF2AB7CA);
        case WorkoutPhaseType.complete:
          return Colors.white38;
      }
    }

    if (program == WorkoutProgram.vo2max) {
      switch (type) {
        case WorkoutPhaseType.warmup:
        case WorkoutPhaseType.cooldown:
          return const Color(0xFF6BCB77);
        case WorkoutPhaseType.work:
          return const Color(0xFFFF5A5F);
        case WorkoutPhaseType.rest:
          return const Color(0xFF2AB7CA);
        case WorkoutPhaseType.complete:
          return Colors.white38;
      }
    }

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
    required this.icon,
    required this.isDone,
    required this.isActive,
    this.remainingSeconds,
    this.cue,
    this.intensity,
    this.set,
  });

  final String label;
  final int seconds;
  final int? remainingSeconds;
  final int? set;
  final Color color;
  final IconData icon;
  final bool isDone;
  final bool isActive;
  final String? cue;
  final String? intensity;

  @override
  Widget build(BuildContext context) {
    final statusColor = isDone
        ? color.withValues(alpha: 0.45)
        : isActive
            ? color
            : Colors.white24;

    return Container(
      width: 176,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: statusColor, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: statusColor, size: 16),
              const SizedBox(width: 6),
              Text(
                _formatDuration(
                  (isActive ? remainingSeconds : null) ?? seconds,
                ),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (cue != null) ...[
            const SizedBox(height: 2),
            Text(
              cue!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const Spacer(),
          if (intensity != null)
            Text(
              intensity!,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          const SizedBox(height: 2),
          Text(
            set == null ? '${seconds}s' : '${seconds}s  | Set $set',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int durationSeconds) {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes == 0) {
      return '${durationSeconds}s';
    }
    if (seconds == 0) {
      return '$minutes min';
    }
    return '${minutes}m ${seconds}s';
  }
}
