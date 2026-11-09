import 'package:flutter/foundation.dart';

enum BudgetCategory {
  housing('Housing', 'housing'),
  food('Food', 'food'),
  transport('Transport', 'transport'),
  utilities('Utilities', 'utilities'),
  health('Health', 'health'),
  travel('Travel', 'travel'),
  shopping('Shopping', 'shopping'),
  entertainment('Entertainment', 'entertainment'),
  other('Other', 'other');

  const BudgetCategory(this.label, this.key);
  final String label;
  final String key;

  static BudgetCategory fromKey(Object? key) =>
      BudgetCategory.values.firstWhere(
        (value) => value.key == key,
        orElse: () => BudgetCategory.other,
      );
}

@immutable
class CurrencyUnit {
  const CurrencyUnit(this.code, this.exponent, this.label);
  final String code;
  final int exponent;
  final String label;

  static const supported = [
    CurrencyUnit('USD', 2, 'US Dollar'),
    CurrencyUnit('EUR', 2, 'Euro'),
    CurrencyUnit('GBP', 2, 'British Pound'),
    CurrencyUnit('CAD', 2, 'Canadian Dollar'),
    CurrencyUnit('AUD', 2, 'Australian Dollar'),
    CurrencyUnit('NZD', 2, 'New Zealand Dollar'),
    CurrencyUnit('CHF', 2, 'Swiss Franc'),
    CurrencyUnit('SGD', 2, 'Singapore Dollar'),
    CurrencyUnit('HKD', 2, 'Hong Kong Dollar'),
    CurrencyUnit('CNY', 2, 'Chinese Yuan'),
    CurrencyUnit('INR', 2, 'Indian Rupee'),
    CurrencyUnit('PHP', 2, 'Philippine Peso'),
    CurrencyUnit('JPY', 0, 'Japanese Yen'),
    CurrencyUnit('KRW', 0, 'South Korean Won'),
    CurrencyUnit('KWD', 3, 'Kuwaiti Dinar'),
  ];

  static CurrencyUnit? byCode(Object? code) =>
      supported.where((currency) => currency.code == code).firstOrNull;
}

class ExactMoney {
  const ExactMoney(this.minor, this.currency);
  final int minor;
  final CurrencyUnit currency;

  static const maximumMinor = 9000000000000;

  static int? parse(
    String input,
    CurrencyUnit currency, {
    bool allowZero = false,
  }) {
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(input.trim());
    if (match == null) return null;
    final fraction = match.group(2) ?? '';
    if (fraction.length > currency.exponent) return null;
    final scale = BigInt.from(10).pow(currency.exponent);
    final whole = BigInt.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fractional = fraction.isEmpty
        ? BigInt.zero
        : BigInt.parse(fraction.padRight(currency.exponent, '0'));
    final amount = whole * scale + fractional;
    if (amount < (allowZero ? BigInt.zero : BigInt.one) ||
        amount > BigInt.from(maximumMinor)) {
      return null;
    }
    return amount.toInt();
  }

  String format() {
    final scale = BigInt.from(10).pow(currency.exponent);
    final value = BigInt.from(minor);
    final whole = (value ~/ scale).toString();
    if (currency.exponent == 0) return '$whole ${currency.code}';
    final fraction = (value % scale).toString().padLeft(currency.exponent, '0');
    return '$whole.$fraction ${currency.code}';
  }
}

class ExpenseSplit {
  const ExpenseSplit(this.firstMinor, this.secondMinor);

  final int firstMinor;
  final int secondMinor;

  static ExpenseSplit? parse({
    required int totalMinor,
    required CurrencyUnit currency,
    required bool equal,
    String first = '',
    String second = '',
  }) {
    if (totalMinor <= 0 || totalMinor > ExactMoney.maximumMinor) return null;
    if (equal) {
      final firstMinor = totalMinor ~/ 2;
      return ExpenseSplit(firstMinor, totalMinor - firstMinor);
    }
    final firstMinor = ExactMoney.parse(first, currency, allowZero: true);
    final secondMinor = ExactMoney.parse(second, currency, allowZero: true);
    if (firstMinor == null ||
        secondMinor == null ||
        firstMinor + secondMinor != totalMinor) {
      return null;
    }
    return ExpenseSplit(firstMinor, secondMinor);
  }
}

@immutable
class BudgetMember {
  const BudgetMember({
    required this.userId,
    required this.label,
    required this.seat,
  });
  final String userId;
  final String label;
  final int seat;
}

