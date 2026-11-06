import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/application/auth_controller.dart';
import '../../authentication/domain/auth_repository.dart';
import '../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  if (repository is ProfileRepository) return repository as ProfileRepository;
  return const _UnavailableProfileRepository();
});

class _UnavailableProfileRepository implements ProfileRepository {
  const _UnavailableProfileRepository();

  @override
  Future<UserProfile> loadMyProfile({
    required String userId,
    required String fallbackDisplayName,
  }) => Future.error(const ProfileFailure());

  @override
  Future<PartnerProfile?> loadPartnerProfile() =>
      Future.error(const ProfileFailure());

  @override
  Future<Uint8List?> downloadAvatar(String path) =>
      Future.error(const ProfileFailure());

  @override
  Future<UserProfile> saveMyProfile({
    required String userId,
    required String displayName,
    required String about,
    required String? avatarPath,
  }) => Future.error(const ProfileFailure());

  @override
  Future<String> uploadMyAvatar({
    required String userId,
    required Uint8List bytes,
  }) => Future.error(const ProfileFailure());

  @override
  Future<void> removeMyAvatar(String path) =>
      Future.error(const ProfileFailure());
}

class ProfileState {
  const ProfileState({
    this.userId,
    this.myProfile,
    this.partnerProfile,
    this.myAvatarBytes,
    this.partnerAvatarBytes,
    this.pendingAvatarRemovalPath,
    this.partnerLoadFailed = false,
    this.loading = false,
    this.saving = false,
    this.photoBusy = false,
    this.error,
    this.notice,
  });

  final String? userId;
  final UserProfile? myProfile;
  final PartnerProfile? partnerProfile;
  final Uint8List? myAvatarBytes;
  final Uint8List? partnerAvatarBytes;
  final String? pendingAvatarRemovalPath;
  final bool partnerLoadFailed;
  final bool loading;
  final bool saving;
  final bool photoBusy;
  final String? error;
  final String? notice;
}

final profileControllerProvider =
    NotifierProvider<ProfileController, ProfileState>(ProfileController.new);

class ProfileController extends Notifier<ProfileState> {
  int _generation = 0;

  @override
  ProfileState build() => const ProfileState();

  void clear() {
    _generation++;
    state = const ProfileState();
  }

  void showError(String message) {
    state = ProfileState(
      userId: state.userId,
      myProfile: state.myProfile,
      partnerProfile: state.partnerProfile,
      myAvatarBytes: state.myAvatarBytes,
      partnerAvatarBytes: state.partnerAvatarBytes,
      partnerLoadFailed: state.partnerLoadFailed,
      pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
      error: message,
    );
  }

  Future<void> load(AccountContext account) async {
    final generation = ++_generation;
    state = ProfileState(userId: account.userId, loading: true);
    final repository = ref.read(profileRepositoryProvider);
    try {
      final profile = await repository.loadMyProfile(
        userId: account.userId,
        fallbackDisplayName: account.displayName ?? 'Twogethera member',
      );
      if (generation != _generation) return;
      state = ProfileState(
        userId: account.userId,
        myProfile: profile,
        loading: true,
      );

      Uint8List? myAvatar;
      if (profile.avatarPath != null) {
        try {
          myAvatar = await repository.downloadAvatar(profile.avatarPath!);
        } catch (_) {
          state = ProfileState(
            userId: account.userId,
            myProfile: profile,
            loading: true,
            error: 'Your profile photo could not be loaded. Try again.',
          );
        }
      }
      if (generation != _generation) return;

      final paired = account.spaces.any((space) => space.state == 'paired');
      PartnerProfile? partner;
      Uint8List? partnerAvatar;
      var partnerLoadFailed = false;
      var error = state.error;
      if (paired) {
        try {
          partner = await repository.loadPartnerProfile();
          if (partner?.avatarPath != null) {
            try {
              partnerAvatar = await repository.downloadAvatar(
                partner!.avatarPath!,
              );
            } catch (_) {
              error = 'Your partner’s profile photo could not be loaded.';
            }
          }
        } catch (_) {
          error = 'Your partner’s profile could not be loaded. Try again.';
          partnerLoadFailed = true;
        }
      }
      if (generation != _generation) return;
      state = ProfileState(
        userId: account.userId,
        myProfile: profile,
        partnerProfile: partner,
        myAvatarBytes: myAvatar,
        partnerAvatarBytes: partnerAvatar,
        partnerLoadFailed: partnerLoadFailed,
        error: error,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = ProfileState(
        userId: account.userId,
        error: 'Your profile could not be loaded. Try again.',
      );
    }
  }

  Future<bool> save({
    required String displayName,
    required String about,
  }) async {
    final userId = state.userId;
    final current = state.myProfile;
    if (userId == null || current == null || state.saving) return false;
    state = ProfileState(
      userId: userId,
      myProfile: current,
      partnerProfile: state.partnerProfile,
      myAvatarBytes: state.myAvatarBytes,
      partnerAvatarBytes: state.partnerAvatarBytes,
      partnerLoadFailed: state.partnerLoadFailed,
      pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
      saving: true,
    );
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .saveMyProfile(
            userId: userId,
            displayName: displayName.trim(),
            about: about.trim(),
            avatarPath: current.avatarPath,
          );
      if (state.userId != userId) return false;
      state = ProfileState(
        userId: userId,
        myProfile: saved,
        partnerProfile: state.partnerProfile,
        myAvatarBytes: state.myAvatarBytes,
        partnerAvatarBytes: state.partnerAvatarBytes,
        partnerLoadFailed: state.partnerLoadFailed,
        pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
        notice: 'Your profile was saved.',
      );
      return true;
    } catch (_) {
      if (state.userId == userId) {
        state = ProfileState(
          userId: userId,
          myProfile: current,
          partnerProfile: state.partnerProfile,
          myAvatarBytes: state.myAvatarBytes,
          partnerAvatarBytes: state.partnerAvatarBytes,
          partnerLoadFailed: state.partnerLoadFailed,
          pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
          error: 'Your profile could not be saved. Try again.',
        );
      }
      return false;
    }
  }

