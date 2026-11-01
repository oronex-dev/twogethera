import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/dashboard_preferences.dart';

final dashboardPreferencesRepositoryProvider =
    Provider<DashboardPreferencesRepository>((ref) {
      final repository = ref.watch(authRepositoryProvider);
      if (repository is DashboardPreferencesRepository) {
        return repository as DashboardPreferencesRepository;
      }
      throw const DashboardPreferencesFailure();
    });

class DashboardPreferencesState {
  const DashboardPreferencesState({
    this.userId,
    this.preferences = const DashboardPreferences(
      order: DashboardModule.values,
      visible: {
        DashboardModule.bucketList,
        DashboardModule.importantDates,
        DashboardModule.plans,
      },
    ),
    this.loading = false,
    this.saving = false,
    this.error,
  });

  final String? userId;
  final DashboardPreferences preferences;
  final bool loading;
  final bool saving;
  final String? error;
}

final dashboardPreferencesControllerProvider =
    NotifierProvider<DashboardPreferencesController, DashboardPreferencesState>(
      DashboardPreferencesController.new,
    );

class DashboardPreferencesController
    extends Notifier<DashboardPreferencesState> {
  @override
  DashboardPreferencesState build() => const DashboardPreferencesState();

  Future<void> load(String userId) async {
    state = DashboardPreferencesState(
      userId: userId,
      preferences: state.userId == userId
          ? state.preferences
          : DashboardPreferences.defaults(),
      loading: true,
    );
    try {
      final loaded = await ref
          .read(dashboardPreferencesRepositoryProvider)
          .loadDashboardPreferences(userId);
      if (state.userId != userId) return;
      state = DashboardPreferencesState(
        userId: userId,
        preferences: loaded ?? DashboardPreferences.defaults(),
      );
    } catch (_) {
      if (state.userId != userId) return;
      state = DashboardPreferencesState(
        userId: userId,
        preferences: DashboardPreferences.defaults(),
        error: 'Personalization could not be loaded. Try again.',
      );
    }
  }

  Future<bool> save(DashboardPreferences preferences) async {
    final userId = state.userId;
    if (userId == null || state.saving) return false;
    final previous = state.preferences;
    state = DashboardPreferencesState(
      userId: userId,
      preferences: preferences,
      saving: true,
    );
    try {
      await ref
          .read(dashboardPreferencesRepositoryProvider)
          .saveDashboardPreferences(userId, preferences);
      if (state.userId == userId) {
        state = DashboardPreferencesState(
          userId: userId,
          preferences: preferences,
        );
      }
      return true;
    } catch (_) {
      if (state.userId == userId) {
        state = DashboardPreferencesState(
          userId: userId,
          preferences: previous,
          error: 'Personalization could not be saved. Try again.',
        );
      }
      return false;
    }
  }
}