@immutable
class CoupleBudget {
  const CoupleBudget({
    required this.id,
    required this.coupleId,
    required this.monthStart,
    required this.currency,
    required this.limitMinor,
    required this.revision,
    required this.categoryLimits,
  });
  final String id;
  final String coupleId;
  final DateTime monthStart;
  final CurrencyUnit currency;
  final int limitMinor;
  final int revision;
  final Map<BudgetCategory, int> categoryLimits;

  factory CoupleBudget.fromJson(
    Map<String, dynamic> json, {
    Map<BudgetCategory, int> categoryLimits = const {},
  }) {
    final currency = CurrencyUnit.byCode(json['currency_code']);
    if (currency == null ||
        currency.exponent != (json['currency_exponent'] as num).toInt()) {
      throw const FormatException('Unsupported budget currency.');
    }
    return CoupleBudget(
      id: json['id'] as String,
      coupleId: json['couple_id'] as String,
      monthStart: DateTime.parse(json['month_start'] as String),
      currency: currency,
      limitMinor: (json['limit_minor'] as num).toInt(),
      revision: (json['revision'] as num).toInt(),
      categoryLimits: Map.unmodifiable(categoryLimits),
    );
  }
}

@immutable
class CoupleExpense {
  const CoupleExpense({
    required this.id,
    required this.coupleId,
    required this.budgetId,
    required this.title,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.occurredOn,
    required this.category,
    required this.paidByUser,
    required this.splitMode,
    required this.splitAUserId,
    required this.splitAMinor,
    required this.splitBUserId,
    required this.splitBMinor,
    required this.revision,
    required this.receiptCount,
    this.recurringRuleId,
  });
  final String id;
  final String coupleId;
  final String budgetId;
  final String title;
  final String description;
  final int amountMinor;
  final CurrencyUnit currency;
  final DateTime occurredOn;
  final BudgetCategory category;
  final String paidByUser;
  final String splitMode;
  final String splitAUserId;
  final int splitAMinor;
  final String splitBUserId;
  final int splitBMinor;
  final int revision;
  final int receiptCount;
  final String? recurringRuleId;

  factory CoupleExpense.fromJson(Map<String, dynamic> json) {
    final currency = CurrencyUnit.byCode(json['currency_code']);
    if (currency == null ||
        currency.exponent != (json['currency_exponent'] as num).toInt()) {
      throw const FormatException('Unsupported expense currency.');
    }
    return CoupleExpense(
      id: json['id'] as String,
      coupleId: json['couple_id'] as String,
      budgetId: json['budget_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      amountMinor: (json['amount_minor'] as num).toInt(),
      currency: currency,
      occurredOn: DateTime.parse(json['occurred_on'] as String),
      category: BudgetCategory.fromKey(json['category_key']),
      paidByUser: json['paid_by_user'] as String,
      splitMode: json['split_mode'] as String,
      splitAUserId: json['split_a_user_id'] as String,
      splitAMinor: (json['split_a_minor'] as num).toInt(),
      splitBUserId: json['split_b_user_id'] as String,
      splitBMinor: (json['split_b_minor'] as num).toInt(),
      revision: (json['revision'] as num).toInt(),
      receiptCount: (json['receipt_count'] as num?)?.toInt() ?? 0,
      recurringRuleId: json['recurring_rule_id'] as String?,
    );
  }
}

@immutable
class RecurringExpenseRule {
  const RecurringExpenseRule({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.category,
    required this.paidByUser,
    required this.splitAUserId,
    required this.splitAMinor,
    required this.splitBUserId,
    required this.splitBMinor,
    required this.frequency,
    required this.startsOn,
    required this.active,
    required this.revision,
    this.endsOn,
  });
  final String id;
  final String coupleId;
  final String title;
  final String description;
  final int amountMinor;
  final CurrencyUnit currency;
  final BudgetCategory category;
  final String paidByUser;
  final String splitAUserId;
  final int splitAMinor;
  final String splitBUserId;
  final int splitBMinor;
  final String frequency;
  final DateTime startsOn;
  final DateTime? endsOn;
  final bool active;
  final int revision;

