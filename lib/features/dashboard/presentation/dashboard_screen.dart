import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../../shared_planner/application/shared_planner_controller.dart';
import '../../shared_planner/domain/shared_planner_repository.dart';
import '../application/dashboard_preferences_controller.dart';
import '../domain/dashboard_preferences.dart';

var _plannerCreateRequestSequence = 0;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _requestedUser;
  String? _requestedCouple;

  void _openPlannerCreateAction(String action, int tab) {
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${_plannerCreateRequestSequence++}';
    context.go(
      Uri(
        path: '/planner',
        queryParameters: {
          'tab': '$tab',
          'create': action,
          'request': requestId,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final userId = auth.phase == AuthPhase.authenticated
        ? auth.context?.userId
        : null;
    final couple = auth.context?.spaces
        .where((space) => space.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;

    if (userId != _requestedUser) {
      _requestedUser = userId;
      if (userId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref
                .read(dashboardPreferencesControllerProvider.notifier)
                .load(userId);
          }
        });
      }
    }
    if (coupleId != _requestedCouple) {
      _requestedCouple = coupleId;
      if (coupleId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(sharedPlannerControllerProvider.notifier).load(coupleId);
          }
        });
      }
    }

    final preferences = ref.watch(dashboardPreferencesControllerProvider);
    final effectivePreferences = preferences.userId == userId
        ? preferences.preferences
        : DashboardPreferences.defaults();
    final planner = ref.watch(sharedPlannerControllerProvider);
    final snapshot = planner.coupleId == coupleId ? planner.snapshot : null;
    final name = auth.context?.displayName?.trim();
    final greeting = name == null || name.isEmpty
        ? 'Your shared space'
        : 'Welcome back, $name';

    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: greeting,
            description: 'A clear view of what is coming up for both of you.',
          ),
          const SizedBox(height: AppSpace.md),
          if (coupleId != null)
            _QuickActions(
              onAddIdea: () => _openPlannerCreateAction('bucket', 0),
              onAddDate: () => _openPlannerCreateAction('date', 1),
              onNewPlan: () => _openPlannerCreateAction('plan', 2),
            )
          else if (auth.phase == AuthPhase.authenticated)
            const _ConnectionAction(),
          const SizedBox(height: AppSpace.md),
          if (userId != null &&
              preferences.userId == userId &&
              preferences.error != null)
            _InlineNotice(
              message: preferences.error!,
              color: Theme.of(context).colorScheme.error,
            ),
          if (coupleId != null && planner.error != null)
            _InlineNotice(
              message: planner.error!,
              color: Theme.of(context).colorScheme.error,
              action: TextButton(
                onPressed: () => ref
                    .read(sharedPlannerControllerProvider.notifier)
                    .load(coupleId),
                child: const Text('Retry'),
              ),
            ),
          if (auth.phase == AuthPhase.loading ||
              auth.phase == AuthPhase.refreshing)
            const _LoadingSummary()
          else if (auth.phase != AuthPhase.authenticated)
            _SignedOutSummary(onSignIn: () => context.go('/auth/welcome'))
          else if (coupleId == null)
            const _UnpairedSummary()
          else if (snapshot == null && planner.loading)
            const _LoadingSummary()
          else if (snapshot == null)
            _PlannerUnavailable(
              onRetry: () => ref
                  .read(sharedPlannerControllerProvider.notifier)
                  .load(coupleId),
            )
          else ...[
            const SectionHeading(
              title: 'Your shared planner',
              description: 'The moments ahead and the plans taking shape.',
            ),
            if (userId != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: preferences.saving
                      ? null
                      : () => _customizeDashboard(effectivePreferences),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Customize summaries'),
                ),
              ),
            if ((preferences.userId == userId && preferences.loading) ||
                planner.loading)
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.sm),
                child: LinearProgressIndicator(),
              ),
            const SizedBox(height: AppSpace.md),
            for (final module in effectivePreferences.order)
              if (effectivePreferences.visible.contains(module))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: _DashboardSummaryModule(
                    module: module,
                    snapshot: snapshot,
                    onOpen: (type, id, tab) => context.go(
                      '/planner?tab=$tab&type=$type&item=${Uri.encodeComponent(id)}',
                    ),
                  ),
                ),
          ],
          const SizedBox(height: AppSpace.md),
        ],
      ),
    );
  }

  Future<void> _customizeDashboard(DashboardPreferences original) async {
    final result = await showDialog<DashboardPreferences>(
      context: context,
      builder: (dialogContext) {
        var order = List<DashboardModule>.of(original.order);
        var visible = Set<DashboardModule>.of(original.visible);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Customize your dashboard'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose which shared summaries appear and arrange their order.',
                  ),
                  const SizedBox(height: AppSpace.md),
                  for (var index = 0; index < order.length; index++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(order[index].label),
                      leading: Checkbox(
                        value: visible.contains(order[index]),
                        onChanged: (value) => setDialogState(() {
                          if (value == true) {
                            visible.add(order[index]);
                          } else {
                            visible.remove(order[index]);
                          }
                        }),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Move ${order[index].label} up',
                            onPressed: index == 0
                                ? null
                                : () => setDialogState(() {
                                    final item = order.removeAt(index);
                                    order.insert(index - 1, item);
                                  }),
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            tooltip: 'Move ${order[index].label} down',
                            onPressed: index == order.length - 1
                                ? null
                                : () => setDialogState(() {
                                    final item = order.removeAt(index);
                                    order.insert(index + 1, item);
                                  }),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  DashboardPreferences(
                    order: List.unmodifiable(order),
                    visible: Set.unmodifiable(visible),
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    final saved = await ref
        .read(dashboardPreferencesControllerProvider.notifier)
        .save(result);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Dashboard updated.'
                : 'Dashboard changes could not be saved.',
          ),
        ),
      );
    }
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddIdea,
    required this.onAddDate,
    required this.onNewPlan,
  });

  final VoidCallback onAddIdea;
  final VoidCallback onAddDate;
  final VoidCallback onNewPlan;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpace.sm,
    runSpacing: AppSpace.sm,
    children: [
      FilledButton.tonalIcon(
        onPressed: onAddIdea,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add an idea'),
      ),
      FilledButton.tonalIcon(
        onPressed: onAddDate,
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('Add an important date'),
      ),
      FilledButton.tonalIcon(
        onPressed: onNewPlan,
        icon: const Icon(Icons.event_note_outlined),
        label: const Text('Create a plan'),
      ),
    ],
  );
}

