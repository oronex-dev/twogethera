import '../data/budget_csv_download.dart';
import '../domain/budget_export.dart';
import '../domain/budget_models.dart';

bool exportBudgetCsv(BudgetSnapshot snapshot, DateTime month) {
  final files = BudgetCsvExport.fromSnapshot(snapshot: snapshot, month: month);
  final monthKey =
      '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
  final summarySaved = downloadBudgetCsv(
    'twogethera-budget-summary-$monthKey.csv',
    files.summary,
  );
  final expensesSaved = downloadBudgetCsv(
    'twogethera-expenses-$monthKey.csv',
    files.expenses,
  );
  return summarySaved && expensesSaved;
}
