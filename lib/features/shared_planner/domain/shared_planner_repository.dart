enum PlannerBucketCategory {
  travel('Travel'),
  home('Home'),
  food('Food & dining'),
  adventure('Adventure'),
  learning('Learning'),
  celebration('Celebrations'),
  other('Other');

  const PlannerBucketCategory(this.label);
  final String label;
}

class RecoverableSharedRecord {
  const RecoverableSharedRecord({
    required this.table,
    required this.id,
    required this.deletedAt,
    required this.restoreUntil,
  });

  final String table;
  final String id;
  final DateTime deletedAt;
  final DateTime restoreUntil;

  String get label => switch (table) {
    'bucket_list_items' => 'Bucket List item',
    'important_dates' => 'Important Date',
    'plans' => 'Plan and checklist',
    'plan_tasks' => 'Plan task',
    'couple_memories' => 'Memory',
    'date_night_ideas' => 'Date Night idea',
    'shared_goals' => 'Shared Goal and milestones',
    'shared_goal_milestones' => 'Goal milestone',
    _ => 'Shared item',
  };

  factory RecoverableSharedRecord.fromJson(Map<String, dynamic> json) =>
      RecoverableSharedRecord(
        table: json['target_table'] as String,
        id: json['target_id'] as String,
        deletedAt: DateTime.parse(json['deleted_at'] as String),
        restoreUntil: DateTime.parse(json['restore_until'] as String),
      );
}

abstract interface class SharedContentRecoveryRepository {
  Future<List<RecoverableSharedRecord>> listRecoverableSharedRecords();
  Future<bool> restoreSharedRecord(RecoverableSharedRecord record);
}

enum ImportantDateKind { birthday, anniversary, special }

enum AnnualLeapDayPolicy {
  feb28('Celebrate on February 28 in non-leap years'),
  skip('Skip the date in non-leap years');

  const AnnualLeapDayPolicy(this.label);
  final String label;
}

class BucketListItem {
  const BucketListItem({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.description,
    required this.category,
    required this.completed,
    required this.revision,
    this.targetDate,
  });

  final String id;
  final String coupleId;
  final String title;
  final String description;
  final PlannerBucketCategory category;
  final bool completed;
  final int revision;
  final DateTime? targetDate;

  factory BucketListItem.fromJson(Map<String, dynamic> json) => BucketListItem(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    category: PlannerBucketCategory.values.firstWhere(
      (value) => value.name == json['category_key'],
      orElse: () => PlannerBucketCategory.other,
    ),
    completed: json['is_completed'] as bool? ?? false,
    revision: (json['revision'] as num).toInt(),
    targetDate: json['target_date'] == null
        ? null
        : DateTime.parse(json['target_date'] as String),
  );
}

class ImportantDateEntry {
  const ImportantDateEntry({
    required this.id,
    required this.coupleId,
    required this.kind,
    required this.title,
    required this.date,
    required this.notes,
    required this.annual,
    required this.leapDayPolicy,
    required this.revision,
  });

  final String id;
  final String coupleId;
  final ImportantDateKind kind;
  final String title;
  final DateTime date;
  final String notes;
  final bool annual;
  final AnnualLeapDayPolicy? leapDayPolicy;
  final int revision;

  DateTime nextOccurrence(DateTime now) {
    if (!annual) return DateTime(date.year, date.month, date.day);
    var year = now.year;
    for (var attempt = 0; attempt < 9; attempt++, year++) {
      DateTime? candidate;
      if (date.month == 2 && date.day == 29 && !_isLeapYear(year)) {
        if (leapDayPolicy == AnnualLeapDayPolicy.skip) continue;
        candidate = DateTime(year, 2, 28);
      } else {
        candidate = DateTime(year, date.month, date.day);
      }
      if (!candidate.isBefore(DateTime(now.year, now.month, now.day))) {
        return candidate;
      }
    }
    throw StateError('No upcoming annual occurrence could be calculated.');
  }

  int daysUntil(DateTime now) =>
      nextOccurrence(now)
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;

  static bool _isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  factory ImportantDateEntry.fromJson(Map<String, dynamic> json) =>
      ImportantDateEntry(
        id: json['id'] as String,
        coupleId: json['couple_id'] as String,
        kind: ImportantDateKind.values.firstWhere(
          (value) => value.name == json['kind'],
        ),
        title: json['title'] as String,
        date: DateTime.parse(json['date_value'] as String),
        notes: json['notes'] as String? ?? '',
        annual: json['recurrence'] == 'annual',
        leapDayPolicy: switch (json['leap_day_policy']) {
          'feb28' => AnnualLeapDayPolicy.feb28,
          'skip' => AnnualLeapDayPolicy.skip,
          _ => null,
        },
        revision: (json['revision'] as num).toInt(),
      );
}

class PlanTask {
  const PlanTask({
    required this.id,
    required this.coupleId,
    required this.planId,
    required this.title,
    required this.completed,
    required this.revision,
    required this.sortOrder,
  });

  final String id;
  final String coupleId;
  final String planId;
  final String title;
  final bool completed;
  final int revision;
  final int sortOrder;

  factory PlanTask.fromJson(Map<String, dynamic> json) => PlanTask(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    planId: json['plan_id'] as String,
    title: json['title'] as String,
    completed: json['is_completed'] as bool? ?? false,
    revision: (json['revision'] as num).toInt(),
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class SharedPlan {
  const SharedPlan({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.location,
    required this.revision,
    required this.tasks,
    this.endsAt,
  });

  final String id;
  final String coupleId;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String location;
  final int revision;
  final List<PlanTask> tasks;

  factory SharedPlan.fromJson(
    Map<String, dynamic> json, {
    List<PlanTask> tasks = const [],
  }) => SharedPlan(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
    endsAt: json['ends_at'] == null
        ? null
        : DateTime.parse(json['ends_at'] as String).toLocal(),
    location: json['location'] as String? ?? '',
    revision: (json['revision'] as num).toInt(),
    tasks: List.unmodifiable(tasks),
  );
}

class SharedPlannerSnapshot {
  const SharedPlannerSnapshot({
    required this.bucketItems,
    required this.importantDates,
    required this.plans,
  });

  final List<BucketListItem> bucketItems;
  final List<ImportantDateEntry> importantDates;
  final List<SharedPlan> plans;
}

abstract interface class SharedPlannerRepository {
  Future<SharedPlannerSnapshot> load(String coupleId);
  Future<void> createBucketItem(String coupleId, Map<String, dynamic> values);
  Future<void> updateBucketItem(
    String coupleId,
    BucketListItem item,
    Map<String, dynamic> values,
  );
  Future<void> deleteBucketItem(String coupleId, BucketListItem item);
  Future<void> createImportantDate(
    String coupleId,
    Map<String, dynamic> values,
  );
  Future<void> updateImportantDate(
    String coupleId,
    ImportantDateEntry date,
    Map<String, dynamic> values,
  );
  Future<void> deleteImportantDate(String coupleId, ImportantDateEntry date);
  Future<void> createPlan(String coupleId, Map<String, dynamic> values);
  Future<void> updatePlan(
    String coupleId,
    SharedPlan plan,
    Map<String, dynamic> values,
  );
  Future<void> deletePlan(String coupleId, SharedPlan plan);
  Future<void> createTask(String coupleId, String planId, String title);
  Future<void> updateTask(
    String coupleId,
    PlanTask task,
    Map<String, dynamic> values,
  );
  Future<void> deleteTask(String coupleId, PlanTask task);
}

class SharedPlannerFailure implements Exception {
  const SharedPlannerFailure();
  String get message => 'We could not save that change. Refresh and try again.';
}
