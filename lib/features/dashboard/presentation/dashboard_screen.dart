import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../../shared/widgets/together_mark.dart';
import '../../authentication/application/auth_controller.dart';
import '../../shared_planner/application/shared_planner_controller.dart';
import '../../shared_planner/domain/shared_planner_repository.dart';
import '../application/dashboard_preferences_controller.dart';
import '../domain/dashboard_preferences.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _requestedUser;
  String? _requestedCouple;

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
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _WelcomeHero(),
          const SizedBox(height: 40),
          const SectionHeading(
            title: 'Our story starts here',
            description:
                'Room for the big dreams. And the beautifully ordinary days.',
          ),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: userId == null || preferences.saving
                  ? null
                  : () => _customizeDashboard(effectivePreferences),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Customize dashboard'),
            ),
          ),
          if (preferences.userId == userId && preferences.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                preferences.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if ((preferences.userId == userId && preferences.loading) ||
              (coupleId != null && planner.loading && snapshot == null))
            const LinearProgressIndicator(),
          if (coupleId != null && planner.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Row(
                children: [
                  Expanded(child: Text(planner.error!)),
                  TextButton(
                    onPressed: () => ref
                        .read(sharedPlannerControllerProvider.notifier)
                        .load(coupleId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          for (final module in effectivePreferences.order)
            if (effectivePreferences.visible.contains(module))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: _DashboardSummaryModule(
                  module: module,
                  snapshot: snapshot,
                  paired: coupleId != null,
                  onOpen: (type, id, tab) => context.go(
                    '/planner?tab=$tab&type=$type&item=${Uri.encodeComponent(id)}',
                  ),
                ),
              ),
          const SizedBox(height: 24),
          SurfaceCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Make plans together',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Keep your shared ideas, important dates, and plans in one calm place.',
                    ),
                  ],
                );
                final action = FilledButton.tonalIcon(
                  onPressed: () => context.go('/planner'),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Open shared planner'),
                );
                if (constraints.maxWidth < 680 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [text, const SizedBox(height: 20), action],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 24),
                    action,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          SurfaceCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A space for two',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Invite your partner with a private, one-time code.',
                    ),
                  ],
                );
                final action = FilledButton.tonalIcon(
                  onPressed: () => context.go('/partner'),
                  icon: const Icon(Icons.favorite_border_rounded),
                  label: const Text('Partner linking'),
                );
                if (constraints.maxWidth < 680 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [text, const SizedBox(height: 20), action],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 24),
                    action,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const AdaptiveGrid(
            children: [
              IdeaCard(
                icon: Icons.north_east_rounded,
                title: 'A little more someday',
                description: 'The places to go. The things to try. A home for your shared dreams.',
              ),
              IdeaCard(
                icon: Icons.wb_sunny_outlined,
                title: 'Moments that matter',
                description:
                    'Milestones and small celebrations, held a little closer.',
              ),
              IdeaCard(
                icon: Icons.spa_outlined,
                title: 'Life, in your rhythm',
                description: 'A calmer way to make room for what matters to both of you.',
              ),
            ],
          ),
          const SizedBox(height: 32),
          SurfaceCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Made to feel like yours',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Explore the colors, details, and little interactions taking shape.',
                    ),
                  ],
                );
                final action = OutlinedButton.icon(
                  onPressed: () => context.go('/studio'),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Explore the studio'),
                );
                if (constraints.maxWidth < 680 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [text, const SizedBox(height: 24), action],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: text),
                    const SizedBox(width: 28),
                    action,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Thoughtfully built for a life together.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
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

class _DashboardSummaryModule extends StatelessWidget {
  const _DashboardSummaryModule({
    required this.module,
    required this.snapshot,
    required this.paired,
    required this.onOpen,
  });

