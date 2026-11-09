import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/app/twogethera_app.dart';
import 'package:twogethera/features/settings/presentation/settings_screen.dart';
import 'package:twogethera/app/theme/app_theme.dart';
import 'package:twogethera/app/theme/design_tokens.dart';
import 'package:twogethera/features/appearance/application/appearance_controller.dart';
import 'package:twogethera/features/appearance/domain/appearance_preferences.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';

class _AppearanceRepository implements AppearancePreferencesRepository {
  final values = <String, AppearancePreferences>{};
  final saves = <String>[];
  bool failSave = false;
  int loadFailures = 0;
  Completer<AppearancePreferences?>? pendingLoad;

  @override
  Future<AppearancePreferences?> loadAppearancePreferences(
    String userId,
  ) async {
    if (loadFailures > 0) {
      loadFailures--;
      throw const AppearancePreferencesFailure();
    }
    if (pendingLoad != null && userId == 'partner-b') {
      return pendingLoad!.future;
    }
    return values[userId];
  }

  @override
  Future<void> saveAppearancePreferences(
    String userId,
    AppearancePreferences preferences,
  ) async {
    if (failSave) throw const AppearancePreferencesFailure();
    values[userId] = preferences;
    saves.add(userId);
  }
}

class _AuthenticatedAppearanceController extends AuthController {
  @override
  AuthViewState build() => const AuthViewState(
    AuthPhase.authenticated,
    context: AccountContext(userId: 'partner-b', spaces: []),
  );
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final brightest = a > b ? a : b;
  final darkest = a > b ? b : a;
  return (brightest + .05) / (darkest + .05);
}

