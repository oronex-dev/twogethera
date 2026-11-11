import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/budget/domain/budget_export.dart';
import 'package:twogethera/features/budget/domain/budget_models.dart';

void main() {
  final usd = CurrencyUnit.byCode('USD')!;
  final jpy = CurrencyUnit.byCode('JPY')!;
  final kwd = CurrencyUnit.byCode('KWD')!;

  group('ExactMoney', () {
    test('parses and formats exact minor units for currency exponents', () {
      expect(ExactMoney.parse('123.45', usd), 12345);
      expect(ExactMoney(12345, usd).format(), '123.45 USD');
      expect(ExactMoney.parse('123', jpy), 123);
      expect(ExactMoney.parse('1.234', kwd), 1234);
      expect(ExactMoney.parse('0.00', usd, allowZero: true), 0);
    });

    test(
      'rejects excess precision, malformed, zero, negative, and overflow',
      () {
        expect(ExactMoney.parse('1.001', usd), isNull);
        expect(ExactMoney.parse('1.0', jpy), isNull);
        expect(ExactMoney.parse('1e3', usd), isNull);
        expect(ExactMoney.parse('-1', usd), isNull);
        expect(ExactMoney.parse('0', usd), isNull);
        expect(ExactMoney.parse('90000000000.01', usd), isNull);
      },
    );
  });

  group('RecurringExpenseRule date-only schedule', () {
    RecurringExpenseRule rule({
      required String frequency,
      required DateTime startsOn,
      DateTime? endsOn,
    }) => RecurringExpenseRule(
      id: 'rule-1',
      coupleId: 'couple-1',
      title: 'Rent',
      description: '',
      amountMinor: 10000,
      currency: usd,
      category: BudgetCategory.housing,
      paidByUser: 'user-a',
      splitAUserId: 'user-a',
      splitAMinor: 5000,
      splitBUserId: 'user-b',
      splitBMinor: 5000,
      frequency: frequency,
      startsOn: startsOn,
      endsOn: endsOn,
      active: true,
      revision: 1,
    );

    test('monthly occurrences stay anchored and clamp at month end', () {
      final schedule = rule(
        frequency: 'monthly',
        startsOn: DateTime(2026, 1, 31),
      );
      expect(
        schedule.occurrencesBetween(DateTime(2026, 2), DateTime(2026, 3, 31)),
        [DateTime(2026, 2, 28), DateTime(2026, 3, 31)],
      );
      expect(
        schedule.nextUnrecordedOccurrence([DateTime(2026, 1, 31)]),
        DateTime(2026, 2, 28),
      );
    });

    test('yearly leap-day schedule clamps and returns to leap day', () {
      final schedule = rule(
        frequency: 'yearly',
        startsOn: DateTime(2024, 2, 29),
      );
      expect(
        schedule.occurrencesBetween(DateTime(2025), DateTime(2028, 12, 31)),
        [
          DateTime(2025, 2, 28),
          DateTime(2026, 2, 28),
          DateTime(2027, 2, 28),
          DateTime(2028, 2, 29),
        ],
      );
    });

    test('start and inclusive end dates bound weekly occurrences', () {
      final schedule = rule(
        frequency: 'weekly',
        startsOn: DateTime(2026, 1, 7),
        endsOn: DateTime(2026, 1, 21),
      );
      expect(
        schedule.occurrencesBetween(DateTime(2026, 1), DateTime(2026, 1, 31)),
        [DateTime(2026, 1, 7), DateTime(2026, 1, 14), DateTime(2026, 1, 21)],
      );
    });
  });

  group('ExpenseSplit', () {
    test('equal split conserves odd minor units deterministically', () {
      final split = ExpenseSplit.parse(
        totalMinor: 1001,
        currency: usd,
        equal: true,
      );
      expect(split?.firstMinor, 500);
      expect(split?.secondMinor, 501);
      expect(split!.firstMinor + split.secondMinor, 1001);
    });

    test('custom split requires exact sum and valid precision', () {
      expect(
        ExpenseSplit.parse(
          totalMinor: 1001,
          currency: usd,
          equal: false,
          first: '5.00',
          second: '5.01',
        ),
        const TypeMatcher<ExpenseSplit>(),
      );
      expect(
        ExpenseSplit.parse(
          totalMinor: 1001,
          currency: usd,
          equal: false,
          first: '5.00',
          second: '5.00',
        ),
        isNull,
      );
      final onePartnerPays = ExpenseSplit.parse(
        totalMinor: 1001,
        currency: usd,
        equal: false,
        first: '10.01',
        second: '0',
      );
      expect(onePartnerPays?.firstMinor, 1001);
      expect(onePartnerPays?.secondMinor, 0);
      expect(
        ExpenseSplit.parse(
          totalMinor: 1001,
          currency: usd,
          equal: false,
          first: '5.001',
          second: '5.00',
        ),
        isNull,
      );
    });
  });

  group('Budget CSV export', () {
    test('exports selected-month totals and actual expense rows', () {
      final snapshot = BudgetSnapshot(
        budget: CoupleBudget(
          id: 'budget-1',
          coupleId: 'couple-1',
          monthStart: DateTime(2026, 11),
          currency: usd,
          limitMinor: 50000,
          revision: 1,
          categoryLimits: const {BudgetCategory.food: 20000},
        ),
        expenses: [
          CoupleExpense(
            id: 'expense-1',
            coupleId: 'couple-1',
            budgetId: 'budget-1',
            title: 'Lunch, with partner',
            description: 'Cafe "Rose"',
            amountMinor: 1234,
            currency: usd,
            occurredOn: DateTime(2026, 11, 7),
            category: BudgetCategory.food,
            paidByUser: 'user-a',
            splitMode: 'equal',
            splitAUserId: 'user-a',
            splitAMinor: 617,
            splitBUserId: 'user-b',
            splitBMinor: 617,
            revision: 1,
          ),
        ],
        recurringRules: const [],
        members: const [
          BudgetMember(userId: 'user-a', label: 'You', seat: 1),
          BudgetMember(userId: 'user-b', label: 'Partner 2', seat: 2),
        ],
      );

      final result = BudgetCsvExport.fromSnapshot(
        snapshot: snapshot,
        month: DateTime(2026, 11),
      );
      expect(result.summary, contains('November 2026'));
      expect(result.summary, contains('500.00'));
      expect(result.summary, contains('12.34'));
      expect(result.summary, contains('487.66'));
      expect(result.expenses, contains('2026-11-07'));
      expect(result.expenses, contains('Lunch, with partner'));
      expect(result.expenses, contains('Cafe ""Rose""'));
      expect(result.expenses, contains('12.34'));
      expect(result.expenses, contains('You'));
      expect(result.expenses, isNot(contains('user-a')));
    });

    test('escapes spreadsheet formulas in user-entered text', () {
      final snapshot = BudgetSnapshot(
        budget: CoupleBudget(
          id: 'budget-1',
          coupleId: 'couple-1',
          monthStart: DateTime(2026, 11),
          currency: usd,
          limitMinor: 10000,
          revision: 1,
          categoryLimits: const {},
        ),
        expenses: [
          CoupleExpense(
            id: 'expense-1',
            coupleId: 'couple-1',
            budgetId: 'budget-1',
            title: '=IMPORT("remote")',
            description: '',
            amountMinor: 100,
            currency: usd,
            occurredOn: DateTime(2026, 11, 1),
            category: BudgetCategory.other,
            paidByUser: 'user-a',
            splitMode: 'equal',
            splitAUserId: 'user-a',
            splitAMinor: 50,
            splitBUserId: 'user-b',
            splitBMinor: 50,
            revision: 1,
          ),
        ],
        recurringRules: const [],
        members: const [],
      );
      final result = BudgetCsvExport.fromSnapshot(
        snapshot: snapshot,
        month: DateTime(2026, 11),
      );
      expect(result.expenses, contains("'=IMPORT("));
    });
  });

  group('Budget authorization error mapping', () {
    test('explains paired-space and participant guard failures safely', () {
      expect(
        BudgetOperationFailure.fromPostgresCode(
          '42501',
          databaseMessage: 'active paired couple required',
        ).message,
        contains('active for both partners'),
      );
      expect(
        BudgetOperationFailure.fromPostgresCode(
          '42501',
          databaseMessage:
              'expense participants must be current couple members',
        ).message,
        contains('expense split'),
      );
    });

    test('does not expose unknown database error text', () {
      final failure = BudgetOperationFailure.fromPostgresCode(
        '42501',
        databaseMessage: 'private row content and credentials',
      );
      expect(failure.message, contains('Access check 42501'));
      expect(failure.message, isNot(contains('credentials')));
    });
  });
}