class _ConnectionAction extends StatelessWidget {
  const _ConnectionAction();

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpace.sm,
    runSpacing: AppSpace.xs,
    children: [
      Text('Connect with your partner to open the shared planner.'),
      FilledButton.tonalIcon(
        onPressed: () => context.go('/partner'),
        icon: const Icon(Icons.favorite_border_rounded),
        label: const Text('Link with your partner'),
      ),
    ],
  );
}

class _SignedOutSummary extends StatelessWidget {
  const _SignedOutSummary({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        const Text('Sign in to see your shared plans and milestones.'),
        FilledButton.tonalIcon(
          onPressed: onSignIn,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Sign in'),
        ),
      ],
    ),
  );
}

class _UnpairedSummary extends StatelessWidget {
  const _UnpairedSummary();

  @override
  Widget build(BuildContext context) => const SurfaceCard(
    child: Row(
      children: [
        Icon(Icons.lock_outline_rounded),
        SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            'Shared planner data appears after both partners are linked.',
          ),
        ),
      ],
    ),
  );
}

class _LoadingSummary extends StatelessWidget {
  const _LoadingSummary();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(),
      SizedBox(height: AppSpace.sm),
      Text('Loading your shared planner…'),
    ],
  );
}

class _PlannerUnavailable extends StatelessWidget {
  const _PlannerUnavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      children: [
        const Expanded(child: Text('Your planner could not be loaded.')),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.message,
    required this.color,
    this.action,
  });
  final String message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.sm),
    child: Row(
      children: [
        Expanded(
          child: Text(message, style: TextStyle(color: color)),
        ),
        action ?? const SizedBox.shrink(),
      ],
    ),
  );
}

class _DashboardSummaryModule extends StatelessWidget {
  const _DashboardSummaryModule({
    required this.module,
    required this.snapshot,
    required this.onOpen,
  });

