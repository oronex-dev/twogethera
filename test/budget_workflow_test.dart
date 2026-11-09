import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/budget/application/budget_controller.dart';
import 'package:twogethera/features/budget/domain/budget_models.dart';
import 'package:twogethera/features/budget/presentation/budget_screen.dart';

class _PairedAuth extends AuthController {
  @override
  AuthViewState build() => const AuthViewState(
    AuthPhase.authenticated,
    context: AccountContext(
      userId: 'member-a',
      spaces: [SpaceContext(id: 'test-couple', state: 'paired', epoch: 1)],
    ),
  );
}

class _BudgetRepo implements BudgetRepository {
  _BudgetRepo({this.failExpense = false}) {
    final currency = CurrencyUnit.byCode('USD')!;
    snapshot = BudgetSnapshot(
      budget: CoupleBudget(
        id: 'budget-current',
        coupleId: 'test-couple',
        monthStart: DateTime(DateTime.now().year, DateTime.now().month),
        currency: currency,
        limitMinor: 50000,
        revision: 1,
        categoryLimits: const {},
      ),
      expenses: const [],
      recurringRules: const [],
      members: const [
        BudgetMember(userId: 'member-a', label: 'You', seat: 1),
        BudgetMember(userId: 'member-b', label: 'Partner 2', seat: 2),
      ],
    );
  }

  late BudgetSnapshot snapshot;
  final bool failExpense;
  Map<String, dynamic>? savedExpense;
  int loads = 0;

  @override
  Future<BudgetSnapshot> loadBudget(String coupleId, DateTime month) async {
    loads++;
    return snapshot;
  }

  @override
  Future<void> saveExpense(
    String coupleId,
    String budgetId,
    CurrencyUnit currency,
    Map<String, dynamic> values, {
    String? expenseId,
    int? expectedRevision,
  }) async {
    if (failExpense) {
      throw BudgetOperationFailure.fromPostgresCode('23514');
    }
    savedExpense = Map.of(values);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('expense form reaches the repository with exact minor units', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _BudgetRepo();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _PairedAuth()),
        budgetRepositoryProvider.overrideWithValue(repository),
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
    await tester.ensureVisible(find.text('Add expense'));
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog).last,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Dinner');
    await tester.enterText(fields.at(2), '12.34');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(repository.savedExpense?['amount_minor'], 1234);
    expect(repository.savedExpense?['split_a_minor'], 617);
    expect(repository.savedExpense?['split_b_minor'], 617);
    expect(repository.loads, greaterThanOrEqualTo(2));
    expect(find.text('Expense saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense database validation errors are actionable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _BudgetRepo(failExpense: true);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(() => _PairedAuth()),
        budgetRepositoryProvider.overrideWithValue(repository),
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
    await tester.ensureVisible(find.text('Add expense'));
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog).last,
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Dinner');
    await tester.enterText(fields.at(2), '12.34');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Check the amount, currency, date, and split'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('recurring schedule dialog is scrollable at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _BudgetRepo();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _PairedAuth()),
          budgetRepositoryProvider.overrideWithValue(repository),
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
      final recurringAction = find.widgetWithText(
        OutlinedButton,
        'Recurring expense',
      );
      await tester.ensureVisible(recurringAction);
      await tester.tap(recurringAction);
      await tester.pumpAndSettle();

      expect(find.text('Recurring expense schedule'), findsOneWidget);
      expect(find.textContaining('Dates use the start date'), findsOneWidget);
      expect(find.text('Save schedule'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
