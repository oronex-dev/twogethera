import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/profile/application/profile_controller.dart';
import 'package:twogethera/features/profile/domain/profile_repository.dart';

class _Profiles implements ProfileRepository {
  String? loadedUser;
  String? savedUser;
  int partnerLoads = 0;
  final avatars = <String, Uint8List>{};
  int avatarDownloads = 0;
  int avatarUploads = 0;
  int avatarRemovals = 0;
  String? removeFailure;
  bool failLoad = false;
  bool failPartnerLoad = false;
  bool failSave = false;
  late UserProfile profile;

  _Profiles() {
    profile = const UserProfile(
      userId: 'user-a',
      displayName: 'Partner A',
      about: 'Private note',
      avatarPath: 'user-a/avatar',
      revision: 1,
    );
  }

  @override
  Future<UserProfile> loadMyProfile({
    required String userId,
    required String fallbackDisplayName,
  }) async {
    loadedUser = userId;
    if (failLoad) throw const ProfileFailure();
    if (userId != profile.userId) {
      return UserProfile(
        userId: userId,
        displayName: fallbackDisplayName,
        about: '',
        revision: 1,
      );
    }
    return profile;
  }

  @override
  Future<PartnerProfile?> loadPartnerProfile() async {
    partnerLoads++;
    if (failPartnerLoad) throw const ProfileFailure();
    return const PartnerProfile(displayName: 'Partner B');
  }

  @override
  Future<Uint8List?> downloadAvatar(String path) async {
    avatarDownloads++;
    return avatars[path];
  }

  @override
  Future<UserProfile> saveMyProfile({
    required String userId,
    required String displayName,
    required String about,
    required String? avatarPath,
  }) async {
    savedUser = userId;
    if (failSave) throw const ProfileFailure();
    profile = UserProfile(
      userId: userId,
      displayName: displayName,
      about: about,
      avatarPath: avatarPath,
      revision: profile.revision + 1,
    );
    return profile;
  }

  @override
  Future<String> uploadMyAvatar({
    required String userId,
    required Uint8List bytes,
  }) async {
    avatarUploads++;
    final path = '$userId/avatar';
    avatars[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<void> removeMyAvatar(String path) async {
    avatarRemovals++;
    if (removeFailure != null) throw const ProfileFailure();
  }
}

void main() {
  late _Profiles repository;
  late ProviderContainer container;

  setUp(() {
    repository = _Profiles();
    container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  test('loads only the signed-in user profile when unpaired', () async {
    await container
        .read(profileControllerProvider.notifier)
        .load(const AccountContext(userId: 'user-a', spaces: []));

    final state = container.read(profileControllerProvider);
    expect(repository.loadedUser, 'user-a');
    expect(state.myProfile?.about, 'Private note');
    expect(state.partnerProfile, isNull);
    expect(repository.partnerLoads, 0);
  });

  test('loads partner projection only for a paired account', () async {
    await container
        .read(profileControllerProvider.notifier)
        .load(
          const AccountContext(
            userId: 'user-a',
            spaces: [SpaceContext(id: 'couple', state: 'paired', epoch: 2)],
          ),
        );

    expect(
      container.read(profileControllerProvider).partnerProfile?.displayName,
      'Partner B',
    );
    expect(repository.partnerLoads, 1);
  });

  test('partner load failure is not presented as an unset profile', () async {
    repository.failPartnerLoad = true;
    await container
        .read(profileControllerProvider.notifier)
        .load(
          const AccountContext(
            userId: 'user-a',
            spaces: [SpaceContext(id: 'couple', state: 'paired', epoch: 2)],
          ),
        );

    final state = container.read(profileControllerProvider);
    expect(state.partnerProfile, isNull);
    expect(state.partnerLoadFailed, isTrue);
    expect(state.error, contains('could not be loaded'));
  });

  test('saving is scoped to the authenticated profile owner', () async {
    final controller = container.read(profileControllerProvider.notifier);
    await controller.load(const AccountContext(userId: 'user-a', spaces: []));

    expect(
      await controller.save(displayName: 'New Name', about: 'About'),
      isTrue,
    );
    expect(repository.savedUser, 'user-a');
    expect(
      container.read(profileControllerProvider).myProfile?.displayName,
      'New Name',
    );
  });

  test(
    'save failure retains the last saved profile and shows safe error',
    () async {
      final controller = container.read(profileControllerProvider.notifier);
      await controller.load(const AccountContext(userId: 'user-a', spaces: []));
      repository.failSave = true;

      expect(await controller.save(displayName: 'Changed', about: ''), isFalse);
      final state = container.read(profileControllerProvider);
      expect(state.myProfile?.displayName, 'Partner A');
      expect(state.error, contains('could not be saved'));
    },
  );

  test(
    'load failure exposes no profile data and offers generic error',
    () async {
      repository.failLoad = true;
      await container
          .read(profileControllerProvider.notifier)
          .load(const AccountContext(userId: 'user-a', spaces: []));

      final state = container.read(profileControllerProvider);
      expect(state.myProfile, isNull);
      expect(state.error, 'Your profile could not be loaded. Try again.');
    },
  );

  test(
    'profile photo workflow remains disabled before its security gate',
    () async {
      final controller = container.read(profileControllerProvider.notifier);
      await controller.load(
        const AccountContext(
          userId: 'user-a',
          spaces: [SpaceContext(id: 'couple', state: 'paired', epoch: 1)],
        ),
      );

      expect(repository.avatarDownloads, 0);
      expect(
        await controller.updateAvatar(Uint8List.fromList([1, 2, 3])),
        isFalse,
      );
      expect(await controller.removeAvatar(), isFalse);
      expect(repository.avatarUploads, 0);
      expect(repository.avatarRemovals, 0);
      expect(repository.profile.avatarPath, 'user-a/avatar');
    },
  );

  test(
    'photo upload and download are not invoked before verification',
    () async {
      final controller = container.read(profileControllerProvider.notifier);
      const account = AccountContext(userId: 'user-a', spaces: []);
      await controller.load(account);
      final uploaded = Uint8List.fromList([1, 2, 3, 4]);
      expect(await controller.updateAvatar(uploaded), isFalse);
      expect(repository.profile.avatarPath, 'user-a/avatar');

      controller.clear();
      await controller.load(account);
      final restored = container.read(profileControllerProvider);
      expect(restored.myProfile?.avatarPath, 'user-a/avatar');
      expect(restored.myAvatarBytes, isNull);
      expect(repository.avatarUploads, 0);
      expect(repository.avatarDownloads, 0);
    },
  );
}
