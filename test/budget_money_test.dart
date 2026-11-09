import 'package:flutter_test/flutter_test.dart';
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
}