  final DashboardModule module;
  final SharedPlannerSnapshot? snapshot;
  final bool paired;
  final void Function(String type, String id, int tab) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bucketItems =
        snapshot?.bucketItems.where((item) => !item.completed).toList() ??
        const <BucketListItem>[];
    final now = DateTime.now();
    final dates = List<ImportantDateEntry>.of(
      snapshot?.importantDates.where((entry) {
            final next = entry.nextOccurrence(now);
            return !next.isBefore(DateTime(now.year, now.month, now.day));
          }) ??
          const <ImportantDateEntry>[],
    );
    dates.sort(
      (a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)),
    );
    final plans = List<SharedPlan>.of(
      snapshot?.plans.where((plan) => !plan.startsAt.isBefore(now)) ??
          const <SharedPlan>[],
    );
    plans.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final (title, icon) = switch (module) {
      DashboardModule.bucketList => (
        'Active shared goals',
        Icons.checklist_rounded,
      ),
      DashboardModule.importantDates => ('Coming up', Icons.cake_outlined),
      DashboardModule.plans => ('Upcoming plans', Icons.event_note_outlined),
    };
    final count = switch (module) {
      DashboardModule.bucketList => bucketItems.length,
      DashboardModule.importantDates => dates.length,
      DashboardModule.plans => plans.length,
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
              if (paired && snapshot != null) Text('$count'),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          if (!paired)
            const Text('Link your partner to see shared planner summaries.')
          else if (snapshot == null)
            const Text(
              'Your shared summary will appear here when it is available.',
            )
          else if (count == 0)
            Text(switch (module) {
              DashboardModule.bucketList =>
                'No active ideas yet. Add one to start dreaming together.',
              DashboardModule.importantDates =>
                'No upcoming dates on your calendar.',
              DashboardModule.plans =>
                'No upcoming plans. Make room for something together.',
            })
          else ...[
            for (final item in switch (module) {
              DashboardModule.bucketList =>
                bucketItems
                    .take(2)
                    .map((item) => (item.title, 'bucket', item.id, 0))
                    .toList(),
              DashboardModule.importantDates =>
                dates
                    .take(2)
                    .map(
                      (item) => (
                        item.title,
                        '${item.daysUntil(now)} days away',
                        item.id,
                        1,
                      ),
                    )
                    .toList(),
              DashboardModule.plans =>
                plans
                    .take(2)
                    .map(
                      (item) => (
                        item.title,
                        _formatPlanDate(item.startsAt),
                        item.id,
                        2,
                      ),
                    )
                    .toList(),
            })
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.$1),
                subtitle: Text(
                  item.$2 == 'bucket' ? 'Bucket list idea' : item.$2,
                ),
                trailing: const Icon(Icons.arrow_forward_rounded, size: 18),
                onTap: () => onOpen(
                  switch (module) {
                    DashboardModule.bucketList => 'bucket',
                    DashboardModule.importantDates => 'date',
                    DashboardModule.plans => 'plan',
                  },
                  item.$3,
                  item.$4,
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatPlanDate(DateTime value) =>
      '${value.month}/${value.day} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(32),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          BrandColors.of(context).heroStart,
          BrandColors.of(context).heroEnd,
        ],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 600 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20;
          final words = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PreviewBadge(),
              const SizedBox(height: 32),
              Semantics(
                header: true,
                child: Text(
                  'A little space.\nFor the two of you.',
                  style: wide && constraints.maxWidth >= 900
                      ? Theme.of(context).textTheme.displayLarge
                      : Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Make room for shared dreams, meaningful dates, and everyday moments.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => context.go('/studio'),
                label: const Text('Discover the details'),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          );
          if (wide) {
            return Row(
              children: [
                Expanded(flex: 3, child: words),
                const SizedBox(width: 24),
                const Expanded(
                  flex: 2,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: TogetherMark(size: 260),
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              words,
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerRight,
                child: TogetherMark(size: 144),
              ),
            ],
          );
        },
      ),
    ),
  );
}
