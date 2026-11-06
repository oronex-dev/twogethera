import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/budget/application/budget_controller.dart';
import 'package:twogethera/features/budget/domain/budget_models.dart';
import 'package:twogethera/features/budget/presentation/budget_screen.dart';
import 'package:twogethera/features/memories/application/memories_controller.dart';
import 'package:twogethera/features/memories/domain/memory_models.dart';
import 'package:twogethera/features/memories/presentation/memories_screen.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.paired);
  final bool paired;

  @override
  AuthViewState build() => AuthViewState(
    AuthPhase.authenticated,
    context: AccountContext(
      userId: 'synthetic-user',
      spaces: paired
          ? const [
              SpaceContext(id: 'synthetic-couple', state: 'paired', epoch: 1),
            ]
          : const [],
    ),
  );
}

class _BudgetRepo implements BudgetRepository {
  int loads = 0;
  bool failNext = false;
  @override
  Future<BudgetSnapshot> loadBudget(String coupleId, DateTime month) async {
    loads++;
    if (failNext) {
      failNext = false;
      throw StateError('synthetic network failure');
    }
    return const BudgetSnapshot(
      budget: null,
      expenses: [],
      recurringRules: [],
      members: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoriesRepo implements MemoriesRepository {
  int loads = 0;
  bool failNext = false;
  @override
  Future<MemoriesSnapshot> loadMemories(String coupleId) async {
    loads++;
    if (failNext) {
      failNext = false;
      throw StateError('synthetic network failure');
    }
    return const MemoriesSnapshot(memories: [], importantDates: []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('unpaired budget and memories stay gated at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final budgets = _BudgetRepo();
      final memories = _MemoriesRepo();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _FixedAuth(false)),
          budgetRepositoryProvider.overrideWithValue(budgets),
          memoriesRepositoryProvider.overrideWithValue(memories),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: BudgetScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Budget is shared'), findsOneWidget);
      expect(budgets.loads, 0);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MemoriesScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Memories are shared'), findsOneWidget);
      expect(memories.loads, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paired users see empty budget and memory states after loading', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final budgets = _BudgetRepo();
    final memories = _MemoriesRepo();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _FixedAuth(true)),
        budgetRepositoryProvider.overrideWithValue(budgets),
        memoriesRepositoryProvider.overrideWithValue(memories),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BudgetScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start with a monthly budget'), findsOneWidget);
    expect(budgets.loads, 1);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MemoriesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your timeline starts with a moment.'), findsOneWidget);
    expect(memories.loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both features show retryable load errors', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final budgets = _BudgetRepo()..failNext = true;
    final memories = _MemoriesRepo()..failNext = true;
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _FixedAuth(true)),
        budgetRepositoryProvider.overrideWithValue(budgets),
        memoriesRepositoryProvider.overrideWithValue(memories),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BudgetScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('We could not load shared expenses'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Start with a monthly budget'), findsOneWidget);
    expect(budgets.loads, 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MemoriesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('We could not load memories'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Your timeline starts with a moment.'), findsOneWidget);
    expect(memories.loads, 2);
    expect(tester.takeException(), isNull);
  });
}
