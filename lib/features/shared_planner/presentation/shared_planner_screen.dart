import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../application/shared_planner_controller.dart';
import '../domain/shared_planner_repository.dart';

class SharedPlannerScreen extends ConsumerStatefulWidget {
  const SharedPlannerScreen({this.embedded = false, super.key});

  /// The app shell supplies the shared header and primary navigation when true.
  final bool embedded;

  @override
  ConsumerState<SharedPlannerScreen> createState() =>
      _SharedPlannerScreenState();
}

class _SharedPlannerScreenState extends ConsumerState<SharedPlannerScreen> {
  String? _requestedCoupleId;
  String? _openedSearchTarget;
  String? _openedCreateRequest;

  @override
  Widget build(BuildContext context) {
    final uri = _routeUri(context);
    final initialTab = (int.tryParse(uri.queryParameters['tab'] ?? '') ?? 0)
        .clamp(0, 2);
    final itemType = uri.queryParameters['type'];
    final itemId = uri.queryParameters['item'];
    final createAction = uri.queryParameters['create'];
    final createRequest =
        uri.queryParameters['request'] ??
        (createAction == null ? null : 'legacy:$createAction:$initialTab');
    final targetKey = itemType == null || itemId == null
        ? null
        : '$itemType:$itemId';
    final auth = ref.watch(authControllerProvider);
    final couple = auth.context?.spaces
        .where((space) => space.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;
    if (coupleId != _requestedCoupleId) {
      _requestedCoupleId = coupleId;
      if (coupleId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(
              ref.read(sharedPlannerControllerProvider.notifier).load(coupleId),
            );
          }
        });
      }
    }

    if (coupleId == null) {
      return widget.embedded ? Scaffold(body: _unpairedBody()) : _unpaired();
    }
    final state = ref.watch(sharedPlannerControllerProvider);
    final snapshot = state.snapshot;
    if (snapshot != null &&
        targetKey != null &&
        targetKey != _openedSearchTarget) {
      _openedSearchTarget = targetKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSearchTarget(coupleId, snapshot, itemType!, itemId!);
      });
    }
    if (snapshot != null &&
        widget.embedded &&
        createAction != null &&
        createRequest != _openedCreateRequest) {
      _openedCreateRequest = createRequest;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (createAction) {
          case 'bucket':
            unawaited(_editBucket(context, ref, coupleId));
          case 'date':
            unawaited(_editDate(context, ref, coupleId));
          case 'plan':
            unawaited(_editPlan(context, ref, coupleId));
        }
        context.replace('/planner?tab=$initialTab');
      });
    }

    if (widget.embedded) {
      return Scaffold(
        body: state.loading && snapshot == null
            ? const Center(child: CircularProgressIndicator())
            : snapshot == null
            ? _loadError(coupleId, state.error)
            : Column(
                children: [
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.md,
                        AppSpace.sm,
                        AppSpace.md,
                        0,
                      ),
                      child: _InlineError(
                        message: state.error!,
                        onRetry: () => ref
                            .read(sharedPlannerControllerProvider.notifier)
                            .load(coupleId),
                      ),
                    ),
                  Expanded(child: _plannerTab(initialTab, coupleId, snapshot)),
                ],
              ),
      );
    }
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shared planner'),
          actions: [
            IconButton(
              tooltip: 'Refresh planner',
              onPressed: state.loading
                  ? null
                  : () => ref
                        .read(sharedPlannerControllerProvider.notifier)
                        .load(coupleId),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Bucket list'),
              Tab(text: 'Important dates'),
              Tab(text: 'Plans & calendar'),
            ],
          ),
        ),
        body: state.loading && snapshot == null
            ? const Center(child: CircularProgressIndicator())
            : snapshot == null
            ? _loadError(coupleId, state.error)
            : Column(
                children: [
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.md,
                        AppSpace.sm,
                        AppSpace.md,
                        0,
                      ),
                      child: _InlineError(
                        message: state.error!,
                        onRetry: () => ref
                            .read(sharedPlannerControllerProvider.notifier)
                            .load(coupleId),
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _BucketListTab(
                          coupleId: coupleId,
                          items: snapshot.bucketItems,
                        ),
                        _ImportantDatesTab(
                          coupleId: coupleId,
                          dates: snapshot.importantDates,
                        ),
                        _PlansTab(coupleId: coupleId, plans: snapshot.plans),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Uri _routeUri(BuildContext context) {
    try {
      return GoRouterState.of(context).uri;
    } catch (_) {
      return Uri(path: '/planner');
    }
  }

  void _openSearchTarget(
    String coupleId,
    SharedPlannerSnapshot snapshot,
    String type,
    String id,
  ) {
    switch (type) {
      case 'bucket':
        for (final item in snapshot.bucketItems) {
          if (item.id == id) {
            unawaited(_editBucket(context, ref, coupleId, item));
            return;
          }
        }
      case 'date':
        for (final date in snapshot.importantDates) {
          if (date.id == id) {
            unawaited(_editDate(context, ref, coupleId, date));
            return;
          }
        }
      case 'plan':
        for (final plan in snapshot.plans) {
          if (plan.id == id) {
            unawaited(_editPlan(context, ref, coupleId, plan));
            return;
          }
        }
      case 'task':
        for (final plan in snapshot.plans) {
          for (final task in plan.tasks) {
            if (task.id == id) {
              unawaited(_editTask(context, ref, task));
              return;
            }
          }
        }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('That item is no longer available. Refresh the planner.'),
      ),
    );
  }

  Widget _unpaired() => Scaffold(
    appBar: AppBar(title: const Text('Shared planner')),
    body: _unpairedBody(),
  );

  Widget _unpairedBody() => ResponsivePage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'A space for two',
          description: 'The shared planner becomes available after both partners accept the invitation.',
        ),
        const SizedBox(height: AppSpace.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 30),
              const SizedBox(height: AppSpace.md),
              const Text('No planner data has been loaded.'),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: () => context.go('/partner'),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Link with your partner'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _plannerTab(
    int index,
    String coupleId,
    SharedPlannerSnapshot snapshot,
  ) => switch (index) {
    1 => _ImportantDatesTab(coupleId: coupleId, dates: snapshot.importantDates),
    2 => _PlansTab(coupleId: coupleId, plans: snapshot.plans),
    _ => _BucketListTab(coupleId: coupleId, items: snapshot.bucketItems),
  };

  Widget _loadError(String coupleId, String? error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 36),
          const SizedBox(height: AppSpace.md),
          Text(error ?? 'We could not load your shared planner.'),
          const SizedBox(height: AppSpace.md),
          FilledButton.tonalIcon(
            onPressed: () => ref
                .read(sharedPlannerControllerProvider.notifier)
                .load(coupleId),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _BucketListTab extends ConsumerWidget {
  const _BucketListTab({required this.coupleId, required this.items});
  final String coupleId;
  final List<BucketListItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = items.where((item) => item.completed).length;
    final ratio = items.isEmpty ? 0.0 : done / items.length;
    return _TabPage(
      title: 'Things to do together',
      description: 'Collect the little adventures and big dreams you share.',
      actionLabel: 'Add an idea',
      actionIcon: Icons.add_rounded,
      onAction: () => _editBucket(context, ref, coupleId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SurfaceCard(
            padding: AppSpace.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        items.isEmpty
                            ? 'Your shared progress'
                            : '$done of ${items.length} done',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text('${(ratio * 100).round()}%'),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                Semantics(
                  label:
                      'Bucket list progress, ${(ratio * 100).round()} percent',
                  child: LinearProgressIndicator(value: ratio),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (items.isEmpty)
            const _EmptyCard(
              icon: Icons.auto_awesome_outlined,
              title: 'A list with room to dream',
              description: 'Add your first shared idea and choose a category.',
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: SurfaceCard(
                  padding: AppSpace.md,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: item.completed,
                        onChanged: (_) => ref
                            .read(sharedPlannerControllerProvider.notifier)
                            .toggleBucket(item),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: InkWell(
                          onTap: () =>
                              _editBucket(context, ref, coupleId, item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        decoration: item.completed
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                ),
                                if (item.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(item.description),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    _Pill(item.category.label),
                                    if (item.targetDate != null)
                                      _Pill(
                                        'By ${_dateLabel(item.targetDate!)}',
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete ${item.title}',
                        onPressed: () => _confirmDelete(
                          context,
                          title: 'Delete this idea?',
                          onDelete: () => ref
                              .read(sharedPlannerControllerProvider.notifier)
                              .deleteBucket(item),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _ImportantDatesTab extends ConsumerWidget {
  const _ImportantDatesTab({required this.coupleId, required this.dates});
  final String coupleId;
  final List<ImportantDateEntry> dates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final sorted = [...dates]
      ..sort((a, b) => a.daysUntil(today).compareTo(b.daysUntil(today)));
    return _TabPage(
      title: 'The dates that matter',
      description:
          'Birthdays, anniversaries, and little milestones to look forward to.',
      actionLabel: 'Add a date',
      actionIcon: Icons.event_available_rounded,
      onAction: () => _editDate(context, ref, coupleId),
      child: dates.isEmpty
          ? const _EmptyCard(
              icon: Icons.calendar_month_rounded,
              title: 'Keep a moment close',
              description:
                  'Add a birthday, anniversary, or another special date.',
            )
          : Column(
              children: [
                for (final entry in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: SurfaceCard(
                      padding: AppSpace.md,
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Builder(
                                  builder: (context) {
                                    final remaining = entry.daysUntil(today);
                                    return Column(
                                      children: [
                                        Text(
                                          remaining < 0 ? '—' : '$remaining',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        Text(
                                          remaining < 0
                                              ? 'passed'
                                              : remaining == 0
                                              ? 'today'
                                              : remaining == 1
                                              ? 'day'
                                              : 'days',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  _editDate(context, ref, coupleId, entry),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_capitalize(entry.kind.name)} · ${entry.annual ? 'Every year' : _dateLabel(entry.date)}',
                                    ),
                                    if (entry.notes.isNotEmpty)
                                      Text(
                                        entry.notes,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete ${entry.title}',
                            onPressed: () => _confirmDelete(
                              context,
                              title: 'Delete this date?',
                              onDelete: () => ref
                                  .read(
                                    sharedPlannerControllerProvider.notifier,
                                  )
                                  .deleteImportantDate(entry),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PlansTab extends ConsumerWidget {
  const _PlansTab({required this.coupleId, required this.plans});
  final String coupleId;
  final List<SharedPlan> plans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TabPage(
      title: 'Make a plan together',
      description: 'Choose a time, share the details, and keep the little tasks in one place.',
      actionLabel: 'New plan',
      actionIcon: Icons.add_rounded,
      onAction: () => _editPlan(context, ref, coupleId),
      child: plans.isEmpty
          ? const _EmptyCard(
              icon: Icons.event_note_rounded,
              title: 'Nothing on the calendar yet',
              description: 'Create a plan and add tasks for both of you.',
            )
          : Column(
              children: [
                for (final plan in plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: SurfaceCard(
                      padding: AppSpace.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.event_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: AppSpace.sm),
                              Expanded(
                                child: InkWell(
                                  onTap: () =>
                                      _editPlan(context, ref, coupleId, plan),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dateTimeLabel(context, plan.startsAt),
                                      ),
                                      if (plan.location.isNotEmpty)
                                        Text(plan.location),
                                      if (plan.description.isNotEmpty)
                                        Text(plan.description),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit ${plan.title}',
                                onPressed: () =>
                                    _editPlan(context, ref, coupleId, plan),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete ${plan.title}',
                                onPressed: () => _confirmDelete(
                                  context,
                                  title: 'Delete this plan and its checklist?',
                                  onDelete: () => ref
                                      .read(
                                        sharedPlannerControllerProvider
                                            .notifier,
                                      )
                                      .deletePlan(plan),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          if (plan.tasks.isEmpty)
                            const Text('No checklist tasks yet.')
                          else
                            for (final task in plan.tasks)
                              Row(
                                children: [
                                  Checkbox(
                                    value: task.completed,
                                    onChanged: (_) => ref
                                        .read(
                                          sharedPlannerControllerProvider
                                              .notifier,
                                        )
                                        .toggleTask(task),
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () =>
                                          _editTask(context, ref, task),
                                      child: Text(
                                        task.title,
                                        style: TextStyle(
                                          decoration: task.completed
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete task ${task.title}',
                                    onPressed: () => _confirmDelete(
                                      context,
                                      title: 'Remove this task?',
                                      onDelete: () => ref
                                          .read(
                                            sharedPlannerControllerProvider
                                                .notifier,
                                          )
                                          .deleteTask(task),
                                    ),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                          const SizedBox(height: AppSpace.xs),
                          OutlinedButton.icon(
                            onPressed: () => _addTask(context, ref, plan),
                            icon: const Icon(Icons.add_task_rounded),
                            label: const Text('Add checklist task'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String description;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 520 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppLayout.maxContent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact) ...[
                  SectionHeading(title: title, description: description),
                  const SizedBox(height: AppSpace.md),
                  FilledButton.tonalIcon(
                    onPressed: onAction,
                    icon: Icon(actionIcon),
                    label: Text(actionLabel),
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: SectionHeading(
                          title: title,
                          description: description,
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      FilledButton.tonalIcon(
                        onPressed: onAction,
                        icon: Icon(actionIcon),
                        label: Text(actionLabel),
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpace.lg),
                child,
                const SizedBox(height: AppSpace.lg),
                Text(
                  'Changes are shared with your partner when saved. Planner data is available online while your couple space is active.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Row(
      children: [
        Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(description),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: SurfaceCard(
      padding: AppSpace.sm,
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _editBucket(
  BuildContext context,
  WidgetRef ref,
  String coupleId, [
  BucketListItem? item,
]) async {
  final title = TextEditingController(text: item?.title ?? '');
  final description = TextEditingController(text: item?.description ?? '');
  var category = item?.category ?? PlannerBucketCategory.other;
  DateTime? targetDate = item?.targetDate;
  final values = await _showDialogAndWaitForClose<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(item == null ? 'Add to your bucket list' : 'Edit idea'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Idea'),
                ),
                TextField(
                  controller: description,
                  maxLines: 3,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'A few details'),
                ),
                const SizedBox(height: AppSpace.sm),
                DropdownButtonFormField<PlannerBucketCategory>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final value in PlannerBucketCategory.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => category = value);
                  },
                ),
                const SizedBox(height: AppSpace.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    targetDate == null
                        ? 'No target date'
                        : 'Target: ${_dateLabel(targetDate!)}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Choose target date',
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: targetDate ?? DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2200),
                          );
                          if (value != null) {
                            setDialogState(() => targetDate = value);
                          }
                        },
                        icon: const Icon(Icons.calendar_month_rounded),
                      ),
                      if (targetDate != null)
                        IconButton(
                          tooltip: 'Clear target date',
                          onPressed: () =>
                              setDialogState(() => targetDate = null),
                          icon: const Icon(Icons.clear_rounded),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, {
                'title': title.text.trim(),
                'description': description.text.trim(),
                'category_key': category.name,
                'target_date': targetDate == null
                    ? null
                    : _dateKey(targetDate!),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  description.dispose();
  if (values == null) return;
  final controller = ref.read(sharedPlannerControllerProvider.notifier);
  final success = item == null
      ? await controller.createBucket(values)
      : await controller.updateBucket(item, values);
  if (context.mounted) {
    _toast(
      context,
      success
          ? 'Idea saved for both of you.'
          : 'Could not save this idea. Refresh and try again.',
    );
  }
}

Future<void> _editDate(
  BuildContext context,
  WidgetRef ref,
  String coupleId, [
  ImportantDateEntry? entry,
]) async {
  final title = TextEditingController(text: entry?.title ?? '');
  final notes = TextEditingController(text: entry?.notes ?? '');
  var kind = entry?.kind ?? ImportantDateKind.special;
  var date = entry?.date ?? DateTime.now();
  var annual = entry?.annual ?? true;
  var leapPolicy = entry?.leapDayPolicy;
  final values = await _showDialogAndWaitForClose<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          entry == null ? 'Add an important date' : 'Edit important date',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ImportantDateKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Kind'),
                  items: [
                    for (final value in ImportantDateKind.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(_capitalize(value.name)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        kind = value;
                        if (kind != ImportantDateKind.special) annual = true;
                      });
                    }
                  },
                ),
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'What are you celebrating?',
                  ),
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Date: ${_dateLabel(date)}'),
                  trailing: IconButton(
                    tooltip: 'Choose date',
                    onPressed: () async {
                      final value = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (value != null) setDialogState(() => date = value);
                    },
                    icon: const Icon(Icons.calendar_month_rounded),
                  ),
                ),
                if (kind == ImportantDateKind.special)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Repeat every year'),
                    value: annual,
                    onChanged: (value) => setDialogState(() {
                      annual = value;
                      if (!value) leapPolicy = null;
                    }),
                  ),
                if (annual) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'For February 29, choose what happens in non-leap years.',
                    ),
                  ),
                  DropdownButtonFormField<AnnualLeapDayPolicy>(
                    initialValue: leapPolicy,
                    decoration: const InputDecoration(
                      labelText: 'Leap-day behavior',
                    ),
                    items: [
                      for (final value in AnnualLeapDayPolicy.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => leapPolicy = value),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty || (annual && leapPolicy == null)) {
                return;
              }
              Navigator.pop(dialogContext, {
                'kind': kind.name,
                'title': title.text.trim(),
                'notes': notes.text.trim(),
                'date_value': _dateKey(date),
                'recurrence': annual ? 'annual' : 'once',
                'leap_day_policy': annual ? leapPolicy!.name : null,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  notes.dispose();
  if (values == null) return;
  final controller = ref.read(sharedPlannerControllerProvider.notifier);
  final success = entry == null
      ? await controller.createImportantDate(values)
      : await controller.updateImportantDate(entry, values);
  if (context.mounted) {
    _toast(
      context,
      success
          ? 'Important date saved.'
          : 'Could not save this date. Refresh and try again.',
    );
  }
}

Future<void> _editPlan(
  BuildContext context,
  WidgetRef ref,
  String coupleId, [
  SharedPlan? plan,
]) async {
  final title = TextEditingController(text: plan?.title ?? '');
  final description = TextEditingController(text: plan?.description ?? '');
  final location = TextEditingController(text: plan?.location ?? '');
  var startsAt = plan?.startsAt ?? DateTime.now().add(const Duration(hours: 1));
  DateTime? endsAt = plan?.endsAt;
  final values = await _showDialogAndWaitForClose<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(plan == null ? 'Make a plan' : 'Edit plan'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Plan name'),
                ),
                TextField(
                  controller: description,
                  maxLines: 3,
                  maxLength: 10000,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                TextField(
                  controller: location,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Starts'),
                  subtitle: Text(_dateTimeLabel(context, startsAt)),
                  trailing: IconButton(
                    tooltip: 'Choose date and time',
                    onPressed: () async {
                      final dateValue = await showDatePicker(
                        context: context,
                        initialDate: startsAt,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (dateValue == null || !context.mounted) return;
                      final timeValue = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(startsAt),
                      );
                      if (timeValue != null) {
                        setDialogState(
                          () => startsAt = DateTime(
                            dateValue.year,
                            dateValue.month,
                            dateValue.day,
                            timeValue.hour,
                            timeValue.minute,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.schedule_rounded),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    endsAt == null
                        ? 'No end time'
                        : 'Ends · ${_dateTimeLabel(context, endsAt!)}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Choose end time',
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                              endsAt ?? startsAt.add(const Duration(hours: 1)),
                            ),
                          );
                          if (time != null) {
                            setDialogState(
                              () => endsAt = DateTime(
                                startsAt.year,
                                startsAt.month,
                                startsAt.day,
                                time.hour,
                                time.minute,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.more_time_rounded),
                      ),
                      if (endsAt != null)
                        IconButton(
                          tooltip: 'Clear end time',
                          onPressed: () => setDialogState(() => endsAt = null),
                          icon: const Icon(Icons.clear_rounded),
                        ),
                    ],
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Times are saved as an instant and displayed in each partner’s device time zone.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty ||
                  (endsAt != null && !endsAt!.isAfter(startsAt))) {
                return;
              }
              Navigator.pop(dialogContext, {
                'title': title.text.trim(),
                'description': description.text.trim(),
                'location': location.text.trim(),
                'starts_at': startsAt.toUtc().toIso8601String(),
                'ends_at': endsAt?.toUtc().toIso8601String(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  description.dispose();
  location.dispose();
  if (values == null) return;
  final controller = ref.read(sharedPlannerControllerProvider.notifier);
  final success = plan == null
      ? await controller.createPlan(values)
      : await controller.updatePlan(plan, values);
  if (success && plan == null) {
    // The refreshed snapshot now contains the new parent; tasks are added from
    // its card so both mutations remain individually authorized and retryable.
  }
  if (context.mounted) {
    _toast(
      context,
      success
          ? 'Plan saved.'
          : 'Could not save this plan. Refresh and try again.',
    );
  }
}

Future<void> _addTask(
  BuildContext context,
  WidgetRef ref,
  SharedPlan plan,
) async {
  final title = TextEditingController();
  final value = await _textDialog(context, title, 'Add checklist task', 'Task');
  title.dispose();
  if (value == null || value.trim().isEmpty) return;
  final success = await ref
      .read(sharedPlannerControllerProvider.notifier)
      .createTask(plan.id, value.trim());
  if (context.mounted) {
    _toast(
      context,
      success
          ? 'Task added.'
          : 'Could not add the task. Refresh and try again.',
    );
  }
}

Future<void> _editTask(
  BuildContext context,
  WidgetRef ref,
  PlanTask task,
) async {
  final title = TextEditingController(text: task.title);
  final value = await _textDialog(
    context,
    title,
    'Edit checklist task',
    'Task',
  );
  title.dispose();
  if (value == null || value.trim().isEmpty) return;
  final success = await ref
      .read(sharedPlannerControllerProvider.notifier)
      .renameTask(task, value.trim());
  if (context.mounted) {
    _toast(
      context,
      success
          ? 'Task updated.'
          : 'Could not update the task. Refresh and try again.',
    );
  }
}

Future<String?> _textDialog(
  BuildContext context,
  TextEditingController controller,
  String title,
  String label,
) => _showDialogAndWaitForClose<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 240,
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) {
        if (controller.text.trim().isNotEmpty) {
          Navigator.pop(context, controller.text);
        }
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text);
          }
        },
        child: const Text('Save'),
      ),
    ],
  ),
);

Future<void> _confirmDelete(
  BuildContext context, {
  required String title,
  required Future<bool> Function() onDelete,
}) async {
  final confirm = await _showDialogAndWaitForClose<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: const Text(
        'This removes the item from the shared planner for both partners.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  final success = await onDelete();
  if (context.mounted) {
    _toast(
      context,
      success
          ? 'Item deleted.'
          : 'Could not delete the item. Refresh and try again.',
    );
  }
}

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

Future<T?> _showDialogAndWaitForClose<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context).push<T>(route);
  await route.completed;
  return result;
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _dateLabel(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
String _dateTimeLabel(BuildContext context, DateTime date) =>
    '${_dateLabel(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
