import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/ai_workflow.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/services/ai_workflow_service.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/token_storage.dart';
import 'package:mobile/utils/format.dart';
import 'support/fake_photos.dart';

/// An AI plan now has a Trip behind it (created by the API, status follows the
/// operator's decision). These tests cover the optional start date and the
/// "Your trip" link on the plan screen.

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
  String? tripId,
  String goal = 'Beach and culture on the south coast',
  String approval = 'NotRequired',
  String overall = 'PASS',
  int days = 3,
  num budget = 150000,
}) =>
    {
      'id': id,
      'tripId': tripId,
      'travelerId': 'u1',
      'travelerName': 'Sam Traveler',
      'goal': goal,
      'days': days,
      'budget': budget,
      'interests': ['beach'],
      'finalPlan': 'Day 1: Galle Fort',
      'overallStatus': overall,
      'requiresApproval': approval != 'NotRequired',
      'approvalStatus': approval,
      'createdAt': '2026-10-21T09:00:00Z',
      'steps': <Map<String, dynamic>>[],
    };

Map<String, dynamic> _trip(String id, String status,
        {String title = 'Beach and culture on the south coast'}) =>
    {
      'id': id,
      'title': title,
      'startDate': '2026-10-22T00:00:00Z',
      'endDate': '2026-10-24T00:00:00Z',
      'budget': 150000,
      'status': status,
      'travelerName': 'Sam Traveler',
    };

