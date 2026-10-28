import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/design_tokens.dart';
import 'together_mark.dart';

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.path, required this.child, super.key});
  final String path;
  final Widget child;
  static const paths = ['/', '/studio', '/settings'];
  static const labels = ['Home', 'Studio', 'Appearance'];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.auto_awesome_outlined,
    Icons.tune_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final desktop = width >= AppLayout.desktop;
    final tablet = width >= AppLayout.tablet && !desktop;
    final drawer = width < AppLayout.tablet && largeText;
    final selected = paths.indexOf(path).clamp(0, 2);
    void go(int index) => context.go(paths[index]);
    return Scaffold(
      drawer: drawer
          ? Drawer(
              child: SafeArea(
                child: _Sidebar(
                  selected: selected,
                  onSelect: (index) {
                    Navigator.of(context).pop();
                    go(index);
                  },
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: Text(
          path == '/settings'
              ? 'Appearance'
              : desktop
              ? (path == '/studio' ? 'Visual studio' : 'Your space')
              : 'Twogethera',
        ),
        leading: path == '/settings'
            ? IconButton(
                tooltip: 'Back to home',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => go(0),
              )
            : null,
        actions: [
          if (path != '/settings')
            IconButton(
              tooltip: 'Appearance settings',
              onPressed: () => go(2),
              icon: const Icon(Icons.tune_rounded),
            ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: width < AppLayout.tablet && !largeText
          ? NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: go,
              destinations: [
                for (var i = 0; i < paths.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            )
          : null,
      body: LayoutBuilder(
        builder: (context, bodyConstraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              SizedBox(
                width: 236,
                child: _Sidebar(selected: selected, onSelect: go),
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
                      onDestinationSelected: go,
                      labelType: largeText
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < paths.length; i++)
                          NavigationRailDestination(
                            icon: Tooltip(
                              message: labels[i],
                              child: Icon(icons[i]),
                            ),
                            label: Text(labels[i]),
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
  const _Sidebar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: BrandColors.of(context).border)),
    ),
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: TogetherMark(size: 64),
        ),
        Text('Twogethera', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'A life, beautifully shared.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 40),
        for (var i = 0; i < AdaptiveShell.paths.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              selected: selected == i,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Icon(AdaptiveShell.icons[i]),
              title: Text(AdaptiveShell.labels[i]),
              onTap: () => onSelect(i),
            ),
          ),
        const SizedBox(height: 40),
        const Text('A thoughtful beginning.\nAn early look at Twogethera.'),
      ],
    ),
  );
}