  final DashboardModule module;
  final SharedPlannerSnapshot snapshot;
  final void Function(String type, String id, int tab) onOpen;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates =
        snapshot.importantDates
            .where((entry) => !entry.nextOccurrence(now).isBefore(today))
            .toList()
          ..sort(
            (a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)),
          );
    final plans =
        snapshot.plans.where((plan) => !plan.startsAt.isBefore(now)).toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final tasks = [
      for (final plan in snapshot.plans)
        for (final task in plan.tasks)
          if (!task.completed) (task, plan),
    ]..sort((a, b) => a.$2.startsAt.compareTo(b.$2.startsAt));

    final theme = Theme.of(context);
    final title = switch (module) {
      DashboardModule.bucketList => 'Bucket List progress',
      DashboardModule.importantDates => 'Upcoming important dates',
      DashboardModule.plans => 'Upcoming plans & tasks',
    };
    final icon = switch (module) {
      DashboardModule.bucketList => Icons.checklist_rounded,
      DashboardModule.importantDates => Icons.cake_outlined,
      DashboardModule.plans => Icons.event_note_outlined,
    };

    return SurfaceCard(
      key: ValueKey('dashboard-module-${module.storageKey}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          switch (module) {
            DashboardModule.bucketList => _bucketSummary(context, snapshot),
            DashboardModule.importantDates => _dateSummary(context, dates, now),
            DashboardModule.plans => _planSummary(context, plans, tasks),
          },
        ],
      ),
    );
  }

  Widget _bucketSummary(BuildContext context, SharedPlannerSnapshot snapshot) {
    final completed = snapshot.bucketItems
        .where((item) => item.completed)
        .length;
    final total = snapshot.bucketItems.length;
    final ratio = total == 0 ? 0.0 : completed / total;
    final ideas = snapshot.bucketItems
        .where((item) => !item.completed)
        .take(2)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('$completed of $total completed')),
            Text('${(ratio * 100).round()}%'),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Semantics(
          label: 'Bucket List progress, ${(ratio * 100).round()} percent',
          child: LinearProgressIndicator(value: ratio),
        ),
        if (total == 0)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.sm),
            child: Text('Add your first shared idea to start your list.'),
          )
        else if (ideas.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.sm),
            child: Text('You have completed every idea on your list.'),
          )
        else
          for (final item in ideas)
            _SummaryRow(
              title: item.title,
              subtitle: item.category.label,
              onTap: () => onOpen('bucket', item.id, 0),
            ),
      ],
    );
  }

  Widget _dateSummary(
    BuildContext context,
    List<ImportantDateEntry> dates,
    DateTime now,
  ) => dates.isEmpty
      ? const Text('No upcoming important dates. Add a birthday or milestone.')
      : Column(
          children: [
            for (final entry in dates.take(3))
              _SummaryRow(
                title: entry.title,
                subtitle:
                    '${_dateLabel(context, entry.nextOccurrence(now))} · ${entry.daysUntil(now)} ${entry.daysUntil(now) == 1 ? 'day' : 'days'} away',
                onTap: () => onOpen('date', entry.id, 1),
              ),
          ],
        );

  Widget _planSummary(
    BuildContext context,
    List<SharedPlan> plans,
    List<(PlanTask, SharedPlan)> tasks,
  ) {
    if (plans.isEmpty && tasks.isEmpty) {
      return const Text(
        'No upcoming plans or open tasks. Make a plan together.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final plan in plans.take(2))
          _SummaryRow(
            title: plan.title,
            subtitle: _dateLabel(context, plan.startsAt),
            onTap: () => onOpen('plan', plan.id, 2),
          ),
        if (tasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpace.xs,
              bottom: AppSpace.xs,
            ),
            child: Text(
              'Open tasks · ${tasks.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final (task, plan) in tasks.take(3))
            _SummaryRow(
              title: task.title,
              subtitle: plan.title,
              icon: Icons.radio_button_unchecked_rounded,
              onTap: () => onOpen('task', task.id, 2),
            ),
        ] else if (plans.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.xs),
            child: Text('No open tasks.'),
          ),
      ],
    );
  }

  String _dateLabel(BuildContext context, DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value);
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Icon(icon, size: 18),
    onTap: onTap,
  );
}
