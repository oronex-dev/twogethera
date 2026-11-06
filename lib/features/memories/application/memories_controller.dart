import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/memory_models.dart';

final memoriesRepositoryProvider = Provider<MemoriesRepository>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  if (repository is MemoriesRepository) return repository as MemoriesRepository;
  throw StateError('Memories are unavailable.');
});

class MemoriesState {
  const MemoriesState({
    this.coupleId,
    this.snapshot,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
  });
  final String? coupleId;
  final MemoriesSnapshot? snapshot;
  final bool loading;
  final bool saving;
  final String? error;
  final String? notice;
}

final memoriesControllerProvider =
    NotifierProvider<MemoriesController, MemoriesState>(MemoriesController.new);

class MemoriesController extends Notifier<MemoriesState> {
  int _loadGeneration = 0;

  @override
  MemoriesState build() {
    ref.listen(authControllerProvider, (_, next) {
      final coupleId = state.coupleId;
      final stillPaired =
          next.phase == AuthPhase.authenticated &&
          next.context?.spaces.any(
                (space) => space.id == coupleId && space.state == 'paired',
              ) ==
              true;
      if (coupleId != null && !stillPaired) {
        _loadGeneration++;
        state = const MemoriesState();
      }
    });
    return const MemoriesState();
  }

  bool _paired(String id) {
    final auth = ref.read(authControllerProvider);
    return auth.phase == AuthPhase.authenticated &&
        auth.context?.spaces.any(
              (space) => space.id == id && space.state == 'paired',
            ) ==
            true;
  }

  Future<void> load(String coupleId) async {
    final generation = ++_loadGeneration;
    if (!_paired(coupleId)) {
      state = const MemoriesState(
        error: 'Link your partner before viewing shared memories.',
      );
      return;
    }
    state = MemoriesState(
      coupleId: coupleId,
      snapshot: state.coupleId == coupleId ? state.snapshot : null,
      loading: true,
    );
    try {
      final snapshot = await ref
          .read(memoriesRepositoryProvider)
          .loadMemories(coupleId);
      if (generation != _loadGeneration || !_paired(coupleId)) {
        if (generation != _loadGeneration) return;
        state = const MemoriesState(
          error: 'Shared memories are no longer available.',
        );
        return;
      }
      state = MemoriesState(coupleId: coupleId, snapshot: snapshot);
    } catch (_) {
      if (generation != _loadGeneration) return;
      if (state.coupleId == coupleId) {
        state = MemoriesState(
          coupleId: coupleId,
          snapshot: state.snapshot,
          error: 'We could not load memories. Check your connection and retry.',
        );
      }
    }
  }

  Future<bool> save(Map<String, dynamic> values, {String? memoryId}) => _mutate(
    (repository, coupleId) =>
        repository.saveMemory(coupleId, values, memoryId: memoryId),
    notice: memoryId == null ? 'Memory added.' : 'Memory updated.',
  );

  Future<bool> delete(CoupleMemory memory) => _mutate(
    (repository, coupleId) => repository.deleteMemory(coupleId, memory),
    notice: 'Memory and attached photos removed.',
  );

  Future<bool> toggleFavorite(CoupleMemory memory) => _mutate(
    (repository, coupleId) => repository.toggleFavorite(coupleId, memory),
    notice: memory.favorite ? 'Removed from favorites.' : 'Added to favorites.',
  );

  Future<bool> addPhotos(
    String memoryId,
    List<({Uint8List bytes, String contentType})> photos,
  ) => _mutate(
    (repository, coupleId) => repository.addPhotos(coupleId, memoryId, photos),
    notice: 'Photos added securely.',
  );

  Future<bool> removePhoto(MemoryPhoto photo) => _mutate(
    (repository, coupleId) => repository.removePhoto(coupleId, photo),
    notice: 'Photo removed.',
  );

  Future<bool> _mutate(
    Future<void> Function(MemoriesRepository, String) action, {
    required String notice,
  }) async {
    final coupleId = state.coupleId;
    if (coupleId == null || !_paired(coupleId) || state.saving) return false;
    state = MemoriesState(
      coupleId: coupleId,
      snapshot: state.snapshot,
      saving: true,
    );
    try {
      await action(ref.read(memoriesRepositoryProvider), coupleId);
      if (!_paired(coupleId)) return false;
      await load(coupleId);
      if (state.error != null) return false;
      state = MemoriesState(
        coupleId: coupleId,
        snapshot: state.snapshot,
        notice: notice,
      );
      return true;
    } catch (_) {
      if (state.coupleId == coupleId) {
        state = MemoriesState(
          coupleId: coupleId,
          snapshot: state.snapshot,
          error: 'We could not save that change. Try again.',
        );
      }
      return false;
    }
  }
}
