import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/shared_planner_repository.dart';

class SharedPlannerState {
  const SharedPlannerState({
    this.coupleId,
    this.snapshot,
    this.loading = false,
    this.error,
  });

  final String? coupleId;
  final SharedPlannerSnapshot? snapshot;
  final bool loading;
  final String? error;

  SharedPlannerState copyWith({
    String? coupleId,
    SharedPlannerSnapshot? snapshot,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => SharedPlannerState(
    coupleId: coupleId ?? this.coupleId,
    snapshot: snapshot ?? this.snapshot,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
  );
}

final sharedPlannerControllerProvider =
    NotifierProvider<SharedPlannerController, SharedPlannerState>(
      SharedPlannerController.new,
    );

class SharedPlannerController extends Notifier<SharedPlannerState> {
  @override
  SharedPlannerState build() {
    ref.listen(authControllerProvider, (_, next) {
      final coupleId = state.coupleId;
      final stillPaired =
          next.phase == AuthPhase.authenticated &&
          next.context?.spaces.any(
                (space) => space.id == coupleId && space.state == 'paired',
              ) ==
              true;
      if (coupleId != null && !stillPaired) {
        state = const SharedPlannerState();
      }
    });
    return const SharedPlannerState();
  }

  bool _isPaired(String coupleId) {
    final auth = ref.read(authControllerProvider);
    return auth.phase == AuthPhase.authenticated &&
        auth.context?.spaces.any(
              (space) => space.id == coupleId && space.state == 'paired',
            ) ==
            true;
  }

  Future<void> load(String coupleId) async {
    if (!_isPaired(coupleId)) {
      state = const SharedPlannerState(
        loading: false,
        error: 'Link your partner before opening shared planner data.',
      );
      return;
    }
    state = SharedPlannerState(
      coupleId: coupleId,
      snapshot: state.coupleId == coupleId ? state.snapshot : null,
      loading: true,
    );
    try {
      final snapshot = await ref
          .read(sharedPlannerRepositoryProvider)
          .load(coupleId);
      if (!_isPaired(coupleId)) {
        state = const SharedPlannerState(
          error: 'Your shared planner is no longer available.',
        );
        return;
      }
      state = SharedPlannerState(coupleId: coupleId, snapshot: snapshot);
    } on SharedPlannerFailure {
      state = state.copyWith(
        loading: false,
        error: 'We could not load your shared planner. Try again.',
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'We could not load your shared planner. Try again.',
      );
    }
  }

  Future<bool> createBucket(Map<String, dynamic> values) => _mutate(
    (repository, coupleId) => repository.createBucketItem(coupleId, values),
  );

  Future<bool> updateBucket(BucketListItem item, Map<String, dynamic> values) =>
      _mutate(
        (repository, coupleId) =>
            repository.updateBucketItem(coupleId, item, values),
      );

  Future<bool> toggleBucket(BucketListItem item) =>
      updateBucket(item, {'is_completed': !item.completed});

  Future<bool> deleteBucket(BucketListItem item) => _mutate(
    (repository, coupleId) => repository.deleteBucketItem(coupleId, item),
  );

  Future<bool> createImportantDate(Map<String, dynamic> values) => _mutate(
    (repository, coupleId) => repository.createImportantDate(coupleId, values),
  );

  Future<bool> updateImportantDate(
    ImportantDateEntry entry,
    Map<String, dynamic> values,
  ) => _mutate(
    (repository, coupleId) =>
        repository.updateImportantDate(coupleId, entry, values),
  );

  Future<bool> deleteImportantDate(ImportantDateEntry entry) => _mutate(
    (repository, coupleId) => repository.deleteImportantDate(coupleId, entry),
  );

  Future<bool> createPlan(Map<String, dynamic> values) => _mutate(
    (repository, coupleId) => repository.createPlan(coupleId, values),
  );

  Future<bool> updatePlan(SharedPlan plan, Map<String, dynamic> values) =>
      _mutate(
        (repository, coupleId) => repository.updatePlan(coupleId, plan, values),
      );

  Future<bool> deletePlan(SharedPlan plan) =>
      _mutate((repository, coupleId) => repository.deletePlan(coupleId, plan));

  Future<bool> createTask(String planId, String title) => _mutate(
    (repository, coupleId) => repository.createTask(coupleId, planId, title),
  );

  Future<bool> toggleTask(PlanTask task) => _mutate(
    (repository, coupleId) => repository.updateTask(coupleId, task, {
      'is_completed': !task.completed,
    }),
  );

  Future<bool> renameTask(PlanTask task, String title) => _mutate(
    (repository, coupleId) =>
        repository.updateTask(coupleId, task, {'title': title}),
  );

  Future<bool> deleteTask(PlanTask task) =>
      _mutate((repository, coupleId) => repository.deleteTask(coupleId, task));

  Future<bool> _mutate(
    Future<void> Function(SharedPlannerRepository, String) operation,
  ) async {
    final coupleId = state.coupleId;
    if (coupleId == null || !_isPaired(coupleId)) {
      state = state.copyWith(
        error: 'Your shared planner is no longer available.',
      );
      return false;
    }
    try {
      await operation(ref.read(sharedPlannerRepositoryProvider), coupleId);
      await load(coupleId);
      return state.error == null;
    } on SharedPlannerFailure catch (failure) {
      state = state.copyWith(loading: false, error: failure.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'We could not save that change. Refresh and try again.',
      );
      return false;
    }
  }
}
