enum DashboardModule { bucketList, importantDates, plans }

extension DashboardModulePresentation on DashboardModule {
  String get label => switch (this) {
    DashboardModule.bucketList => 'Bucket list',
    DashboardModule.importantDates => 'Important dates',
    DashboardModule.plans => 'Upcoming plans',
  };

  String get storageKey => switch (this) {
    DashboardModule.bucketList => 'bucket_list',
    DashboardModule.importantDates => 'important_dates',
    DashboardModule.plans => 'plans',
  };

  static DashboardModule? fromStorageKey(String value) => switch (value) {
    'bucket_list' => DashboardModule.bucketList,
    'important_dates' => DashboardModule.importantDates,
    'plans' => DashboardModule.plans,
    _ => null,
  };
}

class DashboardPreferences {
  const DashboardPreferences({required this.order, required this.visible});

  factory DashboardPreferences.defaults() => const DashboardPreferences(
    order: DashboardModule.values,
    visible: {
      DashboardModule.bucketList,
      DashboardModule.importantDates,
      DashboardModule.plans,
    },
  );

  final List<DashboardModule> order;
  final Set<DashboardModule> visible;

  DashboardPreferences copyWith({
    List<DashboardModule>? order,
    Set<DashboardModule>? visible,
  }) => DashboardPreferences(
    order: List.unmodifiable(order ?? this.order),
    visible: Set.unmodifiable(visible ?? this.visible),
  );

  factory DashboardPreferences.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['module_order'];
    final rawVisible = json['visible_modules'];
    if (rawOrder is! List || rawVisible is! List) {
      return DashboardPreferences.defaults();
    }
    final order = rawOrder
        .whereType<String>()
        .map(DashboardModulePresentation.fromStorageKey)
        .whereType<DashboardModule>()
        .toSet();
    final visible = rawVisible
        .whereType<String>()
        .map(DashboardModulePresentation.fromStorageKey)
        .whereType<DashboardModule>()
        .toSet();
    for (final module in DashboardModule.values) {
      order.add(module);
    }
    return DashboardPreferences(
      order: List.unmodifiable(order),
      visible: Set.unmodifiable(visible),
    );
  }

  Map<String, dynamic> toJson() => {
    'module_order': order.map((module) => module.storageKey).toList(),
    'visible_modules': DashboardModule.values
        .where(visible.contains)
        .map((module) => module.storageKey)
        .toList(),
  };
}

abstract interface class DashboardPreferencesRepository {
  Future<DashboardPreferences?> loadDashboardPreferences(String userId);
  Future<void> saveDashboardPreferences(
    String userId,
    DashboardPreferences preferences,
  );
}

class DashboardPreferencesFailure implements Exception {
  const DashboardPreferencesFailure();
}
