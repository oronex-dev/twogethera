import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/date_night_models.dart';

final dateNightRepositoryProvider = Provider<DateNightRepository>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  if (repository is DateNightRepository) {
    return repository as DateNightRepository;
  }
  throw StateError('Date night planning is unavailable.');
});

class DateNightsState {
  const DateNightsState({
    this.coupleId,
    this.snapshot,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
  });
  final String? coupleId;
  final DateNightSnapshot? snapshot;
  final bool loading;
  final bool saving;
  final String? error;
  final String? notice;
}

final dateNightsControllerProvider =
    NotifierProvider<DateNightsController, DateNightsState>(
      DateNightsController.new,
    );

class DateNightsController extends Notifier<DateNightsState> {
  int _generation = 0;
  @override
  DateNightsState build() {
    ref.listen(authControllerProvider, (_, next) {
      if (state.coupleId != null && !_paired(next, state.coupleId!)) {
        _generation++;
        state = const DateNightsState();
      }
    });
    return const DateNightsState();
  }

  bool _paired(AuthViewState auth, String id) =>
      auth.phase == AuthPhase.authenticated &&
      auth.context?.spaces.any((s) => s.id == id && s.state == 'paired') ==
          true;
  bool _allowed(String id) => _paired(ref.read(authControllerProvider), id);

  Future<void> load(String id) async {
    final generation = ++_generation;
    if (!_allowed(id)) {
      state = const DateNightsState(
        error: 'Link your partner to plan date nights together.',
      );
      return;
    }
    state = DateNightsState(
      coupleId: id,
      snapshot: state.coupleId == id ? state.snapshot : null,
      loading: true,
    );
    try {
      final snapshot = await ref
          .read(dateNightRepositoryProvider)
          .loadDateNights(id);
      if (generation != _generation || !_allowed(id)) return;
      state = DateNightsState(coupleId: id, snapshot: snapshot);
    } catch (_) {
      if (generation == _generation) {
        state = DateNightsState(
          coupleId: id,
          snapshot: state.snapshot,
          error: 'Date nights could not be loaded. Check your connection and retry.',
        );
      }
    }
  }

  Future<bool> save(
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) => _mutate(
    (repo, couple) => repo.saveDateNight(
      couple,
      values,
      id: id,
      expectedRevision: expectedRevision,
    ),
    id == null ? 'Idea saved.' : 'Date night updated.',
  );
  Future<bool> vote(String ideaId, String response) => _mutate(
    (repo, couple) => repo.saveDateNightVote(couple, ideaId, response),
    'Your response was saved.',
  );

  Future<bool> _mutate(
    Future<void> Function(DateNightRepository, String) action,
    String notice,
  ) async {
    final id = state.coupleId;
    if (id == null || !_allowed(id) || state.saving) return false;
    state = DateNightsState(
      coupleId: id,
      snapshot: state.snapshot,
      saving: true,
    );
    try {
      await action(ref.read(dateNightRepositoryProvider), id);
      if (!_allowed(id)) return false;
      await load(id);
      if (state.error != null) return false;
      state = DateNightsState(
        coupleId: id,
        snapshot: state.snapshot,
        notice: notice,
      );
      return true;
    } on DateNightRevisionConflict {
      if (_allowed(id)) {
        await load(id);
        state = DateNightsState(
          coupleId: id,
          snapshot: state.snapshot,
          error: 'This idea changed elsewhere. The latest version was loaded; review it and reapply your change.',
        );
      }
      return false;
    } catch (_) {
      state = DateNightsState(
        coupleId: id,
        snapshot: state.snapshot,
        error: 'The change could not be saved. Refresh and try again.',
      );
      return false;
    }
  }
}
