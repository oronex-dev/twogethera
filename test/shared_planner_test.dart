import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/shared_planner/domain/shared_planner_repository.dart';
import 'package:twogethera/features/shared_planner/presentation/shared_planner_screen.dart';

class _PlannerAuth implements AuthRepository {
  _PlannerAuth(this.context);
  final AccountContext context;
  final _events = StreamController<AuthSignal>.broadcast(sync: true);

  @override
  Stream<AuthSignal> get changes => _events.stream;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<AccountContext> accountContext() async => context;
  @override
  Future<void> clearLocalSession() async {}
  @override
  Future<void> dispose() => _events.close();
}

class _PlannerRepository implements SharedPlannerRepository {
  int loadCalls = 0;
  bool failNextLoad = false;
  SharedPlannerSnapshot snapshot = const SharedPlannerSnapshot(
    bucketItems: [],
    importantDates: [],
    plans: [],
  );

  @override
  Future<SharedPlannerSnapshot> load(String coupleId) async {
    loadCalls++;
    if (failNextLoad) {
      failNextLoad = false;
      throw const SharedPlannerFailure();
    }
    return snapshot;
  }

  @override
  Future<void> createBucketItem(
    String coupleId,
    Map<String, dynamic> values,
  ) async {
    snapshot = SharedPlannerSnapshot(
      bucketItems: [
        ...snapshot.bucketItems,
        BucketListItem(
          id: 'item-${snapshot.bucketItems.length}',
          coupleId: coupleId,
          title: values['title'] as String,
          description: values['description'] as String,
          category: PlannerBucketCategory.values.byName(
            values['category_key'] as String,
          ),
          completed: false,
          revision: 1,
          targetDate: null,
        ),
      ],
      importantDates: snapshot.importantDates,
      plans: snapshot.plans,
    );
  }

  @override
  Future<void> updateBucketItem(
    String coupleId,
    BucketListItem item,
    Map<String, dynamic> values,
  ) async {
    snapshot = SharedPlannerSnapshot(
      bucketItems: [
        for (final current in snapshot.bucketItems)
          if (current.id == item.id)
            BucketListItem(
              id: current.id,
              coupleId: current.coupleId,
              title: values['title'] as String? ?? current.title,
              description:
                  values['description'] as String? ?? current.description,
              category: values['category_key'] == null
                  ? current.category
                  : PlannerBucketCategory.values.byName(
                      values['category_key'] as String,
                    ),
              completed: values['is_completed'] as bool? ?? current.completed,
              revision: current.revision + 1,
              targetDate: current.targetDate,
            )
          else
            current,
      ],
      importantDates: snapshot.importantDates,
      plans: snapshot.plans,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('annual leap-day choices produce the selected next occurrence', () {
    final base = ImportantDateEntry(
      id: 'date',
      coupleId: 'couple',
      kind: ImportantDateKind.anniversary,
      title: 'Anniversary',
      date: DateTime(2024, 2, 29),
      notes: '',
      annual: true,
      leapDayPolicy: AnnualLeapDayPolicy.feb28,
      revision: 1,
    );
    expect(base.nextOccurrence(DateTime(2027, 1, 1)), DateTime(2027, 2, 28));
    final skip = ImportantDateEntry(
      id: 'date',
      coupleId: 'couple',
      kind: ImportantDateKind.anniversary,
      title: 'Anniversary',
      date: DateTime(2024, 2, 29),
      notes: '',
      annual: true,
      leapDayPolicy: AnnualLeapDayPolicy.skip,
      revision: 1,
    );
    expect(skip.nextOccurrence(DateTime(2027, 1, 1)), DateTime(2028, 2, 29));
  });

  testWidgets('unpaired screen never reads planner repository', (tester) async {
    final auth = _PlannerAuth(
      const AccountContext(userId: 'unpaired', spaces: []),
    );
    final planner = _PlannerRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sharedPlannerRepositoryProvider.overrideWithValue(planner),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SharedPlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No planner data has been loaded.'), findsOneWidget);
    expect(find.text('Link with your partner'), findsOneWidget);
    expect(planner.loadCalls, 0);
  });

  testWidgets(
    'paired screen loads remote planner and shows all three empty states',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _PlannerAuth(
        const AccountContext(
          userId: 'paired',
          spaces: [SpaceContext(id: 'couple', state: 'paired', epoch: 2)],
        ),
      );
      final planner = _PlannerRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sharedPlannerRepositoryProvider.overrideWithValue(planner),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(auth.dispose);
      await container
          .read(authControllerProvider.notifier)
          .signIn('partner@example.invalid', 'synthetic-password');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SharedPlannerScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(planner.loadCalls, 1);
      expect(find.text('Things to do together'), findsOneWidget);
      expect(find.text('A list with room to dream'), findsOneWidget);
      await tester.tap(find.text('Important dates'));
      await tester.pumpAndSettle();
      expect(find.text('Keep a moment close'), findsOneWidget);
      await tester.ensureVisible(find.text('Plans & calendar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plans & calendar'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing on the calendar yet'), findsOneWidget);
      await tester.ensureVisible(find.text('Bucket list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bucket list'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add an idea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an idea'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Walk at sunrise');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Walk at sunrise'), findsOneWidget);
      expect(find.text('0 of 1 done'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 done'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final width in [320.0, 800.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpAndSettle();
        expect(find.text('Walk at sunrise'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('planner displays an error and recovers on retry', (
    tester,
  ) async {
    final auth = _PlannerAuth(
      const AccountContext(
        userId: 'paired',
        spaces: [SpaceContext(id: 'couple', state: 'paired', epoch: 2)],
      ),
    );
    final planner = _PlannerRepository()..failNextLoad = true;
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sharedPlannerRepositoryProvider.overrideWithValue(planner),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);
    await container
        .read(authControllerProvider.notifier)
        .signIn('partner@example.invalid', 'synthetic-password');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SharedPlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('We could not load your shared planner. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('A list with room to dream'), findsOneWidget);
    expect(planner.loadCalls, 2);
    expect(tester.takeException(), isNull);
  });
}
