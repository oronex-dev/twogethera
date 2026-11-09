import 'package:flutter/foundation.dart';

enum SharedGoalStatus { active, paused, completed }

class SharedGoalRevisionConflict implements Exception {
  const SharedGoalRevisionConflict();
}

@immutable
class SharedGoalMilestone {
  const SharedGoalMilestone({
    required this.id,
    required this.goalId,
    required this.title,
    required this.description,
    required this.completed,
    required this.revision,
    required this.sortOrder,
    this.targetOn,
  });
  final String id;
  final String goalId;
  final String title;
  final String description;
  final bool completed;
  final int revision;
  final int sortOrder;
  final DateTime? targetOn;

  factory SharedGoalMilestone.fromJson(Map<String, dynamic> json) =>
      SharedGoalMilestone(
        id: json['id'] as String,
        goalId: json['goal_id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        completed: json['is_completed'] as bool,
        revision: (json['revision'] as num).toInt(),
        sortOrder: (json['sort_order'] as num).toInt(),
        targetOn: json['target_on'] == null
            ? null
            : DateTime.parse(json['target_on'] as String),
      );
}

@immutable
class SharedGoal {
  const SharedGoal({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.revision,
    required this.milestones,
    this.targetOn,
  });
  final String id;
  final String coupleId;
  final String title;
  final String description;
  final String category;
  final SharedGoalStatus status;
  final int revision;
  final List<SharedGoalMilestone> milestones;
  final DateTime? targetOn;

  int get completedMilestones => milestones.where((m) => m.completed).length;
  double get progress => milestones.isEmpty
      ? (status == SharedGoalStatus.completed ? 1 : 0)
      : completedMilestones / milestones.length;

  factory SharedGoal.fromJson(
    Map<String, dynamic> json, {
    List<SharedGoalMilestone> milestones = const [],
  }) => SharedGoal(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    category: json['category'] as String,
    status: SharedGoalStatus.values.byName(json['status'] as String),
    revision: (json['revision'] as num).toInt(),
    milestones: List.unmodifiable(milestones),
    targetOn: json['target_on'] == null
        ? null
        : DateTime.parse(json['target_on'] as String),
  );
}

@immutable
class SharedGoalsSnapshot {
  const SharedGoalsSnapshot(this.goals);
  final List<SharedGoal> goals;
}

abstract interface class SharedGoalsRepository {
  Future<SharedGoalsSnapshot> loadSharedGoals(String coupleId);
  Future<void> saveSharedGoal(
    String coupleId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  });
  Future<void> saveMilestone(
    String coupleId,
    String goalId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  });
}
