import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../../authentication/domain/auth_repository.dart';
import '../application/budget_export.dart';
import '../application/budget_controller.dart';
import '../domain/budget_models.dart';

const _budgetParticipantDiagnosticsEnabled = bool.fromEnvironment(
  'TWOTHERGA_BUDGET_DIAGNOSTICS',
  defaultValue: false,
);

void _logRejectedParticipantMapping(
  String operation,
  List<BudgetMember> members,
  Map<String, dynamic> values,
) {
  if (!_budgetParticipantDiagnosticsEnabled) return;

  final seat1 = members.where((member) => member.seat == 1).toList();
  final seat2 = members.where((member) => member.seat == 2).toList();
  final activeMemberIds = members
      .where((member) => member.seat == 1 || member.seat == 2)
      .map((member) => member.userId)
      .toSet();
  final splitA = values['split_a_user_id'];
  final splitB = values['split_b_user_id'];
  final payer = values['paid_by_user'];
  final splitAIsActive = splitA is String && activeMemberIds.contains(splitA);
  final splitBIsActive = splitB is String && activeMemberIds.contains(splitB);
  final participantsAreDistinct =
      splitA is String && splitB is String && splitA != splitB;
  final hasExactlyTwoActiveSeats =
      members.length == 2 &&
      activeMemberIds.length == 2 &&
      seat1.length == 1 &&
      seat2.length == 1;
  final participantsAreActivePair =
      hasExactlyTwoActiveSeats &&
      splitAIsActive &&
      splitBIsActive &&
      participantsAreDistinct;
  final payerIsActive = payer is String && activeMemberIds.contains(payer);
  final participantsMatchSeatOrder =
      seat1.length == 1 &&
      seat2.length == 1 &&
      splitA == seat1.single.userId &&
      splitB == seat2.single.userId;

  debugPrint(
    'Twogethera Budget participant diagnostic: operation=$operation '
    'split_a_active=$splitAIsActive split_b_active=$splitBIsActive '
    'distinct=$participantsAreDistinct active_pair=$participantsAreActivePair '
    'payer_active=$payerIsActive seat_ordered=$participantsMatchSeatOrder',
  );
}

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _query = '';
  BudgetCategory? _filter;
  String? _requestedKey;
  bool _expenseParticipantDiagnosticUsed = false;
  bool _recurringParticipantDiagnosticUsed = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final couple = auth.context?.spaces
        .where((space) => space.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;
    if (coupleId == null) _requestedKey = null;
    final state = ref.watch(budgetControllerProvider);
    final requestKey = coupleId == null
        ? null
        : '$coupleId:${_month.year}-${_month.month}';
    if (requestKey != null && requestKey != _requestedKey) {
      _requestedKey = requestKey;
      final requestedCoupleId = coupleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref
              .read(budgetControllerProvider.notifier)
              .load(requestedCoupleId!, _month);
        }
      });
    }

    if (coupleId == null) {
      return ResponsivePage(
        child: SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Budget is shared',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Link your partner before creating a shared budget.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/partner'),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Link partner'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = state.coupleId == coupleId && state.month == _month
        ? state.snapshot
        : null;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'A clear view of your spending',
            description: 'Plan together, record expenses, and see where the month is going.',
          ),
          const SizedBox(height: AppSpace.md),
          _MonthSelector(
            month: _month,
            onMove: (delta) => setState(() {
              _month = DateTime(_month.year, _month.month + delta);
              _requestedKey = null;
            }),
          ),
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: snapshot?.budget == null || state.loading
                  ? null
                  : () => _exportBudget(snapshot!, _month),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
          ),
          if (state.error != null)
            _BudgetNotice(
              message: state.error!,
              isError: true,
              action: TextButton(
                onPressed: () => ref
                    .read(budgetControllerProvider.notifier)
                    .load(coupleId, _month),
                child: const Text('Retry'),
              ),
            ),
          if (state.notice != null)
            _BudgetNotice(message: state.notice!, isError: false),
          if (state.loading && snapshot == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (snapshot == null)
            const _BudgetEmpty(
              title: 'Your budget is loading',
              body: 'Your couple data will appear here when available.',
            )
          else if (snapshot.budget == null) ...[
            _BudgetEmpty(
              title: 'Start with a monthly budget',
              body: 'Choose a currency and spending limit. Existing amounts are never converted when the currency changes.',
              action: FilledButton.icon(
                onPressed: state.saving ? null : () => _editBudget(snapshot),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create budget'),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            _RecurringSection(
              snapshot: snapshot,
              onAdd: () => _editRecurring(snapshot),
              onEdit: (rule) => _editRecurring(snapshot, rule: rule),
              onToggleActive: (rule) => ref
                  .read(budgetControllerProvider.notifier)
                  .setRecurringRuleActive(rule, !rule.active),
              onRecord: (rule) => _recordOccurrence(snapshot, rule),
            ),
          ] else ...[
            _BudgetSummary(
              snapshot: snapshot,
              saving: state.saving,
              onEditBudget: () => _editBudget(snapshot),
              onAddExpense: () => _editExpense(snapshot),
              onAddRecurring: () => _editRecurring(snapshot),
            ),
            const SizedBox(height: AppSpace.md),
            _CategoryOverview(
              snapshot: snapshot,
              onLimit: (category) => _editCategoryLimit(snapshot, category),
            ),
            const SizedBox(height: AppSpace.md),
            _RecurringSection(
              snapshot: snapshot,
              onAdd: () => _editRecurring(snapshot),
              onEdit: (rule) => _editRecurring(snapshot, rule: rule),
              onToggleActive: (rule) => ref
                  .read(budgetControllerProvider.notifier)
                  .setRecurringRuleActive(rule, !rule.active),
              onRecord: (rule) => _recordOccurrence(snapshot, rule),
            ),
            const SizedBox(height: AppSpace.md),
            _ExpenseHistory(
              snapshot: snapshot,
              query: _query,
              category: _filter,
              onQuery: (value) => setState(() => _query = value),
              onFilter: (value) => setState(() => _filter = value),
              onEdit: (expense) => _editExpense(snapshot, expense: expense),
              onDelete: (expense) => _deleteExpense(expense),
            ),
          ],
        ],
      ),
    );
  }

  void _exportBudget(BudgetSnapshot snapshot, DateTime month) {
    try {
      final downloaded = exportBudgetCsv(snapshot, month);
      _showMessage(
        downloaded
            ? 'Budget summary and expense CSV files were downloaded.'
            : 'CSV export is available in a supported web browser.',
      );
    } catch (_) {
      _showMessage(
        'The selected month could not be exported. Refresh and retry.',
      );
    }
  }

  Future<void> _editBudget(BudgetSnapshot snapshot) async {
    final budget = snapshot.budget;
    final initialCurrency = budget?.currency ?? CurrencyUnit.supported.first;
    final initialLimit = budget == null
        ? ''
        : ExactMoney(
            budget.limitMinor,
            initialCurrency,
          ).format().split(' ').first;
    final result = await showDialog<({CurrencyUnit currency, int limit})>(
      context: context,
      builder: (context) => _BudgetFormDialog(
        initialCurrency: initialCurrency,
        initialLimit: initialLimit,
        currencyLocked:
            budget != null &&
            (snapshot.expenses.isNotEmpty ||
                snapshot.recurringRules.isNotEmpty),
      ),
    );
    if (result == null || !mounted) return;
    await ref
        .read(budgetControllerProvider.notifier)
        .saveBudget(result.currency, result.limit);
  }

  Future<void> _editCategoryLimit(
    BudgetSnapshot snapshot,
    BudgetCategory category,
  ) async {
    final budget = snapshot.budget;
    if (budget == null) return;
    final current = budget.categoryLimits[category];
    final controller = TextEditingController(
      text: current == null
          ? ''
          : ExactMoney(current, budget.currency).format().split(' ').first,
    );
    final limit = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${category.label} limit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (${budget.currency.code})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = ExactMoney.parse(controller.text, budget.currency);
              if (parsed == null && controller.text.trim().isNotEmpty) return;
              Navigator.pop(context, parsed ?? 0);
            },
            child: const Text('Save limit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (limit != null && mounted) {
      await ref
          .read(budgetControllerProvider.notifier)
          .saveCategoryLimit(category, limit);
    }
  }

  Future<void> _editExpense(
    BudgetSnapshot snapshot, {
    CoupleExpense? expense,
  }) async {
    final budget = snapshot.budget;
    if (budget == null || snapshot.members.length != 2) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _ExpenseFormDialog(
        currency: budget.currency,
        monthStart: budget.monthStart,
        members: snapshot.members,
        expense: expense,
      ),
    );
    if (values == null || !mounted) return;
    final diagnosticProbe =
        _budgetParticipantDiagnosticsEnabled && expense == null;
    if (diagnosticProbe && _expenseParticipantDiagnosticUsed) {
      _showMessage('The one-time expense diagnostic has already run.');
      return;
    }
    if (diagnosticProbe) {
      _expenseParticipantDiagnosticUsed = true;
      _logRejectedParticipantMapping(
        'couple_expenses.insert',
        snapshot.members,
        values,
      );
      // The trigger runs before NOT NULL constraints. This forces the insert
      // to fail after participant validation, even if that validation passes.
      values['title'] = null;
    }
    final saved = await ref
        .read(budgetControllerProvider.notifier)
        .saveExpense(
          values,
          expenseId: expense?.id,
          expectedRevision: expense?.revision,
        );
    if (diagnosticProbe && saved) {
      _showMessage('Diagnostic stopped unexpectedly; do not retry.');
    }
  }

  Future<void> _editRecurring(
    BudgetSnapshot snapshot, {
    RecurringExpenseRule? rule,
  }) async {
    final budget = snapshot.budget;
    if (snapshot.members.length != 2) return;
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RecurringFormDialog(
        currency:
            rule?.currency ?? budget?.currency ?? CurrencyUnit.supported.first,
        members: snapshot.members,
        rule: rule,
      ),
    );
    if (values != null && mounted) {
      final diagnosticProbe =
          _budgetParticipantDiagnosticsEnabled && rule == null;
      if (diagnosticProbe && _recurringParticipantDiagnosticUsed) {
        _showMessage('The one-time recurring diagnostic has already run.');
        return;
      }
      if (diagnosticProbe) {
        _recurringParticipantDiagnosticUsed = true;
        _logRejectedParticipantMapping(
          'recurring_expense_rules.insert',
          snapshot.members,
          values,
        );
        // The trigger runs before NOT NULL constraints, so this probe cannot
        // persist a recurring rule even when participant validation passes.
        values['title'] = null;
      }
      final saved = await ref
          .read(budgetControllerProvider.notifier)
          .saveRecurringRule(
            values,
            ruleId: rule?.id,
            expectedRevision: rule?.revision,
          );
      if (diagnosticProbe && saved) {
        _showMessage('Diagnostic stopped unexpectedly; do not retry.');
      }
    }
  }

  Future<void> _recordOccurrence(
    BudgetSnapshot snapshot,
    RecurringExpenseRule rule,
  ) async {
    final budget = snapshot.budget;
    if (budget == null || budget.currency.code != rule.currency.code) {
      _showMessage(
        'Create a budget in ${rule.currency.code} to record this schedule.',
      );
      return;
    }
    final first = DateTime(_month.year, _month.month, 1);
    final monthEnd = DateTime(_month.year, _month.month + 1, 0);
    final today = DateTime.now();
    final last = monthEnd.isAfter(today) ? today : monthEnd;
    if (last.isBefore(first)) {
      _showMessage('This month’s occurrence cannot be recorded yet.');
      return;
    }
    final recorded = snapshot.recurringOccurrences
        .where((item) => item.ruleId == rule.id)
        .map((item) => item.date)
        .toSet();
    final due = rule
        .occurrencesBetween(first, last)
        .where((date) => !recorded.contains(date))
        .toList(growable: false);
    if (due.isEmpty) {
      _showMessage(
        'There are no unrecorded scheduled occurrences for this month.',
      );
      return;
    }
    final result = due.length == 1
        ? due.single
        : await showDialog<DateTime>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Choose an occurrence'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final date in due)
                    ListTile(
                      title: Text(_dateLabel(date)),
                      onTap: () => Navigator.pop(context, date),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
    if (result != null && mounted) {
      await ref
          .read(budgetControllerProvider.notifier)
          .recordRecurring(rule, result);
    }
  }

  Future<void> _deleteExpense(CoupleExpense expense) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text(
          'Ordinary deletion reverses the current amount in the minimized audit. Privacy removal hides the expense immediately, cannot be undone, and queues primary-copy cleanup with a 24-hour target.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'privacy'),
            child: const Text('Remove for privacy'),
          ),
          if (expense.description.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'description'),
              child: const Text('Remove description only'),
            ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'ordinary'),
            child: const Text('Delete expense'),
          ),
        ],
      ),
    );
    if (action == 'ordinary' && mounted) {
      await ref.read(budgetControllerProvider.notifier).deleteExpense(expense);
    } else if ((action == 'privacy' || action == 'description') && mounted) {
      final repository = ref.read(authRepositoryProvider);
      try {
        if (repository is! PrivacyRemovalRepository) {
          throw const AuthFailure(AuthProblem.lifecycleUnavailable);
        }
        await (repository as PrivacyRemovalRepository).requestPrivacyRemoval(
          table: 'couple_expenses',
          recordId: expense.id,
          field: action == 'description' ? 'description' : null,
          removeRecord: action == 'privacy',
        );
        final budget = ref.read(budgetControllerProvider);
        final couple = ref
            .read(authControllerProvider)
            .context
            ?.spaces
            .where((space) => space.state == 'paired')
            .firstOrNull;
        if (couple != null && budget.month != null) {
          await ref
              .read(budgetControllerProvider.notifier)
              .load(couple.id, budget.month!);
        }
        if (mounted) {
          _showMessage(
            action == 'privacy'
                ? 'Expense hidden; removal cleanup is queued.'
                : 'The expense description was removed.',
          );
        }
      } on AuthFailure catch (error) {
        if (mounted) _showMessage(error.message);
      } catch (_) {
        if (mounted) {
          _showMessage('The privacy request could not be submitted.');
        }
      }
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({required this.month, required this.onMove});
  final DateTime month;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: 12,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => onMove(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            '${_monthName(month.month)} ${month.year}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () => onMove(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary({
    required this.snapshot,
    required this.saving,
    required this.onEditBudget,
    required this.onAddExpense,
    required this.onAddRecurring,
  });
  final BudgetSnapshot snapshot;
  final bool saving;
  final VoidCallback onEditBudget;
  final VoidCallback onAddExpense;
  final VoidCallback onAddRecurring;

  @override
  Widget build(BuildContext context) {
    final budget = snapshot.budget!;
    final spent = snapshot.totalSpent;
    final fraction = budget.limitMinor == 0
        ? 0.0
        : (spent / budget.limitMinor).clamp(0.0, 1.0);
    final exceeded = snapshot.remaining < 0;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Edit monthly budget',
                onPressed: saving ? null : onEditBudget,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: AppSpace.md,
            children: [
              _Metric(
                label: 'Budget',
                value: ExactMoney(budget.limitMinor, budget.currency).format(),
              ),
              _Metric(
                label: 'Spent',
                value: ExactMoney(spent, budget.currency).format(),
              ),
              _Metric(
                label: exceeded ? 'Over budget' : 'Remaining',
                value: ExactMoney(
                  snapshot.remaining.abs(),
                  budget.currency,
                ).format(),
                danger: exceeded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: fraction,
              color: exceeded
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: saving ? null : onAddExpense,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add expense'),
              ),
              OutlinedButton.icon(
                onPressed: saving ? null : onAddRecurring,
                icon: const Icon(Icons.repeat_rounded),
                label: const Text('Recurring expense'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.danger = false,
  });
  final String label;
  final String value;
  final bool danger;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 145),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 5),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: danger ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    ),
  );
}

