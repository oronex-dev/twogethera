import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../../authentication/presentation/privacy_removal_confirmation.dart';
import '../../budget/domain/budget_models.dart';
import '../application/date_nights_controller.dart';
import '../domain/date_night_models.dart';

class DateNightsScreen extends ConsumerStatefulWidget {
  const DateNightsScreen({super.key});
  @override
  ConsumerState<DateNightsScreen> createState() => _DateNightsScreenState();
}

class _DateNightsScreenState extends ConsumerState<DateNightsScreen> {
  String? _requestedCouple;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final couple = auth.context?.spaces
        .where((s) => s.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;
    final state = ref.watch(dateNightsControllerProvider);
    if (coupleId != null && _requestedCouple != coupleId) {
      _requestedCouple = coupleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(dateNightsControllerProvider.notifier).load(coupleId);
        }
      });
    }
    if (coupleId == null) {
      return const ResponsivePage(
        child: SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date nights are shared'),
              SizedBox(height: 8),
              Text(
                'Link your partner to suggest and plan activities together.',
              ),
            ],
          ),
        ),
      );
    }
    final snapshot = state.coupleId == coupleId ? state.snapshot : null;
    final ideas =
        (snapshot?.ideas ?? const <DateNightIdea>[])
            .where(
              (idea) =>
                  '${idea.title} ${idea.description} ${idea.location} ${idea.sharedNotes}'
                      .toLowerCase()
                      .contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            int rank(DateNightIdea idea) => switch (idea.status) {
              DateNightStatus.scheduled => 0,
              DateNightStatus.selected => 1,
              DateNightStatus.proposed => 2,
              DateNightStatus.completed => 3,
              DateNightStatus.cancelled => 4,
            };
            final byStatus = rank(a).compareTo(rank(b));
            return byStatus == 0
                ? (a.scheduledOn ?? DateTime(9999)).compareTo(
                    b.scheduledOn ?? DateTime(9999),
                  )
                : byStatus;
          });
    final userId = auth.context?.userId;
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'Date nights',
            description: 'Share ideas, see each other’s interest, and turn a favorite into a plan.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search date-night ideas',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: state.saving
                    ? null
                    : () => _edit(snapshot?.plans ?? const [], coupleId),
                icon: const Icon(Icons.add),
                label: const Text('Suggest an idea'),
              ),
            ],
          ),
          if (state.error != null)
            _Notice(
              message: state.error!,
              action: TextButton(
                onPressed: () => ref
                    .read(dateNightsControllerProvider.notifier)
                    .load(coupleId),
                child: const Text('Retry'),
              ),
            ),
          if (state.notice != null) _Notice(message: state.notice!),
          if (state.loading && snapshot == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (ideas.isEmpty)
            _Empty(
              onAdd: () => _edit(snapshot?.plans ?? const [], coupleId),
              filtered: _query.isNotEmpty,
            )
          else ...[
            const SizedBox(height: 14),
            for (final idea in ideas)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _IdeaCard(
                  idea: idea,
                  plans: snapshot?.plans ?? const [],
                  userId: userId,
                  onEdit: () =>
                      _edit(snapshot?.plans ?? const [], coupleId, idea),
                  onVote: (vote) => ref
                      .read(dateNightsControllerProvider.notifier)
                      .vote(idea.id, vote),
                  onReviewBudget: idea.estimatedAmountMinor == null
                      ? null
                      : () => context.go('/budget'),
                  onPrivacyRemove: (field) => confirmPrivacyRemoval(
                    context,
                    ref,
                    table: 'date_night_ideas',
                    recordId: idea.id,
                    field: field,
                    onSubmitted: () => ref
                        .read(dateNightsControllerProvider.notifier)
                        .load(coupleId),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(
    List<({String id, String title})> plans,
    String coupleId, [
    DateNightIdea? idea,
  ]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DateNightForm(idea: idea, plans: plans),
    );
    if (values == null || !mounted) return;
    await ref
        .read(dateNightsControllerProvider.notifier)
        .save(values, id: idea?.id, expectedRevision: idea?.revision);
  }
}

class _DateNightForm extends StatefulWidget {
  const _DateNightForm({required this.plans, this.idea});
  final List<({String id, String title})> plans;
  final DateNightIdea? idea;
  @override
  State<_DateNightForm> createState() => _DateNightFormState();
}

class _DateNightFormState extends State<_DateNightForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.idea?.title ?? '');
  late final _description = TextEditingController(
    text: widget.idea?.description ?? '',
  );
  late final _location = TextEditingController(
    text: widget.idea?.location ?? '',
  );
  late final _notes = TextEditingController(
    text: widget.idea?.sharedNotes ?? '',
  );
  late final TextEditingController _amount;
  late DateNightStatus _status =
      widget.idea?.status ?? DateNightStatus.proposed;
  late DateTime? _date = widget.idea?.scheduledOn;
  late String? _planId = widget.idea?.planId;
  late CurrencyUnit _currency;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _formatAmount(widget.idea));
    _currency =
        CurrencyUnit.byCode(widget.idea?.estimatedCurrencyCode) ??
        CurrencyUnit.supported.first;
  }

  static String _formatAmount(DateNightIdea? idea) {
    if (idea?.estimatedAmountMinor == null) return '';
    final exp = CurrencyUnit.byCode(idea!.estimatedCurrencyCode)?.exponent ?? 2;
    if (exp == 0) return idea.estimatedAmountMinor.toString();
    final divisor = BigInt.from(10).pow(exp);
    final value = BigInt.from(idea.estimatedAmountMinor!);
    return '${value ~/ divisor}.${(value % divisor).toString().padLeft(exp, '0')}';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _notes.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.idea == null ? 'Suggest a date night' : 'Edit date night',
    ),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _key,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Idea'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Add a short title.' : null,
              ),
              TextFormField(
                controller: _description,
                maxLines: 2,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              DropdownButtonFormField<DateNightStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in DateNightStatus.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.name[0].toUpperCase() + s.name.substring(1),
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _date == null
                        ? 'Choose a calendar date'
                        : MaterialLocalizations.of(context)
                              .formatMediumDate(_date!),
                  ),
                ),
              ),
              TextFormField(
                controller: _location,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Optional location',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Estimated budget',
                        helperText:
                            'Estimate only; does not create an expense.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<CurrencyUnit>(
                      initialValue: _currency,
                      items: [
                        for (final c in CurrencyUnit.supported)
                          DropdownMenuItem(value: c, child: Text(c.code)),
                      ],
                      onChanged: (v) =>
                          setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                initialValue: _planId,
                decoration: const InputDecoration(
                  labelText: 'Linked Plan (optional)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No linked Plan'),
                  ),
                  for (final p in widget.plans)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.title, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _planId = v),
              ),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Shared notes'),
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
          final amountText = _amount.text.trim();
          final minor = amountText.isEmpty
              ? null
              : ExactMoney.parse(amountText, _currency, allowZero: true);
          if (amountText.isNotEmpty && minor == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Enter a valid amount for the selected currency.',
                ),
              ),
            );
            return;
          }
          if ((_status == DateNightStatus.scheduled ||
                  _status == DateNightStatus.completed) &&
              _date == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Choose a date before scheduling or completing this idea.',
                ),
              ),
            );
            return;
          }
          Navigator.pop(context, {
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'status': _status.name,
            'scheduled_on': _date == null ? null : dateNightDateKey(_date!),
            'estimated_amount_minor': minor,
            'estimated_currency_code': minor == null ? null : _currency.code,
            'location': _location.text.trim(),
            'shared_notes': _notes.text.trim(),
            'plan_id': _planId,
          });
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.plans,
    required this.userId,
    required this.onEdit,
    required this.onVote,
    required this.onReviewBudget,
    required this.onPrivacyRemove,
  });
  final DateNightIdea idea;
  final List<({String id, String title})> plans;
  final String? userId;
  final VoidCallback onEdit;
  final ValueChanged<String> onVote;
  final VoidCallback? onReviewBudget;
  final ValueChanged<String?> onPrivacyRemove;
  @override
  Widget build(BuildContext context) {
    final partnerId = idea.votes.keys.where((id) => id != userId).firstOrNull;
    String voteLabel(String? id) => id == null
        ? 'No response'
        : switch (idea.votes[id]) {
            'interested' => 'Interested',
            'not_for_me' => 'Not this one',
            _ => 'No response',
          };
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  idea.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Chip(label: Text(idea.status.name)),
              PopupMenuButton<String>(
                tooltip: 'Privacy removal options',
                onSelected: (value) =>
                    onPrivacyRemove(value == 'record' ? null : value),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'record',
                    child: Text('Remove idea for privacy'),
                  ),
                  if (idea.description.isNotEmpty)
                    const PopupMenuItem(
                      value: 'description',
                      child: Text('Remove description only'),
                    ),
                  if (idea.location.isNotEmpty)
                    const PopupMenuItem(
                      value: 'location',
                      child: Text('Remove location only'),
                    ),
                  if (idea.sharedNotes.isNotEmpty)
                    const PopupMenuItem(
                      value: 'shared_notes',
                      child: Text('Remove shared notes only'),
                    ),
                ],
              ),
            ],
          ),
          if (idea.description.isNotEmpty) Text(idea.description),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              if (idea.scheduledOn != null)
                Text(
                  'Date · ${MaterialLocalizations.of(context).formatMediumDate(idea.scheduledOn!)}',
                ),
              if (idea.location.isNotEmpty) Text('Location · ${idea.location}'),
              if (idea.estimatedAmountMinor != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Estimate · ${ExactMoney(idea.estimatedAmountMinor!, CurrencyUnit.byCode(idea.estimatedCurrencyCode) ?? CurrencyUnit.supported.first).format()}',
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: onReviewBudget,
                      child: const Text('Review Budget'),
                    ),
                  ],
                ),
              if (idea.planId != null)
                Text(
                  'Plan · ${plans.where((p) => p.id == idea.planId).firstOrNull?.title ?? 'Linked plan'}',
                ),
            ],
          ),
          if (idea.sharedNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(idea.sharedNotes),
            ),
          const Divider(height: 24),
          Wrap(
            spacing: 18,
            children: [
              Text('You · ${voteLabel(userId)}'),
              Text('Partner · ${voteLabel(partnerId)}'),
            ],
          ),
          if (idea.status == DateNightStatus.proposed)
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => onVote('interested'),
                  icon: const Icon(Icons.favorite_border),
                  label: const Text('Interested'),
                ),
                TextButton(
                  onPressed: () => onVote('not_for_me'),
                  child: const Text('Not for me'),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(message),
      trailing: action,
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd, required this.filtered});
  final VoidCallback onAdd;
  final bool filtered;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.favorite_border, size: 36),
          const SizedBox(height: 8),
          Text(
            filtered
                ? 'No date-night ideas match your search.'
                : 'Start with one idea you would enjoy together.',
          ),
          if (!filtered)
            TextButton(onPressed: onAdd, child: const Text('Suggest an idea')),
        ],
      ),
    ),
  );
}
