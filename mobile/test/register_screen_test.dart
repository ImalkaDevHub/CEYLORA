import 'package:flutter/material.dart' show FilledButton;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/screens/register_screen.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/token_storage.dart';

import 'support/fake_photos.dart';
import 'support/stays_backend.dart';

class _MemoryStore implements SessionStore {
  AuthSession? saved;
  @override
  Future<AuthSession?> read() async => saved;
  @override
  Future<void> write(AuthSession session) async => saved = session;
  @override
  Future<void> clear() async => saved = null;
}

void main() {
  group('passwordProblem (the API rule: 8-72 characters, a letter and a number)', () {
    test('accepts good passwords, including the limits', () {
      expect(passwordProblem('abcdefg1'), isNull);
      expect(passwordProblem('Passw0rd-Test'), isNull);
      expect(passwordProblem('${'a' * 71}1'), isNull); // 72
    });

    test('refuses short and long passwords', () {
      expect(passwordProblem(null), 'Use 8 to 72 characters');
      expect(passwordProblem(''), 'Use 8 to 72 characters');
      expect(passwordProblem('abc1234'), 'Use 8 to 72 characters'); // 7
      expect(passwordProblem('${'a' * 72}1'), 'Use 8 to 72 characters'); // 73
    });

    test('needs both a letter and a number', () {
      expect(passwordProblem('allletters'), 'Include at least one letter and one number');
      expect(passwordProblem('12345678'), 'Include at least one letter and one number');
      expect(passwordProblem('--------'), 'Include at least one letter and one number');
    });
  });

  group('register screen', () {
    late List<Object> requests;

    Future<void> openRegister(WidgetTester tester) async {
      requests = [];
      final client = MockClient((req) async {
        requests.add(req);
        return json({'message': 'unexpected'}, 500);
      });
      await tester.pumpWidget(CeyloraApp(
        api: ApiClient(httpClient: client, baseUrl: 'http://test'),
        store: _MemoryStore(),
        photoStore: FakeTripPhotoStore(),
        photoPicker: FakePhotoPicker(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New traveler? Create an account'));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, {String name = 'Sam Traveler', String email = 'sam@example.com', String password = 'Passw0rd-Test'}) async {
      await tester.enterText(find.bySemanticsLabel('Full name'), name);
      await tester.enterText(find.bySemanticsLabel('Email'), email);
      await tester.enterText(find.bySemanticsLabel('Password'), password);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create account'));
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
    }

    testWidgets('blocks a weak password before calling the API', (tester) async {
      await openRegister(tester);

      await fill(tester, password: 'secret1'); // 7 characters

      expect(find.text('Use 8 to 72 characters'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('asks for a letter and a number', (tester) async {
      await openRegister(tester);

      await fill(tester, password: 'onlyletters');

      expect(find.text('Include at least one letter and one number'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('blocks an empty form with a message per field', (tester) async {
      await openRegister(tester);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Create account'));
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();

      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Use 8 to 72 characters'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('sends a valid form to the API', (tester) async {
      await openRegister(tester);

      await fill(tester);
      await tester.pump();

      expect(requests, hasLength(1));
    });
  });
}