class _CategoryOverview extends StatelessWidget {
  const _CategoryOverview({required this.snapshot, required this.onLimit});
  final BudgetSnapshot snapshot;
  final ValueChanged<BudgetCategory> onLimit;

  @override
  Widget build(BuildContext context) {
    final budget = snapshot.budget!;
    final totals = <BudgetCategory, int>{};
    for (final item in snapshot.expenses) {
      totals.update(
        item.category,
        (value) => value + item.amountMinor,
        ifAbsent: () => item.amountMinor,
      );
    }
    final categories = BudgetCategory.values
        .where(
          (category) =>
              totals.containsKey(category) ||
              budget.categoryLimits.containsKey(category),
        )
        .toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By category', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (categories.isEmpty)
            const Text('Category spending will appear after you add expenses.')
          else
            for (final category in categories)
              _CategoryBar(
                category: category,
                spent: totals[category] ?? 0,
                limit: budget.categoryLimits[category],
                totalLimit: budget.limitMinor,
                currency: budget.currency,
                onLimit: () => onLimit(category),
              ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.category,
    required this.spent,
    required this.limit,
    required this.totalLimit,
    required this.currency,
    required this.onLimit,
  });
  final BudgetCategory category;
  final int spent;
  final int? limit;
  final int totalLimit;
  final CurrencyUnit currency;
  final VoidCallback onLimit;
  @override
  Widget build(BuildContext context) {
    final fraction = (limit ?? totalLimit) <= 0
        ? 0.0
        : (spent / (limit ?? totalLimit)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(category.label)),
                    IconButton(
                      tooltip: 'Set ${category.label} limit',
                      onPressed: onLimit,
                      icon: const Icon(Icons.tune_rounded, size: 18),
                    ),
                  ],
                ),
                LinearProgressIndicator(value: fraction, minHeight: 6),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Text(
              '${ExactMoney(spent, currency).format()}${limit == null ? '' : ' / ${ExactMoney(limit!, currency).format()}'}',
              textAlign: TextAlign.end,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringSection extends StatelessWidget {
  const _RecurringSection({
    required this.snapshot,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleActive,
    required this.onRecord,
  });
  final BudgetSnapshot snapshot;
  final VoidCallback onAdd;
  final ValueChanged<RecurringExpenseRule> onEdit;
  final ValueChanged<RecurringExpenseRule> onToggleActive;
  final ValueChanged<RecurringExpenseRule> onRecord;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recurring expenses',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Add recurring expense',
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (snapshot.recurringRules.isEmpty)
          const Text(
            'Schedules are reminders, not recorded spending. Record each occurrence when it happens.',
          ),
        for (final rule in snapshot.recurringRules)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(rule.title),
            subtitle: Builder(
              builder: (context) {
                final recorded = snapshot.recurringOccurrences
                    .where((item) => item.ruleId == rule.id)
                    .map((item) => item.date);
                final next = rule.nextUnrecordedOccurrence(recorded);
                final nextLabel = next == null
                    ? ' · Schedule ended'
                    : ' · Next ${_dateLabel(next)}';
                return Text(
                  '${rule.frequency} · ${rule.category.label} · ${ExactMoney(rule.amountMinor, rule.currency).format()} · ${rule.active ? 'Active' : 'Paused'}$nextLabel',
                );
              },
            ),
            trailing: Wrap(
              spacing: 0,
              children: [
                IconButton(
                  tooltip: 'Edit schedule',
                  onPressed: () => onEdit(rule),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: rule.active ? 'Pause schedule' : 'Resume schedule',
                  onPressed: () => onToggleActive(rule),
                  icon: Icon(
                    rule.active
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                TextButton(
                  onPressed: rule.active ? () => onRecord(rule) : null,
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ExpenseHistory extends StatelessWidget {
  const _ExpenseHistory({
    required this.snapshot,
    required this.query,
    required this.category,
    required this.onQuery,
    required this.onFilter,
    required this.onEdit,
    required this.onDelete,
  });
  final BudgetSnapshot snapshot;
  final String query;
  final BudgetCategory? category;
  final ValueChanged<String> onQuery;
  final ValueChanged<BudgetCategory?> onFilter;
  final ValueChanged<CoupleExpense> onEdit;
  final ValueChanged<CoupleExpense> onDelete;
  @override
  Widget build(BuildContext context) {
    final members = {
      for (final member in snapshot.members) member.userId: member.label,
    };
    final normalized = query.trim().toLowerCase();
    final results = snapshot.expenses
        .where(
          (expense) =>
              (category == null || expense.category == category) &&
              (normalized.isEmpty ||
                  '${expense.title} ${expense.description} ${expense.category.label}'
                      .toLowerCase()
                      .contains(normalized)),
        )
        .toList();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Expense history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  onChanged: onQuery,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Search expenses',
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<BudgetCategory?>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    for (final item in BudgetCategory.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: onFilter,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                snapshot.expenses.isEmpty
                    ? 'No expenses recorded for this month.'
                    : 'No expenses match this search.',
              ),
            )
          else
            for (final expense in results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(_categoryIcon(expense.category)),
                ),
                title: Text(expense.title),
                subtitle: Text(
                  '${_dateLabel(expense.occurredOn)} · ${expense.category.label} · Paid by ${members[expense.paidByUser] ?? 'partner'} · Split ${ExactMoney(expense.splitAMinor, expense.currency).format()} / ${ExactMoney(expense.splitBMinor, expense.currency).format()}',
                ),
                trailing: Wrap(
                  children: [
                    Text(
                      ExactMoney(
                        expense.amountMinor,
                        expense.currency,
                      ).format(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    IconButton(
                      tooltip: 'Edit expense',
                      onPressed: () => onEdit(expense),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete expense',
                      onPressed: () => onDelete(expense),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({
    required this.currency,
    required this.monthStart,
    required this.members,
    this.expense,
  });
  final CurrencyUnit currency;
  final DateTime monthStart;
  final List<BudgetMember> members;
  final CoupleExpense? expense;
  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _splitA;
  late final TextEditingController _splitB;
  late DateTime _date;
  late BudgetCategory _category;
  late String _paidBy;
  late String _splitMode;
  String? _error;
  @override
  void initState() {
    super.initState();
    final value = widget.expense;
    _title = TextEditingController(text: value?.title ?? '');
    _description = TextEditingController(text: value?.description ?? '');
    _amount = TextEditingController(
      text: value == null
          ? ''
          : ExactMoney(
              value.amountMinor,
              widget.currency,
            ).format().split(' ').first,
    );
    _splitA = TextEditingController(
      text: value == null
          ? ''
          : ExactMoney(
              value.splitAMinor,
              widget.currency,
            ).format().split(' ').first,
    );
    _splitB = TextEditingController(
      text: value == null
          ? ''
          : ExactMoney(
              value.splitBMinor,
              widget.currency,
            ).format().split(' ').first,
    );
    final now = DateTime.now();
    _date =
        value?.occurredOn ??
        (now.year == widget.monthStart.year &&
                now.month == widget.monthStart.month
            ? now
            : widget.monthStart);
    _category = value?.category ?? BudgetCategory.other;
    _paidBy = value?.paidByUser ?? widget.members.first.userId;
    _splitMode = value?.splitMode ?? 'equal';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    _splitA.dispose();
    _splitB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.expense == null ? 'Add expense' : 'Edit expense'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _description,
              maxLength: 2000,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.currency.code})',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Enter digits with a period for the currency’s fractional units. No symbols or separators.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BudgetCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final item in BudgetCategory.values)
                  DropdownMenuItem(value: item, child: Text(item.label)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            DropdownButtonFormField<String>(
              initialValue: _paidBy,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: [
                for (final member in widget.members)
                  DropdownMenuItem(
                    value: member.userId,
                    child: Text(member.label),
                  ),
              ],
              onChanged: (v) => setState(() => _paidBy = v ?? _paidBy),
            ),
            DropdownButtonFormField<String>(
              initialValue: _splitMode,
              decoration: const InputDecoration(labelText: 'Split'),
              items: const [
                DropdownMenuItem(value: 'equal', child: Text('Equal split')),
                DropdownMenuItem(value: 'custom', child: Text('Custom split')),
              ],
              onChanged: (v) => setState(() => _splitMode = v ?? 'equal'),
            ),
            if (_splitMode == 'custom') ...[
              TextField(
                controller: _splitA,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${widget.members[0].label} share',
                ),
              ),
              TextField(
                controller: _splitB,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${widget.members[1].label} share',
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_dateLabel(_date)),
              ),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save expense')),
    ],
  );

  Future<void> _chooseDate() async {
    final next = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.monthStart,
      lastDate: DateTime(
        widget.monthStart.year,
        widget.monthStart.month + 1,
        0,
      ),
    );
    if (next != null) setState(() => _date = next);
  }

  void _save() {
    final title = _title.text.trim();
    final amount = ExactMoney.parse(_amount.text, widget.currency);
    if (title.isEmpty || title.length > 160 || amount == null) {
      setState(() => _error = 'Add a title and a valid exact amount.');
      return;
    }
    final split = ExpenseSplit.parse(
      totalMinor: amount,
      currency: widget.currency,
      equal: _splitMode == 'equal',
      first: _splitA.text,
      second: _splitB.text,
    );
    if (split == null) {
      setState(
        () =>
            _error = 'The two exact shares must add up to the expense amount.',
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': title,
      'description': _description.text.trim(),
      'amount_minor': amount,
      'occurred_on': _dateKey(_date),
      'category_key': _category.key,
      'paid_by_user': _paidBy,
      'split_mode': _splitMode,
      'split_a_user_id': widget.members[0].userId,
      'split_a_minor': split.firstMinor,
      'split_b_user_id': widget.members[1].userId,
      'split_b_minor': split.secondMinor,
    });
  }
}

class _RecurringFormDialog extends StatefulWidget {
  const _RecurringFormDialog({
    required this.currency,
    required this.members,
    this.rule,
  });
  final CurrencyUnit currency;
  final List<BudgetMember> members;
  final RecurringExpenseRule? rule;
  @override
  State<_RecurringFormDialog> createState() => _RecurringFormDialogState();
}

class _RecurringFormDialogState extends State<_RecurringFormDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _splitA;
  late final TextEditingController _splitB;
  late String _paidBy;
  late DateTime _startsOn;
  DateTime? _endsOn;
  late String _frequency;
  late String _splitMode;
  late BudgetCategory _category;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _title = TextEditingController(text: rule?.title ?? '');
    _description = TextEditingController(text: rule?.description ?? '');
    _amount = TextEditingController(
      text: rule == null
          ? ''
          : ExactMoney(
              rule.amountMinor,
              widget.currency,
            ).format().split(' ').first,
    );
    final firstMember = widget.members[0];
    final secondMember = widget.members[1];
    _splitA = TextEditingController(
      text: rule == null
          ? ''
          : ExactMoney(
              rule.splitAUserId == firstMember.userId
                  ? rule.splitAMinor
                  : rule.splitBMinor,
              widget.currency,
            ).format().split(' ').first,
    );
    _splitB = TextEditingController(
      text: rule == null
          ? ''
          : ExactMoney(
              rule.splitBUserId == secondMember.userId
                  ? rule.splitBMinor
                  : rule.splitAMinor,
              widget.currency,
            ).format().split(' ').first,
    );
    _paidBy = rule?.paidByUser ?? firstMember.userId;
    _startsOn = rule?.startsOn ?? DateTime.now();
    _endsOn = rule?.endsOn;
    _frequency = rule?.frequency ?? 'monthly';
    _category = rule?.category ?? BudgetCategory.other;
    final firstShare = rule == null
        ? null
        : (rule.splitAUserId == firstMember.userId
              ? rule.splitAMinor
              : rule.splitBMinor);
    final amount = rule?.amountMinor;
    _splitMode =
        amount != null &&
            firstShare == amount ~/ 2 &&
            amount - firstShare! == amount - amount ~/ 2
        ? 'equal'
        : 'custom';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    _splitA.dispose();
    _splitB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.rule == null ? 'Recurring expense schedule' : 'Edit schedule',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A schedule is not recorded spending. An occurrence is added to the budget only when you record it. Dates use the start date as their calendar anchor; monthly and yearly dates fall on the last day when the anchor day does not exist. End dates are inclusive.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _description,
              maxLength: 2000,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.currency.code})',
              ),
            ),
            DropdownButtonFormField<BudgetCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final item in BudgetCategory.values)
                  DropdownMenuItem(value: item, child: Text(item.label)),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequency'),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
              ],
              onChanged: (value) =>
                  setState(() => _frequency = value ?? _frequency),
            ),
            DropdownButtonFormField<String>(
              initialValue: _paidBy,
              decoration: const InputDecoration(labelText: 'Usually paid by'),
              items: [
                for (final member in widget.members)
                  DropdownMenuItem(
                    value: member.userId,
                    child: Text(member.label),
                  ),
              ],
              onChanged: (value) => setState(() => _paidBy = value ?? _paidBy),
            ),
            DropdownButtonFormField<String>(
              initialValue: _splitMode,
              decoration: const InputDecoration(labelText: 'Split'),
              items: const [
                DropdownMenuItem(value: 'equal', child: Text('Equal split')),
                DropdownMenuItem(value: 'custom', child: Text('Custom split')),
              ],
              onChanged: (value) =>
                  setState(() => _splitMode = value ?? _splitMode),
            ),
            if (_splitMode == 'custom') ...[
              TextField(
                controller: _splitA,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${widget.members[0].label} share',
                ),
              ),
              TextField(
                controller: _splitB,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${widget.members[1].label} share',
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _chooseStart,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('Starts ${_dateLabel(_startsOn)}'),
                  ),
                  TextButton.icon(
                    onPressed: _chooseEnd,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _endsOn == null
                          ? 'No end date'
                          : 'Ends ${_dateLabel(_endsOn!)}',
                    ),
                  ),
                  if (_endsOn != null)
                    TextButton(
                      onPressed: () => setState(() => _endsOn = null),
                      child: const Text('Clear end date'),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(widget.rule == null ? 'Save schedule' : 'Save changes'),
      ),
    ],
  );

  Future<void> _chooseStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startsOn = picked;
        if (_endsOn != null && _endsOn!.isBefore(picked)) _endsOn = picked;
      });
    }
  }

  Future<void> _chooseEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsOn ?? _startsOn,
      firstDate: _startsOn,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endsOn = picked);
  }

  void _save() {
    final amount = ExactMoney.parse(_amount.text, widget.currency);
    final title = _title.text.trim();
    if (amount == null || title.isEmpty || title.length > 160) {
      setState(() => _error = 'Add a title and valid exact amount.');
      return;
    }
    if (_endsOn != null && _endsOn!.isBefore(_startsOn)) {
      setState(
        () => _error = 'The end date must be on or after the start date.',
      );
      return;
    }
    final split = ExpenseSplit.parse(
      totalMinor: amount,
      currency: widget.currency,
      equal: _splitMode == 'equal',
      first: _splitA.text,
      second: _splitB.text,
    );
    if (split == null) {
      setState(
        () =>
            _error = 'The two exact shares must add up to the schedule amount.',
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': title,
      'description': _description.text.trim(),
      'amount_minor': amount,
      'currency_code': widget.currency.code,
      'currency_exponent': widget.currency.exponent,
      'category_key': _category.key,
      'paid_by_user': _paidBy,
      'split_a_user_id': widget.members[0].userId,
      'split_a_minor': split.firstMinor,
      'split_b_user_id': widget.members[1].userId,
      'split_b_minor': split.secondMinor,
      'frequency': _frequency,
      'starts_on': _dateKey(_startsOn),
      'ends_on': _endsOn == null ? null : _dateKey(_endsOn!),
      'active': widget.rule?.active ?? true,
    });
  }
}