  /// Returns scheduled local calendar dates in the requested date-only range.
  /// Monthly and yearly occurrences stay anchored to [startsOn]. When a month
  /// has no anchor day, the last day of that month is used. Dates are handled
  /// as calendar dates, not elapsed 24-hour periods, so DST cannot shift them.
  List<DateTime> occurrencesBetween(DateTime first, DateTime last) {
    final start = DateTime.utc(startsOn.year, startsOn.month, startsOn.day);
    final lower = DateTime.utc(first.year, first.month, first.day);
    final upper = DateTime.utc(last.year, last.month, last.day);
    if (upper.isBefore(lower) || upper.isBefore(start)) return const [];
    final result = <DateTime>[];
    var occurrence = start;
    switch (frequency) {
      case 'weekly':
        final days = lower.difference(start).inDays;
        final weeks = days <= 0 ? 0 : days ~/ 7;
        occurrence = start.add(Duration(days: weeks * 7));
        while (occurrence.isBefore(lower)) {
          occurrence = occurrence.add(const Duration(days: 7));
        }
      case 'monthly':
        final months =
            (lower.year - start.year) * 12 + lower.month - start.month;
        occurrence = _monthlyOccurrence(start, months < 0 ? 0 : months);
        while (occurrence.isBefore(lower)) {
          occurrence = _monthlyOccurrence(
            start,
            _monthOffset(start, occurrence) + 1,
          );
        }
      case 'yearly':
        final years = lower.year - start.year;
        occurrence = _yearlyOccurrence(start, years < 0 ? 0 : years);
        while (occurrence.isBefore(lower)) {
          occurrence = _yearlyOccurrence(
            start,
            occurrence.year - start.year + 1,
          );
        }
      default:
        return const [];
    }
    final finalDate = endsOn == null
        ? upper
        : DateTime.utc(endsOn!.year, endsOn!.month, endsOn!.day).isBefore(upper)
        ? DateTime.utc(endsOn!.year, endsOn!.month, endsOn!.day)
        : upper;
    while (!occurrence.isAfter(finalDate)) {
      result.add(DateTime(occurrence.year, occurrence.month, occurrence.day));
      occurrence = switch (frequency) {
        'weekly' => occurrence.add(const Duration(days: 7)),
        'monthly' => _monthlyOccurrence(
          start,
          _monthOffset(start, occurrence) + 1,
        ),
        'yearly' => _yearlyOccurrence(start, occurrence.year - start.year + 1),
        _ => occurrence,
      };
    }
    return List.unmodifiable(result);
  }

  DateTime? nextUnrecordedOccurrence(Iterable<DateTime> recorded) {
    final known = recorded
        .map((date) => DateTime.utc(date.year, date.month, date.day))
        .toSet();
    var occurrence = DateTime.utc(startsOn.year, startsOn.month, startsOn.day);
    if (endsOn != null && endsOn!.isBefore(startsOn)) return null;
    for (var count = 0; count < 20000; count++) {
      if (endsOn != null &&
          occurrence.isAfter(
            DateTime.utc(endsOn!.year, endsOn!.month, endsOn!.day),
          )) {
        return null;
      }
      if (!known.contains(occurrence)) {
        return DateTime(occurrence.year, occurrence.month, occurrence.day);
      }
      final start = DateTime.utc(startsOn.year, startsOn.month, startsOn.day);
      if (frequency == 'weekly') {
        occurrence = occurrence.add(const Duration(days: 7));
      } else if (frequency == 'monthly') {
        occurrence = _monthlyOccurrence(
          start,
          _monthOffset(start, occurrence) + 1,
        );
      } else if (frequency == 'yearly') {
        occurrence = _yearlyOccurrence(start, occurrence.year - start.year + 1);
      } else {
        return null;
      }
    }
    return null;
  }

  static int _monthOffset(DateTime start, DateTime value) =>
      (value.year - start.year) * 12 + value.month - start.month;

  static DateTime _monthlyOccurrence(DateTime start, int monthOffset) {
    final monthIndex = start.year * 12 + start.month - 1 + monthOffset;
    final year = monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(year, month, start.day.clamp(1, lastDay));
  }

  static DateTime _yearlyOccurrence(DateTime start, int yearOffset) {
    final year = start.year + yearOffset;
    final lastDay = DateTime.utc(year, start.month + 1, 0).day;
    return DateTime.utc(year, start.month, start.day.clamp(1, lastDay));
  }

