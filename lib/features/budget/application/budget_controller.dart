import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../domain/budget_models.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  if (repository is BudgetRepository) return repository as BudgetRepository;
  throw StateError('Budget data is unavailable.');
});

class BudgetState {
  const BudgetState({
    this.coupleId,
    this.month,
    this.snapshot,
    this.loading = false,
    this.saving = false,
    this.error,
    this.notice,
  });
  final String? coupleId;
  final DateTime? month;
  final BudgetSnapshot? snapshot;
  final bool loading;
  final bool saving;
  final String? error;
  final String? notice;
}

final budgetControllerProvider =
    NotifierProvider<BudgetController, BudgetState>(BudgetController.new);

class BudgetController extends Notifier<BudgetState> {
  int _loadGeneration = 0;

  @override
  BudgetState build() {
    ref.listen(authControllerProvider, (_, next) {
      final coupleId = state.coupleId;
      if (coupleId == null || !_isPairedIn(next, coupleId)) {
        _loadGeneration++;
        if (coupleId != null) state = const BudgetState();
      }
    });
    return const BudgetState();
  }

  bool _isPairedIn(AuthViewState auth, String coupleId) =>
      auth.phase == AuthPhase.authenticated &&
      auth.context?.spaces.any(
            (space) => space.id == coupleId && space.state == 'paired',
          ) ==
          true;

  bool _isPaired(String coupleId) =>
      _isPairedIn(ref.read(authControllerProvider), coupleId);

  Future<void> load(String coupleId, DateTime month) async {
    final generation = ++_loadGeneration;
    if (!_isPaired(coupleId)) {
      state = const BudgetState(
        error: 'Link your partner before opening shared expenses.',
      );
      return;
    }
    final normalized = DateTime(month.year, month.month);
    state = BudgetState(
      coupleId: coupleId,
      month: normalized,
      snapshot: state.coupleId == coupleId && state.month == normalized
          ? state.snapshot
          : null,
      loading: true,
    );
    try {
      final snapshot = await ref
          .read(budgetRepositoryProvider)
          .loadBudget(coupleId, normalized);
      if (generation != _loadGeneration || !_isPaired(coupleId)) {
        if (generation != _loadGeneration) return;
        state = const BudgetState(
          error: 'Shared expenses are no longer available.',
        );
        return;
      }
      state = BudgetState(
        coupleId: coupleId,
        month: normalized,
        snapshot: snapshot,
      );
    } catch (_) {
      if (generation != _loadGeneration) return;
      if (state.coupleId == coupleId) {
        state = BudgetState(
          coupleId: coupleId,
          month: normalized,
          snapshot: state.snapshot,
          error: 'We could not load shared expenses. Check your connection and retry.',
        );
      }
    }
  }

  Future<bool> saveBudget(CurrencyUnit currency, int limitMinor) => _mutate(
    (repo, couple, month) =>
        repo.saveBudget(couple, month, currency, limitMinor),
    success: 'Monthly budget saved.',
  );

  Future<bool> saveCategoryLimit(BudgetCategory category, int limitMinor) {
    final budget = state.snapshot?.budget;
    if (budget == null) return Future.value(false);
    return _mutate(
      (repo, couple, _) =>
          repo.saveCategoryLimit(couple, budget.id, category, limitMinor),
      success: 'Category limit saved.',
    );
  }

  Future<bool> saveExpense(
    Map<String, dynamic> values, {
    String? expenseId,
    int? expectedRevision,
  }) {
    final snapshot = state.snapshot;
    final budget = snapshot?.budget;
    if (budget == null) return Future.value(false);
    return _mutate(
      (repo, couple, _) => repo.saveExpense(
        couple,
        budget.id,
        budget.currency,
        values,
        expenseId: expenseId,
        expectedRevision: expectedRevision,
      ),
      success: 'Expense saved.',
    );
  }

  Future<bool> deleteExpense(CoupleExpense expense) => _mutate(
    (repo, couple, _) => repo.deleteExpense(couple, expense),
    success: 'Expense deleted.',
  );

  Future<bool> saveRecurringRule(
    Map<String, dynamic> values, {
    String? ruleId,
    int? expectedRevision,
  }) => _mutate(
    (repo, couple, _) => repo.saveRecurringRule(
      couple,
      values,
      ruleId: ruleId,
      expectedRevision: expectedRevision,
    ),
    success: 'Recurring expense saved.',
  );

  Future<bool> setRecurringRuleActive(RecurringExpenseRule rule, bool active) =>
      _mutate(
        (repo, couple, _) => repo.setRecurringRuleActive(couple, rule, active),
        success: active
            ? 'Recurring schedule resumed.'
            : 'Recurring schedule paused.',
      );

  Future<bool> recordRecurring(RecurringExpenseRule rule, DateTime date) {
    final budget = state.snapshot?.budget;
    if (budget == null) return Future.value(false);
    return _mutate(
      (repo, couple, _) => repo.recordRecurringOccurrence(
        couple,
        budget.id,
        budget.currency,
        rule,
        date,
      ),
      success: 'Recurring expense recorded.',
    );
  }

  Future<bool> _mutate(
    Future<void> Function(BudgetRepository, String, DateTime) action, {
    required String success,
  }) async {
    final coupleId = state.coupleId;
    final month = state.month;
    if (coupleId == null ||
        month == null ||
        !_isPaired(coupleId) ||
        state.saving) {
      return false;
    }
    state = BudgetState(
      coupleId: coupleId,
      month: month,
      snapshot: state.snapshot,
      saving: true,
    );
    try {
      await action(ref.read(budgetRepositoryProvider), coupleId, month);
      if (!_isPaired(coupleId)) return false;
      await load(coupleId, month);
      if (state.error != null) return false;
      state = BudgetState(
        coupleId: coupleId,
        month: month,
        snapshot: state.snapshot,
        notice: success,
      );
      return true;
    } on BudgetOperationFailure catch (error) {
      if (state.coupleId == coupleId) {
        state = BudgetState(
          coupleId: coupleId,
          month: month,
          snapshot: state.snapshot,
          error: error.message,
        );
      }
      return false;
    } catch (_) {
      if (state.coupleId == coupleId) {
        state = BudgetState(
          coupleId: coupleId,
          month: month,
          snapshot: state.snapshot,
          error: 'We could not save that change. Refresh and try again.',
        );
      }
      return false;
    }
  }
}
