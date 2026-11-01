import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twogethera/app/theme/app_theme.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/dashboard/domain/dashboard_preferences.dart';
import 'package:twogethera/features/dashboard/presentation/dashboard_screen.dart';
import 'package:twogethera/features/shared_planner/domain/shared_planner_repository.dart';
import 'package:twogethera/features/shared_planner/presentation/global_search_screen.dart';
import 'package:twogethera/features/shared_planner/presentation/shared_planner_screen.dart';

class _Cp008Repository
    implements
        AuthRepository,
        SharedPlannerRepository,
        DashboardPreferencesRepository {
  _Cp008Repository({this.paired = true});
  final bool paired;
  final events = StreamController<AuthSignal>.broadcast(sync: true);
  int plannerLoads = 0;
  DashboardPreferences? storedPreferences;

  final fixture = SharedPlannerSnapshot(
    bucketItems: const [
      BucketListItem(
        id: 'bucket-1',
        coupleId: 'couple-1',
        title: 'See the northern lights',
        description: 'Trip idea',
        category: PlannerBucketCategory.travel,
        completed: false,
        revision: 1,
      ),
    ],
    importantDates: [
      ImportantDateEntry(
        id: 'date-1',
        coupleId: 'couple-1',
        kind: ImportantDateKind.special,
        title: 'First dance',
        date: DateTime(2030, 6, 15),
        notes: 'Our song',
        annual: false,
        leapDayPolicy: null,
        revision: 1,
      ),
    ],
    plans: [
      SharedPlan(
        id: 'plan-1',
        coupleId: 'couple-1',
        title: 'Summer road trip',
        description: 'Coast drive',
        startsAt: DateTime(2030, 7, 1, 9),
        location: 'Coast',
        revision: 1,
        tasks: [
          PlanTask(
            id: 'task-1',
            coupleId: 'couple-1',
            planId: 'plan-1',
            title: 'Check passport',
            completed: false,
            revision: 1,
            sortOrder: 0,
          ),
        ],
      ),
    ],
  );

  @override
  Stream<AuthSignal> get changes => events.stream;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<AccountContext> accountContext() async => AccountContext(
    userId: 'user-1',
    spaces: paired
        ? const [SpaceContext(id: 'couple-1', state: 'paired', epoch: 1)]
        : const [],
  );
  @override
  Future<void> clearLocalSession() async {}
  @override
  Future<void> dispose() => events.close();

  @override
  Future<SharedPlannerSnapshot> load(String coupleId) async {
    plannerLoads++;
    return fixture;
  }

  @override
  Future<DashboardPreferences?> loadDashboardPreferences(String userId) async =>
      storedPreferences;

  @override
  Future<void> saveDashboardPreferences(
    String userId,
    DashboardPreferences preferences,
  ) async {
    storedPreferences = preferences;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('global search groups planner results and opens the exact task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Cp008Repository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await container.read(authControllerProvider.notifier).signIn('a', 'b');
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, _) => const GlobalSearchScreen()),
        GoRoute(
          path: '/planner',
          builder: (_, _) => const SharedPlannerScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Search across your shared ideas, dates, plans, and checklists.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'no matching item');
    await tester.pumpAndSettle();
    expect(find.textContaining('No matches for'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'passport');
    await tester.pumpAndSettle();
    expect(find.text('Checklist tasks'), findsOneWidget);
    expect(find.text('Check passport'), findsOneWidget);
    await tester.tap(find.text('Check passport'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/planner');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['type'],
      'task',
    );
    expect(find.text('Edit checklist task'), findsOneWidget);
    expect(find.byType(TextField).first, findsOneWidget);
    expect(repository.plannerLoads, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard module visibility and ordering save to the account repository',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Cp008Repository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      await container.read(authControllerProvider.notifier).signIn('a', 'b');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dashboard-module-bucket_list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dashboard-module-important_dates')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dashboard-module-plans')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Customize dashboard'));
      await tester.tap(find.text('Customize dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first); // hide bucket list
      await tester.tap(find.byTooltip('Move Upcoming plans up'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move Upcoming plans up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repository.storedPreferences, isNotNull);
      expect(
        repository.storedPreferences!.visible.contains(
          DashboardModule.bucketList,
        ),
        isFalse,
      );
      expect(repository.storedPreferences!.order.first, DashboardModule.plans);
      expect(
        await repository.loadDashboardPreferences('user-1'),
        repository.storedPreferences,
      );
      expect(
        find.byKey(const ValueKey('dashboard-module-bucket_list')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('dashboard-module-plans')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unpaired global search never loads planner data', (
    tester,
  ) async {
    final repository = _Cp008Repository(paired: false);
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    addTearDown(repository.dispose);
    await container.read(authControllerProvider.notifier).signIn('a', 'b');
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(path: '/search', builder: (_, _) => const GlobalSearchScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Link your partner to search shared planner data.'),
      findsOneWidget,
    );
    expect(repository.plannerLoads, 0);
    expect(tester.takeException(), isNull);
  });
}
