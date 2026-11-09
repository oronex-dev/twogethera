import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/shared_goal_models.dart';

final sharedGoalsRepositoryProvider = Provider<SharedGoalsRepository>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  if (repository is SharedGoalsRepository) {
    return repository as SharedGoalsRepository;
  }
  throw StateError('Shared goals are unavailable.');
});

class SharedGoalsState {
  const SharedGoalsState({
    this.coupleId,
    this.snapshot,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
  });
  final String? coupleId;
  final SharedGoalsSnapshot? snapshot;
  final bool loading;
  final bool saving;
  final String? error;
  final String? notice;
}

final sharedGoalsControllerProvider =
    NotifierProvider<SharedGoalsController, SharedGoalsState>(
      SharedGoalsController.new,
    );

class SharedGoalsController extends Notifier<SharedGoalsState> {
  int _generation = 0;
  @override
  SharedGoalsState build() {
    ref.listen(authControllerProvider, (_, next) {
      if (state.coupleId != null && !_paired(next, state.coupleId!)) {
        _generation++;
        state = const SharedGoalsState();
      }
    });
    return const SharedGoalsState();
  }

  bool _paired(AuthViewState auth, String id) =>
      auth.phase == AuthPhase.authenticated &&
      auth.context?.spaces.any((s) => s.id == id && s.state == 'paired') ==
          true;
  bool _allowed(String id) => _paired(ref.read(authControllerProvider), id);

  Future<void> load(String id) async {
    final generation = ++_generation;
    if (!_allowed(id)) {
      state = const SharedGoalsState(
        error: 'Link your partner to set shared goals.',
      );
      return;
    }
    state = SharedGoalsState(
      coupleId: id,
      snapshot: state.coupleId == id ? state.snapshot : null,
      loading: true,
    );
    try {
      final snapshot = await ref
          .read(sharedGoalsRepositoryProvider)
          .loadSharedGoals(id);
      if (generation != _generation || !_allowed(id)) return;
      state = SharedGoalsState(coupleId: id, snapshot: snapshot);
    } catch (_) {
      if (generation == _generation) {
        state = SharedGoalsState(
          coupleId: id,
          snapshot: state.snapshot,
          error: 'Shared goals could not be loaded. Check your connection and retry.',
        );
      }
    }
  }

  Future<bool> saveGoal(
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) => _mutate(
    (repo, couple) => repo.saveSharedGoal(
      couple,
      values,
      id: id,
      expectedRevision: expectedRevision,
    ),
    id == null ? 'Goal created.' : 'Goal updated.',
  );
  Future<bool> saveMilestone(
    String goalId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) => _mutate(
    (repo, couple) => repo.saveMilestone(
      couple,
      goalId,
      values,
      id: id,
      expectedRevision: expectedRevision,
    ),
    id == null ? 'Milestone added.' : 'Milestone updated.',
  );

  Future<bool> _mutate(
    Future<void> Function(SharedGoalsRepository, String) action,
    String notice,
  ) async {
    final id = state.coupleId;
    if (id == null || !_allowed(id) || state.saving) return false;
    state = SharedGoalsState(
      coupleId: id,
      snapshot: state.snapshot,
      saving: true,
    );
    try {
      await action(ref.read(sharedGoalsRepositoryProvider), id);
      if (!_allowed(id)) return false;
      await load(id);
      if (state.error != null) return false;
      state = SharedGoalsState(
        coupleId: id,
        snapshot: state.snapshot,
        notice: notice,
      );
      return true;
    } on SharedGoalRevisionConflict {
      if (_allowed(id)) {
        await load(id);
        state = SharedGoalsState(
          coupleId: id,
          snapshot: state.snapshot,
          error: 'This goal or milestone changed elsewhere. The latest version was loaded; review it and reapply your change.',
        );
      }
      return false;
    } catch (_) {
      state = SharedGoalsState(
        coupleId: id,
        snapshot: state.snapshot,
        error: 'The change could not be saved. Refresh and try again.',
      );
      return false;
    }
  }
}