void main() {
  test('six curated themes define readable light and dark palettes', () {
    expect(TwogetheraTheme.values, hasLength(6));
    for (final theme in TwogetheraTheme.values) {
      for (final brightness in Brightness.values) {
        final preferences = AppearancePreferences(theme: theme);
        final data = brightness == Brightness.dark
            ? AppTheme.dark(preferences)
            : AppTheme.light(preferences);
        final brand = data.extension<BrandColors>();
        expect(brand, isNotNull, reason: theme.label);
        expect(
          _contrast(data.colorScheme.onSurface, data.colorScheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.label} $brightness text/surface contrast',
        );
        expect(
          _contrast(data.colorScheme.onPrimary, data.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.label} $brightness button contrast',
        );
        expect(
          _contrast(data.colorScheme.onSecondary, data.colorScheme.secondary),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.label} $brightness secondary contrast',
        );
        expect(
          _contrast(data.colorScheme.onTertiary, data.colorScheme.tertiary),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.label} $brightness accent contrast',
        );
        expect(brand!.border, isNot(brand.canvas));
      }
    }
  });

  test('custom HEX validation and preference serialization are strict', () {
    expect(parseHexColor('#AABBCC'), const Color(0xFFAABBCC));
    expect(parseHexColor('aabbcc'), const Color(0xFFAABBCC));
    expect(parseHexColor('#abc'), isNull);
    expect(parseHexColor('#GGCC00'), isNull);
    expect(parseHexColor('##AABBCC'), isNull);

    const preferences = AppearancePreferences(
      mode: ThemeMode.dark,
      theme: TwogetheraTheme.oceanBlue,
      customHex: '#20A0D0',
      fontSize: PersonalFontSize.large,
      gradientPreset: GradientPreset.custom,
      gradientStartHex: '#F0D7E4',
      gradientEndHex: '#CFC7EA',
      gradientDirection: GradientDirection.horizontal,
    );
    expect(
      AppearancePreferences.fromJson(preferences.toJson()).toJson(),
      preferences.toJson(),
    );
  });

  test('custom accent coordinates semantic palette colors and reset restores theme', () {
    final rose = AppearancePalettes.forTheme(
      TwogetheraTheme.roseGold,
      Brightness.light,
    );
    final custom = AppearancePalettes.withCustomPrimary(
      rose,
      const Color(0xFF147D9C),
      Brightness.light,
    );
    expect(custom.primary, const Color(0xFF147D9C));
    expect(custom.secondary, isNot(rose.secondary));
    expect(custom.accent, isNot(rose.accent));
    expect(custom.heroStart, isNot(rose.heroStart));
  });

  test(
    'custom gradients and font scale apply without changing text contrast',
    () {
      const preferences = AppearancePreferences(
        gradientPreset: GradientPreset.custom,
        gradientStartHex: '#E8C5D1',
        gradientEndHex: '#BDB3E8',
        gradientDirection: GradientDirection.vertical,
        fontSize: PersonalFontSize.large,
      );
      final theme = AppTheme.light(preferences);
      final brand = theme.extension<BrandColors>()!;
      expect(brand.heroStart, const Color(0xFFE8C5D1));
      expect(brand.heroEnd, const Color(0xFFBDB3E8));
      expect(brand.heroBegin, Alignment.topCenter);
      expect(brand.heroFinish, Alignment.bottomCenter);
      expect(
        theme.textTheme.bodyLarge!.fontSize,
        closeTo(AppTheme.light().textTheme.bodyLarge!.fontSize! * 1.12, .01),
      );
      expect(
        _contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  test(
    'appearance changes persist per account and remain independent',
    () async {
      final repository = _AppearanceRepository()
        ..values['partner-a'] = const AppearancePreferences(
          mode: ThemeMode.light,
          theme: TwogetheraTheme.roseGold,
        )
        ..values['partner-b'] = const AppearancePreferences(
          mode: ThemeMode.dark,
          theme: TwogetheraTheme.midnightSlate,
        );
      final container = ProviderContainer(
        overrides: [
          appearancePreferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appearanceControllerProvider.notifier);

      await controller.load('partner-a');
      expect(
        container.read(appearanceControllerProvider).preferences.theme,
        TwogetheraTheme.roseGold,
      );
      await controller.selectTheme(TwogetheraTheme.emerald);
      await controller.setMode(ThemeMode.light);

      controller.clearAccount();
      await controller.load('partner-b');
      expect(
        container.read(appearanceControllerProvider).preferences.theme,
        TwogetheraTheme.midnightSlate,
      );
      expect(
        container.read(appearanceControllerProvider).preferences.mode,
        ThemeMode.dark,
      );
      await controller.applyCustomColor(const Color(0xFF6952A3));
      await controller.setFontSize(PersonalFontSize.large);
      await controller.applyCustomGradient(
        start: const Color(0xFFE8C5D1),
        end: const Color(0xFFBDB3E8),
        direction: GradientDirection.vertical,
      );

      expect(repository.values['partner-a']?.theme, TwogetheraTheme.emerald);
      expect(repository.values['partner-a']?.customHex, isNull);
      expect(
        repository.values['partner-a']?.fontSize,
        PersonalFontSize.defaultSize,
      );
      expect(
        repository.values['partner-b']?.theme,
        TwogetheraTheme.midnightSlate,
      );
      expect(repository.values['partner-b']?.customHex, '#6952A3');
      expect(repository.values['partner-b']?.fontSize, PersonalFontSize.large);
      expect(repository.values['partner-b']?.gradientStartHex, '#E8C5D1');
      expect(
        repository.values['partner-b']?.gradientDirection,
        GradientDirection.vertical,
      );
      expect(repository.saves, [
        'partner-a',
        'partner-a',
        'partner-b',
        'partner-b',
        'partner-b',
      ]);
    },
  );

  test('failed save rolls back without losing the stored choice', () async {
    final repository = _AppearanceRepository()
      ..values['owner'] = const AppearancePreferences(
        theme: TwogetheraTheme.champagne,
      );
    final container = ProviderContainer(
      overrides: [
        appearancePreferencesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appearanceControllerProvider.notifier);
    await controller.load('owner');
    repository.failSave = true;

    expect(await controller.selectTheme(TwogetheraTheme.amethyst), isFalse);
    expect(
      container.read(appearanceControllerProvider).preferences.theme,
      TwogetheraTheme.champagne,
    );
    expect(
      container.read(appearanceControllerProvider).error,
      contains('could not be saved'),
    );
  });

  test(
    'load failure keeps owner identity, blocks writes, and retries',
    () async {
      final repository = _AppearanceRepository()
        ..values['owner'] = const AppearancePreferences(
          mode: ThemeMode.dark,
          theme: TwogetheraTheme.oceanBlue,
        )
        ..loadFailures = 1;
      final container = ProviderContainer(
        overrides: [
          appearancePreferencesRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appearanceControllerProvider.notifier);

      await controller.load('owner');
      var state = container.read(appearanceControllerProvider);
      expect(state.userId, 'owner');
      expect(state.loaded, isFalse);
      expect(state.error, contains('could not be loaded'));
      expect(await controller.selectTheme(TwogetheraTheme.emerald), isFalse);
      expect(repository.saves, isEmpty);

      await controller.load('owner', force: true);
      state = container.read(appearanceControllerProvider);
      expect(state.userId, 'owner');
      expect(state.loaded, isTrue);
      expect(state.preferences.theme, TwogetheraTheme.oceanBlue);
      expect(state.preferences.mode, ThemeMode.dark);
      expect(repository.saves, isEmpty);
    },
  );

  testWidgets(
    'account switch shows neutral loading until that account theme is loaded',
    (tester) async {
      final repository = _AppearanceRepository()
        ..values['partner-a'] = const AppearancePreferences(
          theme: TwogetheraTheme.emerald,
          mode: ThemeMode.dark,
        )
        ..pendingLoad = Completer<AppearancePreferences?>();
      final container = ProviderContainer(
        overrides: [
          appearancePreferencesRepositoryProvider.overrideWithValue(repository),
          authControllerProvider.overrideWith(
            _AuthenticatedAppearanceController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(appearanceControllerProvider.notifier)
          .load('partner-a');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TwogetheraApp(),
        ),
      );
      await tester.pump();
      expect(find.text('Loading your personal appearance…'), findsOneWidget);
      expect(find.text('Your shared space'), findsNothing);

      repository.pendingLoad!.complete(
        const AppearancePreferences(
          theme: TwogetheraTheme.midnightSlate,
          mode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Loading your personal appearance…'), findsNothing);
      expect(find.text('Your shared space'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('Your shared space')))
            .colorScheme
            .primary,
        AppearancePalettes.forTheme(
          TwogetheraTheme.midnightSlate,
          Brightness.dark,
        ).primary,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings retry reloads preferences for the signed-in owner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _AppearanceRepository()
      ..values['owner'] = const AppearancePreferences(
        theme: TwogetheraTheme.amethyst,
      )
      ..loadFailures = 1;
    final container = ProviderContainer(
      overrides: [
        appearancePreferencesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appearanceControllerProvider.notifier).load('owner');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Your appearance is personal to your account and follows you across devices.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Appearance could not be loaded. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Appearance could not be loaded. Try again.'),
      findsNothing,
    );
    expect(
      container.read(appearanceControllerProvider).preferences.theme,
      TwogetheraTheme.amethyst,
    );
    expect(repository.saves, isEmpty);
  });

  testWidgets(
    'HEX preview validates first and applies only after confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          appearancePreferencesRepositoryProvider.overrideWithValue(
            _AppearanceRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      Widget app() => UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            final appearance = ref.watch(appearanceControllerProvider);
            return MaterialApp(
              theme: AppTheme.light(appearance.preferences),
              darkTheme: AppTheme.dark(appearance.preferences),
              themeMode: appearance.preferences.mode,
              home: const Scaffold(body: SettingsScreen()),
            );
          },
        ),
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final initialPrimary = Theme.of(
        tester.element(find.text('Make yourself at home')),
      ).colorScheme.primary;
      await tester.enterText(find.byType(TextField), '#XYZ');
      await tester.ensureVisible(find.text('Preview color'));
      await tester.tap(find.text('Preview color'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a valid HEX color'), findsOneWidget);
      expect(find.text('Preview · not applied'), findsNothing);

      await tester.enterText(find.byType(TextField), '#12AB34');
      await tester.ensureVisible(find.text('Preview color'));
      await tester.tap(find.text('Preview color'));
      await tester.pumpAndSettle();
      expect(find.text('Preview · not applied'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text('Make yourself at home')))
            .colorScheme
            .primary,
        initialPrimary,
      );

      await tester.ensureVisible(find.text('Apply color'));
      await tester.tap(find.text('Apply color'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Make yourself at home')))
            .colorScheme
            .primary,
        const Color(0xFF12AB34),
      );
      await tester.ensureVisible(find.text('Reset to Rose Gold'));
      await tester.tap(find.text('Reset to Rose Gold'));
      await tester.pumpAndSettle();
      expect(
        container.read(appearanceControllerProvider).preferences.customHex,
        isNull,
      );
    },
  );

  testWidgets('swatches, gradient presets, and personal font size persist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _AppearanceRepository();
    final container = ProviderContainer(
      overrides: [
        appearancePreferencesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appearanceControllerProvider.notifier).load('owner');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light(
              ref.watch(appearanceControllerProvider).preferences,
            ),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('Ocean'));
    await tester.tap(find.byTooltip('Ocean'));
    await tester.pumpAndSettle();
    expect(find.text('Preview · not applied'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply color'));
    await tester.tap(find.text('Apply color'));
    await tester.pumpAndSettle();
    expect(repository.values['owner']?.customHex, '#356B8C');

    await tester.ensureVisible(find.text('Ocean mist'));
    await tester.tap(find.text('Ocean mist'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Vertical'));
    await tester.tap(find.text('Vertical'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply gradient'));
    await tester.tap(find.text('Apply gradient'));
    await tester.pumpAndSettle();
    expect(
      repository.values['owner']?.gradientPreset,
      GradientPreset.oceanMist,
    );
    expect(
      repository.values['owner']?.gradientDirection,
      GradientDirection.vertical,
    );

    await tester.ensureVisible(find.text('Large'));
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();
    expect(repository.values['owner']?.fontSize, PersonalFontSize.large);
    expect(tester.takeException(), isNull);
  });
}
