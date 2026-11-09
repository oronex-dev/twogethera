import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/appearance_preferences.dart';

final appearancePreferencesRepositoryProvider =
    Provider<AppearancePreferencesRepository>((ref) {
      final repository = ref.watch(authRepositoryProvider);
      if (repository is AppearancePreferencesRepository) {
        return repository as AppearancePreferencesRepository;
      }
      return const _UnavailableAppearancePreferencesRepository();
    });

class _UnavailableAppearancePreferencesRepository
    implements AppearancePreferencesRepository {
  const _UnavailableAppearancePreferencesRepository();

  @override
  Future<AppearancePreferences?> loadAppearancePreferences(
    String userId,
  ) async => null;

  @override
  Future<void> saveAppearancePreferences(
    String userId,
    AppearancePreferences preferences,
  ) async {}
}

class AppearanceState {
  const AppearanceState({
    this.userId,
    this.preferences = const AppearancePreferences(),
    this.loaded = false,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
  });

  final String? userId;
  final AppearancePreferences preferences;
  final bool loaded;
  final bool loading;
  final bool saving;
  final String? error;
  final String? notice;
}

final appearanceControllerProvider =
    NotifierProvider<AppearanceController, AppearanceState>(
      AppearanceController.new,
    );

final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(
    appearanceControllerProvider.select((state) => state.preferences.mode),
  ),
);

class AppearanceController extends Notifier<AppearanceState> {
  int _generation = 0;
  String? _attemptedUserId;

  @override
  AppearanceState build() => const AppearanceState();

  Future<void> load(String userId, {bool force = false}) async {
    if (_attemptedUserId == userId && !force) return;
    _attemptedUserId = userId;
    final generation = ++_generation;
    final previousPreferences = state.userId == userId
        ? state.preferences
        : const AppearancePreferences();
    state = AppearanceState(
      userId: userId,
      preferences: previousPreferences,
      loading: true,
    );
    try {
      final saved = await ref
          .read(appearancePreferencesRepositoryProvider)
          .loadAppearancePreferences(userId);
      if (generation != _generation || state.userId != userId) return;
      state = AppearanceState(
        userId: userId,
        preferences: saved ?? const AppearancePreferences(),
        loaded: true,
      );
    } catch (_) {
      if (generation != _generation || state.userId != userId) return;
      state = AppearanceState(
        userId: userId,
        preferences: previousPreferences,
        error: 'Appearance could not be loaded. Try again.',
      );
    }
  }

  void clearAccount() {
    _generation++;
    _attemptedUserId = null;
    state = const AppearanceState();
  }

  Future<bool> setMode(ThemeMode mode) => _update(
    state.preferences.copyWith(mode: mode),
    notice: 'Appearance updated.',
  );

  Future<bool> selectTheme(TwogetheraTheme theme) => _update(
    state.preferences.copyWith(theme: theme, clearCustomHex: true),
    notice: '${theme.label} selected.',
  );

  Future<bool> applyCustomColor(Color color) {
    final hex =
        '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    return _update(
      state.preferences.copyWith(customHex: hex),
      notice: 'Custom color applied.',
    );
  }

  Future<bool> resetCustomColor() => _update(
    state.preferences.copyWith(clearCustomHex: true),
    notice: '${state.preferences.theme.label} palette restored.',
  );

  Future<bool> setFontSize(PersonalFontSize size) => _update(
    state.preferences.copyWith(fontSize: size),
    notice: '${size.label} text size selected.',
  );

  Future<bool> selectGradientPreset(
    GradientPreset preset, {
    GradientDirection? direction,
  }) => _update(
    state.preferences.copyWith(
      gradientPreset: preset,
      gradientDirection: direction,
      clearGradientColors: true,
    ),
    notice: '${preset.label} gradient selected.',
  );

  Future<bool> applyCustomGradient({
    required Color start,
    required Color end,
    required GradientDirection direction,
  }) => _update(
    state.preferences.copyWith(
      gradientPreset: GradientPreset.custom,
      gradientStartHex: _hex(start),
      gradientEndHex: _hex(end),
      gradientDirection: direction,
    ),
    notice: 'Custom gradient applied.',
  );

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Future<bool> _update(
    AppearancePreferences next, {
    required String notice,
  }) async {
    final current = state;
    if (current.saving ||
        current.loading ||
        (current.userId != null && !current.loaded)) {
      return false;
    }
    if (current.userId == null) {
      state = AppearanceState(
        preferences: next,
        notice: 'Sign in to save this appearance across your devices.',
      );
      return true;
    }
    final userId = current.userId!;
    state = AppearanceState(
      userId: userId,
      preferences: next,
      loaded: true,
      saving: true,
    );
    try {
      await ref
          .read(appearancePreferencesRepositoryProvider)
          .saveAppearancePreferences(userId, next);
      if (state.userId != userId) return false;
      state = AppearanceState(
        userId: userId,
        preferences: next,
        loaded: true,
        notice: notice,
      );
      return true;
    } catch (_) {
      if (state.userId == userId) {
        state = AppearanceState(
          userId: userId,
          preferences: current.preferences,
          loaded: true,
          error: 'Appearance could not be saved. Try again.',
        );
      }
      return false;
    }
  }
}
