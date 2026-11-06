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
