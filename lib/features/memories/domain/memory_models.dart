import 'package:flutter/foundation.dart';

enum MemoryCategory {
  everyday('Everyday', 'everyday'),
  travel('Travel', 'travel'),
  celebration('Celebration', 'celebration'),
  milestone('Milestone', 'milestone'),
  home('Home', 'home'),
  other('Other', 'other');

  const MemoryCategory(this.label, this.key);
  final String label;
  final String key;

  static MemoryCategory fromKey(Object? key) =>
      MemoryCategory.values.firstWhere(
        (value) => value.key == key,
        orElse: () => MemoryCategory.everyday,
      );
}

@immutable
class MemoryPhoto {
  const MemoryPhoto({
    required this.id,
    required this.memoryId,
    required this.objectPath,
    required this.contentType,
    required this.byteSize,
  });
  final String id;
  final String memoryId;
  final String objectPath;
  final String contentType;
  final int byteSize;

  factory MemoryPhoto.fromJson(Map<String, dynamic> json) => MemoryPhoto(
    id: json['id'] as String,
    memoryId: json['memory_id'] as String,
    objectPath: json['object_path'] as String,
    contentType: json['content_type'] as String,
    byteSize: (json['byte_size'] as num).toInt(),
  );
}

@immutable
class CoupleMemory {
  const CoupleMemory({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.caption,
    required this.personalNotes,
    required this.date,
    required this.category,
    required this.tags,
    required this.favorite,
    required this.revision,
    required this.photos,
    this.importantDateId,
  });
  final String id;
  final String coupleId;
  final String title;
  final String caption;
  final String personalNotes;
  final DateTime date;
  final MemoryCategory category;
  final List<String> tags;
  final bool favorite;
  final int revision;
  final List<MemoryPhoto> photos;
  final String? importantDateId;

  factory CoupleMemory.fromJson(
    Map<String, dynamic> json, {
    List<MemoryPhoto> photos = const [],
  }) => CoupleMemory(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    title: json['title'] as String,
    caption: json['caption'] as String? ?? '',
    personalNotes: json['personal_notes'] as String? ?? '',
    date: DateTime.parse(json['memory_on'] as String),
    category: MemoryCategory.fromKey(json['category_key']),
    tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
    favorite: json['is_favorite'] as bool? ?? false,
    revision: (json['revision'] as num).toInt(),
    photos: List.unmodifiable(photos),
    importantDateId: json['important_date_id'] as String?,
  );
}

@immutable
class MemoriesSnapshot {
  const MemoriesSnapshot({
    required this.memories,
    required this.importantDates,
  });
  final List<CoupleMemory> memories;
  final List<({String id, String title})> importantDates;
}

abstract interface class MemoriesRepository {
  Future<MemoriesSnapshot> loadMemories(String coupleId);
  Future<void> saveMemory(
    String coupleId,
    Map<String, dynamic> values, {
    String? memoryId,
  });
  Future<void> deleteMemory(String coupleId, CoupleMemory memory);
  Future<void> toggleFavorite(String coupleId, CoupleMemory memory);
  Future<void> addPhotos(
    String coupleId,
    String memoryId,
    List<({Uint8List bytes, String contentType})> photos,
  );
  Future<void> removePhoto(String coupleId, MemoryPhoto photo);
  Future<Uint8List> downloadPhoto(String objectPath);
}
