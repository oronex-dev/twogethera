import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/design_components.dart';
import '../../../shared/widgets/responsive_page.dart';
import '../../authentication/application/auth_controller.dart';
import '../../authentication/domain/auth_repository.dart';
import '../application/memories_controller.dart';
import '../domain/memory_models.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});
  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  String? _requestedCouple;
  String _query = '';
  MemoryCategory? _category;
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final couple = auth.context?.spaces
        .where((s) => s.state == 'paired')
        .firstOrNull;
    final coupleId = auth.phase == AuthPhase.authenticated ? couple?.id : null;
    if (coupleId == null) _requestedCouple = null;
    final state = ref.watch(memoriesControllerProvider);
    if (coupleId != null && coupleId != _requestedCouple) {
      _requestedCouple = coupleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(memoriesControllerProvider.notifier).load(coupleId);
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
                'Memories are shared',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Link your partner to create a shared timeline.'),
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
    final snapshot = state.coupleId == coupleId ? state.snapshot : null;
    final memories = (snapshot?.memories ?? const <CoupleMemory>[]).where((
      memory,
    ) {
      final q = _query.trim().toLowerCase();
      return (_category == null || memory.category == _category) &&
          (!_favoritesOnly || memory.favorite) &&
          (q.isEmpty ||
              '${memory.title} ${memory.caption} ${memory.personalNotes} ${memory.tags.join(' ')}'
                  .toLowerCase()
                  .contains(q));
    }).toList();
    return ResponsivePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'The moments you keep',
            description: 'A private shared journal for the stories you want to remember.',
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Search memories, notes, and tags',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: _favoritesOnly
                    ? 'Show all memories'
                    : 'Show favorites',
                onPressed: () =>
                    setState(() => _favoritesOnly = !_favoritesOnly),
                icon: Icon(
                  _favoritesOnly
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: state.saving
                    ? null
                    : () => _editMemory(snapshot?.importantDates ?? const []),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add memory'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _category == null,
                onSelected: (_) => setState(() => _category = null),
              ),
              for (final category in MemoryCategory.values)
                ChoiceChip(
                  label: Text(category.label),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          if (state.error != null)
            _MemoryNotice(
              message: state.error!,
              action: TextButton(
                onPressed: () => ref
                    .read(memoriesControllerProvider.notifier)
                    .load(coupleId),
                child: const Text('Retry'),
              ),
            ),
          if (state.notice != null) _MemoryNotice(message: state.notice!),
          if (state.loading && snapshot == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (memories.isEmpty)
            _MemoryEmpty(
              isFiltered:
                  _query.isNotEmpty || _category != null || _favoritesOnly,
              onAdd: () => _editMemory(snapshot?.importantDates ?? const []),
            )
          else ...[
            const SizedBox(height: AppSpace.md),
            AdaptiveGrid(
              minWidth: 300,
              children: [
                for (final memory in memories)
                  _MemoryCard(
                    memory: memory,
                    onOpen: () => _showMemory(memory, snapshot!.importantDates),
                    onFavorite: () => ref
                        .read(memoriesControllerProvider.notifier)
                        .toggleFavorite(memory),
                    onEdit: () =>
                        _editMemory(snapshot!.importantDates, memory: memory),
                    onDelete: () => _deleteMemory(memory),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editMemory(
    List<({String id, String title})> dates, {
    CoupleMemory? memory,
  }) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _MemoryForm(memory: memory, importantDates: dates),
    );
    if (values == null || !mounted) return;
    final photoFiles =
        values.remove('photo_files')
            as List<({Uint8List bytes, String contentType})>? ??
        [];
    final controller = ref.read(memoriesControllerProvider.notifier);
    final saved = await controller.save(values, memoryId: memory?.id);
    if (!saved || !mounted) return;
    if (photoFiles.isNotEmpty) {
      final current = ref.read(memoriesControllerProvider).snapshot?.memories;
      final savedMemory =
          memory ??
          current
              ?.where(
                (item) =>
                    item.title == values['title'] &&
                    item.date == DateTime.parse(values['memory_on']),
              )
              .firstOrNull;
      if (savedMemory != null) {
        await controller.addPhotos(savedMemory.id, photoFiles);
      } else {
        _showMessage(
          'The memory was saved. Reopen it to attach the selected photos.',
        );
      }
    }
  }

  Future<void> _deleteMemory(CoupleMemory memory) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this memory?'),
        content: const Text(
          'Ordinary removal is recoverable by either active partner for seven days. Privacy removal hides the memory and attached photos immediately, cannot be undone, and queues primary-copy cleanup with a 24-hour target.',
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
          if (memory.caption.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'field:caption'),
              child: const Text('Remove caption only'),
            ),
          if (memory.personalNotes.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, 'field:personal_notes'),
              child: const Text('Remove shared notes only'),
            ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'ordinary'),
            child: const Text('Remove for 7 days'),
          ),
        ],
      ),
    );
    if (action == 'ordinary' && mounted) {
      await ref.read(memoriesControllerProvider.notifier).delete(memory);
    } else if ((action == 'privacy' || action?.startsWith('field:') == true) &&
        mounted) {
      final repository = ref.read(authRepositoryProvider);
      try {
        if (repository is! PrivacyRemovalRepository) {
          throw const AuthFailure(AuthProblem.lifecycleUnavailable);
        }
        await (repository as PrivacyRemovalRepository).requestPrivacyRemoval(
          table: 'couple_memories',
          recordId: memory.id,
          field: action == 'privacy' ? null : action!.substring(6),
          removeRecord: action == 'privacy',
        );
        await ref
            .read(memoriesControllerProvider.notifier)
            .load(memory.coupleId);
        if (mounted) {
          _showMessage(
            action == 'privacy'
                ? 'Memory hidden; removal cleanup is queued.'
                : 'The selected shared text was removed.',
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

  Future<void> _showMemory(
    CoupleMemory memory,
    List<({String id, String title})> dates,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _MemoryDetail(
        memory: memory,
        onAddPhotos: () => _addPhotos(memory),
        onRemovePhoto: (photo) => _removePhoto(photo),
        onEdit: () {
          Navigator.pop(context);
          _editMemory(dates, memory: memory);
        },
      ),
    );
  }

  Future<void> _addPhotos(CoupleMemory memory) async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 90);
    final photos = <({Uint8List bytes, String contentType})>[];
    for (final file in files.take(10 - memory.photos.length)) {
      photos.add((
        bytes: await file.readAsBytes(),
        contentType: file.mimeType ?? 'image/jpeg',
      ));
    }
    if (photos.isNotEmpty && mounted) {
      final saved = await ref
          .read(memoriesControllerProvider.notifier)
          .addPhotos(memory.id, photos);
      if (saved && mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _removePhoto(MemoryPhoto photo) async {
    if (mounted) {
      final removed = await ref
          .read(memoriesControllerProvider.notifier)
          .removePhoto(photo);
      if (removed && mounted) Navigator.of(context).pop();
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    required this.onOpen,
    required this.onFavorite,
    required this.onEdit,
    required this.onDelete,
  });
  final CoupleMemory memory;
  final VoidCallback onOpen, onFavorite, onEdit, onDelete;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: 12,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 1.45,
              child: memory.photos.isEmpty
                  ? ColoredBox(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: Center(
                        child: Icon(
                          Icons.photo_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    )
                  : _PrivatePhoto(
                      path: memory.photos.first.objectPath,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                memory.title,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: memory.favorite ? 'Remove favorite' : 'Add favorite',
              onPressed: onFavorite,
              icon: Icon(
                memory.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
            ),
          ],
        ),
        Text(
          '${_memoryDate(memory.date)} · ${memory.category.label}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (memory.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              memory.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (memory.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              children: [
                for (final tag in memory.tags.take(4))
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Edit memory',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Remove memory',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PrivatePhoto extends ConsumerStatefulWidget {
  const _PrivatePhoto({required this.path, this.fit = BoxFit.cover});
  final String path;
  final BoxFit fit;
  @override
  ConsumerState<_PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends ConsumerState<_PrivatePhoto> {
  late Future<Uint8List> _bytes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PrivatePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  void _load() =>
      _bytes = ref.read(memoriesRepositoryProvider).downloadPhoto(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Icon(
            Icons.lock_outline_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Image.memory(
        snapshot.data!,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    },
  );
}

class _MemoryDetail extends StatelessWidget {
  const _MemoryDetail({
    required this.memory,
    required this.onAddPhotos,
    required this.onRemovePhoto,
    required this.onEdit,
  });
  final CoupleMemory memory;
  final VoidCallback onAddPhotos;
  final ValueChanged<MemoryPhoto> onRemovePhoto;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 800),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    memory.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit memory',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text('${_memoryDate(memory.date)} · ${memory.category.label}'),
            const SizedBox(height: 16),
            if (memory.caption.isNotEmpty)
              Text(
                memory.caption,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            if (memory.personalNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(memory.personalNotes),
              ),
            if (memory.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(memory.tags.map((tag) => '#$tag').join('  ')),
              ),
            if (memory.photos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Expanded(
                child: PageView(
                  children: [
                    for (final photo in memory.photos)
                      Stack(
                        children: [
                          Positioned.fill(
                            child: _PrivatePhoto(
                              path: photo.objectPath,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: IconButton.filledTonal(
                              tooltip: 'Remove photo',
                              onPressed: () => onRemovePhoto(photo),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ] else
              const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onAddPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add photos'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MemoryForm extends StatefulWidget {
  const _MemoryForm({required this.importantDates, this.memory});
  final List<({String id, String title})> importantDates;
  final CoupleMemory? memory;
  @override
  State<_MemoryForm> createState() => _MemoryFormState();
}

class _MemoryFormState extends State<_MemoryForm> {
  late final TextEditingController _title = TextEditingController(
    text: widget.memory?.title ?? '',
  );
  late final TextEditingController _caption = TextEditingController(
    text: widget.memory?.caption ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.memory?.personalNotes ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.memory?.tags.join(', ') ?? '',
  );
  late DateTime _date = widget.memory?.date ?? DateTime.now();
  late MemoryCategory _category =
      widget.memory?.category ?? MemoryCategory.everyday;
  String? _importantDateId;
  List<({Uint8List bytes, String contentType})> _photos = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _importantDateId = widget.memory?.importantDateId;
  }

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    _notes.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.memory == null ? 'Add a memory' : 'Edit memory'),
    content: SizedBox(
      width: 520,
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
              controller: _caption,
              maxLength: 4000,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Caption'),
            ),
            TextField(
              controller: _notes,
              maxLength: 4000,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Shared notes',
                helperText: 'Visible to your partner',
              ),
            ),
            DropdownButtonFormField<MemoryCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final value in MemoryCategory.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags',
                helperText: 'Separate tags with commas',
              ),
            ),
            if (widget.importantDates.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _importantDateId,
                decoration: const InputDecoration(
                  labelText: 'Related important date (optional)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No linked date'),
                  ),
                  for (final date in widget.importantDates)
                    DropdownMenuItem(value: date.id, child: Text(date.title)),
                ],
                onChanged: (value) => setState(() => _importantDateId = value),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_memoryDate(_date)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _choosePhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  _photos.isEmpty
                      ? 'Choose photos'
                      : '${_photos.length} photos selected',
                ),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: _save, child: const Text('Save memory')),
    ],
  );
  Future<void> _chooseDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _choosePhotos() async {
    final existing = widget.memory?.photos.length ?? 0;
    final files = await ImagePicker().pickMultiImage(imageQuality: 90);
    final values = <({Uint8List bytes, String contentType})>[];
    for (final file in files.take((10 - existing).clamp(0, 10))) {
      values.add((
        bytes: await file.readAsBytes(),
        contentType: file.mimeType ?? 'image/jpeg',
      ));
    }
    if (mounted) setState(() => _photos = values);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty || title.length > 160) {
      setState(() => _error = 'Add a title up to 160 characters.');
      return;
    }
    final tags = _tags.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .take(12)
        .toList();
    Navigator.pop(context, <String, dynamic>{
      'title': title,
      'caption': _caption.text.trim(),
      'personal_notes': _notes.text.trim(),
      'memory_on': _dateKey(_date),
      'category_key': _category.key,
      'tags': tags,
      'important_date_id': _importantDateId,
      '_revision': widget.memory?.revision,
      'photo_files': _photos,
    });
  }
}

class _MemoryEmpty extends StatelessWidget {
  const _MemoryEmpty({required this.isFiltered, required this.onAdd});
  final bool isFiltered;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.photo_album_outlined,
          size: 34,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          isFiltered
              ? 'No memories match those filters.'
              : 'Your timeline starts with a moment.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Photos are delivered through authenticated requests from private storage. They are not public links.',
        ),
        if (!isFiltered) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a memory'),
          ),
        ],
      ],
    ),
  );
}

class _MemoryNotice extends StatelessWidget {
  const _MemoryNotice({required this.message, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.sm),
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
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

String _memoryDate(DateTime date) =>
    '${_monthName(date.month)} ${date.day}, ${date.year}';
String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
