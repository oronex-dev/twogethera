import 'dart:typed_data';

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.about,
    required this.revision,
    this.avatarPath,
  });

  final String userId;
  final String displayName;
  final String about;
  final int revision;
  final String? avatarPath;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String,
    about: json['about'] as String? ?? '',
    avatarPath: json['avatar_path'] as String?,
    revision: (json['revision'] as num?)?.toInt() ?? 1,
  );
}

/// Deliberately contains only fields authorized for an active partner.
class PartnerProfile {
  const PartnerProfile({required this.displayName, this.avatarPath});

  final String displayName;
  final String? avatarPath;

  factory PartnerProfile.fromJson(Map<String, dynamic> json) => PartnerProfile(
    displayName: json['display_name'] as String,
    avatarPath: json['avatar_path'] as String?,
  );
}

abstract interface class ProfileRepository {
  Future<UserProfile> loadMyProfile({
    required String userId,
    required String fallbackDisplayName,
  });

  Future<PartnerProfile?> loadPartnerProfile();

  Future<Uint8List?> downloadAvatar(String path);

  Future<UserProfile> saveMyProfile({
    required String userId,
    required String displayName,
    required String about,
    required String? avatarPath,
  });

  Future<String> uploadMyAvatar({
    required String userId,
    required Uint8List bytes,
  });

  Future<void> removeMyAvatar(String path);
}

class ProfileFailure implements Exception {
  const ProfileFailure();
}
