import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../authentication/application/auth_controller.dart';
import '../application/shared_planner_controller.dart';
import '../domain/shared_planner_repository.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _query = TextEditingController();
  String? _requestedCouple;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final couple = auth.context?.spaces
        .where((space) => space.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;
    final planner = ref.watch(sharedPlannerControllerProvider);
    if (coupleId != _requestedCouple) {
      _requestedCouple = coupleId;
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

    final results = coupleId == null || planner.coupleId != coupleId
        ? const <_SearchResult>[]
        : _search(planner.snapshot, _query.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Search your shared space')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Search ideas, dates, plans, and tasks',
                      labelText: 'Search shared planner',
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _query.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear_rounded),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Expanded(
                    child: coupleId == null
                        ? _message(
                            Icons.lock_outline_rounded,
                            'Link your partner to search shared planner data.',
                          )
                        : planner.loading && planner.snapshot == null
                        ? const Center(child: CircularProgressIndicator())
                        : planner.snapshot == null
                        ? _error(planner.error)
                        : _query.text.trim().isEmpty
                        ? _message(
                            Icons.manage_search_rounded,
                            'Search across your shared ideas, dates, plans, and checklists.',
                          )
                        : results.isEmpty
                        ? _message(
                            Icons.search_off_rounded,
                            'No matches for “${_query.text.trim()}”.',
                          )
                        : _organizedResults(results),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _organizedResults(List<_SearchResult> results) {
    const kinds = [
      _SearchKind.bucket,
      _SearchKind.date,
      _SearchKind.plan,
      _SearchKind.task,
    ];
    final children = <Widget>[];
    for (final kind in kinds) {
      final group = results.where((result) => result.kind == kind).toList();
      if (group.isEmpty) continue;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm, top: AppSpace.md),
          child: SectionHeading(
            title: kind.label,
            description:
                '${group.length} ${group.length == 1 ? 'match' : 'matches'}',
          ),
        ),
      );
      for (final result in group) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: SurfaceCard(
              padding: 0,
              child: ListTile(
                leading: Icon(kind.icon),
                title: Text(result.title),
                subtitle: Text(result.subtitle),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => context.go(
                  '/planner?tab=${result.tab}&type=${result.type}&item=${Uri.encodeComponent(result.id)}',
                ),
              ),
            ),
          ),
        );
      }
    }
    return ListView(padding: EdgeInsets.zero, children: children);
  }

  Widget _message(IconData icon, String message) => Center(
    child: SurfaceCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: AppSpace.md),
          Text(message),
        ],
      ),
    ),
  );

  Widget _error(String? message) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message ?? 'Search could not load shared data.'),
        const SizedBox(height: AppSpace.md),
        FilledButton.tonalIcon(
          onPressed: () {
            final id = _requestedCouple;
            if (id != null) {
              unawaited(
                ref.read(sharedPlannerControllerProvider.notifier).load(id),
              );
            }
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ],
    ),
  );

  List<_SearchResult> _search(SharedPlannerSnapshot? snapshot, String query) {
    if (snapshot == null || query.trim().isEmpty) return const [];
    final needle = query.trim().toLowerCase();
    final results = <_SearchResult>[];
    for (final item in snapshot.bucketItems) {
      if (_matches(needle, [
        item.title,
        item.description,
        item.category.label,
      ])) {
        results.add(
          _SearchResult(
            kind: _SearchKind.bucket,
            id: item.id,
            title: item.title,
            subtitle:
                '${item.category.label} · ${item.completed ? 'Completed' : 'In progress'}',
            tab: 0,
            type: 'bucket',
          ),
        );
      }
    }
    for (final entry in snapshot.importantDates) {
      if (_matches(needle, [entry.title, entry.notes, entry.kind.name])) {
        results.add(
          _SearchResult(
            kind: _SearchKind.date,
            id: entry.id,
            title: entry.title,
            subtitle:
                '${_capitalize(entry.kind.name)} · ${_dateLabel(entry.date)}',
            tab: 1,
            type: 'date',
          ),
        );
      }
    }
    for (final plan in snapshot.plans) {
      if (_matches(needle, [plan.title, plan.description, plan.location])) {
        results.add(
          _SearchResult(
            kind: _SearchKind.plan,
            id: plan.id,
            title: plan.title,
            subtitle:
                '${_dateLabel(plan.startsAt)}${plan.location.isEmpty ? '' : ' · ${plan.location}'}',
            tab: 2,
            type: 'plan',
          ),
        );
      }
      for (final task in plan.tasks) {
        if (_matches(needle, [task.title, plan.title])) {
          results.add(
            _SearchResult(
              kind: _SearchKind.task,
              id: task.id,
              title: task.title,
              subtitle:
                  'Checklist · ${plan.title} · ${task.completed ? 'Done' : 'To do'}',
              tab: 2,
              type: 'task',
            ),
          );
        }
      }
    }
    return results;
  }

  bool _matches(String query, List<String> values) =>
      values.any((value) => value.toLowerCase().contains(query));

  String _capitalize(String value) =>
      value[0].toUpperCase() + value.substring(1);

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

enum _SearchKind {
  bucket('Bucket list', Icons.checklist_rounded),
  date('Important dates', Icons.cake_outlined),
  plan('Plans', Icons.event_note_outlined),
  task('Checklist tasks', Icons.task_alt_rounded);

  const _SearchKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _SearchResult {
  const _SearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tab,
    required this.type,
  });

  final _SearchKind kind;
  final String id;
  final String title;
  final String subtitle;
  final int tab;
  final String type;
}
