import 'package:flutter/foundation.dart';

enum DateNightStatus { proposed, selected, scheduled, completed, cancelled }

class DateNightRevisionConflict implements Exception {
  const DateNightRevisionConflict();
}

@immutable
class DateNightIdea {
  const DateNightIdea({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.description,
    required this.status,
    required this.revision,
    required this.votes,
    this.scheduledOn,
    this.estimatedAmountMinor,
    this.estimatedCurrencyCode,
    this.location = '',
    this.sharedNotes = '',
    this.planId,
  });

  final String id;
  final String coupleId;
  final String title;
  final String description;
  final DateNightStatus status;
  final int revision;
  final Map<String, String> votes;
  final DateTime? scheduledOn;
  final int? estimatedAmountMinor;
  final String? estimatedCurrencyCode;
  final String location;
  final String sharedNotes;
  final String? planId;

  factory DateNightIdea.fromJson(
    Map<String, dynamic> json, {
    Map<String, String> votes = const {},
  }) => DateNightIdea(
    id: json['id'] as String,
    coupleId: json['couple_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    status: DateNightStatus.values.byName(json['status'] as String),
    revision: (json['revision'] as num).toInt(),
    votes: Map.unmodifiable(votes),
    scheduledOn: json['scheduled_on'] == null
        ? null
        : DateTime.parse(json['scheduled_on'] as String),
    estimatedAmountMinor: (json['estimated_amount_minor'] as num?)?.toInt(),
    estimatedCurrencyCode: json['estimated_currency_code'] as String?,
    location: json['location'] as String? ?? '',
    sharedNotes: json['shared_notes'] as String? ?? '',
    planId: json['plan_id'] as String?,
  );
}

@immutable
class DateNightSnapshot {
  const DateNightSnapshot(this.ideas, this.plans);
  final List<DateNightIdea> ideas;
  final List<({String id, String title})> plans;
}

abstract interface class DateNightRepository {
  Future<DateNightSnapshot> loadDateNights(String coupleId);
  Future<void> saveDateNight(
    String coupleId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  });
  Future<void> saveDateNightVote(
    String coupleId,
    String ideaId,
    String response,
  );
}

String dateNightDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
