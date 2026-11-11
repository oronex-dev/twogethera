import 'budget_models.dart';

class BudgetCsvExport {
  const BudgetCsvExport({required this.summary, required this.expenses});

  final String summary;
  final String expenses;

  static BudgetCsvExport fromSnapshot({
    required BudgetSnapshot snapshot,
    required DateTime month,
  }) {
    final budget = snapshot.budget;
    if (budget == null) {
      throw StateError('A monthly budget is required before export.');
    }

    final currency = budget.currency;
    final spentByCategory = <BudgetCategory, int>{};
    for (final expense in snapshot.expenses) {
      spentByCategory.update(
        expense.category,
        (amount) => amount + expense.amountMinor,
        ifAbsent: () => expense.amountMinor,
      );
    }

    final percentage = budget.limitMinor == 0
        ? 'Not available'
        : '${(snapshot.totalSpent * 100 / budget.limitMinor).toStringAsFixed(1)}%';
    final summaryRows = <List<Object?>>[
      ['Twogethera — Shared Budget'],
      ['Month', _monthLabel(month)],
      ['Currency', currency.code],
      ['Monthly budget', _money(budget.limitMinor, currency)],
      ['Total expenses', _money(snapshot.totalSpent, currency)],
      ['Remaining', _money(snapshot.remaining, currency)],
      ['Percentage spent', percentage],
      [],
      ['Category', 'Budgeted', 'Spent'],
      for (final category in BudgetCategory.values)
        [
          category.label,
          _money(budget.categoryLimits[category] ?? 0, currency),
          _money(spentByCategory[category] ?? 0, currency),
        ],
      [
        'Total',
        _money(budget.limitMinor, currency),
        _money(snapshot.totalSpent, currency),
      ],
    ];

    final memberLabels = {
      for (final member in snapshot.members) member.userId: member.label,
    };
    final expenseRows = <List<Object?>>[
      ['Twogethera — Expense Records'],
      ['Month', _monthLabel(month)],
      [],
      [
        'Date',
        'Expense',
        'Description',
        'Category',
        'Amount',
        'Currency',
        'Paid by',
        'Split type',
        'Partner 1 share',
        'Partner 2 share',
      ],
      for (final expense in snapshot.expenses)
        [
          _dateLabel(expense.occurredOn),
          expense.title,
          expense.description,
          expense.category.label,
          _money(expense.amountMinor, currency),
          expense.currency.code,
          memberLabels[expense.paidByUser] ?? 'Partner',
          expense.splitMode,
          _money(expense.splitAMinor, currency),
          _money(expense.splitBMinor, currency),
        ],
      [
        'Total',
        '',
        '',
        '',
        _money(snapshot.totalSpent, currency),
        currency.code,
      ],
    ];

    return BudgetCsvExport(
      summary: _csv(summaryRows),
      expenses: _csv(expenseRows),
    );
  }
}

String _csv(List<List<Object?>> rows) => rows
    .map((row) => row.map((value) => _cell(value?.toString() ?? '')).join(','))
    .join('\r\n');

String _cell(String value) {
  // Prevent spreadsheet formula execution in user-entered text fields.
  final isNumericCell = RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value);
  final formulaLike = RegExp(r'^[\t\r ]*[=+@-]').hasMatch(value);
  final safe = formulaLike && !isNumericCell ? "'$value" : value;
  return '"${safe.replaceAll('"', '""')}"';
}

String _money(int minor, CurrencyUnit currency) {
  final formatted = ExactMoney(minor, currency).format();
  return formatted.substring(0, formatted.lastIndexOf(' '));
}

String _dateLabel(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _monthLabel(DateTime month) =>
    '${_monthNames[month.month - 1]} ${month.year}';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
