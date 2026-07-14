import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/models/workout_models.dart';
import 'package:my_app/services/settings_service.dart';

class WorkoutBuilderPage extends StatefulWidget {
  const WorkoutBuilderPage({super.key, this.showBuilder = true});

  final bool showBuilder;

  @override
  State<WorkoutBuilderPage> createState() => _WorkoutBuilderPageState();
}

class _WorkoutBuilderPageState extends State<WorkoutBuilderPage> {
  final SettingsService _settingsService = SettingsService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();

  List<_WorkoutDraftExercise> _draftExercises = const [_WorkoutDraftExercise()];
  List<WorkoutBuilderRoutine> _savedRoutines = const [];
  bool _loadingSaved = true;
  String? _editingRoutineId;
  bool _didHandleRouteArgs = false;

  bool get _isEditing => _editingRoutineId != null;

  int get _draftTotalSeconds => _draftExercises.fold<int>(
    0,
    (sum, exercise) => sum + exercise.workSeconds + exercise.restSeconds,
  );

  @override
  void initState() {
    super.initState();
    _loadSavedRoutines();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didHandleRouteArgs || !widget.showBuilder) {
      return;
    }

    _didHandleRouteArgs = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is WorkoutBuilderRoutine) {
      _editRoutine(args);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedRoutines() async {
    final routines = await _settingsService.loadWorkoutBuilderRoutines();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedRoutines = routines;
      _loadingSaved = false;
    });
  }

  void _upsertRoutineLocally(WorkoutBuilderRoutine routine) {
    final index = _savedRoutines.indexWhere((entry) => entry.id == routine.id);
    final next = [..._savedRoutines];
    if (index >= 0) {
      next[index] = routine;
    } else {
      next.insert(0, routine);
    }
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _savedRoutines = next;
      _loadingSaved = false;
    });
  }

  void _addExercise() {
    setState(() {
      _draftExercises = [..._draftExercises, const _WorkoutDraftExercise()];
    });
  }

  void _removeExerciseAt(int index) {
    if (_draftExercises.length <= 1) {
      return;
    }
    setState(() {
      _draftExercises = [
        ..._draftExercises.sublist(0, index),
        ..._draftExercises.sublist(index + 1),
      ];
    });
  }

  void _reorderExercise(int oldIndex, int newIndex) {
    setState(() {
      final next = [..._draftExercises];
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = next.removeAt(oldIndex);
      next.insert(newIndex, moved);
      _draftExercises = next;
    });
  }

  Future<void> _attachMedia(int index) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _draftExercises[index] = _draftExercises[index].copyWith(
          mediaPath: picked.path,
        );
      });
    } catch (_) {
      _showMessage('Could not attach media for this exercise.');
    }
  }

  void _removeMedia(int index) {
    setState(() {
      _draftExercises[index] = _draftExercises[index].copyWith(mediaPath: '');
    });
  }

  void _clearDraft() {
    setState(() {
      _editingRoutineId = null;
      _nameController.clear();
      _draftExercises = const [_WorkoutDraftExercise()];
    });
  }

  void _editRoutine(WorkoutBuilderRoutine routine) {
    setState(() {
      _editingRoutineId = routine.id;
      _nameController.text = routine.name;
      _draftExercises = routine.exercises
          .map(
            (exercise) => _WorkoutDraftExercise(
              name: exercise.name,
              workSeconds: exercise.workSeconds,
              restSeconds: exercise.restSeconds,
              mediaPath: exercise.mediaPath,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> _duplicateRoutine(WorkoutBuilderRoutine routine) async {
    final duplicate = WorkoutBuilderRoutine(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '${routine.name} Copy',
      createdAt: DateTime.now(),
      exercises: routine.exercises,
    );

    await _settingsService.saveWorkoutBuilderRoutine(duplicate);
    await _loadSavedRoutines();
    _showMessage('Duplicated "${routine.name}".');
  }

  Future<void> _saveRoutine() async {
    final wasEditing = _isEditing;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Add a workout name before saving.');
      return;
    }

    final exercises = _draftExercises
        .map((draft) => draft.toExercise())
        .where((exercise) => exercise.name.trim().isNotEmpty)
        .toList(growable: false);

    if (exercises.isEmpty) {
      _showMessage('Add at least one exercise.');
      return;
    }

    final routine = WorkoutBuilderRoutine(
      id: _editingRoutineId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
      exercises: exercises,
    );

    _upsertRoutineLocally(routine);
    await _settingsService.saveWorkoutBuilderRoutine(routine);
    _clearDraft();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasEditing
              ? 'Workout updated and ready to use.'
              : 'Workout saved to My Workouts.',
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Start now',
          onPressed: () {
            unawaited(_startRoutine(routine));
          },
        ),
      ),
    );
  }

  Future<void> _deleteRoutine(WorkoutBuilderRoutine routine) async {
    await _settingsService.deleteWorkoutBuilderRoutine(routine.id);
    if (_editingRoutineId == routine.id) {
      _clearDraft();
    }
    await _loadSavedRoutines();
    _showMessage('Deleted "${routine.name}".');
  }

  Future<void> _openBuilderForEdit(WorkoutBuilderRoutine routine) async {
    await Navigator.of(context).pushNamed('/workout-builder', arguments: routine);
    await _loadSavedRoutines();
  }

  Future<void> _startRoutine(WorkoutBuilderRoutine routine) async {
    await Navigator.of(context).pushNamed(
      '/workout-builder-player',
      arguments: routine,
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes == 0) {
      return '${remainder}s';
    }
    return '${minutes}m ${remainder.toString().padLeft(2, '0')}s';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.showBuilder ? 'Workout Builder' : 'My Workouts';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF101A2B),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF141B2D), Color(0xFF0A1020), Color(0xFF1A2439)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            if (widget.showBuilder) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit Workout' : 'Create Workout',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isEditing)
                          TextButton.icon(
                            onPressed: _clearDraft,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Cancel'),
                          ),
                      ],
                    ),
                    TextField(
                      controller: _nameController,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: 'Workout name',
                        hintText: 'Leg Burner Intervals',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SummaryChip(
                          icon: Icons.fitness_center_rounded,
                          label: '${_draftExercises.length} exercises',
                        ),
                        _SummaryChip(
                          icon: Icons.timer_rounded,
                          label: _formatDuration(_draftTotalSeconds),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ReorderableListView.builder(
                      itemCount: _draftExercises.length,
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorderItem: _reorderExercise,
                      itemBuilder: (context, index) {
                        final exercise = _draftExercises[index];
                        return _ExerciseEditorCard(
                          key: ValueKey(
                            'draft-${exercise.name}-${exercise.workSeconds}-${exercise.restSeconds}-${exercise.mediaPath}-$index',
                          ),
                          index: index,
                          exercise: exercise,
                          onChanged: (updated) {
                            setState(() {
                              _draftExercises[index] = updated;
                            });
                          },
                          onAttachMedia: () => _attachMedia(index),
                          onRemoveMedia: () => _removeMedia(index),
                          onRemove: () => _removeExerciseAt(index),
                          removeEnabled: _draftExercises.length > 1,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _addExercise,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add Exercise'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saveRoutine,
                            icon: const Icon(Icons.save_rounded),
                            label: Text(_isEditing ? 'Update' : 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed('/workout-builder'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create New Workout'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Workouts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (!_loadingSaved)
                  Text(
                    '${_savedRoutines.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingSaved)
              const Center(child: CircularProgressIndicator())
            else if (_savedRoutines.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'No saved workouts yet. Build one above and save it.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            else
              ..._savedRoutines.map(
                (routine) => _SavedRoutineCard(
                  routine: routine,
                  onStart: () => _startRoutine(routine),
                  onPublish: () {
                    unawaited(
                      Navigator.of(context).pushNamed(
                        '/community',
                        arguments: routine,
                      ),
                    );
                  },
                  onEdit: () {
                    if (widget.showBuilder) {
                      _editRoutine(routine);
                    } else {
                      unawaited(_openBuilderForEdit(routine));
                    }
                  },
                  onDuplicate: () => _duplicateRoutine(routine),
                  onDelete: () => _deleteRoutine(routine),
                  formatDuration: _formatDuration,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _WorkoutDraftExercise {
  const _WorkoutDraftExercise({
    this.name = 'Exercise',
    this.workSeconds = 40,
    this.restSeconds = 20,
    this.mediaPath = '',
  });

  final String name;
  final int workSeconds;
  final int restSeconds;
  final String mediaPath;

  _WorkoutDraftExercise copyWith({
    String? name,
    int? workSeconds,
    int? restSeconds,
    String? mediaPath,
  }) {
    return _WorkoutDraftExercise(
      name: name ?? this.name,
      workSeconds: workSeconds ?? this.workSeconds,
      restSeconds: restSeconds ?? this.restSeconds,
      mediaPath: mediaPath ?? this.mediaPath,
    );
  }

  WorkoutBuilderExercise toExercise() {
    return WorkoutBuilderExercise(
      name: name.trim().isEmpty ? 'Exercise' : name.trim(),
      workSeconds: workSeconds,
      restSeconds: restSeconds,
      mediaPath: mediaPath,
    );
  }
}

class _ExerciseEditorCard extends StatelessWidget {
  const _ExerciseEditorCard({
    super.key,
    required this.index,
    required this.exercise,
    required this.onChanged,
    required this.onAttachMedia,
    required this.onRemoveMedia,
    required this.onRemove,
    required this.removeEnabled,
  });

  final int index;
  final _WorkoutDraftExercise exercise;
  final ValueChanged<_WorkoutDraftExercise> onChanged;
  final VoidCallback onAttachMedia;
  final VoidCallback onRemoveMedia;
  final VoidCallback onRemove;
  final bool removeEnabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withValues(alpha: 0.06),
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.drag_indicator_rounded, color: Colors.white54),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Exercise ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: removeEnabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Delete exercise',
                ),
              ],
            ),
            TextFormField(
              initialValue: exercise.name,
              key: ValueKey('exercise-name-$index-${exercise.name}'),
              onChanged: (value) => onChanged(exercise.copyWith(name: value)),
              decoration: const InputDecoration(
                labelText: 'Exercise name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            _StepperRow(
              label: 'Work duration (sec)',
              value: exercise.workSeconds,
              min: 5,
              max: 900,
              step: 5,
              onChanged: (value) => onChanged(exercise.copyWith(workSeconds: value)),
            ),
            _StepperRow(
              label: 'Rest duration (sec)',
              value: exercise.restSeconds,
              min: 0,
              max: 900,
              step: 5,
              onChanged: (value) => onChanged(exercise.copyWith(restSeconds: value)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAttachMedia,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      exercise.mediaPath.trim().isEmpty
                          ? 'Attach GIF / image'
                          : 'Change media',
                    ),
                  ),
                ),
                if (exercise.mediaPath.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onRemoveMedia,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Remove media',
                  ),
                ],
              ],
            ),
            if (exercise.mediaPath.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(exercise.mediaPath),
                    height: 130,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) {
                      return Container(
                        height: 90,
                        alignment: Alignment.center,
                        color: Colors.black26,
                        child: const Text(
                          'Media preview unavailable',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: value <= min ? null : () => onChanged((value - step).clamp(min, max)),
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            onPressed: value >= max ? null : () => onChanged((value + step).clamp(min, max)),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _SavedRoutineCard extends StatelessWidget {
  const _SavedRoutineCard({
    required this.routine,
    required this.onStart,
    required this.onPublish,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.formatDuration,
  });

  final WorkoutBuilderRoutine routine;
  final VoidCallback onStart;
  final VoidCallback onPublish;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final String Function(int seconds) formatDuration;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    routine.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'publish':
                        onPublish();
                        break;
                      case 'edit':
                        onEdit();
                        break;
                      case 'duplicate':
                        onDuplicate();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'publish',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.public_rounded),
                        title: Text('Publish to Community'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'duplicate',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.copy_all_rounded),
                        title: Text('Duplicate'),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              '${routine.exercises.length} exercises • ${formatDuration(routine.estimatedDurationSeconds)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            ...routine.exercises.take(3).map(
              (exercise) => Text(
                '• ${exercise.name} (${exercise.workSeconds}s work, ${exercise.restSeconds}s rest)',
                style: const TextStyle(color: Colors.white60),
              ),
            ),
            if (routine.exercises.length > 3)
              Text(
                '+${routine.exercises.length - 3} more',
                style: const TextStyle(color: Colors.white60),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