class _BudgetFormDialog extends StatefulWidget {
  const _BudgetFormDialog({
    required this.initialCurrency,
    required this.initialLimit,
    required this.currencyLocked,
  });
  final CurrencyUnit initialCurrency;
  final String initialLimit;
  final bool currencyLocked;
  @override
  State<_BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends State<_BudgetFormDialog> {
  late CurrencyUnit _currency = widget.initialCurrency;
  late final TextEditingController _limit = TextEditingController(
    text: widget.initialLimit,
  );
  String? _error;
  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.initialLimit.isEmpty
          ? 'Create monthly budget'
          : 'Edit monthly budget',
    ),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<CurrencyUnit>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: [
              for (final unit in CurrencyUnit.supported)
                DropdownMenuItem(
                  value: unit,
                  child: Text('${unit.code} · ${unit.label}'),
                ),
            ],
            onChanged: widget.currencyLocked
                ? null
                : (value) => setState(() => _currency = value ?? _currency),
          ),
          TextField(
            controller: _limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly limit (${_currency.code})',
            ),
          ),
          if (widget.currencyLocked)
            const Text(
              'Currency is locked once this month has recorded expenses. Create a new month budget to use another currency.',
            ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save budget')),
    ],
  );
  void _save() {
    if (_limit.text.trim().isEmpty) {
      setState(() => _error = 'Enter a monthly limit.');
      return;
    }
    final value = ExactMoney.parse(_limit.text, _currency, allowZero: true);
    if (value == null) {
      setState(() => _error = 'Enter an exact valid amount.');
      return;
    }
    Navigator.pop(context, (currency: _currency, limit: value));
  }
}