void main() {
  group('AiWorkflow.tripId', () {
    test('is read from the response', () {
      expect(AiWorkflow.fromJson(_wf('w1', tripId: 't1')).tripId, 't1');
    });

    test('is null for plans made before trips were linked', () {
      expect(AiWorkflow.fromJson(_wf('w1')).tripId, isNull);
    });
  });

  group('AiWorkflowService.start startDate', () {
    Future<Map<String, dynamic>> sentBody({DateTime? startDate}) async {
      late http.Request seen;
      final api = ApiClient(
          httpClient: MockClient((req) async {
            seen = req;
            return _json(_wf('w1', tripId: 't1'), 201);
          }),
          baseUrl: 'http://test');
      await AiWorkflowService(api).start(
        goal: 'g',
        days: 2,
        budget: 1000,
        interests: const ['beach'],
        startDate: startDate,
      );
      return jsonDecode(seen.body) as Map<String, dynamic>;
    }

    test('sends a date-only string when a date is picked', () async {
      final body = await sentBody(startDate: DateTime(2026, 11, 5));
      expect(body['startDate'], '2026-11-05');
    });

    test('leaves the key out when no date is picked', () async {
      final body = await sentBody();
      expect(body.containsKey('startDate'), isFalse);
    });
  });

  group('picked dates', () {
    test('formatPickedDate shows the day the user picked', () {
      expect(formatPickedDate(DateTime(2026, 11, 1)), '1 Nov 2026');
      expect(formatPickedDate(DateTime(2026, 12, 31)), '31 Dec 2026');
    });

    testWidgets('the create-trip form shows the picked day, not the day before',
        (tester) async {
      final api = ApiClient(
          httpClient: MockClient((req) async => _json(<dynamic>[], 200)),
          baseUrl: 'http://test');
      await tester
          .pumpWidget(CeyloraApp(
          api: api,
          store: _MemoryStore(_session()),
          photoStore: FakeTripPhotoStore(),
          photoPicker: FakePhotoPicker(),
        ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New trip'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the picker opens on today
      await tester.pumpAndSettle();

      expect(find.text(formatPickedDate(DateTime.now())), findsWidgets);
    });
  });

  group('AI plan to trip UI', () {
    late List<Map<String, dynamic>> workflows;
    late List<Map<String, dynamic>> trips;
    late List<http.Request> log;

    setUp(() {
      workflows = [];
      trips = [];
      log = [];
    });

    MockClient backend() => MockClient((req) async {
          log.add(req);
          final path = req.url.path;
          if (req.method == 'GET' && path == '/api/trips/mine') {
            return _json(trips, 200);
          }
          if (req.method == 'GET' && path == '/api/ai/workflows/mine') {
            return _json(workflows, 200);
          }
          if (req.method == 'GET' && path.startsWith('/api/ai/workflows/')) {
            final id = path.split('/').last;
            final row = workflows.where((w) => w['id'] == id);
            return row.isEmpty ? _json({}, 404) : _json(row.first, 200);
          }
          if (req.method == 'POST' && path == '/api/ai/workflows') {
            // Mirrors the API: a plan that needs approval creates a Submitted trip.
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final trip = _trip('t${trips.length + 1}', 'Submitted',
                title: body['goal'] as String);
            trips.add(trip);
            final created = _wf('w${workflows.length + 1}',
                tripId: trip['id'] as String,
                goal: body['goal'] as String,
                approval: 'AwaitingApproval');
            workflows.add(created);
            return _json(created, 201);
          }
          return _json({}, 404);
        });

    Future<void> pumpSignedIn(WidgetTester tester) async {
      final api = ApiClient(httpClient: backend(), baseUrl: 'http://test');
      await tester
          .pumpWidget(CeyloraApp(
          api: api,
          store: _MemoryStore(_session()),
          photoStore: FakeTripPhotoStore(),
          photoPicker: FakePhotoPicker(),
        ));
      await tester.pumpAndSettle();
    }

    Future<void> openPlans(WidgetTester tester) async {
      await tester.tap(find.text('AI plans').last);
      await tester.pumpAndSettle();
    }

    Future<void> openNewPlanForm(WidgetTester tester) async {
      await openPlans(tester);
      await tester.tap(find.text('Plan with AI'));
      await tester.pumpAndSettle();
      await tester.enterText(find.bySemanticsLabel('Trip goal'), 'Hill country');
      await tester.enterText(find.bySemanticsLabel('Days'), '4');
      await tester.enterText(find.bySemanticsLabel('Budget'), '90000');
    }

    int tripLoads() => log
        .where((r) => r.method == 'GET' && r.url.path == '/api/trips/mine')
        .length;

    Future<void> unmount(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox()); // cancels any poll timer

    testWidgets('the start date is optional and defaults to tomorrow',
        (tester) async {
      await pumpSignedIn(tester);
      await openNewPlanForm(tester);

      expect(find.text('Start date (optional)'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);

      await tester.ensureVisible(find.text('Create plan'));
      await tester.tap(find.text('Create plan'));
      await tester.pumpAndSettle();

      final post = log.singleWhere((r) => r.method == 'POST');
      expect(
          (jsonDecode(post.body) as Map<String, dynamic>)
              .containsKey('startDate'),
          isFalse);
      await unmount(tester);
    });

    testWidgets('a picked start date is sent, and can be cleared',
        (tester) async {
      await pumpSignedIn(tester);
      await openNewPlanForm(tester);

      await tester.ensureVisible(find.text('Tomorrow'));
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the picker opens on tomorrow
      await tester.pumpAndSettle();

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(find.text(formatPickedDate(tomorrow)), findsOneWidget);
      expect(find.text('Tomorrow'), findsNothing);

      await tester.tap(find.byTooltip('Clear start date'));
      await tester.pump();
      expect(find.text('Tomorrow'), findsOneWidget);

      // Pick again and submit it.
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create plan'));
      await tester.tap(find.text('Create plan'));
      await tester.pumpAndSettle();

      final post = log.singleWhere((r) => r.method == 'POST');
      expect((jsonDecode(post.body) as Map<String, dynamic>)['startDate'],
          toApiDate(tomorrow));
      await unmount(tester);
    });

    testWidgets('planning creates a trip: My trips reloads and the plan links it',
        (tester) async {
      await pumpSignedIn(tester);
      final loadsBefore = tripLoads();
      await openNewPlanForm(tester);
      await tester.ensureVisible(find.text('Create plan'));
      await tester.tap(find.text('Create plan'));
      await tester.pumpAndSettle();

      expect(tripLoads(), greaterThan(loadsBefore));
      expect(find.text('Your trip'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget); // the trip's status

      await tester.tap(find.text('Your trip'));
      await tester.pumpAndSettle();
      expect(find.text('Trip details'), findsOneWidget);
      expect(find.text('Hill country'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('an operator decision updates the linked trip on screen',
        (tester) async {
      trips = [_trip('t1', 'Submitted')];
      workflows = [
        _wf('w1', tripId: 't1', approval: 'AwaitingApproval'),
      ];
      await pumpSignedIn(tester);
      await openPlans(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();
      expect(find.text('Your trip'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      final loadsBefore = tripLoads();

      // The operator approves: the API confirms the trip as well.
      workflows[0] = {...workflows[0], 'approvalStatus': 'Approved'};
      trips[0] = {...trips[0], 'status': 'Confirmed'};
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('An operator approved this plan.'), findsOneWidget);
      expect(tripLoads(), greaterThan(loadsBefore));
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Submitted'), findsNothing);
      await unmount(tester);
    });

    testWidgets('a rejected decision shows the trip as cancelled',
        (tester) async {
      trips = [_trip('t1', 'Submitted')];
      workflows = [_wf('w1', tripId: 't1', approval: 'AwaitingApproval')];
      await pumpSignedIn(tester);
      await openPlans(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();

      workflows[0] = {...workflows[0], 'approvalStatus': 'Rejected'};
      trips[0] = {...trips[0], 'status': 'Cancelled'};
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('Cancelled'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a plan without a trip shows no trip card', (tester) async {
      workflows = [_wf('w1')];
      await pumpSignedIn(tester);
      await openPlans(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();

      expect(find.text('Your trip'), findsNothing);
      await unmount(tester);
    });

    testWidgets('opening a trip My trips cannot find explains instead of failing',
        (tester) async {
      // The plan points at a trip that is not in the traveler's list.
      workflows = [_wf('w1', tripId: 'missing', approval: 'AwaitingApproval')];
      await pumpSignedIn(tester);
      await openPlans(tester);
      await tester.tap(find.text('Beach and culture on the south coast'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Your trip'));
      await tester.pumpAndSettle();

      expect(find.text('Could not open the trip. Try again from My trips.'),
          findsOneWidget);
      expect(find.text('Trip details'), findsNothing);
      await unmount(tester);
    });
  });
}
