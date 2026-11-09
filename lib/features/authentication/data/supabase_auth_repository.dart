import 'dart:async';
import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../../dashboard/domain/dashboard_preferences.dart';
import '../../appearance/domain/appearance_preferences.dart';
import '../../budget/domain/budget_models.dart';
import '../../memories/domain/memory_models.dart';
import '../../date_nights/domain/date_night_models.dart';
import '../../goals/domain/shared_goal_models.dart';
import '../domain/password_policy.dart';
import '../domain/auth_repository.dart';
import '../../partner_linking/domain/partner_invitation_repository.dart';
import '../../shared_planner/domain/shared_planner_repository.dart';
import '../../profile/domain/profile_repository.dart';
import 'local_auth_clients.dart';

class SupabaseAuthRepository
    implements
        AuthExperienceRepository,
        PrivateBetaAccountLifecycleRepository,
        PrivacyRemovalRepository,
        PartnerInvitationRepository,
        SharedPlannerRepository,
        SharedContentRecoveryRepository,
        DashboardPreferencesRepository,
        AppearancePreferencesRepository,
        ProfileRepository,
        BudgetRepository,
        MemoriesRepository,
        DateNightRepository,
        SharedGoalsRepository {
  SupabaseAuthRepository({
    required this._createClients,
    this.allowRealAccounts = false,
    this.emailRedirectTo,
  });
  final LocalAuthClients Function() _createClients;
  final bool allowRealAccounts;
  final String? emailRedirectTo;
  final _changes = StreamController<AuthSignal>.broadcast(sync: true);
  LocalAuthClients? _clients;
  StreamSubscription<AuthState>? _subscription;
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _refresh;
  final Map<String, String> _pendingPrivacyOperationIds = {};
  @override
  Stream<AuthSignal> get changes => _changes.stream;

  LocalAuthClients _open() {
    if (_disposed) throw const AuthFailure(AuthProblem.expired);
    if (_clients != null) return _clients!;
    final clients = _clients = _createClients();
    _subscription = clients.auth.onAuthStateChange.listen(
      (event) {
        if (_clients != clients || _disposed) return;
        // Peer SDK broadcasts never authorize this adapter or replace its token.
        if (event.fromBroadcast) return;
        // SDK events are observed but never commit authority. Only an owned
        // operation's response, checked against its generation, may do that.
      },
      onError: (Object _, StackTrace _) {
        // Operations classify network/credential errors; no raw SDK diagnostics.
      },
    );
    return clients;
  }

  void _observeAcceptedSession(LocalAuthClients clients) {
    final session = clients.acceptedSession;
    final expiry = session?.expiresAt;
    if (expiry == null || _disposed || clients != _clients) return;
    _expiry?.cancel();
    final remaining = DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
        .difference(DateTime.now());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      // Keep the refresh credential in RAM for an explicit refresh only.
      // validSession still rejects every data request after access expiry.
      if (!_disposed && clients == _clients) _changes.add(AuthSignal.expired);
    });
    _changes.add(
      clients.recoveryOnly ? AuthSignal.recoveryVerified : AuthSignal.signedIn,
    );
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _discard(AuthSignal.cleared);
    if (!allowRealAccounts &&
        !email.toLowerCase().endsWith('@example.invalid')) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
    final clients = _open();
    final version = _generation;
    try {
      final response = await clients.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 8));
      if (_disposed || version != _generation || _clients != clients) {
        throw const AuthFailure(AuthProblem.expired);
      }
      final session = response.session;
      if (session == null) throw const AuthFailure(AuthProblem.expired);
      clients.acceptSession(session);
      clients.validSession();
      _observeAcceptedSession(clients);
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      _current(clients, version);
      await _discard(AuthSignal.cleared);
      throw AuthFailure(
        error.code == 'email_not_confirmed'
            ? AuthProblem.emailUnconfirmed
            : error.statusCode == '400' || error.statusCode == '401'
            ? AuthProblem.invalidCredentials
            : AuthProblem.unavailable,
      );
    } catch (error) {
      _current(clients, version);
      await _discard(AuthSignal.cleared);
      throw const AuthFailure(AuthProblem.unavailable);
    }
  }

  void _current(LocalAuthClients clients, int version) {
    if (_disposed || version != _generation || clients != _clients) {
      throw const AuthFailure(AuthProblem.expired);
    }
  }

  bool _transient(Object error) =>
      error is TimeoutException ||
      error is! AuthException ||
      error is AuthRetryableFetchException ||
      error.statusCode == null ||
      (int.tryParse(error.statusCode ?? '') ?? 0) >= 500;

  @override
  Future<void> refreshSession() {
    final pending = _refresh;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = _refreshOwned().whenComplete(() {
      if (identical(_refresh, operation)) _refresh = null;
    });
    _refresh = operation;
    return operation;
  }

  Future<void> _refreshOwned() async {
    final clients = _clients;
    final session = clients?.acceptedSession;
    if (clients == null || session?.refreshToken == null) {
      throw const AuthFailure(AuthProblem.expired);
    }
    if (clients.recoveryOnly) {
      throw const AuthFailure(AuthProblem.recoveryRequired);
    }
    final version = _generation;
    try {
      final result = await clients.auth
          .refreshSession(session!.refreshToken)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      final next = result.session;
      if (next == null || next.user.id != session.user.id) {
        throw const AuthFailure(AuthProblem.expired);
      }
      clients.acceptSession(next);
      clients.validSession();
      _observeAcceptedSession(clients);
    } catch (error) {
      if (version != _generation || clients != _clients || _disposed) {
        throw const AuthFailure(AuthProblem.expired);
      }
      // A lost response may have rotated the token on the server. Never retry
      // a possibly spent credential: fail closed and require explicit sign-in.
      await _discard(AuthSignal.expired);
      throw AuthFailure(
        _transient(error) ? AuthProblem.unavailable : AuthProblem.expired,
      );
    }
  }

  @override
  Future<void> signOut() => _logout(SignOutScope.local);

  @override
  Future<void> closeCoupleSpace(String operationId) async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data
          .schema('public')
          .rpc(
            'close_my_couple_space',
            params: {'p_operation_id': operationId},
          );
      if (result is! Map || result['status'] != 'closed') {
        throw const AuthFailure(AuthProblem.lifecycleUnavailable);
      }
      await _discard(AuthSignal.cleared);
    } on AuthFailure {
      rethrow;
    } on FunctionException catch (error) {
      if (error.status == 403 &&
          error.details.toString().contains('recent_sign_in_required')) {
        throw const AuthFailure(AuthProblem.reauthenticationRequired);
      }
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    } catch (_) {
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    }
  }

  @override
  Future<void> deleteAccount(String operationId) async {
    final clients = _authorizedClients();
    try {
      final response = await clients.data.functions.invoke(
        'delete-account',
        body: {'operation_id': operationId},
      );
      final responseBody = response.data;
      if (response.status != 200 && response.status != 202) {
        throw AuthFailure(
          response.status == 403
              ? AuthProblem.reauthenticationRequired
              : AuthProblem.lifecycleUnavailable,
        );
      }
      if (responseBody is! Map ||
          !{'completed', 'processing'}.contains(responseBody['status'])) {
        throw const AuthFailure(AuthProblem.lifecycleUnavailable);
      }
      await _discard(AuthSignal.cleared);
    } on AuthFailure {
      rethrow;
    } on FunctionException catch (error) {
      if (error.status == 403 &&
          error.details.toString().contains('recent_sign_in_required')) {
        throw const AuthFailure(AuthProblem.reauthenticationRequired);
      }
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    } catch (_) {
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    }
  }

  @override
  Future<void> requestPrivacyRemoval({
    required String table,
    required String recordId,
    String? field,
    bool removeRecord = true,
  }) async {
    const allowedTables = {
      'bucket_list_items',
      'important_dates',
      'plans',
      'plan_tasks',
      'couple_memories',
      'date_night_ideas',
      'shared_goals',
      'shared_goal_milestones',
      'couple_expenses',
      'recurring_expense_rules',
      'memory_attachments',
      'expense_receipts',
    };
    if (!allowedTables.contains(table)) {
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    }
    const allowedFields = <String, Set<String>>{
      'bucket_list_items': {'description'},
      'important_dates': {'notes'},
      'plans': {'description', 'location'},
      'couple_memories': {'caption', 'personal_notes'},
      'date_night_ideas': {'description', 'location', 'shared_notes'},
      'shared_goals': {'description'},
      'shared_goal_milestones': {'description'},
      'couple_expenses': {'description'},
      'recurring_expense_rules': {'description'},
    };
    if ((field == null && !removeRecord) ||
        (field != null &&
            (removeRecord || allowedFields[table]?.contains(field) != true))) {
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    }
    final clients = _authorizedClients();
    final operationKey = '$table:$recordId:${field ?? 'record'}';
    final operationId = _pendingPrivacyOperationIds.putIfAbsent(
      operationKey,
      newPartnerOperationId,
    );
    try {
      final requestId = await clients.data
          .schema('public')
          .rpc(
            'record_my_privacy_removal',
            params: {
              'p_operation_id': operationId,
              'p_table': table,
              'p_record_id': recordId,
              'p_field': field,
              'p_remove_record': removeRecord,
            },
          );
      if (requestId is! String) {
        throw const AuthFailure(AuthProblem.lifecycleUnavailable);
      }
      _pendingPrivacyOperationIds.remove(operationKey);
      clients.validSession();
    } on AuthFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '42501' &&
          error.message.toLowerCase().contains('reauthentication')) {
        throw const AuthFailure(AuthProblem.reauthenticationRequired);
      }
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    } catch (_) {
      throw const AuthFailure(AuthProblem.lifecycleUnavailable);
    }
  }

  Future<void> _logout(SignOutScope scope) async {
    final clients = _clients;
    final session = clients?.acceptedSession;
    // Detach authority BEFORE any server await; retain only the outbound
    // operation's credential until its bounded revocation request completes.
    _generation++;
    _expiry?.cancel();
    _clients = null;
    _refresh = null;
    final subscription = _subscription;
    _subscription = null;
    clients?.clearAcceptedSession();
    if (!_disposed) _changes.add(AuthSignal.cleared);
    await subscription?.cancel();
    if (clients == null) return;
    try {
      if (session != null) {
        var token = session.accessToken;
        if (session.isExpired) {
          final refreshed = await clients.auth
              .refreshSession(session.refreshToken)
              .timeout(const Duration(seconds: 8));
          token =
              refreshed.session?.accessToken ??
              (throw const AuthFailure(AuthProblem.expired));
        }
        // This is the same supported /logout operation used by SDK signOut.
        // Despite its SDK namespace, it uses the OWN USER JWT + public key,
        // never a service-role/admin credential or a peer's currentSession.
        await clients.auth.admin
            .signOut(token, scope: scope)
            .timeout(const Duration(seconds: 8));
      }
    } catch (_) {
      throw const AuthFailure(AuthProblem.unavailable);
    } finally {
      await clients.dispose();
    }
  }

  void _synthetic(String email) {
    if (!allowRealAccounts &&
        !email.toLowerCase().endsWith('@example.invalid')) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
  }

  @override
  Future<void> register(String email, String password) =>
      _register(email, password);

  @override
  Future<void> registerProfile(
    String email,
    String password,
    String displayName,
  ) {
    final name = displayName.trim();
    if (name.length < 2 || name.length > 64) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
    return _register(email, password, name: name);
  }

  Future<void> _register(String email, String password, {String? name}) async {
    await _discard(AuthSignal.cleared);
    _synthetic(email);
    if (validateNewPassword(password) != null) {
      throw const AuthFailure(AuthProblem.passwordRejected);
    }
    final clients = _open();
    final version = _generation;
    try {
      final response = await clients.auth
          .signUp(
            email: email,
            password: password,
            emailRedirectTo: emailRedirectTo,
            data: name == null ? null : {'display_name': name},
          )
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      if (response.session != null) {
        throw const AuthFailure(AuthProblem.configuration);
      }
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      _current(clients, version);
      throw AuthFailure.registrationResponse(
        code: error.code,
        transient: _transient(error),
      );
    } catch (error) {
      _current(clients, version);
      throw AuthFailure(
        _transient(error)
            ? AuthProblem.unavailable
            : AuthProblem.registrationRejected,
      );
    }
  }

  @override
  Future<void> resendVerification(String email) async {
    await _discard(AuthSignal.cleared);
    _synthetic(email);
    final clients = _open();
    final version = _generation;
    try {
      await clients.auth
          .resend(
            type: OtpType.signup,
            email: email,
            emailRedirectTo: emailRedirectTo,
          )
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      _current(clients, version);
      if (_transient(error)) throw const AuthFailure(AuthProblem.unavailable);
      // Account-specific failures receive the same public acknowledgement.
    }
  }

  @override
  Future<void> requestRecovery(String email) async {
    await _discard(AuthSignal.cleared);
    _synthetic(email);
    final clients = _open();
    final version = _generation;
    try {
      await clients.auth
          .resetPasswordForEmail(email, redirectTo: emailRedirectTo)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      if (_transient(error)) throw const AuthFailure(AuthProblem.unavailable);
      // Identical public response for absent/known addresses and auth API
      // account-specific request errors. No mailbox/existence information.
    }
  }

  @override
  Future<void> verifyLink(String link, {required bool recovery}) async {
    await _discard(AuthSignal.cleared);
    final clients = _open();
    final version = _generation;
    final uri = Uri.tryParse(link.trim());
    final type = recovery ? 'recovery' : 'signup';
    final trustedOrigin = allowRealAccounts
        ? uri != null &&
              uri.scheme == 'https' &&
              uri.origin == clients.endpoint.origin
        : uri != null &&
              uri.scheme == 'http' &&
              {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host);
    final query = uri?.queryParametersAll;
    final tokenKey = query?.containsKey('token_hash') == true
        ? 'token_hash'
        : query?.containsKey('token') == true
        ? 'token'
        : null;
    final expectedKeys = {
      ?tokenKey,
      'type',
      if (query?.containsKey('redirect_to') == true) 'redirect_to',
    };
    if (uri == null ||
        !trustedOrigin ||
        uri.port != clients.endpoint.port ||
        uri.path != '/auth/v1/verify' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        tokenKey == null ||
        query!.keys.toSet().difference(expectedKeys).isNotEmpty ||
        query.length != expectedKeys.length ||
        query.values.any((values) => values.length != 1) ||
        query['type']!.single != type ||
        link.length > 8192) {
      throw const AuthFailure(AuthProblem.invalidLink);
    }
    final hash = query[tokenKey]!.single;
    if (hash.isEmpty) {
      throw const AuthFailure(AuthProblem.invalidLink);
    }
    try {
      final response = await clients.auth
          .verifyOTP(
            tokenHash: hash,
            type: recovery ? OtpType.recovery : OtpType.signup,
          )
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      final session = response.session;
      if (session == null) throw const AuthFailure(AuthProblem.invalidLink);
      clients.acceptSession(session, recovery: recovery);
      _observeAcceptedSession(clients);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(
        _transient(error) ? AuthProblem.unavailable : AuthProblem.invalidLink,
      );
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    if (validateNewPassword(password) != null) {
      throw const AuthFailure(AuthProblem.passwordRejected);
    }
    final clients = _clients;
    final version = _generation;
    if (clients == null || !clients.recoveryOnly) {
      throw const AuthFailure(AuthProblem.recoveryRequired);
    }
    try {
      await clients
          .updatePasswordPinned(password)
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      // A password reset revokes all Auth refresh sessions, including this
      // recovery session; require fresh password sign-in afterward.
      await _logout(SignOutScope.global);
    } on AuthFailure {
      rethrow;
    } catch (error) {
      throw AuthFailure(
        _transient(error)
            ? AuthProblem.unavailable
            : AuthProblem.passwordRejected,
      );
    }
  }

  @override
  Future<AccountContext> accountContext() async {
    final clients = _clients;
    if (clients == null) throw const AuthFailure(AuthProblem.expired);
    final version = _generation;
    try {
      final session = clients.validSession();
      await clients.data.rpc('ensure_account');
      final result = await clients.data.rpc('account_context');
      if (version != _generation || _disposed || _clients != clients) {
        throw const AuthFailure(AuthProblem.expired);
      }
      clients.validSession();
      if (result is! Map ||
          result['user_id'] != session.user.id ||
          result['spaces'] is! List) {
        throw const AuthFailure(AuthProblem.denied);
      }
      final spaces = <SpaceContext>[];
      for (final row in result['spaces'] as List) {
        if (row is! Map ||
            row['space_id'] is! String ||
            !{'draft', 'paired'}.contains(row['state']) ||
            row['epoch'] is! int) {
          throw const AuthFailure(AuthProblem.denied);
        }
        spaces.add(
          SpaceContext(
            id: row['space_id'] as String,
            state: row['state'] as String,
            epoch: row['epoch'] as int,
          ),
        );
      }
      final profile = await clients.data
          .from('user_profiles')
          .select('display_name')
          .eq('user_id', session.user.id)
          .maybeSingle();
      _current(clients, version);
      return AccountContext(
        userId: session.user.id,
        spaces: List.unmodifiable(spaces),
        displayName: switch (profile?['display_name'] ??
            session.user.userMetadata?['display_name']) {
          final String value
              when value.trim().length >= 2 && value.trim().length <= 64 =>
            value.trim(),
          _ => null,
        },
        email: session.user.email,
      );
    } on AuthFailure {
      rethrow;
    } on PostgrestException catch (error) {
      _current(clients, version);
      if (error.code == '42501') throw const AuthFailure(AuthProblem.denied);
      if (error.code == 'PGRST301' || error.code == 'PGRST303') {
        await _discard(AuthSignal.expired);
        throw const AuthFailure(AuthProblem.expired);
      }
      throw const AuthFailure(AuthProblem.unavailable);
    } on AuthException {
      _current(clients, version);
      await _discard(AuthSignal.expired);
      throw const AuthFailure(AuthProblem.expired);
    } catch (_) {
      throw const AuthFailure(AuthProblem.unavailable);
    }
  }

  @override
  Future<UserProfile> loadMyProfile({
    required String userId,
    required String fallbackDisplayName,
  }) async {
    final clients = _authorizedClients();
    if (clients.validSession().user.id != userId) {
      throw const ProfileFailure();
    }
    try {
      final row = await clients.data
          .from('user_profiles')
          .select('user_id,display_name,about,avatar_path,revision')
          .eq('user_id', userId)
          .maybeSingle();
      clients.validSession();
      if (row == null) {
        return UserProfile(
          userId: userId,
          displayName: fallbackDisplayName,
          about: '',
          revision: 1,
        );
      }
      if (row['user_id'] != userId) throw const ProfileFailure();
      return UserProfile.fromJson(row);
    } catch (_) {
      throw const ProfileFailure();
    }
  }

  @override
  Future<PartnerProfile?> loadPartnerProfile() async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data.rpc('partner_profile');
      clients.validSession();
      if (result == null) return null;
      if (result is! Map || result['display_name'] is! String) {
        throw const ProfileFailure();
      }
      return PartnerProfile.fromJson(Map<String, dynamic>.from(result));
    } catch (_) {
      throw const ProfileFailure();
    }
  }

  @override
  Future<Uint8List?> downloadAvatar(String path) async {
    final clients = _authorizedClients();
    try {
      clients.validSession();
      final bytes = await clients.data.storage
          .from('profile-photos')
          .download(path);
      clients.validSession();
      return bytes;
    } catch (_) {
      throw const ProfileFailure();
    }
  }

  @override
  Future<UserProfile> saveMyProfile({
    required String userId,
    required String displayName,
    required String about,
    required String? avatarPath,
  }) async {
    final clients = _authorizedClients();
    if (clients.validSession().user.id != userId) {
      throw const ProfileFailure();
    }
    final normalizedName = displayName.trim();
    final normalizedAbout = about.trim();
    if (normalizedName.length < 2 ||
        normalizedName.length > 64 ||
        normalizedAbout.length > 280 ||
        (avatarPath != null && avatarPath != '$userId/avatar')) {
      throw const ProfileFailure();
    }
    final values = {
      'display_name': normalizedName,
      'about': normalizedAbout,
      'avatar_path': avatarPath,
    };
    try {
      final existing = await clients.data
          .from('user_profiles')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      final dynamic result = existing == null
          ? await clients.data
                .from('user_profiles')
                .insert({'user_id': userId, ...values})
                .select('user_id,display_name,about,avatar_path,revision')
                .single()
          : await clients.data
                .from('user_profiles')
                .update(values)
                .eq('user_id', userId)
                .select('user_id,display_name,about,avatar_path,revision')
                .single();
      clients.validSession();
      if (result is! Map || result['user_id'] != userId) {
        throw const ProfileFailure();
      }
      return UserProfile.fromJson(Map<String, dynamic>.from(result));
    } catch (_) {
      throw const ProfileFailure();
    }
  }

  @override
  Future<String> uploadMyAvatar({
    required String userId,
    required Uint8List bytes,
  }) async {
    final clients = _authorizedClients();
    if (clients.validSession().user.id != userId ||
        bytes.isEmpty ||
        bytes.length > 5 * 1024 * 1024) {
      throw const ProfileFailure();
    }
    final path = '$userId/avatar';
    try {
      await clients.data.storage
          .from('profile-photos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              // The object uses a stable per-user path; prevent browsers/CDN
              // caches from serving the prior image after an upsert.
              cacheControl: '0',
              upsert: true,
            ),
          );
      clients.validSession();
      return path;
    } catch (_) {
      throw const ProfileFailure();
    }
  }

  @override
  Future<void> removeMyAvatar(String path) async {
    final clients = _authorizedClients();
    final userId = clients.validSession().user.id;
    if (path != '$userId/avatar') throw const ProfileFailure();
    try {
      await clients.data.storage.from('profile-photos').remove([path]);
      clients.validSession();
    } catch (_) {
      throw const ProfileFailure();
    }
  }

  @override
  Future<PartnerLinkContext> loadPartnerContext() async {
    final data = await _partnerRpc('partner_link_context', const {});
    if (data['user_id'] is! String) throw const PartnerInvitationFailure();
    final rawSpace = data['space'];
    PartnerSpaceSummary? space;
    if (rawSpace != null) {
      if (rawSpace is! Map ||
          rawSpace['id'] is! String ||
          rawSpace['state'] is! String ||
          rawSpace['epoch'] is! int) {
        throw const PartnerInvitationFailure();
      }
      final state = switch (rawSpace['state']) {
        'draft' => PartnerSpaceState.draft,
        'paired' => PartnerSpaceState.paired,
        _ => throw const PartnerInvitationFailure(),
      };
      space = PartnerSpaceSummary(
        id: rawSpace['id'] as String,
        state: state,
        authorizationEpoch: rawSpace['epoch'] as int,
      );
    }
    final rawInvitation = data['invitation'];
    PartnerInvitationSummary? invitation;
    if (rawInvitation != null) {
      if (rawInvitation is! Map ||
          rawInvitation['id'] is! String ||
          rawInvitation['state'] is! String ||
          rawInvitation['recipient_hint'] is! String ||
          rawInvitation['expires_at'] is! String) {
        throw const PartnerInvitationFailure();
      }
      final state = switch (rawInvitation['state']) {
        'pending' => PartnerInvitationState.pending,
        'expired' => PartnerInvitationState.expired,
        'revoked' => PartnerInvitationState.revoked,
        _ => null,
      };
      final expiresAt = DateTime.tryParse(
        rawInvitation['expires_at'] as String,
      );
      if (state == null || expiresAt == null) {
        throw const PartnerInvitationFailure();
      }
      invitation = PartnerInvitationSummary(
        id: rawInvitation['id'] as String,
        state: state,
        recipientHint: rawInvitation['recipient_hint'] as String,
        expiresAt: expiresAt.toUtc(),
      );
    }
    return PartnerLinkContext(space: space, invitation: invitation);
  }

  @override
  Future<void> createDraftSpace(String operationId) async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data
          .schema('public')
          .rpc('create_couple_space', params: {'p_operation_id': operationId});
      if (result is! String) throw const PartnerInvitationFailure();
      clients.validSession();
    } on PartnerInvitationFailure {
      rethrow;
    } catch (_) {
      throw const PartnerInvitationFailure();
    }
  }

  @override
  Future<IssuedPartnerInvitation> issueInvitation({
    required String operationId,
    required String spaceId,
    required int expectedEpoch,
    required String recipientEmail,
  }) async {
    final data = await _partnerRpc('issue_partner_invitation', {
      'p_operation_id': operationId,
      'p_couple_id': spaceId,
      'p_expected_epoch': expectedEpoch,
      'p_recipient_email': recipientEmail,
    });
    if (data['status'] != 'created' ||
        data['invitation_id'] is! String ||
        data['recipient_hint'] is! String ||
        data['expires_at'] is! String) {
      throw const PartnerInvitationFailure();
    }
    final expiresAt = DateTime.tryParse(data['expires_at'] as String);
    if (expiresAt == null) throw const PartnerInvitationFailure();
    return IssuedPartnerInvitation(
      invitationId: data['invitation_id'] as String,
      recipientHint: data['recipient_hint'] as String,
      expiresAt: expiresAt.toUtc(),
      oneTimeToken: data['token'] is String ? data['token'] as String : null,
      replayed: data['replayed'] == true,
    );
  }

  @override
  Future<String> acceptInvitation({
    required String operationId,
    required String oneTimeToken,
  }) async {
    final data = await _partnerRpc('accept_partner_invitation', {
      'p_operation_id': operationId,
      'p_token': oneTimeToken,
    });
    if (data['status'] != 'accepted' || data['space_id'] is! String) {
      throw const PartnerInvitationFailure();
    }
    return data['space_id'] as String;
  }

  @override
  Future<void> revokeInvitation({
    required String operationId,
    required String invitationId,
  }) async {
    final data = await _partnerRpc('revoke_partner_invitation', {
      'p_operation_id': operationId,
      'p_invitation_id': invitationId,
    });
    if (data['status'] != 'revoked') throw const PartnerInvitationFailure();
  }

  @override
  Future<List<RecoverableSharedRecord>> listRecoverableSharedRecords() async {
    final clients = _authorizedClients();
    try {
      final data = await clients.data
          .schema('public')
          .rpc('list_my_recoverable_shared_records');
      if (data is! List) throw const SharedPlannerFailure();
      return data
          .whereType<Map>()
          .map(
            (row) => RecoverableSharedRecord.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<bool> restoreSharedRecord(RecoverableSharedRecord record) async {
    final clients = _authorizedClients();
    if (!const {
      'bucket_list_items',
      'important_dates',
      'plans',
      'plan_tasks',
      'couple_memories',
      'date_night_ideas',
      'shared_goals',
      'shared_goal_milestones',
    }.contains(record.table)) {
      return false;
    }
    try {
      final result = await clients.data
          .schema('public')
          .rpc(
            'restore_my_shared_record',
            params: {'p_table': record.table, 'p_record_id': record.id},
          );
      clients.validSession();
      return result == true;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  LocalAuthClients _authorizedClients() {
    final clients = _clients;
    if (clients == null) throw const PartnerInvitationFailure();
    try {
      clients.validSession();
      return clients;
    } catch (_) {
      throw const PartnerInvitationFailure();
    }
  }

  Future<Map> _partnerRpc(String function, Map<String, dynamic> params) async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data
          .schema('public')
          .rpc(function, params: params);
      clients.validSession();
      if (result is! Map) throw const PartnerInvitationFailure();
      return result;
    } catch (_) {
      throw const PartnerInvitationFailure();
    }
  }

  @override
  Future<SharedPlannerSnapshot> load(String coupleId) async {
    final clients = _authorizedClients();
    try {
      final schema = clients.data.schema('public');
      final bucketRows = await schema
          .from('bucket_list_items')
          .select()
          .eq('couple_id', coupleId)
          .order('created_at');
      final dateRows = await schema
          .from('important_dates')
          .select()
          .eq('couple_id', coupleId)
          .order('date_value');
      final planRows = await schema
          .from('plans')
          .select()
          .eq('couple_id', coupleId)
          .order('starts_at');
      final planIds = (planRows as List)
          .cast<Map>()
          .map((row) => row['id'] as String)
          .toList(growable: false);
      final taskRows = planIds.isEmpty
          ? const <Map>[]
          : (await schema
                    .from('plan_tasks')
                    .select()
                    .eq('couple_id', coupleId)
                    .inFilter('plan_id', planIds)
                    .order('sort_order'))
                as List;
      clients.validSession();
      final tasksByPlan = <String, List<PlanTask>>{};
      for (final row in taskRows.cast<Map>()) {
        final task = PlanTask.fromJson(Map<String, dynamic>.from(row));
        (tasksByPlan[task.planId] ??= []).add(task);
      }
      return SharedPlannerSnapshot(
        bucketItems: List.unmodifiable(
          bucketRows.cast<Map>().map(
            (row) => BucketListItem.fromJson(Map<String, dynamic>.from(row)),
          ),
        ),
        importantDates: List.unmodifiable(
          dateRows.cast<Map>().map(
            (row) =>
                ImportantDateEntry.fromJson(Map<String, dynamic>.from(row)),
          ),
        ),
        plans: List.unmodifiable(
          planRows.cast<Map>().map(
            (row) => SharedPlan.fromJson(
              Map<String, dynamic>.from(row),
              tasks: tasksByPlan[row['id'] as String] ?? const [],
            ),
          ),
        ),
      );
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> createBucketItem(String coupleId, Map<String, dynamic> values) =>
      _plannerInsert('bucket_list_items', {'couple_id': coupleId, ...values});

  @override
  Future<void> updateBucketItem(
    String coupleId,
    BucketListItem item,
    Map<String, dynamic> values,
  ) => _plannerUpdate(
    'bucket_list_items',
    coupleId,
    item.id,
    item.revision,
    values,
  );

  @override
  Future<void> deleteBucketItem(String coupleId, BucketListItem item) =>
      _plannerDelete(
        'delete_bucket_list_item',
        coupleId,
        item.id,
        item.revision,
      );

  @override
  Future<void> createImportantDate(
    String coupleId,
    Map<String, dynamic> values,
  ) => _plannerInsert('important_dates', {'couple_id': coupleId, ...values});

  @override
  Future<void> updateImportantDate(
    String coupleId,
    ImportantDateEntry date,
    Map<String, dynamic> values,
  ) => _plannerUpdate(
    'important_dates',
    coupleId,
    date.id,
    date.revision,
    values,
  );

  @override
  Future<void> deleteImportantDate(String coupleId, ImportantDateEntry date) =>
      _plannerDelete('delete_important_date', coupleId, date.id, date.revision);

  @override
  Future<void> createPlan(String coupleId, Map<String, dynamic> values) =>
      _plannerInsert('plans', {'couple_id': coupleId, ...values});

  @override
  Future<void> updatePlan(
    String coupleId,
    SharedPlan plan,
    Map<String, dynamic> values,
  ) => _plannerUpdate('plans', coupleId, plan.id, plan.revision, values);

  @override
  Future<void> deletePlan(String coupleId, SharedPlan plan) =>
      _plannerDelete('delete_plan', coupleId, plan.id, plan.revision);

  @override
  Future<void> createTask(String coupleId, String planId, String title) =>
      _plannerInsert('plan_tasks', {
        'couple_id': coupleId,
        'plan_id': planId,
        'title': title,
      });

  @override
  Future<void> updateTask(
    String coupleId,
    PlanTask task,
    Map<String, dynamic> values,
  ) => _plannerUpdate('plan_tasks', coupleId, task.id, task.revision, values);

  @override
  Future<void> deleteTask(String coupleId, PlanTask task) =>
      _plannerDelete('delete_plan_task', coupleId, task.id, task.revision);

  Future<void> _plannerInsert(String table, Map<String, dynamic> values) async {
    final clients = _authorizedClients();
    try {
      await clients.data
          .schema('public')
          .from(table)
          .insert(values)
          .select('id')
          .single();
      clients.validSession();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  Future<void> _plannerUpdate(
    String table,
    String coupleId,
    String id,
    int revision,
    Map<String, dynamic> values,
  ) async {
    final clients = _authorizedClients();
    try {
      final row = await clients.data
          .schema('public')
          .from(table)
          .update(values)
          .eq('couple_id', coupleId)
          .eq('id', id)
          .eq('revision', revision)
          .select('id')
          .maybeSingle();
      clients.validSession();
      if (row == null) throw const SharedPlannerFailure();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  Future<void> _plannerDelete(
    String function,
    String coupleId,
    String id,
    int revision,
  ) async {
    final clients = _authorizedClients();
    try {
      final deleted = await clients.data
          .schema('public')
          .rpc(
            function,
            params: {
              'p_couple_id': coupleId,
              if (function == 'delete_bucket_list_item') 'p_item_id': id,
              if (function == 'delete_important_date') 'p_date_id': id,
              if (function == 'delete_plan') 'p_plan_id': id,
              if (function == 'delete_plan_task') 'p_task_id': id,
              'p_expected_revision': revision,
            },
          );
      clients.validSession();
      if (deleted != true) throw const SharedPlannerFailure();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<DashboardPreferences?> loadDashboardPreferences(String userId) async {
    final clients = _authorizedClients();
    try {
      final row = await clients.data
          .schema('public')
          .from('user_dashboard_preferences')
          .select('module_order,visible_modules')
          .eq('user_id', userId)
          .maybeSingle();
      clients.validSession();
      return row == null
          ? null
          : DashboardPreferences.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      throw const DashboardPreferencesFailure();
    }
  }

  @override
  Future<void> saveDashboardPreferences(
    String userId,
    DashboardPreferences preferences,
  ) async {
    final clients = _authorizedClients();
    try {
      await clients.data
          .schema('public')
          .from('user_dashboard_preferences')
          .upsert({
            'user_id': userId,
            ...preferences.toJson(),
          }, onConflict: 'user_id');
      clients.validSession();
    } catch (_) {
      throw const DashboardPreferencesFailure();
    }
  }

  @override
  Future<AppearancePreferences?> loadAppearancePreferences(
    String userId,
  ) async {
    final clients = _authorizedClients();
    if (clients.validSession().user.id != userId) {
      throw const AppearancePreferencesFailure();
    }
    try {
      final row = await clients.data
          .schema('public')
          .from('user_dashboard_preferences')
          .select(
            'appearance_mode,appearance_theme,appearance_custom_hex,'
            'appearance_font_size,appearance_gradient_preset,'
            'appearance_gradient_start_hex,appearance_gradient_end_hex,'
            'appearance_gradient_direction',
          )
          .eq('user_id', userId)
          .maybeSingle();
      clients.validSession();
      return row == null
          ? null
          : AppearancePreferences.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      throw const AppearancePreferencesFailure();
    }
  }

  @override
  Future<void> saveAppearancePreferences(
    String userId,
    AppearancePreferences preferences,
  ) async {
    final clients = _authorizedClients();
    if (clients.validSession().user.id != userId) {
      throw const AppearancePreferencesFailure();
    }
    try {
      await clients.data
          .schema('public')
          .from('user_dashboard_preferences')
          .upsert({
            'user_id': userId,
            ...preferences.toJson(),
          }, onConflict: 'user_id');
      clients.validSession();
    } catch (_) {
      throw const AppearancePreferencesFailure();
    }
  }

  @override
  Future<BudgetSnapshot> loadBudget(String coupleId, DateTime month) async {
    final clients = _authorizedClients();
    if (coupleId.isEmpty) throw const SharedPlannerFailure();
    try {
      final data = clients.data.schema('public');
      final monthStart = DateTime(month.year, month.month, 1);
      final monthKey = _dateKey(monthStart);
      final budgetRows = await data
          .from('couple_budgets')
          .select()
          .eq('couple_id', coupleId)
          .eq('month_start', monthKey)
          .limit(1);
      final members = await data
          .from('couple_memberships')
          .select('user_id,seat')
          .eq('couple_id', coupleId)
          .eq('state', 'active')
          .order('seat');
      final session = clients.validSession();
      final memberList = (members as List)
          .map((row) {
            final map = Map<String, dynamic>.from(row);
            final userId = map['user_id'] as String;
            return BudgetMember(
              userId: userId,
              seat: (map['seat'] as num).toInt(),
              label: userId == session.user.id
                  ? 'You'
                  : 'Partner ${map['seat'] == 1 ? '1' : '2'}',
            );
          })
          .toList(growable: false);
      CoupleBudget? budget;
      final expenses = <CoupleExpense>[];
      final rules = <RecurringExpenseRule>[];
      if (budgetRows.isNotEmpty) {
        final rawBudget = Map<String, dynamic>.from(budgetRows.first);
        final budgetId = rawBudget['id'] as String;
        final categoryRows = await data
            .from('budget_category_limits')
            .select('category_key,limit_minor')
            .eq('couple_id', coupleId)
            .eq('budget_id', budgetId);
        final categories = <BudgetCategory, int>{};
        for (final row in categoryRows) {
          final map = Map<String, dynamic>.from(row);
          categories[BudgetCategory.fromKey(map['category_key'])] =
              (map['limit_minor'] as num).toInt();
        }
        budget = CoupleBudget.fromJson(rawBudget, categoryLimits: categories);
        final expenseRows = await data
            .from('couple_expenses')
            .select()
            .eq('couple_id', coupleId)
            .eq('budget_id', budgetId)
            .order('occurred_on', ascending: false)
            .order('created_at', ascending: false);
        expenses.addAll(
          (expenseRows as List).map(
            (row) => CoupleExpense.fromJson(Map<String, dynamic>.from(row)),
          ),
        );
      }
      // Schedules are independent of a month-specific budget. Load them even
      // when the selected month has no budget, so they remain reviewable after
      // month navigation or refresh.
      final ruleRows = await data
          .from('recurring_expense_rules')
          .select()
          .eq('couple_id', coupleId)
          .order('starts_on');
      rules.addAll(
        (ruleRows as List).map(
          (row) =>
              RecurringExpenseRule.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
      final occurrenceRows = await data
          .from('couple_expenses')
          .select('recurring_rule_id,recurrence_key')
          .eq('couple_id', coupleId)
          .not('recurring_rule_id', 'is', null)
          .order('recurrence_key');
      final occurrences = (occurrenceRows as List)
          .map((row) {
            final map = Map<String, dynamic>.from(row);
            return RecurringExpenseOccurrence(
              ruleId: map['recurring_rule_id'] as String,
              date: DateTime.parse(map['recurrence_key'] as String),
            );
          })
          .toList(growable: false);
      clients.validSession();
      return BudgetSnapshot(
        budget: budget,
        expenses: List.unmodifiable(expenses),
        recurringRules: List.unmodifiable(rules),
        members: List.unmodifiable(memberList),
        recurringOccurrences: List.unmodifiable(occurrences),
      );
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveBudget(
    String coupleId,
    DateTime month,
    CurrencyUnit currency,
    int limitMinor,
  ) async {
    final clients = _authorizedClients();
    if (limitMinor < 0 || limitMinor > ExactMoney.maximumMinor) {
      throw const SharedPlannerFailure();
    }
    try {
      await clients.data.schema('public').from('couple_budgets').upsert({
        'couple_id': coupleId,
        'month_start': _dateKey(DateTime(month.year, month.month, 1)),
        'currency_code': currency.code,
        'currency_exponent': currency.exponent,
        'limit_minor': limitMinor,
      }, onConflict: 'couple_id,month_start');
      clients.validSession();
    } on PostgrestException catch (error) {
      throw BudgetOperationFailure.fromPostgresCode(error.code);
    } catch (_) {
      throw const BudgetOperationFailure(
        'The monthly budget could not be saved. Refresh and try again.',
      );
    }
  }

  @override
  Future<void> saveCategoryLimit(
    String coupleId,
    String budgetId,
    BudgetCategory category,
    int limitMinor,
  ) async {
    final clients = _authorizedClients();
    if (limitMinor < 0 || limitMinor > ExactMoney.maximumMinor) {
      throw const SharedPlannerFailure();
    }
    try {
      await clients.data.schema('public').from('budget_category_limits').upsert(
        {
          'couple_id': coupleId,
          'budget_id': budgetId,
          'category_key': category.key,
          'limit_minor': limitMinor,
        },
        onConflict: 'budget_id,category_key',
      );
      clients.validSession();
    } on PostgrestException catch (error) {
      throw BudgetOperationFailure.fromPostgresCode(error.code);
    } catch (_) {
      throw const BudgetOperationFailure(
        'The category limit could not be saved. Refresh and try again.',
      );
    }
  }

  @override
  Future<void> saveExpense(
    String coupleId,
    String budgetId,
    CurrencyUnit currency,
    Map<String, dynamic> values, {
    String? expenseId,
    int? expectedRevision,
  }) async {
    final clients = _authorizedClients();
    try {
      final table = clients.data.schema('public').from('couple_expenses');
      if (expenseId == null) {
        await table.insert({
          ...values,
          'couple_id': coupleId,
          'budget_id': budgetId,
          'currency_code': currency.code,
          'currency_exponent': currency.exponent,
        });
      } else {
        if (expectedRevision == null) throw const SharedPlannerFailure();
        final result = await table
            .update(values)
            .eq('couple_id', coupleId)
            .eq('id', expenseId)
            .eq('revision', expectedRevision)
            .select('id')
            .maybeSingle();
        if (result == null) throw const SharedPlannerFailure();
      }
      clients.validSession();
    } on PostgrestException catch (error) {
      throw BudgetOperationFailure.fromPostgresCode(error.code);
    } catch (_) {
      throw const BudgetOperationFailure(
        'The expense could not be saved. Refresh and try again.',
      );
    }
  }

  @override
  Future<void> deleteExpense(String coupleId, CoupleExpense expense) async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data
          .schema('public')
          .rpc(
            'delete_couple_expense',
            params: {
              'p_couple_id': coupleId,
              'p_expense_id': expense.id,
              'p_expected_revision': expense.revision,
            },
          );
      clients.validSession();
      if (result != true) throw const SharedPlannerFailure();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveRecurringRule(
    String coupleId,
    Map<String, dynamic> values, {
    String? ruleId,
    int? expectedRevision,
  }) async {
    final clients = _authorizedClients();
    try {
      final table = clients.data
          .schema('public')
          .from('recurring_expense_rules');
      if (ruleId == null) {
        await table.insert({...values, 'couple_id': coupleId});
      } else {
        if (expectedRevision == null) {
          throw const BudgetOperationFailure(
            'Refresh the schedule before editing it.',
          );
        }
        final result = await table
            .update(values)
            .eq('couple_id', coupleId)
            .eq('id', ruleId)
            .eq('revision', expectedRevision)
            .select('id')
            .maybeSingle();
        if (result == null) {
          throw const BudgetOperationFailure(
            'This schedule changed on another device. Refresh and try again.',
          );
        }
      }
      clients.validSession();
    } on BudgetOperationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw BudgetOperationFailure.fromPostgresCode(error.code);
    } catch (_) {
      throw const BudgetOperationFailure(
        'The recurring schedule could not be saved. Refresh and try again.',
      );
    }
  }

  @override
  Future<void> setRecurringRuleActive(
    String coupleId,
    RecurringExpenseRule rule,
    bool active,
  ) async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data
          .schema('public')
          .from('recurring_expense_rules')
          .update({'active': active})
          .eq('couple_id', coupleId)
          .eq('id', rule.id)
          .eq('revision', rule.revision)
          .select('id')
          .maybeSingle();
      if (result == null) {
        throw const BudgetOperationFailure(
          'This schedule changed on another device. Refresh and try again.',
        );
      }
      clients.validSession();
    } on BudgetOperationFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw BudgetOperationFailure.fromPostgresCode(error.code);
    } catch (_) {
      throw const BudgetOperationFailure(
        'The recurring schedule could not be changed. Refresh and try again.',
      );
    }
  }

  @override
  Future<void> recordRecurringOccurrence(
    String coupleId,
    String budgetId,
    CurrencyUnit currency,
    RecurringExpenseRule rule,
    DateTime occurrence,
  ) async {
    final clients = _authorizedClients();
    final date = DateTime(occurrence.year, occurrence.month, occurrence.day);
    if (!rule.active ||
        rule.currency.code != currency.code ||
        rule.occurrencesBetween(date, date).isEmpty) {
      throw const BudgetOperationFailure(
        'Choose an active scheduled occurrence in the schedule currency.',
      );
    }
    final splitA = rule.splitAMinor;
    try {
      await clients.data.schema('public').from('couple_expenses').insert({
        'couple_id': coupleId,
        'budget_id': budgetId,
        'title': rule.title,
        'description': rule.description,
        'amount_minor': rule.amountMinor,
        'currency_code': currency.code,
        'currency_exponent': currency.exponent,
        'occurred_on': _dateKey(date),
        'category_key': rule.category.key,
        'paid_by_user': rule.paidByUser,
        'split_mode': 'custom',
        'split_a_user_id': rule.splitAUserId,
        'split_a_minor': splitA,
        'split_b_user_id': rule.splitBUserId,
        'split_b_minor': rule.splitBMinor,
        'recurring_rule_id': rule.id,
        'recurrence_key': _dateKey(date),
      });
      clients.validSession();
    } on PostgrestException catch (error) {
      throw BudgetOperationFailure.fromPostgresCode(
        error.code,
        duplicateOccurrence: true,
      );
    } catch (_) {
      throw const BudgetOperationFailure(
        'The occurrence could not be recorded. Refresh and try again.',
      );
    }
  }

  @override
  Future<List<ExpenseReceipt>> loadReceipts(
    String coupleId,
    String expenseId,
  ) async {
    final clients = _authorizedClients();
    try {
      final rows = await clients.data
          .schema('public')
          .from('expense_receipts')
          .select()
          .eq('couple_id', coupleId)
          .eq('expense_id', expenseId)
          .order('created_at');
      clients.validSession();
      return List.unmodifiable(
        (rows as List).map(
          (row) => ExpenseReceipt.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> uploadReceipt(
    String coupleId,
    String expenseId,
    Uint8List bytes,
    String contentType,
  ) async {
    final clients = _authorizedClients();
    if (bytes.isEmpty ||
        bytes.length > 10 * 1024 * 1024 ||
        !{'image/jpeg', 'image/png', 'image/webp'}.contains(contentType)) {
      throw const SharedPlannerFailure();
    }
    String? receiptId;
    String? path;
    try {
      final row = await clients.data
          .schema('public')
          .from('expense_receipts')
          .insert({
            'couple_id': coupleId,
            'expense_id': expenseId,
            'content_type': contentType,
            'byte_size': bytes.length,
          })
          .select('id,object_path')
          .single();
      receiptId = row['id'] as String;
      path = row['object_path'] as String;
      await clients.data.storage
          .from('couple-receipts')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      clients.validSession();
    } catch (_) {
      if (path != null) {
        try {
          await clients.data.storage.from('couple-receipts').remove([path]);
          path = null;
        } catch (_) {}
      }
      if (receiptId != null) {
        try {
          if (path == null) {
            await clients.data
                .schema('public')
                .rpc(
                  'delete_couple_expense_receipt',
                  params: {'p_couple_id': coupleId, 'p_receipt_id': receiptId},
                );
          }
        } catch (_) {}
      }
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<Uint8List> downloadReceipt(String path) async {
    final clients = _authorizedClients();
    try {
      final bytes = await clients.data.storage
          .from('couple-receipts')
          .download(path);
      clients.validSession();
      return bytes;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> deleteReceipt(ExpenseReceipt receipt) async {
    final clients = _authorizedClients();
    try {
      await clients.data.storage.from('couple-receipts').remove([
        receipt.objectPath,
      ]);
      final removed = await clients.data
          .schema('public')
          .rpc(
            'delete_couple_expense_receipt',
            params: {
              'p_couple_id': receipt.coupleId,
              'p_receipt_id': receipt.id,
            },
          );
      if (removed != true) throw const SharedPlannerFailure();
      clients.validSession();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<MemoriesSnapshot> loadMemories(String coupleId) async {
    final clients = _authorizedClients();
    try {
      final data = clients.data.schema('public');
      final memoryRows = await data
          .from('couple_memories')
          .select()
          .eq('couple_id', coupleId)
          .order('memory_on', ascending: false)
          .order('created_at', ascending: false);
      final attachmentRows = await data
          .from('memory_attachments')
          .select()
          .eq('couple_id', coupleId)
          .order('created_at');
      final dateRows = await data
          .from('important_dates')
          .select('id,title')
          .eq('couple_id', coupleId)
          .order('date_value');
      final photosByMemory = <String, List<MemoryPhoto>>{};
      for (final row in attachmentRows as List) {
        final photo = MemoryPhoto.fromJson(Map<String, dynamic>.from(row));
        photosByMemory.putIfAbsent(photo.memoryId, () => []).add(photo);
      }
      clients.validSession();
      return MemoriesSnapshot(
        memories: List.unmodifiable(
          (memoryRows as List).map((row) {
            final map = Map<String, dynamic>.from(row);
            return CoupleMemory.fromJson(
              map,
              photos: photosByMemory[map['id']] ?? const [],
            );
          }),
        ),
        importantDates: List.unmodifiable(
          (dateRows as List).map((row) {
            final map = Map<String, dynamic>.from(row);
            return (id: map['id'] as String, title: map['title'] as String);
          }),
        ),
      );
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveMemory(
    String coupleId,
    Map<String, dynamic> values, {
    String? memoryId,
  }) async {
    final clients = _authorizedClients();
    try {
      final table = clients.data.schema('public').from('couple_memories');
      if (memoryId == null) {
        values.remove('_revision');
        await table.insert({...values, 'couple_id': coupleId});
      } else {
        final revision = values.remove('_revision');
        if (revision is! int) throw const SharedPlannerFailure();
        final result = await table
            .update(values)
            .eq('couple_id', coupleId)
            .eq('id', memoryId)
            .eq('revision', revision)
            .select('id')
            .maybeSingle();
        if (result == null) throw const SharedPlannerFailure();
      }
      clients.validSession();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> deleteMemory(String coupleId, CoupleMemory memory) async {
    final clients = _authorizedClients();
    try {
      for (final photo in memory.photos) {
        await clients.data.storage.from('couple-memories').remove([
          photo.objectPath,
        ]);
        final removed = await clients.data
            .schema('public')
            .rpc(
              'delete_couple_memory_attachment',
              params: {'p_couple_id': coupleId, 'p_attachment_id': photo.id},
            );
        if (removed != true) throw const SharedPlannerFailure();
      }
      final result = await clients.data
          .schema('public')
          .rpc(
            'delete_couple_memory',
            params: {
              'p_couple_id': coupleId,
              'p_memory_id': memory.id,
              'p_expected_revision': memory.revision,
            },
          );
      clients.validSession();
      if (result != true) throw const SharedPlannerFailure();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> toggleFavorite(String coupleId, CoupleMemory memory) async {
    final clients = _authorizedClients();
    try {
      final row = await clients.data
          .schema('public')
          .from('couple_memories')
          .update({'is_favorite': !memory.favorite})
          .eq('couple_id', coupleId)
          .eq('id', memory.id)
          .eq('revision', memory.revision)
          .select('id')
          .maybeSingle();
      if (row == null) throw const SharedPlannerFailure();
      clients.validSession();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> addPhotos(
    String coupleId,
    String memoryId,
    List<({Uint8List bytes, String contentType})> photos,
  ) async {
    final clients = _authorizedClients();
    if (photos.isEmpty || photos.length > 10) {
      throw const SharedPlannerFailure();
    }
    for (final photo in photos) {
      if (photo.bytes.isEmpty ||
          photo.bytes.length > 15 * 1024 * 1024 ||
          !{
            'image/jpeg',
            'image/png',
            'image/webp',
          }.contains(photo.contentType)) {
        throw const SharedPlannerFailure();
      }
      String? attachmentId;
      String? path;
      try {
        final row = await clients.data
            .schema('public')
            .from('memory_attachments')
            .insert({
              'couple_id': coupleId,
              'memory_id': memoryId,
              'content_type': photo.contentType,
              'byte_size': photo.bytes.length,
            })
            .select('id,object_path')
            .single();
        attachmentId = row['id'] as String;
        path = row['object_path'] as String;
        await clients.data.storage
            .from('couple-memories')
            .uploadBinary(
              path,
              photo.bytes,
              fileOptions: FileOptions(
                contentType: photo.contentType,
                upsert: false,
              ),
            );
        clients.validSession();
      } catch (_) {
        if (path != null) {
          try {
            await clients.data.storage.from('couple-memories').remove([path]);
            path = null;
          } catch (_) {}
        }
        if (attachmentId != null) {
          try {
            if (path == null) {
              await clients.data
                  .schema('public')
                  .rpc(
                    'delete_couple_memory_attachment',
                    params: {
                      'p_couple_id': coupleId,
                      'p_attachment_id': attachmentId,
                    },
                  );
            }
          } catch (_) {}
        }
        throw const SharedPlannerFailure();
      }
    }
  }

  @override
  Future<void> removePhoto(String coupleId, MemoryPhoto photo) async {
    final clients = _authorizedClients();
    try {
      await clients.data.storage.from('couple-memories').remove([
        photo.objectPath,
      ]);
      final removed = await clients.data
          .schema('public')
          .rpc(
            'delete_couple_memory_attachment',
            params: {'p_couple_id': coupleId, 'p_attachment_id': photo.id},
          );
      if (removed != true) throw const SharedPlannerFailure();
      clients.validSession();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<Uint8List> downloadPhoto(String objectPath) async {
    final clients = _authorizedClients();
    try {
      final bytes = await clients.data.storage
          .from('couple-memories')
          .download(objectPath);
      clients.validSession();
      return bytes;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  Future<String> _runRevisionCommand(
    String function,
    Map<String, dynamic> params,
  ) async {
    final clients = _authorizedClients();
    try {
      final result = await clients.data
          .schema('public')
          .rpc(function, params: params);
      clients.validSession();
      if (result is! String ||
          !{'updated', 'conflict', 'unavailable', 'invalid'}.contains(result)) {
        throw const SharedPlannerFailure();
      }
      return result;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<DateNightSnapshot> loadDateNights(String coupleId) async {
    final clients = _authorizedClients();
    try {
      final data = clients.data.schema('public');
      final rows = await data
          .from('date_night_ideas')
          .select()
          .eq('couple_id', coupleId)
          .order('scheduled_on', nullsFirst: false)
          .order('created_at', ascending: false);
      final plans = await data
          .from('plans')
          .select('id,title')
          .eq('couple_id', coupleId)
          .order('starts_at');
      final rawIdeas = (rows as List).cast<Map>();
      final ids = rawIdeas.map((row) => row['id'] as String).toList();
      final rawVotes = ids.isEmpty
          ? const <Map>[]
          : (await data
                    .from('date_night_votes')
                    .select('idea_id,user_id,response')
                    .eq('couple_id', coupleId)
                    .inFilter('idea_id', ids))
                as List;
      final grouped = <String, Map<String, String>>{};
      for (final row in rawVotes.cast<Map>()) {
        final vote = Map<String, dynamic>.from(row);
        (grouped[vote['idea_id'] as String] ??= {})[vote['user_id'] as String] =
            vote['response'] as String;
      }
      clients.validSession();
      return DateNightSnapshot(
        List.unmodifiable(
          rawIdeas.map(
            (row) => DateNightIdea.fromJson(
              Map<String, dynamic>.from(row),
              votes: grouped[row['id'] as String] ?? const {},
            ),
          ),
        ),
        List.unmodifiable(
          (plans as List).map((row) {
            final value = Map<String, dynamic>.from(row);
            return (id: value['id'] as String, title: value['title'] as String);
          }),
        ),
      );
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveDateNight(
    String coupleId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) async {
    final clients = _authorizedClients();
    try {
      final table = clients.data.schema('public').from('date_night_ideas');
      if (id == null) {
        await table
            .insert({...values, 'couple_id': coupleId})
            .select('id')
            .single();
      } else {
        if (expectedRevision == null) throw const SharedPlannerFailure();
        final result = await _runRevisionCommand('update_date_night_idea', {
          'p_couple_id': coupleId,
          'p_idea_id': id,
          'p_expected_revision': expectedRevision,
          'p_changes': values,
        });
        if (result == 'conflict') throw const DateNightRevisionConflict();
        if (result != 'updated') throw const SharedPlannerFailure();
      }
      clients.validSession();
    } on DateNightRevisionConflict {
      rethrow;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveDateNightVote(
    String coupleId,
    String ideaId,
    String response,
  ) async {
    final clients = _authorizedClients();
    try {
      if (!{'interested', 'not_for_me'}.contains(response)) {
        throw const SharedPlannerFailure();
      }
      final data = clients.data.schema('public');
      final userId = clients.validSession().user.id;
      final current = await data
          .from('date_night_votes')
          .select('idea_id')
          .eq('couple_id', coupleId)
          .eq('idea_id', ideaId)
          .eq('user_id', userId)
          .maybeSingle();
      if (current == null) {
        await data.from('date_night_votes').insert({
          'couple_id': coupleId,
          'idea_id': ideaId,
          'user_id': userId,
          'response': response,
        });
      } else {
        await data
            .from('date_night_votes')
            .update({'response': response})
            .eq('couple_id', coupleId)
            .eq('idea_id', ideaId)
            .eq('user_id', userId);
      }
      clients.validSession();
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<SharedGoalsSnapshot> loadSharedGoals(String coupleId) async {
    final clients = _authorizedClients();
    try {
      final data = clients.data.schema('public');
      final goals = await data
          .from('shared_goals')
          .select()
          .eq('couple_id', coupleId)
          .order('created_at', ascending: false);
      final ids = (goals as List)
          .cast<Map>()
          .map((row) => row['id'] as String)
          .toList();
      final milestoneRows = ids.isEmpty
          ? const <Map>[]
          : (await data
                    .from('shared_goal_milestones')
                    .select()
                    .eq('couple_id', coupleId)
                    .inFilter('goal_id', ids)
                    .order('sort_order')
                    .order('created_at'))
                as List;
      final grouped = <String, List<SharedGoalMilestone>>{};
      for (final row in milestoneRows.cast<Map>()) {
        final milestone = SharedGoalMilestone.fromJson(
          Map<String, dynamic>.from(row),
        );
        (grouped[milestone.goalId] ??= []).add(milestone);
      }
      clients.validSession();
      return SharedGoalsSnapshot(
        List.unmodifiable(
          (goals).cast<Map>().map(
            (row) => SharedGoal.fromJson(
              Map<String, dynamic>.from(row),
              milestones: grouped[row['id'] as String] ?? const [],
            ),
          ),
        ),
      );
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveSharedGoal(
    String coupleId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) async {
    final clients = _authorizedClients();
    try {
      final table = clients.data.schema('public').from('shared_goals');
      if (id == null) {
        await table
            .insert({...values, 'couple_id': coupleId})
            .select('id')
            .single();
      } else {
        if (expectedRevision == null) throw const SharedPlannerFailure();
        final result = await _runRevisionCommand('update_shared_goal', {
          'p_couple_id': coupleId,
          'p_goal_id': id,
          'p_expected_revision': expectedRevision,
          'p_changes': values,
        });
        if (result == 'conflict') throw const SharedGoalRevisionConflict();
        if (result != 'updated') throw const SharedPlannerFailure();
      }
      clients.validSession();
    } on SharedGoalRevisionConflict {
      rethrow;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  @override
  Future<void> saveMilestone(
    String coupleId,
    String goalId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) async {
    final clients = _authorizedClients();
    try {
      final table = clients.data
          .schema('public')
          .from('shared_goal_milestones');
      if (id == null) {
        await table
            .insert({...values, 'couple_id': coupleId, 'goal_id': goalId})
            .select('id')
            .single();
      } else {
        if (expectedRevision == null) throw const SharedPlannerFailure();
        final result = await _runRevisionCommand(
          'update_shared_goal_milestone',
          {
            'p_couple_id': coupleId,
            'p_goal_id': goalId,
            'p_milestone_id': id,
            'p_expected_revision': expectedRevision,
            'p_changes': values,
          },
        );
        if (result == 'conflict') throw const SharedGoalRevisionConflict();
        if (result != 'updated') throw const SharedPlannerFailure();
      }
      clients.validSession();
    } on SharedGoalRevisionConflict {
      rethrow;
    } catch (_) {
      throw const SharedPlannerFailure();
    }
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _discard(AuthSignal reason) async {
    _generation++;
    _expiry?.cancel();
    final clients = _clients;
    _clients = null;
    final subscription = _subscription;
    _subscription = null;
    _refresh = null;
    if (!_disposed) _changes.add(reason);
    await subscription?.cancel();
    await clients?.dispose();
  }

  @override
  Future<void> clearLocalSession() => _discard(AuthSignal.cleared);
  @override
  Future<void> dispose() async {
    _disposed = true;
    await _discard(AuthSignal.cleared);
    await _changes.close();
  }
}