class _BudgetEmpty extends StatelessWidget {
  const _BudgetEmpty({required this.title, required this.body, this.action});
  final String title;
  final String body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.account_balance_wallet_outlined,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _BudgetNotice extends StatelessWidget {
  const _BudgetNotice({
    required this.message,
    required this.isError,
    this.action,
  });
  final String message;
  final bool isError;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Material(
      color: isError
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            ?action,
          ],
        ),
      ),
    ),
  );
}

String _monthName(int month) => const [
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
][month - 1];
String _dateLabel(DateTime value) =>
    '${_monthName(value.month)} ${value.day}, ${value.year}';
String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
IconData _categoryIcon(BudgetCategory category) => switch (category) {
  BudgetCategory.housing => Icons.home_outlined,
  BudgetCategory.food => Icons.restaurant_outlined,
  BudgetCategory.transport => Icons.directions_car_outlined,
  BudgetCategory.utilities => Icons.bolt_outlined,
  BudgetCategory.health => Icons.health_and_safety_outlined,
  BudgetCategory.travel => Icons.flight_outlined,
  BudgetCategory.shopping => Icons.shopping_bag_outlined,
  BudgetCategory.entertainment => Icons.movie_outlined,
  BudgetCategory.other => Icons.receipt_long_outlined,
};