  Future<bool> updateAvatar(Uint8List bytes) async {
    final userId = state.userId;
    final current = state.myProfile;
    if (userId == null || current == null || state.photoBusy) return false;
    _setPhotoBusy(true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      final path = await repository.uploadMyAvatar(
        userId: userId,
        bytes: bytes,
      );
      final saved = await repository.saveMyProfile(
        userId: userId,
        displayName: current.displayName,
        about: current.about,
        avatarPath: path,
      );
      if (state.userId != userId) return false;
      state = ProfileState(
        userId: userId,
        myProfile: saved,
        partnerProfile: state.partnerProfile,
        myAvatarBytes: bytes,
        partnerAvatarBytes: state.partnerAvatarBytes,
        partnerLoadFailed: state.partnerLoadFailed,
        pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
        notice: 'Your profile photo was updated.',
      );
      return true;
    } catch (_) {
      if (state.userId == userId) {
        state = ProfileState(
          userId: userId,
          myProfile: current,
          partnerProfile: state.partnerProfile,
          myAvatarBytes: state.myAvatarBytes,
          partnerAvatarBytes: state.partnerAvatarBytes,
          partnerLoadFailed: state.partnerLoadFailed,
          pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
          error: 'Your profile photo could not be updated. Try again.',
        );
      }
      return false;
    }
  }

  Future<bool> removeAvatar() async {
    final userId = state.userId;
    final current = state.myProfile;
    final path = current?.avatarPath ?? state.pendingAvatarRemovalPath;
    if (userId == null || current == null || path == null || state.photoBusy) {
      return false;
    }
    _setPhotoBusy(true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      final saved = await repository.saveMyProfile(
        userId: userId,
        displayName: current.displayName,
        about: current.about,
        avatarPath: null,
      );
      // The profile pointer is cleared first, so partner authorization stops
      // before the Storage object is removed.
      await repository.removeMyAvatar(path);
      if (state.userId != userId) return false;
      state = ProfileState(
        userId: userId,
        myProfile: saved,
        partnerProfile: state.partnerProfile,
        partnerAvatarBytes: state.partnerAvatarBytes,
        partnerLoadFailed: state.partnerLoadFailed,
        pendingAvatarRemovalPath: null,
        notice: 'Your profile photo was removed.',
      );
      return true;
    } catch (_) {
      if (state.userId == userId) {
        state = ProfileState(
          userId: userId,
          // The database pointer was cleared before Storage deletion. Keep
          // that privacy change visible even if physical purge needs retry.
          myProfile: current.copyWith(avatarPath: null),
          partnerProfile: state.partnerProfile,
          myAvatarBytes: null,
          partnerAvatarBytes: state.partnerAvatarBytes,
          partnerLoadFailed: state.partnerLoadFailed,
          pendingAvatarRemovalPath: path,
          error: 'The profile photo could not be fully removed. Partner access is blocked; retry removal.',
        );
      }
      return false;
    }
  }

  void _setPhotoBusy(bool busy) {
    state = ProfileState(
      userId: state.userId,
      myProfile: state.myProfile,
      partnerProfile: state.partnerProfile,
      myAvatarBytes: state.myAvatarBytes,
      partnerAvatarBytes: state.partnerAvatarBytes,
      partnerLoadFailed: state.partnerLoadFailed,
      pendingAvatarRemovalPath: state.pendingAvatarRemovalPath,
      photoBusy: busy,
    );
  }
}

extension on UserProfile {
  UserProfile copyWith({String? avatarPath}) => UserProfile(
    userId: userId,
    displayName: displayName,
    about: about,
    avatarPath: avatarPath,
    revision: revision,
  );
}
