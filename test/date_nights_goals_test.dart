import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twogethera/features/authentication/application/auth_controller.dart';
import 'package:twogethera/features/authentication/domain/auth_repository.dart';
import 'package:twogethera/features/date_nights/domain/date_night_models.dart';
import 'package:twogethera/features/date_nights/application/date_nights_controller.dart';
import 'package:twogethera/features/date_nights/presentation/date_nights_screen.dart';
import 'package:twogethera/features/goals/domain/shared_goal_models.dart';
import 'package:twogethera/features/goals/application/shared_goals_controller.dart';
import 'package:twogethera/features/goals/presentation/shared_goals_screen.dart';

void main() {
  test(
    'date-night model retains date-only schedule and independent responses',
    () {
      final idea = DateNightIdea.fromJson(
        {
          'id': 'idea-1',
          'couple_id': 'couple-1',
          'title': 'Museum afternoon',
          'description': '',
          'status': 'scheduled',
          'revision': 2,
          'scheduled_on': '2026-12-01',
          'estimated_amount_minor': 2500,
          'estimated_currency_code': 'USD',
        },
        votes: const {'a': 'interested', 'b': 'not_for_me'},
      );

      expect(idea.scheduledOn, DateTime(2026, 12, 1));
      expect(idea.votes['a'], 'interested');
      expect(idea.votes['b'], 'not_for_me');
      expect(dateNightDateKey(idea.scheduledOn!), '2026-12-01');
    },
  );

  test('goal progress is derived from milestone completion, never money', () {
    final goal = SharedGoal.fromJson(
      {
        'id': 'goal-1',
        'couple_id': 'couple-1',
        'title': 'Learn to cook together',
        'description': '',
        'category': 'learning',
        'status': 'active',
        'revision': 1,
      },
      milestones: const [
        SharedGoalMilestone(
          id: 'm1',
          goalId: 'goal-1',
          title: 'Pick a recipe',
          description: '',
          completed: true,
          revision: 2,
          sortOrder: 0,
        ),
        SharedGoalMilestone(
          id: 'm2',
          goalId: 'goal-1',
          title: 'Cook it',
          description: '',
          completed: false,
          revision: 1,
          sortOrder: 1,
        ),
      ],
    );
    expect(goal.completedMilestones, 1);
    expect(goal.progress, 0.5);
    expect(
      SharedGoal.fromJson({
        'id': 'empty',
        'couple_id': 'couple-1',
        'title': 'Goal',
        'description': '',
        'category': 'other',
        'status': 'completed',
        'revision': 1,
      }).progress,
      1,
    );
  });

  testWidgets('unpaired accounts see no shared planner queries or data', (
    tester,
  ) async {
    final repository = _Phase67Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _TestAuthController(paired: false),
          ),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: DateNightsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Date nights are shared'), findsOneWidget);
    expect(repository.dateNightLoads, 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _TestAuthController(paired: false),
          ),
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: SharedGoalsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shared goals are for both of you'), findsOneWidget);
    expect(repository.goalLoads, 0);
  });

  testWidgets(
    'paired date night and goal pages load their remote empty states',
    (tester) async {
      final repository = _Phase67Repository();
      final overrides = [
        authControllerProvider.overrideWith(
          () => _TestAuthController(paired: true),
        ),
        authRepositoryProvider.overrideWithValue(repository),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(home: Scaffold(body: DateNightsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Start with one idea you would enjoy together.'),
        findsOneWidget,
      );
      expect(repository.dateNightLoads, 1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(home: Scaffold(body: SharedGoalsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('A shared goal can start with one small step.'),
        findsOneWidget,
      );
      expect(repository.goalLoads, 1);
    },
  );

  test(
    'stale date-night and goal edits reload current data and report conflict',
    () async {
      final repository = _Phase67Repository()
        ..conflictDateNightUpdate = true
        ..conflictGoalUpdate = true
        ..conflictMilestoneUpdate = true;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _TestAuthController(paired: true),
          ),
          authRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final dateNights = container.read(dateNightsControllerProvider.notifier);
      await dateNights.load('couple-a');
      final dateSaved = await dateNights.save(
        {'title': 'Edited title'},
        id: 'idea-1',
        expectedRevision: 1,
      );
      expect(dateSaved, isFalse);
      expect(repository.dateNightLoads, 2);
      expect(
        container.read(dateNightsControllerProvider).error,
        contains('changed elsewhere'),
      );

      final goals = container.read(sharedGoalsControllerProvider.notifier);
      await goals.load('couple-a');
      final goalSaved = await goals.saveGoal(
        {'title': 'Edited goal'},
        id: 'goal-1',
        expectedRevision: 1,
      );
      expect(goalSaved, isFalse);
      expect(repository.goalLoads, 2);
      expect(
        container.read(sharedGoalsControllerProvider).error,
        contains('changed elsewhere'),
      );

      final milestoneSaved = await goals.saveMilestone(
        'goal-1',
        {'title': 'Edited milestone'},
        id: 'milestone-1',
        expectedRevision: 1,
      );
      expect(milestoneSaved, isFalse);
      expect(repository.goalLoads, 3);
      expect(
        container.read(sharedGoalsControllerProvider).error,
        contains('changed elsewhere'),
      );
    },
  );
}

class _TestAuthController extends AuthController {
  _TestAuthController({required this.paired});
  final bool paired;
  @override
  AuthViewState build() => AuthViewState(
    AuthPhase.authenticated,
    context: AccountContext(
      userId: 'user-a',
      spaces: paired
          ? const [SpaceContext(id: 'couple-a', state: 'paired', epoch: 1)]
          : const [],
    ),
  );
}

class _Phase67Repository
    implements AuthRepository, DateNightRepository, SharedGoalsRepository {
  int dateNightLoads = 0;
  int goalLoads = 0;
  bool conflictDateNightUpdate = false;
  bool conflictGoalUpdate = false;
  bool conflictMilestoneUpdate = false;
  @override
  Stream<AuthSignal> get changes => const Stream<AuthSignal>.empty();
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<AccountContext> accountContext() async =>
      const AccountContext(userId: 'user-a', spaces: []);
  @override
  Future<void> clearLocalSession() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<DateNightSnapshot> loadDateNights(String coupleId) async {
    dateNightLoads++;
    return const DateNightSnapshot([], []);
  }

  @override
  Future<void> saveDateNight(
    String coupleId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) async {
    if (conflictDateNightUpdate && id != null) {
      throw const DateNightRevisionConflict();
    }
  }

  @override
  Future<void> saveDateNightVote(
    String coupleId,
    String ideaId,
    String response,
  ) async {}
  @override
  Future<SharedGoalsSnapshot> loadSharedGoals(String coupleId) async {
    goalLoads++;
    return const SharedGoalsSnapshot([]);
  }

  @override
  Future<void> saveSharedGoal(
    String coupleId,
    Map<String, dynamic> values, {
    String? id,
    int? expectedRevision,
  }) async {
    if (conflictGoalUpdate && id != null) {
      throw const SharedGoalRevisionConflict();
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
    if (conflictMilestoneUpdate && id != null) {
      throw const SharedGoalRevisionConflict();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
