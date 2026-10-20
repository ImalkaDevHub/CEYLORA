import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/ai_workflow.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/providers/ai_workflows_provider.dart';
import 'package:mobile/providers/trips_provider.dart' show LoadState;
import 'package:mobile/services/ai_workflow_service.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/token_storage.dart';
import 'package:provider/provider.dart';
import 'support/fake_photos.dart';

class _MemoryStore implements SessionStore {
  AuthSession? saved;
  _MemoryStore([this.saved]);
  @override
  Future<AuthSession?> read() async => saved;
  @override
  Future<void> write(AuthSession session) async => saved = session;
  @override
  Future<void> clear() async => saved = null;
}

AuthSession _session() => AuthSession(
      token: 'jwt-token',
      email: 'sam@example.com',
      fullName: 'Sam Traveler',
      role: 'Traveler',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _wf(
  String id, {
  String goal = 'Beach and culture on the south coast',
  int days = 3,
  num budget = 150000,
  List<String> interests = const ['beach', 'culture'],
  String? finalPlan = 'Day 1: Galle Fort\nDay 2: Mirissa\nDay 3: Unawatuna',
  String overall = 'PASS',
  String approval = 'NotRequired',
  String created = '2026-10-20T08:00:00Z',
  List<Map<String, dynamic>>? steps,
}) =>
    {
      'id': id,
      'tripId': null,
      'travelerId': 'u1',
      'travelerName': 'Sam Traveler',
      'goal': goal,
      'days': days,
      'budget': budget,
      'interests': interests,
      'finalPlan': finalPlan,
      'overallStatus': overall,
      'requiresApproval': approval != 'NotRequired',
      'approvalStatus': approval,
      'approvedByUserId': null,
      'approvedAt': null,
      'createdAt': created,
      'completedAt': null,
      'steps': steps ??
          [
            {
              'id': 's1',
              'agentName': 'planner',
              'status': 'completed',
              'startedAt': created,
              'outputSummary': 'Drafted a 3-day itinerary',
            },
            {
              'id': 's2',
              'agentName': 'destination',
              'status': 'completed',
              'startedAt': created,
              'outputSummary': 'Matched 3 destinations',
            },
            {
              'id': 's3',
              'agentName': 'validation_safety',
              'status': 'error',
              'startedAt': created,
              'errorMessage': 'Safety check timed out',
            },
          ],
    };

AiWorkflowService _service(MockClient client,
    {Duration? startTimeout, String baseUrl = 'http://test'}) {
  final api = ApiClient(httpClient: client, baseUrl: baseUrl);
  api.setToken('jwt-token');
  return startTimeout == null
      ? AiWorkflowService(api)
      : AiWorkflowService(api, startTimeout: startTimeout);
}

AiWorkflowsProvider _provider(MockClient client) =>
    AiWorkflowsProvider(_service(client));

void main() {
  group('AiOutcome', () {
    test('maps every approval/validation combination', () {
      AiOutcome of(String approval, String overall) =>
          AiOutcome.from(approvalStatus: approval, overallStatus: overall);

      expect(of('NotRequired', 'PASS'), AiOutcome.ready);
      expect(of('NotRequired', 'NEEDS_REVISION'), AiOutcome.flagged);
      expect(of('NotRequired', 'Pending'), AiOutcome.flagged);
      for (final overall in ['PASS', 'NEEDS_REVISION', 'Pending']) {
        expect(of('AwaitingApproval', overall), AiOutcome.awaitingApproval);
        expect(of('Approved', overall), AiOutcome.approved);
        expect(of('Rejected', overall), AiOutcome.rejected);
        expect(of('RevisionRequested', overall), AiOutcome.revisionRequested);
      }
    });

    test('only unresolved or declined plans can be planned again', () {
      expect(AiOutcome.rejected.canPlanAgain, isTrue);
      expect(AiOutcome.revisionRequested.canPlanAgain, isTrue);
      expect(AiOutcome.flagged.canPlanAgain, isTrue);
      expect(AiOutcome.ready.canPlanAgain, isFalse);
      expect(AiOutcome.approved.canPlanAgain, isFalse);
      expect(AiOutcome.awaitingApproval.canPlanAgain, isFalse);
    });

    test('agent and interest labels are friendly', () {
      expect(agentLabel('planner'), 'Planner');
      expect(agentLabel('destination'), 'Destination research');
      expect(agentLabel('budget_availability'), 'Budget & availability');
      expect(agentLabel('validation_safety'), 'Validation & safety');
      expect(agentLabel('some_new_agent'), 'some new agent');
      expect(interestLabel('citylife'), 'City life');
      expect(aiInterests, contains('wildlife'));
    });
  });

  group('AiWorkflowService', () {
    test('start posts the request body and parses the workflow', () async {
      late http.Request seen;
      final service = _service(MockClient((req) async {
        seen = req;
        return _json(_wf('w1'), 201);
      }));

      final wf = await service.start(
        goal: 'Beach trip',
        days: 4,
        budget: 120000,
        interests: ['beach', 'nature'],
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/ai/workflows');
      expect(seen.headers['Authorization'], 'Bearer jwt-token');
      expect(jsonDecode(seen.body), {
        'goal': 'Beach trip',
        'days': 4,
        'budget': 120000,
        'interests': ['beach', 'nature'],
      });
      expect(wf.id, 'w1');
      expect(wf.steps, hasLength(3));
      expect(wf.steps.last.succeeded, isFalse);
      expect(wf.steps.last.detail, 'Safety check timed out');
      expect(wf.steps.first.detail, 'Drafted a 3-day itinerary');
    });

    test('start allows 60s, longer than the default request timeout', () {
      expect(AiWorkflowService.defaultStartTimeout, const Duration(seconds: 60));
      expect(AiWorkflowService.defaultStartTimeout,
          greaterThan(ApiClient.defaultTimeout));
    });

    test('start uses its own timeout instead of the default', () async {
      final service = _service(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _json(_wf('w1'), 201);
        }),
        startTimeout: const Duration(milliseconds: 40),
      );

      await expectLater(
        service.start(goal: 'x', days: 1, budget: 0, interests: const []),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'The server took too long to respond.')),
      );
    });

    test('start maps any 5xx to the friendly planner message', () async {
      for (final status in [500, 502, 503]) {
        final service = _service(
            MockClient((_) async => _json({'message': 'boom'}, status)));
        await expectLater(
          service.start(goal: 'x', days: 1, budget: 0, interests: const []),
          throwsA(isA<ApiException>()
              .having((e) => e.message, 'message',
                  'The AI planner is unavailable right now. Please try again in a moment.')
              .having((e) => e.statusCode, 'status', status)),
        );
      }
    });

    test('start keeps the server message for 4xx errors', () async {
      final service = _service(MockClient(
          (_) async => _json({'message': 'Days must be between 1 and 60.'}, 400)));

      await expectLater(
        service.start(goal: 'x', days: 99, budget: 0, interests: const []),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'Days must be between 1 and 60.')),
      );
    });

    test('malformed bodies become a clean error', () async {
      final notAMap = _service(MockClient((_) async => _json([1, 2], 200)));
      await expectLater(
        notAMap.start(goal: 'x', days: 1, budget: 0, interests: const []),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('unexpected response'))),
      );

      final notAList = _service(MockClient((_) async => _json({'x': 1}, 200)));
      await expectLater(notAList.mine(), throwsA(isA<ApiException>()));

      final badDate = _service(MockClient(
          (_) async => _json(_wf('w1', created: 'not-a-date'), 200)));
      await expectLater(badDate.get('w1'), throwsA(isA<ApiException>()));

      final missingField = _service(MockClient((_) async {
        final body = _wf('w1')..remove('goal');
        return _json(body, 200);
      }));
      await expectLater(missingField.get('w1'), throwsA(isA<ApiException>()));
    });

    test('mine and get hit the right paths', () async {
      final paths = <String>[];
      final service = _service(MockClient((req) async {
        paths.add(req.url.path);
        return req.url.path.endsWith('/mine')
            ? _json([_wf('w1')], 200)
            : _json(_wf('w9'), 200);
      }));

      expect(await service.mine(), hasLength(1));
      expect((await service.get('w9')).id, 'w9');
      expect(paths, ['/api/ai/workflows/mine', '/api/ai/workflows/w9']);
    });
  });

  group('AiWorkflowsProvider', () {
    test('load keeps the newest plan first', () async {
      final provider = _provider(MockClient((_) async => _json([
            _wf('old', created: '2026-10-01T00:00:00Z'),
            _wf('new', created: '2026-10-18T00:00:00Z'),
            _wf('mid', created: '2026-10-10T00:00:00Z'),
          ], 200)));

      await provider.load();

      expect(provider.state, LoadState.loaded);
      expect(provider.items.map((w) => w.id), ['new', 'mid', 'old']);
    });

    test('load failure keeps the message and failed state', () async {
      final provider = _provider(MockClient((_) async => _json({}, 403)));

      await provider.load();

      expect(provider.state, LoadState.failed);
      expect(provider.error, "You don't have permission to do that.");
    });

    test('start prepends the new plan and returns it', () async {
      var call = 0;
      final provider = _provider(MockClient((req) async {
        call++;
        if (call == 1) {
          return _json([_wf('a', created: '2026-10-01T00:00:00Z')], 200);
        }
        return _json(_wf('b', created: '2026-10-20T00:00:00Z'), 201);
      }));
      await provider.load();

      final (wf, error) = await provider
          .start(goal: 'x', days: 2, budget: 1, interests: const []);

      expect(error, isNull);
      expect(wf!.id, 'b');
      expect(provider.items.map((w) => w.id), ['b', 'a']);
      expect(provider.starting, isFalse);
    });

    test('start returns the friendly error and keeps the list', () async {
      final provider = _provider(MockClient((_) async => _json({}, 500)));

      final (wf, error) = await provider
          .start(goal: 'x', days: 2, budget: 1, interests: const []);

      expect(wf, isNull);
      expect(error, AiWorkflowService.unavailableMessage);
      expect(provider.items, isEmpty);
      expect(provider.starting, isFalse);
    });

    test('a second start while one is running is ignored', () async {
      final gate = Completer<http.Response>();
      var posts = 0;
      final provider = _provider(MockClient((req) {
        posts++;
        return gate.future;
      }));

      final first = provider
          .start(goal: 'x', days: 2, budget: 1, interests: const []);
      expect(provider.starting, isTrue);
      final second = await provider
          .start(goal: 'x', days: 2, budget: 1, interests: const []);

      expect(second, (null, null));
      await Future<void>.delayed(Duration.zero); // let the request reach the mock
      expect(posts, 1);

      gate.complete(_json(_wf('a'), 201));
      final (wf, error) = await first;
      expect(wf!.id, 'a');
      expect(error, isNull);
      expect(provider.starting, isFalse);
      expect(provider.items, hasLength(1));
    });

    test('refresh replaces the plan in place', () async {
      var call = 0;
      final provider = _provider(MockClient((req) async {
        call++;
        if (call == 1) {
          return _json([
            _wf('a', approval: 'AwaitingApproval', created: '2026-10-02T00:00:00Z'),
            _wf('b', created: '2026-10-01T00:00:00Z'),
          ], 200);
        }
        expect(req.url.path, '/api/ai/workflows/a');
        return _json(
            _wf('a', approval: 'Approved', created: '2026-10-02T00:00:00Z'), 200);
      }));
      await provider.load();
      expect(provider.byId('a')!.outcome, AiOutcome.awaitingApproval);

      final error = await provider.refresh('a');

      expect(error, isNull);
      expect(provider.byId('a')!.outcome, AiOutcome.approved);
      expect(provider.items.map((w) => w.id), ['a', 'b']);
    });

    test('refresh failure returns the message and keeps the old plan',
        () async {
      var call = 0;
      final provider = _provider(MockClient((_) async {
        call++;
        return call == 1 ? _json([_wf('a')], 200) : _json({}, 404);
      }));
      await provider.load();

      final error = await provider.refresh('a');

      expect(error, 'Not found.');
      expect(provider.byId('a'), isNotNull);
    });

    test('clear drops plans and ignores a response that lands afterwards',
        () async {
      final gate = Completer<http.Response>();
      var call = 0;
      final provider = _provider(MockClient((_) {
        call++;
        if (call == 1) return Future.value(_json([_wf('a')], 200));
        return gate.future;
      }));
      await provider.load();
      expect(provider.items, hasLength(1));

      final pending = provider.load();
      provider.clear();
      expect(provider.items, isEmpty);
      expect(provider.state, LoadState.idle);

      gate.complete(_json([_wf('leak')], 200));
      await pending;

      expect(provider.items, isEmpty);
      expect(provider.state, LoadState.idle);
    });
  });

  group('AI plans UI', () {
    /// In-memory stand-in for the /api/ai/workflows endpoints.
    late List<Map<String, dynamic>> db;
    late List<http.Request> log;
    // Lets a test hold or customise the POST response.
    late Future<http.Response> Function(http.Request) onCreate;
    late bool failList;

    setUp(() {
      failList = false;
      db = [];
      log = [];
      onCreate = (req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final created = _wf('w${db.length + 1}',
            goal: body['goal'] as String,
            days: body['days'] as int,
            budget: body['budget'] as num,
            interests: (body['interests'] as List).cast<String>(),
            created: '2026-10-21T09:00:00Z');
        db.add(created);
        return _json(created, 201);
      };
    });

    MockClient backend() => MockClient((req) async {
          log.add(req);
          final path = req.url.path;
          if (req.method == 'GET' && path == '/api/ai/workflows/mine') {
            if (failList) return _json({}, 500);
            final rows = [...db]..sort((a, b) =>
                (b['createdAt'] as String).compareTo(a['createdAt'] as String));
            return _json(rows, 200);
          }
          if (req.method == 'GET' && path.startsWith('/api/ai/workflows/')) {
            final id = path.split('/').last;
            final row = db.where((w) => w['id'] == id);
            return row.isEmpty ? _json({}, 404) : _json(row.first, 200);
          }
          if (req.method == 'POST' && path == '/api/ai/workflows') {
            return onCreate(req);
          }
          return _json({}, 404);
        });

    Future<void> pumpSignedIn(WidgetTester tester, [MockClient? client]) async {
      final api =
          ApiClient(httpClient: client ?? backend(), baseUrl: 'http://test');
      await tester
          .pumpWidget(CeyloraApp(
          api: api,
          store: _MemoryStore(_session()),
          photoStore: FakeTripPhotoStore(),
          photoPicker: FakePhotoPicker(),
        ));
      await tester.pumpAndSettle();
    }

    Future<void> openTab(WidgetTester tester) async {
      await tester.tap(find.text('AI plans').last);
      await tester.pumpAndSettle();
    }

    int detailGets(String id) => log
        .where((r) => r.method == 'GET' && r.url.path == '/api/ai/workflows/$id')
        .length;

    Future<void> unmount(WidgetTester tester) async {
      // Disposes screens so a pending poll timer cannot outlive the test.
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('lists the traveler\'s plans with outcome chips',
        (tester) async {
      db = [
        _wf('w1'),
        _wf('w2',
            goal: 'Hill country trek',
            days: 1,
            budget: 80000,
            approval: 'AwaitingApproval',
            created: '2026-10-19T08:00:00Z'),
      ];
      await pumpSignedIn(tester);

      await openTab(tester);

      expect(find.text('Beach and culture on the south coast'), findsOneWidget);
      expect(find.text('3 days · LKR 150,000'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Created 20 Oct 2026'), findsOneWidget);
      expect(find.text('Hill country trek'), findsOneWidget);
      expect(find.text('1 day · LKR 80,000'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsOneWidget);
      // Newest first.
      expect(
          tester.getTopLeft(find.text('Beach and culture on the south coast')).dy,
          lessThan(tester.getTopLeft(find.text('Hill country trek')).dy));
      expect(find.text('Plan with AI'), findsOneWidget);
    });

    testWidgets('shows the empty state', (tester) async {
      await pumpSignedIn(tester);

      await openTab(tester);

      expect(find.textContaining('No AI plans yet'), findsOneWidget);
    });

    testWidgets('shows an error with retry, and retry recovers',
        (tester) async {
      failList = true;
      await pumpSignedIn(tester);
      db = [_wf('w1')];

      await openTab(tester);
      expect(find.text('Something went wrong on the server.'), findsOneWidget);

      failList = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Beach and culture on the south coast'), findsOneWidget);
    });

    testWidgets('form blocks empty and out-of-range input', (tester) async {
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Plan with AI'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create plan'));
      await tester.tap(find.text('Create plan'));
      await tester.pump();

      expect(find.text('Describe what you want from this trip'), findsOneWidget);
      expect(find.text('Enter the number of days'), findsOneWidget);
      expect(find.text('Enter your budget'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Days'), '61');
      await tester.enterText(find.bySemanticsLabel('Budget'), '-5');
      await tester.tap(find.text('Create plan'));
      await tester.pump();
      expect(find.text('Between 1 and 60 days'), findsOneWidget);
      expect(find.text('Budget cannot be negative'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Days'), '0');
      await tester.enterText(find.bySemanticsLabel('Budget'), 'NaN');
      await tester.tap(find.text('Create plan'));
      await tester.pump();
      expect(find.text('Between 1 and 60 days'), findsOneWidget);
      expect(find.text('Enter your budget'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Days'), '2.5');
      await tester.tap(find.text('Create plan'));
      await tester.pump();
      expect(find.text('Enter the number of days'), findsOneWidget);

      expect(log.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('plans a trip, blocks double taps, then shows the detail',
        (tester) async {
      final gate = Completer<http.Response>();
      final standard = onCreate;
      onCreate = (req) async {
        final res = await gate.future;
        // Same persistence as the default handler, once the gate opens.
        return res.statusCode == 200 ? standard(req) : res;
      };
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Plan with AI'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.bySemanticsLabel('Trip goal'), '  Wildlife safari  ');
      await tester.enterText(find.bySemanticsLabel('Days'), '5');
      await tester.enterText(find.bySemanticsLabel('Budget'), '250000');
      await tester.tap(find.text('Wildlife'));
      await tester.tap(find.text('Beach'));
      await tester.pump();
      await tester.ensureVisible(find.text('Create plan'));
      await tester.tap(find.text('Create plan'));
      await tester.pump();

      // Busy state: message shown, button disabled, only one request sent.
      expect(find.textContaining('Planning your trip... this can take up to 30 seconds'),
          findsOneWidget);
      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create plan'));
      expect(button.onPressed, isNull);
      await tester.tap(find.text('Create plan'), warnIfMissed: false);
      await tester.tap(find.text('Create plan'), warnIfMissed: false);
      await tester.pump();
      final posts = log.where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body), {
        'goal': 'Wildlife safari',
        'days': 5,
        'budget': 250000,
        'interests': ['beach', 'wildlife'],
      });

      gate.complete(http.Response('', 200));
      await tester.pumpAndSettle();

      // Replaced by the detail screen of the new plan.
      expect(find.text('New AI plan'), findsNothing);
      expect(find.text('AI plan'), findsOneWidget);
      expect(find.text('Your plan passed all checks and is ready.'),
          findsOneWidget);
      expect(find.text('Wildlife safari'), findsOneWidget);
      expect(find.text('5 days'), findsOneWidget);
      expect(find.text('LKR 250,000'), findsOneWidget);
      expect(find.text('Beach, Wildlife'), findsOneWidget);

      // Back on the list, the new plan is there.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Wildlife safari'), findsOneWidget);
      expect(find.text('5 days · LKR 250,000'), findsOneWidget);
    });

    testWidgets('a planner failure shows a banner and lets the user retry',
        (tester) async {
      onCreate = (_) async => _json({'message': 'internal'}, 500);
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Plan with AI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.bySemanticsLabel('Trip goal'), 'Anything');
      await tester.enterText(find.bySemanticsLabel('Days'), '2');
      await tester.enterText(find.bySemanticsLabel('Budget'), '0');
      await tester.ensureVisible(find.text('Create plan'));

      await tester.tap(find.text('Create plan'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'The AI planner is unavailable right now. Please try again in a moment.'),
          findsOneWidget);
      expect(find.textContaining('Planning your trip'), findsNothing);
      final button =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create plan'));
      expect(button.onPressed, isNotNull);
      // Entered values survive the failure.
      expect(find.text('Anything'), findsOneWidget);
    });

    testWidgets('detail shows the agent trail and the full plan',
        (tester) async {
      db = [_wf('w1')];
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();

      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Planner'), findsOneWidget);
      expect(find.text('Drafted a 3-day itinerary'), findsOneWidget);
      expect(find.text('Destination research'), findsOneWidget);
      expect(find.text('Validation & safety'), findsOneWidget);
      expect(find.text('Safety check timed out'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
      expect(find.byIcon(Icons.error), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(SelectableText), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('Day 2: Mirissa'), findsOneWidget);
      // A good plan has no "plan again" button.
      expect(find.text('Plan again'), findsNothing);
    });

    testWidgets('an awaiting plan polls every 10s and flips to Approved',
        (tester) async {
      db = [_wf('w1', approval: 'AwaitingApproval', overall: 'NEEDS_REVISION')];
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('An operator is reviewing this plan'),
          findsOneWidget);
      expect(find.text('Plan again'), findsNothing);
      expect(detailGets('w1'), 0);

      await tester.pump(const Duration(seconds: 9));
      expect(detailGets('w1'), 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(detailGets('w1'), 1);
      expect(find.text('Awaiting approval'), findsWidgets);

      // The operator approves; the next tick picks it up.
      db[0] = {...db[0], 'approvalStatus': 'Approved'};
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(detailGets('w1'), 2);
      expect(find.text('An operator approved this plan.'), findsOneWidget);
      expect(find.textContaining('An operator is reviewing'), findsNothing);

      // Polling stops once the status has changed.
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(detailGets('w1'), 2);
      await unmount(tester);
    });

    testWidgets('a finished plan is never polled', (tester) async {
      db = [_wf('w1')];
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 35));

      expect(detailGets('w1'), 0);
      await unmount(tester);
    });

    testWidgets('leaving the detail screen stops the poll', (tester) async {
      db = [_wf('w1', approval: 'AwaitingApproval')];
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(detailGets('w1'), 1);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));

      expect(detailGets('w1'), 1);
      await unmount(tester);
    });

    testWidgets('pull to refresh re-reads the plan', (tester) async {
      db = [_wf('w1', approval: 'AwaitingApproval')];
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();
      db[0] = {...db[0], 'approvalStatus': 'Rejected'};

      await tester.fling(find.byType(ListView).last, const Offset(0, 400), 1000);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('An operator rejected this plan.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Plan again'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Plan again'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('plan again prefills the form from a rejected plan',
        (tester) async {
      db = [
        _wf('w1',
            goal: 'Surf and temples',
            days: 7,
            budget: 320000.5,
            interests: ['beach', 'culture'],
            approval: 'Rejected'),
      ];
      await pumpSignedIn(tester);
      await openTab(tester);
      await tester.tap(find.text('Surf and temples'));
      await tester.pumpAndSettle();
      expect(find.text('Rejected'), findsWidgets);

      await tester.scrollUntilVisible(find.text('Plan again'), 200,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Plan again'));
      await tester.pumpAndSettle();

      String text(int i) => tester
          .widget<TextFormField>(find.byType(TextFormField).at(i))
          .controller!
          .text;
      expect(find.text('New AI plan'), findsOneWidget);
      expect(text(0), 'Surf and temples');
      expect(text(1), '7');
      expect(text(2), '320000.5');
      bool selected(String label) =>
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;
      expect(selected('Beach'), isTrue);
      expect(selected('Culture'), isTrue);
      expect(selected('Nature'), isFalse);
    });

    testWidgets('plan again is offered for revisions and flagged plans',
        (tester) async {
      db = [
        _wf('rev', goal: 'Revise me', approval: 'RevisionRequested',
            created: '2026-10-19T00:00:00Z'),
        _wf('flag', goal: 'Flagged one', overall: 'NEEDS_REVISION'),
      ];
      await pumpSignedIn(tester);
      await openTab(tester);

      await tester.tap(find.text('Flagged one'));
      await tester.pumpAndSettle();
      expect(find.text('Needs changes'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Plan again'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Plan again'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Revise me'));
      await tester.pumpAndSettle();
      expect(find.text('Revision requested'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Plan again'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('Plan again'), findsOneWidget);
    });

    testWidgets('signing out clears plans for the next user', (tester) async {
      db = [_wf('w1')];
      await pumpSignedIn(tester);
      await openTab(tester);
      expect(find.text('Beach and culture on the south coast'), findsOneWidget);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      final provider = tester
          .element(find.byType(Scaffold).first)
          .read<AiWorkflowsProvider>();
      expect(provider.items, isEmpty);
      expect(provider.state, LoadState.idle);
    });
  });
}