  factory RecurringExpenseRule.fromJson(Map<String, dynamic> json) {
    final currency = CurrencyUnit.byCode(json['currency_code']);
    if (currency == null ||
        currency.exponent != (json['currency_exponent'] as num).toInt()) {
      throw const FormatException('Unsupported recurring currency.');
    }
    return RecurringExpenseRule(
      id: json['id'] as String,
      coupleId: json['couple_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      amountMinor: (json['amount_minor'] as num).toInt(),
      currency: currency,
      category: BudgetCategory.fromKey(json['category_key']),
      paidByUser: json['paid_by_user'] as String,
      splitAUserId: json['split_a_user_id'] as String,
      splitAMinor: (json['split_a_minor'] as num).toInt(),
      splitBUserId: json['split_b_user_id'] as String,
      splitBMinor: (json['split_b_minor'] as num).toInt(),
      frequency: json['frequency'] as String,
      startsOn: DateTime.parse(json['starts_on'] as String),
      endsOn: json['ends_on'] == null
          ? null
          : DateTime.parse(json['ends_on'] as String),
      active: json['active'] as bool,
      revision: (json['revision'] as num).toInt(),
    );
  }
}

@immutable
class BudgetSnapshot {
  const BudgetSnapshot({
    required this.budget,
    required this.expenses,
    required this.recurringRules,
    required this.members,
    this.recurringOccurrences = const [],
  });
  final CoupleBudget? budget;
  final List<CoupleExpense> expenses;
  final List<RecurringExpenseRule> recurringRules;
  final List<BudgetMember> members;
  final List<RecurringExpenseOccurrence> recurringOccurrences;

  int get totalSpent => expenses.fold(0, (sum, item) => sum + item.amountMinor);
  int get remaining => (budget?.limitMinor ?? 0) - totalSpent;
}

class BudgetOperationFailure implements Exception {
  const BudgetOperationFailure(this.message);
  final String message;

  static BudgetOperationFailure fromPostgresCode(
    String? code, {
    bool duplicateOccurrence = false,
  }) => switch (code) {
    '23505' when duplicateOccurrence => const BudgetOperationFailure(
      'This occurrence has already been recorded.',
    ),
    '23505' => const BudgetOperationFailure(
      'That entry already exists. Refresh the budget and try again.',
    ),
    '23514' => const BudgetOperationFailure(
      'Check the amount, currency, date, and split details, then try again.',
    ),
    '42501' => const BudgetOperationFailure(
      'Shared budget access is unavailable. Confirm that your couple is still linked.',
    ),
    '23503' => const BudgetOperationFailure(
      'The related budget or schedule changed. Refresh and try again.',
    ),
    _ => const BudgetOperationFailure(
      'We could not save that change. Check your connection and retry.',
    ),
  };
}

@immutable
class RecurringExpenseOccurrence {
  const RecurringExpenseOccurrence({required this.ruleId, required this.date});
  final String ruleId;
  final DateTime date;
}

@immutable
class ExpenseReceipt {
  const ExpenseReceipt({
    required this.id,
    required this.coupleId,
    required this.expenseId,
    required this.objectPath,
    required this.contentType,
    required this.byteSize,
  });
  final String id;
  final String coupleId;
  final String expenseId;
  final String objectPath;
  final String contentType;
  final int byteSize;

  factory ExpenseReceipt.fromJson(Map<String, dynamic> json) => ExpenseReceipt(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    expenseId: json['expense_id'] as String,
    objectPath: json['object_path'] as String,
    contentType: json['content_type'] as String,
    byteSize: (json['byte_size'] as num).toInt(),
  );
}

abstract interface class BudgetRepository {
  Future<BudgetSnapshot> loadBudget(String coupleId, DateTime month);
  Future<void> saveBudget(
    String coupleId,
    DateTime month,
    CurrencyUnit currency,
    int limitMinor,
  );
  Future<void> saveCategoryLimit(
    String coupleId,
    String budgetId,
    BudgetCategory category,
    int limitMinor,
  );
  Future<void> saveExpense(
    String coupleId,
    String budgetId,
    CurrencyUnit currency,
    Map<String, dynamic> values, {
    String? expenseId,
    int? expectedRevision,
  });
  Future<void> deleteExpense(String coupleId, CoupleExpense expense);
  Future<void> saveRecurringRule(
    String coupleId,
    Map<String, dynamic> values, {
    String? ruleId,
    int? expectedRevision,
  });
  Future<void> setRecurringRuleActive(
    String coupleId,
    RecurringExpenseRule rule,
    bool active,
  );
  Future<void> recordRecurringOccurrence(
    String coupleId,
    String budgetId,
    CurrencyUnit currency,
    RecurringExpenseRule rule,
    DateTime occurrence,
  );
  Future<List<ExpenseReceipt>> loadReceipts(String coupleId, String expenseId);
  Future<void> uploadReceipt(
    String coupleId,
    String expenseId,
    Uint8List bytes,
    String contentType,
  );
  Future<Uint8List> downloadReceipt(String path);
  Future<void> deleteReceipt(ExpenseReceipt receipt);
}
