import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/profile/application/profile_controller.dart';
import 'package:twogethera/features/profile/domain/profile_repository.dart';
import 'package:twogethera/features/profile/presentation/profile_sections.dart';

class _ProfileAuth extends AuthController {
  int reloadCalls = 0;

  @override
  AuthViewState build() => const AuthViewState(
    AuthPhase.authenticated,
    context: AccountContext(userId: 'user-a', spaces: []),
  );

  @override
  Future<void> reloadContext() async {
    reloadCalls++;
    state = const AuthViewState(AuthPhase.refreshing);
    await Future<void>.delayed(Duration.zero);
    state = const AuthViewState(
      AuthPhase.authenticated,
      context: AccountContext(userId: 'user-a', spaces: []),
    );
  }
}

class _Profiles implements ProfileRepository {
  String? loadedUser;
  String? savedUser;
  int partnerLoads = 0;
  String partnerName = 'Partner B';
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
    return PartnerProfile(displayName: partnerName);
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
    expect(container.read(profileControllerProvider).myProfile?.about, 'About');
    controller.clear();
    await controller.load(const AccountContext(userId: 'user-a', spaces: []));
    expect(
      container.read(profileControllerProvider).myProfile?.displayName,
      'New Name',
    );
    expect(container.read(profileControllerProvider).myProfile?.about, 'About');
  });

  test(
    'partner profile reflects the latest shared display name only',
    () async {
      repository.partnerName = 'Updated Partner';
      await container
          .read(profileControllerProvider.notifier)
          .load(
            const AccountContext(
              userId: 'user-a',
              spaces: [SpaceContext(id: 'couple', state: 'paired', epoch: 2)],
            ),
          );
      final partner = container.read(profileControllerProvider).partnerProfile!;
      expect(partner.displayName, 'Updated Partner');
      expect(partner.avatarPath, isNull);
    },
  );

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

  testWidgets('unsaved profile edits can be discarded deliberately', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(() => _ProfileAuth()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileSections(
                account: AccountContext(userId: 'user-a', spaces: []),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'Unsaved Name');
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, 'Partner A');
  });

  testWidgets('failed profile save retains the draft and shows feedback', (
    tester,
  ) async {
    repository.failSave = true;
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(() => _ProfileAuth()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileSections(
                account: AccountContext(userId: 'user-a', spaces: []),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nameField = find.byType(TextFormField).first;
    await tester.enterText(nameField, 'Unsaved Name');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.controller.text, 'Unsaved Name');
    expect(
      find.text('Your profile could not be saved. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'successful profile save remains visible without context reload',
    (tester) async {
      final auth = _ProfileAuth();
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
          authControllerProvider.overrideWith(() => auth),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProfileSections(
                  account: AccountContext(userId: 'user-a', spaces: []),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Saved Name');
      await tester.enterText(
        find.byType(TextFormField).last,
        'Updated private note',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Saved Name'), findsOneWidget);
      expect(find.text('Updated private note'), findsOneWidget);
      expect(find.text('Your profile could not be displayed.'), findsNothing);
      expect(auth.reloadCalls, 0);
      expect(
        container.read(authControllerProvider).context?.displayName,
        'Saved Name',
      );
      expect(
        container.read(profileControllerProvider).myProfile?.displayName,
        'Saved Name',
      );
      expect(
        container.read(profileControllerProvider).myProfile?.about,
        'Updated private note',
      );
      container.read(profileControllerProvider.notifier).clear();
      await container
          .read(profileControllerProvider.notifier)
          .load(const AccountContext(userId: 'user-a', spaces: []));
      expect(
        container.read(profileControllerProvider).myProfile?.displayName,
        'Saved Name',
      );
      expect(
        container.read(profileControllerProvider).myProfile?.about,
        'Updated private note',
      );
    },
  );
}
