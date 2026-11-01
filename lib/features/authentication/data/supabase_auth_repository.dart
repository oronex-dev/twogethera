import 'dart:async';

import 'package:supabase/supabase.dart';

import '../domain/auth_repository.dart';
import '../../partner_linking/domain/partner_invitation_repository.dart';
import '../../shared_planner/domain/shared_planner_repository.dart';
import 'local_auth_clients.dart';

class SupabaseAuthRepository
    implements
        AuthExperienceRepository,
        PartnerInvitationRepository,
        SharedPlannerRepository {
  SupabaseAuthRepository({required this._createClients});
  final LocalAuthClients Function() _createClients;
  final _changes = StreamController<AuthSignal>.broadcast(sync: true);
  LocalAuthClients? _clients;
  StreamSubscription<AuthState>? _subscription;
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _refresh;
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
    if (!email.endsWith('@example.invalid')) {
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
    if (!email.endsWith('@example.invalid')) {
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
    if (password.length < 16) {
      throw const AuthFailure(AuthProblem.passwordRejected);
    }
    final clients = _open();
    final version = _generation;
    try {
      final response = await clients.auth
          .signUp(
            email: email,
            password: password,
            data: name == null ? null : {'display_name': name},
          )
          .timeout(const Duration(seconds: 8));
      _current(clients, version);
      if (response.session != null) {
        throw const AuthFailure(AuthProblem.configuration);
      }
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
  Future<void> resendVerification(String email) async {
    await _discard(AuthSignal.cleared);
    _synthetic(email);
    final clients = _open();
    final version = _generation;
    try {
      await clients.auth
          .resend(type: OtpType.signup, email: email)
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
          .resetPasswordForEmail(email)
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
    if (uri == null ||
        uri.scheme != 'http' ||
        !{'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri.host) ||
        uri.port != clients.endpoint.port ||
        uri.path != '/auth/v1/verify' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters['type'] != type ||
        link.length > 8192) {
      throw const AuthFailure(AuthProblem.invalidLink);
    }
    final hash =
        uri.queryParameters['token'] ?? uri.queryParameters['token_hash'];
    if (hash == null || hash.isEmpty) {
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
    if (password.length < 16) {
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
      return AccountContext(
        userId: session.user.id,
        spaces: List.unmodifiable(spaces),
        displayName: switch (session.user.userMetadata?['display_name']) {
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
