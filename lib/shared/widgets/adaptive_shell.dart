import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/design_tokens.dart';
import '../../features/authentication/application/auth_controller.dart';
import '../../features/shared_planner/application/shared_planner_controller.dart';
import 'together_mark.dart';

enum _UtilityDestination { memories, studio, appearance }

class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({
    required this.path,
    required this.queryParameters,
    required this.child,
    super.key,
  });

  final String path;
  final Map<String, String> queryParameters;
  final Widget child;

  static const plannerPaths = [
    '/',
    '/planner?tab=0',
    '/planner?tab=1',
    '/planner?tab=2',
    '/budget',
  ];
  static const plannerLabels = [
    'Summary',
    'Bucket List',
    'Important Dates',
    'Plans & Calendar',
    'Budget',
  ];
  static const compactLabels = [
    'Summary',
    'Bucket',
    'Dates',
    'Plans',
    'Budget',
  ];
  static const plannerIcons = [
    Icons.space_dashboard_outlined,
    Icons.checklist_rounded,
    Icons.cake_outlined,
    Icons.event_note_outlined,
    Icons.savings_outlined,
  ];

  int? get selectedIndex {
    if (path == '/budget') return 4;
    if (path == '/planner') {
      final tab = int.tryParse(queryParameters['tab'] ?? '0') ?? 0;
      return tab.clamp(0, 2) + 1;
    }
    return path == '/' ? 0 : null;
  }

  String get pageTitle => switch (path) {
    '/planner' => switch (queryParameters['tab']) {
      '1' => 'Important Dates',
      '2' => 'Plans & Calendar',
      _ => 'Bucket List',
    },
    '/search' => 'Search',
    '/budget' => 'Budget',
    '/memories' => 'Memories',
    '/studio' => 'Design Studio',
    '/settings' => 'Appearance',
    _ => 'Summary',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final authenticated = auth.phase == AuthPhase.authenticated;
    final width = MediaQuery.sizeOf(context).width;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final desktop = width >= AppLayout.desktop;
    final tablet = width >= AppLayout.tablet && !desktop;
    final drawer = width < AppLayout.tablet && largeText;
    final selected = selectedIndex;
    final primaryRoute = selected != null;

    void navigatePlanner(int index) {
      if (index < 4) {
        context.go(plannerPaths[index]);
      } else {
        context.go('/budget');
      }
    }

    void navigateUtility(_UtilityDestination destination) {
      context.go(switch (destination) {
        _UtilityDestination.memories => '/memories',
        _UtilityDestination.studio => '/studio',
        _UtilityDestination.appearance => '/settings',
      });
    }

    void backToSummary() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }

    return Scaffold(
      drawer: drawer
          ? Drawer(
              child: SafeArea(
                child: _Sidebar(
                  selected: selected,
                  onSelectPlanner: (index) {
                    Navigator.of(context).pop();
                    navigatePlanner(index);
                  },
                  onSelectUtility: (destination) {
                    Navigator.of(context).pop();
                    navigateUtility(destination);
                  },
                  onBudget: () {
                    Navigator.of(context).pop();
                    navigatePlanner(4);
                  },
                ),
              ),
            )
          : null,
      appBar: AppBar(
        leading: path == '/' && drawer
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              )
            : path == '/'
            ? null
            : IconButton(
                tooltip: 'Back',
                onPressed: backToSummary,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(pageTitle),
        actions: [
          IconButton(
            tooltip: 'Go to Summary',
            onPressed: () => context.go('/'),
            icon: const TogetherMark(size: 38),
          ),
          IconButton(
            tooltip: 'Search your shared planner',
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search_rounded),
          ),
          if (path == '/planner')
            IconButton(
              tooltip: 'Refresh planner',
              onPressed: () {
                final couple = auth.context?.spaces
                    .where((space) => space.state == 'paired')
                    .firstOrNull;
                if (couple != null) {
                  ref
                      .read(sharedPlannerControllerProvider.notifier)
                      .load(couple.id);
                }
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
          PopupMenuButton<_UtilityDestination>(
            tooltip: 'More options',
            onSelected: navigateUtility,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _UtilityDestination.memories,
                child: Text('Memories'),
              ),
              PopupMenuItem(
                value: _UtilityDestination.studio,
                child: Text('Design Studio'),
              ),
              PopupMenuItem(
                value: _UtilityDestination.appearance,
                child: Text('Appearance'),
              ),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          IconButton(
            tooltip: authenticated ? 'Account' : 'Sign in',
            onPressed: () =>
                context.go(authenticated ? '/account' : '/auth/welcome'),
            icon: Icon(
              authenticated
                  ? Icons.account_circle_outlined
                  : Icons.login_rounded,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      bottomNavigationBar:
          width < AppLayout.tablet && !largeText && primaryRoute
          ? NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: navigatePlanner,
              destinations: [
                for (var i = 0; i < plannerLabels.length; i++)
                  NavigationDestination(
                    tooltip: plannerLabels[i],
                    icon: Icon(plannerIcons[i]),
                    label: compactLabels[i],
                  ),
              ],
            )
          : null,
      body: LayoutBuilder(
        builder: (context, bodyConstraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              SizedBox(
                width: 248,
                child: _Sidebar(
                  selected: selected,
                  onSelectPlanner: navigatePlanner,
                  onSelectUtility: navigateUtility,
                  onBudget: () => navigatePlanner(4),
                ),
              ),
            if (tablet)
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: bodyConstraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: selected,
                      onDestinationSelected: navigatePlanner,
                      labelType: largeText
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < plannerLabels.length; i++)
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: plannerLabels[i],
                              child: Icon(plannerIcons[i]),
                            ),
                            label: Text(plannerLabels[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.onSelectPlanner,
    required this.onSelectUtility,
    required this.onBudget,
  });

  final int? selected;
  final ValueChanged<int> onSelectPlanner;
  final ValueChanged<_UtilityDestination> onSelectUtility;
  final VoidCallback onBudget;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: BrandColors.of(context).border)),
    ),
    child: ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        Semantics(
          button: true,
          label: 'Twogethera Summary',
          child: InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(18),
            child: const Padding(
              padding: EdgeInsets.all(AppSpace.xs),
              child: Row(
                children: [
                  TogetherMark(size: 48),
                  SizedBox(width: AppSpace.sm),
                  Expanded(child: Text('Twogethera')),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        for (var i = 0; i < AdaptiveShell.plannerLabels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: ListTile(
              selected: i == selected,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Icon(AdaptiveShell.plannerIcons[i]),
              title: Text(AdaptiveShell.plannerLabels[i]),
              onTap: i == 4 ? onBudget : () => onSelectPlanner(i),
            ),
          ),
        const Divider(height: AppSpace.xl),
        Text('More', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpace.xs),
        ListTile(
          leading: const Icon(Icons.search_rounded),
          title: const Text('Search'),
          selected: ModalRoute.of(context)?.settings.name == '/search',
          onTap: () => context.go('/search'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Memories'),
          onTap: () => onSelectUtility(_UtilityDestination.memories),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Design Studio'),
          onTap: () => onSelectUtility(_UtilityDestination.studio),
        ),
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Appearance'),
          onTap: () => onSelectUtility(_UtilityDestination.appearance),
        ),
      ],
    ),
  );
}
