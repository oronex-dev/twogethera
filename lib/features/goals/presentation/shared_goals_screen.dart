import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../../authentication/presentation/privacy_removal_confirmation.dart';
import '../application/shared_goals_controller.dart';
import '../domain/shared_goal_models.dart';

class SharedGoalsScreen extends ConsumerStatefulWidget {
  const SharedGoalsScreen({super.key});
  @override
  ConsumerState<SharedGoalsScreen> createState() => _SharedGoalsScreenState();
}

class _SharedGoalsScreenState extends ConsumerState<SharedGoalsScreen> {
  String? _requestedCouple;
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final couple = auth.context?.spaces
        .where((s) => s.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;
    final state = ref.watch(sharedGoalsControllerProvider);
    if (coupleId != null && _requestedCouple != coupleId) {
      _requestedCouple = coupleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(sharedGoalsControllerProvider.notifier).load(coupleId);
        }
      });
    }
    if (coupleId == null) {
      return const ResponsivePage(
        child: SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shared goals are for both of you'),
              SizedBox(height: 8),
              Text(
                'Link your partner to start working toward something together.',
              ),
            ],
          ),
        ),
      );
    }
    final snapshot = state.coupleId == coupleId ? state.snapshot : null;
    final goals =
        (snapshot?.goals ?? const <SharedGoal>[])
            .where(
              (g) =>
                  '${g.title} ${g.description} ${g.category} ${g.milestones.map((m) => m.title).join(' ')}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => a.status.index.compareTo(b.status.index));
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'Shared goals',
            description: 'Choose a meaningful goal, then mark progress together one milestone at a time.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search goals and milestones',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: state.saving ? null : () => _editGoal(coupleId),
                icon: const Icon(Icons.add),
                label: const Text('Create a goal'),
              ),
            ],
          ),
          if (state.error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(state.error!),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(sharedGoalsControllerProvider.notifier)
                      .load(coupleId),
                  child: const Text('Retry'),
                ),
              ),
            ),
          if (state.notice != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(state.notice!),
              ),
            ),
          if (state.loading && snapshot == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (goals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.flag_outlined, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      _query.isEmpty
                          ? 'A shared goal can start with one small step.'
                          : 'No goals match your search.',
                    ),
                    if (_query.isEmpty)
                      TextButton(
                        onPressed: () => _editGoal(coupleId),
                        child: const Text('Create your first goal'),
                      ),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            for (final goal in goals)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _GoalCard(
                  goal: goal,
                  onEdit: () => _editGoal(coupleId, goal),
                  onAddMilestone: () => _editMilestone(coupleId, goal),
                  onMilestone: (m) => _editMilestone(coupleId, goal, m),
                  onPrivacyRemoveGoal: (field) => confirmPrivacyRemoval(
                    context,
                    ref,
                    table: 'shared_goals',
                    recordId: goal.id,
                    field: field,
                    onSubmitted: () => ref
                        .read(sharedGoalsControllerProvider.notifier)
                        .load(coupleId),
                  ),
                  onPrivacyRemoveMilestone: (milestone, field) =>
                      confirmPrivacyRemoval(
                        context,
                        ref,
                        table: 'shared_goal_milestones',
                        recordId: milestone.id,
                        field: field,
                        onSubmitted: () => ref
                            .read(sharedGoalsControllerProvider.notifier)
                            .load(coupleId),
                      ),
                ),
              ),
          ],
          if (goals.any(
            (g) =>
                g.status == SharedGoalStatus.completed ||
                g.milestones.any((m) => m.completed),
          ))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Completed milestones and goals remain in your shared history.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editGoal(String coupleId, [SharedGoal? goal]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _GoalForm(goal: goal),
    );
    if (values == null || !mounted) return;
    await ref
        .read(sharedGoalsControllerProvider.notifier)
        .saveGoal(values, id: goal?.id, expectedRevision: goal?.revision);
  }

  Future<void> _editMilestone(
    String coupleId,
    SharedGoal goal, [
    SharedGoalMilestone? milestone,
  ]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _MilestoneForm(
        milestone: milestone,
        nextOrder: goal.milestones.length,
      ),
    );
    if (values == null || !mounted) return;
    await ref
        .read(sharedGoalsControllerProvider.notifier)
        .saveMilestone(
          goal.id,
          values,
          id: milestone?.id,
          expectedRevision: milestone?.revision,
        );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onEdit,
    required this.onAddMilestone,
    required this.onMilestone,
    required this.onPrivacyRemoveGoal,
    required this.onPrivacyRemoveMilestone,
  });
  final SharedGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onAddMilestone;
  final ValueChanged<SharedGoalMilestone> onMilestone;
  final ValueChanged<String?> onPrivacyRemoveGoal;
  final void Function(SharedGoalMilestone, String?) onPrivacyRemoveMilestone;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                goal.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Chip(label: Text(goal.status.name)),
            IconButton(
              tooltip: 'Edit goal',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'Privacy removal options',
              onSelected: (value) =>
                  onPrivacyRemoveGoal(value == 'record' ? null : value),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'record',
                  child: Text('Remove goal for privacy'),
                ),
                if (goal.description.isNotEmpty)
                  const PopupMenuItem(
                    value: 'description',
                    child: Text('Remove description only'),
                  ),
              ],
            ),
          ],
        ),
        Text(
          '${goal.category}${goal.targetOn == null ? '' : ' · target ${MaterialLocalizations.of(context).formatMediumDate(goal.targetOn!)}'}',
        ),
        if (goal.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(goal.description),
          ),
        const SizedBox(height: 12),
        Semantics(
          label:
              'Goal progress ${goal.completedMilestones} of ${goal.milestones.length} milestones',
          child: LinearProgressIndicator(value: goal.progress),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            goal.milestones.isEmpty
                ? (goal.status == SharedGoalStatus.completed
                      ? 'Completed'
                      : 'No milestones yet')
                : '${goal.completedMilestones} of ${goal.milestones.length} milestones complete',
          ),
        ),
        if (goal.milestones.isNotEmpty) ...[
          const Divider(height: 22),
          for (final milestone in goal.milestones)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                milestone.completed
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                milestone.title,
                style: milestone.completed
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
              subtitle: Text(
                milestone.targetOn == null
                    ? milestone.description
                    : '${milestone.description.isEmpty ? '' : '${milestone.description} · '}${MaterialLocalizations.of(context).formatMediumDate(milestone.targetOn!)}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Update milestone',
                    onPressed: () => onMilestone(milestone),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Milestone privacy removal options',
                    onSelected: (value) => onPrivacyRemoveMilestone(
                      milestone,
                      value == 'record' ? null : value,
                    ),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'record',
                        child: Text('Remove milestone for privacy'),
                      ),
                      if (milestone.description.isNotEmpty)
                        const PopupMenuItem(
                          value: 'description',
                          child: Text('Remove description only'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onAddMilestone,
            icon: const Icon(Icons.add),
            label: const Text('Add milestone'),
          ),
        ),
      ],
    ),
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({this.goal});
  final SharedGoal? goal;
  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.goal?.title ?? '');
  late final _description = TextEditingController(
    text: widget.goal?.description ?? '',
  );
  late final _category = TextEditingController(
    text: widget.goal?.category ?? 'relationship',
  );
  late SharedGoalStatus _status =
      widget.goal?.status ?? SharedGoalStatus.active;
  late DateTime? _target = widget.goal?.targetOn;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.goal == null ? 'Create a shared goal' : 'Edit goal'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _key,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Goal'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Add a title.' : null,
              ),
              TextFormField(
                controller: _description,
                maxLines: 2,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextFormField(
                controller: _category,
                maxLength: 48,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  helperText: 'Relationship, travel, learning, wellness, home, or your own.',
                ),
              ),
              DropdownButtonFormField<SharedGoalStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in SharedGoalStatus.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.name[0].toUpperCase() + s.name.substring(1),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              TextButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _target ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _target = d);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _target == null
                      ? 'Optional target date'
                      : MaterialLocalizations.of(context)
                            .formatMediumDate(_target!),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final d = _target;
          Navigator.pop(context, {
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'category': _category.text.trim(),
            'status': _status.name,
            'target_on': d == null
                ? null
                : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _MilestoneForm extends StatefulWidget {
  const _MilestoneForm({this.milestone, required this.nextOrder});
  final SharedGoalMilestone? milestone;
  final int nextOrder;
  @override
  State<_MilestoneForm> createState() => _MilestoneFormState();
}

class _MilestoneFormState extends State<_MilestoneForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.milestone?.title ?? '',
  );
  late final _description = TextEditingController(
    text: widget.milestone?.description ?? '',
  );
  late bool _completed = widget.milestone?.completed ?? false;
  late DateTime? _target = widget.milestone?.targetOn;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.milestone == null ? 'Add milestone' : 'Update milestone',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Milestone'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Add a title.' : null,
            ),
            TextFormField(
              controller: _description,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Details'),
            ),
            SwitchListTile(
              value: _completed,
              onChanged: (v) => setState(() => _completed = v),
              title: const Text('Completed'),
            ),
            TextButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _target ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _target = d);
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _target == null
                    ? 'Optional target date'
                    : MaterialLocalizations.of(context)
                          .formatMediumDate(_target!),
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
        onPressed: () {
          if (!_key.currentState!.validate()) return;
          final d = _target;
          Navigator.pop(context, {
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'is_completed': _completed,
            'target_on': d == null
                ? null
                : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
            'sort_order': widget.milestone?.sortOrder ?? widget.nextOrder,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}
