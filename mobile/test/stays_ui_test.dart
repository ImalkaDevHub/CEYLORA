import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/providers/accommodations_provider.dart';
import 'package:mobile/providers/bookings_provider.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/token_storage.dart';
import 'package:mobile/utils/format.dart';
import 'package:provider/provider.dart';

import 'support/fake_photos.dart';
import 'support/stays_backend.dart';

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

DateTime _today() => DateUtils.dateOnly(DateTime.now());
DateTime _inDays(int n) => _today().add(Duration(days: n));

void main() {
  late StaysBackend backend;

  setUp(() => backend = StaysBackend());

  Future<void> pumpApp(WidgetTester tester) async {
    final api = ApiClient(httpClient: backend.client, baseUrl: 'http://test');
    await tester.pumpWidget(CeyloraApp(
      api: api,
      store: _MemoryStore(_session()),
      photoStore: FakeTripPhotoStore(),
      photoPicker: FakePhotoPicker(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pumpAndSettle();
  }

  Future<void> openStays(WidgetTester tester) async {
    await pumpApp(tester);
    await openTab(tester, 'Stays');
  }

  Future<void> openStay(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openBookScreen(WidgetTester tester, {String stay = 'Stay 01'}) async {
    await openStays(tester);
    await openStay(tester, stay);
    await tapVisible(tester, find.text('Book this stay'));
  }

  /// Picks check-in (the picker opens on tomorrow) and waits for the quote.
  Future<void> pickDates(WidgetTester tester) async {
    await tester.tap(find.text('Select').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  FilledButton confirmButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm booking'));

  group('Stays list', () {
    testWidgets('shows stays with type, rating and price per night', (tester) async {
      backend.stays = [
        stayJson(1, name: 'Sea View', rating: 4.5, reviews: 8, price: 20000),
        stayJson(2, name: 'Hill Villa', type: 'Villa', price: 35000),
      ];
      await openStays(tester);

      expect(find.text('Sea View'), findsOneWidget);
      expect(find.text('LKR 20,000 / night'), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(8)'), findsOneWidget);
      expect(find.text('No reviews yet'), findsOneWidget); // Hill Villa
      expect(find.text('Villa'), findsWidgets);
      expect(find.text('My bookings'), findsOneWidget);
    });

    testWidgets('the type chips filter the list', (tester) async {
      backend.stays = [
        stayJson(1, name: 'Sea View'),
        stayJson(2, name: 'Hill Villa', type: 'Villa'),
      ];
      await openStays(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Villa'));
      await tester.pumpAndSettle();

      expect(find.text('Hill Villa'), findsOneWidget);
      expect(find.text('Sea View'), findsNothing);
    });

    testWidgets('search waits for a typing pause, then filters', (tester) async {
      backend.stays = [stayJson(1, name: 'Sea View'), stayJson(2, name: 'Hill Villa')];
      await openStays(tester);
      final before = backend.requests('GET', '/api/accommodations').length;

      await tester.enterText(find.byType(TextField), 'hill');
      await tester.pump(const Duration(milliseconds: 200));
      expect(backend.requests('GET', '/api/accommodations').length, before);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Hill Villa'), findsOneWidget);
      expect(find.text('Sea View'), findsNothing);
    });

    testWidgets('sorting by price puts the cheapest first', (tester) async {
      backend.stays = [
        stayJson(1, name: 'Pricey', price: 50000),
        stayJson(2, name: 'Cheap', price: 4000),
      ];
      await openStays(tester);

      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: low to high'));
      await tester.pumpAndSettle();

      final cheap = tester.getTopLeft(find.text('Cheap')).dy;
      final pricey = tester.getTopLeft(find.text('Pricey')).dy;
      expect(cheap, lessThan(pricey));
    });

    testWidgets('shows a no-match message when the search finds nothing', (tester) async {
      await openStays(tester);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.text('No stays match your search.'), findsOneWidget);
    });

    testWidgets('shows an error with retry that recovers', (tester) async {
      backend.listFailure = 500;
      await openStays(tester);
      expect(find.text('Something went wrong on the server.'), findsOneWidget);

      backend.listFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Stay 01'), findsOneWidget);
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      backend.stays = [for (var i = 1; i <= 25; i++) stayJson(i)];
      await openStays(tester);

      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byKey(const Key('stays-list')), const Offset(0, -3000));
        await tester.pumpAndSettle();
      }

      final pages = backend
          .requests('GET', '/api/accommodations')
          .map((r) => r.url.queryParameters['page'])
          .toList();
      expect(pages, containsAll(['1', '2']));
    });
  });

  group('Stay detail and reviews', () {
    setUp(() {
      backend.stays = [
        stayJson(1,
            name: 'Sea View',
            rating: 4.5,
            reviews: 7,
            maxGuests: 3,
            description: 'Rooms facing the Indian Ocean'),
      ];
      backend.reviews['s1'] = [
        for (var i = 1; i <= 7; i++) reviewJson(i, comment: 'Comment $i', rating: 5)
      ];
    });

    testWidgets('shows the stay, its price and the first reviews', (tester) async {
      await openStays(tester);
      await openStay(tester, 'Sea View');

      expect(find.text('Rooms facing the Indian Ocean'), findsOneWidget);
      expect(find.text('LKR 20,000 per room per night'), findsOneWidget);
      expect(find.text('Sleeps up to 3 guests per room'), findsOneWidget);
      expect(find.text('Reviews (7)'), findsOneWidget);
      expect(find.text('Comment 1'), findsOneWidget);
    });

    testWidgets('"Show more reviews" loads the next page', (tester) async {
      await openStays(tester);
      await openStay(tester, 'Sea View');
      expect(find.text('Comment 6'), findsNothing);

      await tapVisible(tester, find.text('Show more reviews'));

      expect(find.text('Comment 6'), findsOneWidget);
      expect(find.text('Comment 7'), findsOneWidget);
      expect(find.text('Show more reviews'), findsNothing);
    });

    testWidgets('a stay with no reviews invites the first one', (tester) async {
      backend.reviews.clear();
      await openStays(tester);
      await openStay(tester, 'Sea View');

      expect(find.textContaining('No reviews yet. Stay here'), findsOneWidget);
    });

    testWidgets('the review dialog needs a rating, shows the API refusal, then saves',
        (tester) async {
      await openStays(tester);
      await openStay(tester, 'Sea View');
      await tapVisible(tester, find.text('Write a review'));
      expect(find.text('Review Sea View'), findsOneWidget);

      // No rating yet.
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(find.text('Choose a rating from 1 to 5 stars.'), findsOneWidget);

      // The stay has not ended: the API says so, right in the dialog.
      backend.reviewFailure = (403, 'You can review a place only after your stay there has ended.');
      await tester.tap(find.byTooltip('4 stars'));
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('You can review a place only after your stay there has ended.'),
          findsOneWidget);
      expect(find.text('Review Sea View'), findsOneWidget);

      // Now it has: the review is saved and shown.
      backend.reviewFailure = null;
      await tester.enterText(find.byType(TextField).last, 'Quiet and clean');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Review Sea View'), findsNothing);
      expect(find.text('Thanks for your review!'), findsOneWidget);
      expect(find.text('Quiet and clean'), findsOneWidget);
      expect(find.text('Reviews (8)'), findsOneWidget);
    });

    testWidgets('cancelling the review dialog sends nothing', (tester) async {
      await openStays(tester);
      await openStay(tester, 'Sea View');
      await tapVisible(tester, find.text('Write a review'));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(backend.requests('POST', '/api/accommodations/s1/reviews'), isEmpty);
    });
  });

  group('Booking a stay', () {
    testWidgets('pick dates, see the price, confirm and land on the booking', (tester) async {
      await openBookScreen(tester);
      expect(find.text('Pick your dates to see the price and availability.'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
      expect(find.text('South coast'), findsWidgets); // the trip is chosen

      await pickDates(tester);

      expect(find.text(formatPickedDate(_inDays(1))), findsOneWidget);
      expect(find.text(formatPickedDate(_inDays(2))), findsOneWidget);
      expect(find.text('1 night × 1 room × LKR 20,000'), findsOneWidget);
      expect(find.text('Total LKR 20,000'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNotNull);

      await tester.ensureVisible(find.text('Confirm booking'));
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();

      expect(find.text('Booking details'), findsOneWidget);
      expect(find.text('Booking confirmed.'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('For South coast'), findsOneWidget);
      expect(find.textContaining('1 room · 1 guest'), findsOneWidget);

      final post = backend.requests('POST', '/api/bookings').single;
      expect(post.body, contains('"tripId":"t1"'));
      expect(post.body, contains('"checkIn":"${apiDate(_inDays(1))}"'));
      expect(post.body, contains('"checkOut":"${apiDate(_inDays(2))}"'));
    });

    testWidgets('changing rooms refreshes the quote', (tester) async {
      await openBookScreen(tester);
      await pickDates(tester);

      await tester.tap(find.byTooltip('more rooms'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('1 night × 2 rooms × LKR 20,000'), findsOneWidget);
      expect(find.text('Total LKR 40,000'), findsOneWidget);
      final quotes = backend.requests('GET', '/api/accommodations/s1/quote');
      expect(quotes.last.url.queryParameters['rooms'], '2');
    });

    testWidgets('too many rooms: says how many are free and disables confirm', (tester) async {
      backend.freeRooms = 1;
      await openBookScreen(tester);
      await pickDates(tester);
      expect(confirmButton(tester).onPressed, isNotNull);

      await tester.tap(find.byTooltip('more rooms'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.textContaining('Only 1 room is free for the whole stay'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('a sold-out stay says so', (tester) async {
      backend.freeRooms = 0;
      await openBookScreen(tester);
      await pickDates(tester);

      expect(find.textContaining('Sold out for some of these nights'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('guests are limited by the rooms and shrink when rooms drop', (tester) async {
      backend.freeRooms = 5;
      await openBookScreen(tester); // sleeps 2 per room

      expect(find.text('Up to 2 for 1 room'), findsOneWidget);
      await tester.tap(find.byTooltip('more guests'));
      await tester.pump();
      var more = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_circle_outline).last);
      expect(more.onPressed, isNull); // 2 of 2

      await tester.tap(find.byTooltip('more rooms'));
      await tester.pump();
      expect(find.text('Up to 4 for 2 rooms'), findsOneWidget);
      await tester.tap(find.byTooltip('more guests'));
      await tester.tap(find.byTooltip('more guests'));
      await tester.pump();

      await tester.tap(find.byTooltip('fewer rooms'));
      await tester.pump();
      expect(find.text('Up to 2 for 1 room'), findsOneWidget);
      // Guests dropped from 4 to the new limit of 2, so one more tap is not possible.
      more = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_circle_outline).last);
      expect(more.onPressed, isNull);
    });

    testWidgets('rooms cannot go below one', (tester) async {
      await openBookScreen(tester);

      final fewer = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.remove_circle_outline).first);
      expect(fewer.onPressed, isNull);
    });

    testWidgets('a booking the API refuses shows its message and stays put', (tester) async {
      backend.bookingFailure =
          json({'message': 'Stay 01 does not have 1 room(s) free on 2026-11-02.'}, 409);
      await openBookScreen(tester);
      await pickDates(tester);
      final quotesBefore = backend.requests('GET', '/api/accommodations/s1/quote').length;

      await tester.ensureVisible(find.text('Confirm booking'));
      await tester.tap(find.text('Confirm booking'));
      await tester.pump(); // let the failure and the re-quote timer start
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not have 1 room(s) free'), findsOneWidget);
      expect(find.text('Booking details'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Confirm booking'), findsOneWidget);
      // It re-checks availability, because someone else may have taken the rooms.
      expect(backend.requests('GET', '/api/accommodations/s1/quote').length,
          greaterThan(quotesBefore));
    });

    testWidgets('without an open trip there is nothing to book for', (tester) async {
      backend.trips = [tripJson('t9', 'Called off', status: 'Cancelled')];
      await openBookScreen(tester);
      await pickDates(tester);

      expect(find.textContaining('You need an open trip'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('a deactivated stay cannot be booked', (tester) async {
      backend.stays = [stayJson(1, active: true)];
      await openStays(tester);
      await openStay(tester, 'Stay 01');
      // The stay was switched off after it was listed.
      backend.stays = [stayJson(1, active: false)];
      await tester.drag(find.byType(ListView).last, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.text('No longer available'), findsOneWidget);
    });
  });

  group('My bookings', () {
    DateTime upcomingIn = _inDays(10), upcomingOut = _inDays(12);

    setUp(() {
      upcomingIn = _inDays(10);
      upcomingOut = _inDays(12);
      backend.bookings = [
        bookingJson('up', checkIn: upcomingIn, checkOut: upcomingOut, stayName: 'Stay 01',
            created: '2026-10-03T00:00:00Z'),
        bookingJson('done', checkIn: _inDays(-10), checkOut: _inDays(-8), stayName: 'Ella Inn',
            created: '2026-10-02T00:00:00Z'),
        bookingJson('gone', checkIn: _inDays(-20), checkOut: _inDays(-18), stayName: 'Old Lodge',
            status: 'Cancelled', created: '2026-10-01T00:00:00Z'),
      ];
    });

    Future<void> openBookings(WidgetTester tester) async {
      await openStays(tester);
      await tester.tap(find.text('My bookings'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every booking, newest first, with status and total', (tester) async {
      await openBookings(tester);

      expect(find.text('Stay 01'), findsOneWidget);
      expect(find.text('Ella Inn'), findsOneWidget);
      expect(find.text('Old Lodge'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Confirmed'), findsNWidgets(2));
      expect(find.text('LKR 40,000'), findsWidgets);
      expect(tester.getTopLeft(find.text('Stay 01')).dy,
          lessThan(tester.getTopLeft(find.text('Old Lodge')).dy));
    });

    testWidgets('shows an empty state', (tester) async {
      backend.bookings = [];
      await openBookings(tester);

      expect(find.textContaining('No bookings yet'), findsOneWidget);
    });

    testWidgets('shows an error with retry that recovers', (tester) async {
      backend.bookingsFailure = 500;
      await openBookings(tester);
      expect(find.text('Something went wrong on the server.'), findsOneWidget);

      backend.bookingsFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Old Lodge'), findsOneWidget);
    });

    testWidgets('a booking opens with its stays, dates and prices', (tester) async {
      await openBookings(tester);
      await tester.tap(find.text('Stay 01'));
      await tester.pumpAndSettle();

      expect(find.text('Booking details'), findsOneWidget);
      expect(find.text('For South coast'), findsOneWidget);
      expect(find.textContaining('2 nights'), findsOneWidget);
      expect(find.text('LKR 20,000 per room per night'), findsOneWidget);
      expect(find.text('Subtotal LKR 40,000'), findsOneWidget);
      expect(find.text('Cancel booking'), findsOneWidget);
    });

    testWidgets('cancelling asks first, then marks the booking cancelled', (tester) async {
      await openBookings(tester);
      await tester.tap(find.text('Stay 01'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Cancel booking'));
      expect(find.text('Cancel this booking?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.text('Booking cancelled.'), findsOneWidget);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.text('Cancel booking'), findsNothing); // nothing left to cancel
      expect(backend.requests('POST', '/api/bookings/up/cancel'), hasLength(1));
    });

    testWidgets('"Keep booking" leaves it untouched', (tester) async {
      await openBookings(tester);
      await tester.tap(find.text('Stay 01'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Cancel booking'));
      await tester.tap(find.text('Keep booking'));
      await tester.pumpAndSettle();

      expect(backend.requests('POST', '/api/bookings/up/cancel'), isEmpty);
      expect(find.text('Cancel booking'), findsOneWidget);
    });

    testWidgets('a refused cancellation shows the reason and keeps the booking',
        (tester) async {
      backend.cancelFailure =
          'This booking can no longer be cancelled because the first stay has started.';
      await openBookings(tester);
      await tester.tap(find.text('Stay 01'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Cancel booking'));
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();

      expect(find.textContaining('first stay has started'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
    });

    testWidgets('only a finished, confirmed stay can be reviewed', (tester) async {
      await openBookings(tester);

      // Upcoming: no review button.
      await tester.tap(find.text('Stay 01'));
      await tester.pumpAndSettle();
      expect(find.text('Write a review'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Cancelled and ended: still none.
      await tester.tap(find.text('Old Lodge'));
      await tester.pumpAndSettle();
      expect(find.text('Write a review'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Confirmed and ended: offered, and it opens the dialog for that stay.
      await tester.tap(find.text('Ella Inn'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Write a review'));
      expect(find.text('Review Ella Inn'), findsOneWidget);
    });
  });

  group('From a trip', () {
    setUp(() {
      backend.trips = [
        tripJson('t2', 'Hill country'),
        tripJson('t1', 'South coast'),
      ];
      backend.bookings = [
        bookingJson('b1', checkIn: _inDays(10), checkOut: _inDays(12), stayName: 'Stay 02'),
        bookingJson('b2', tripId: 't2', tripTitle: 'Hill country', checkIn: _inDays(20),
            checkOut: _inDays(22), stayName: 'Ella Inn'),
      ];
    });

    Future<void> openTrip(WidgetTester tester, String title) async {
      await pumpApp(tester);
      await openTab(tester, 'My trips');
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets("the trip lists only its own bookings", (tester) async {
      await openTrip(tester, 'South coast');
      await tester.ensureVisible(find.text('Book a stay'));
      await tester.pumpAndSettle();

      expect(find.text('Stays (1)'), findsOneWidget);
      expect(find.text('Stay 02'), findsOneWidget);
      expect(find.text('Ella Inn'), findsNothing);
    });

    testWidgets('a trip without bookings says so', (tester) async {
      backend.bookings = [];
      await openTrip(tester, 'South coast');
      await tester.ensureVisible(find.text('Book a stay'));
      await tester.pumpAndSettle();

      expect(find.text('No stays booked for this trip yet.'), findsOneWidget);
    });

    testWidgets('Book a stay picks a stay and books it for that trip', (tester) async {
      await openTrip(tester, 'South coast');
      await tapVisible(tester, find.text('Book a stay'));
      expect(find.text('Choose a stay'), findsOneWidget);
      expect(find.text('My bookings'), findsNothing); // picker mode has no shortcut

      await openStay(tester, 'Stay 01');
      await tapVisible(tester, find.text('Book this stay'));
      await pickDates(tester);

      // The trip we came from is already chosen, not just the first in the list.
      expect(find.text('South coast'), findsWidgets);
      await tester.ensureVisible(find.text('Confirm booking'));
      await tester.tap(find.text('Confirm booking'));
      await tester.pumpAndSettle();

      expect(backend.requests('POST', '/api/bookings').single.body, contains('"tripId":"t1"'));
      expect(find.text('For South coast'), findsOneWidget);
    });

    testWidgets('a cancelled trip cannot take new bookings', (tester) async {
      backend.trips = [tripJson('t1', 'South coast', status: 'Cancelled')];
      await openTrip(tester, 'South coast');

      expect(find.text('Book a stay'), findsNothing);
    });
  });

  testWidgets('signing out clears stays and bookings for the next user', (tester) async {
    backend.bookings = [bookingJson('b1', checkIn: _inDays(10), checkOut: _inDays(12))];
    await openStays(tester);
    final context = tester.element(find.byType(Scaffold).first);
    final stays = context.read<AccommodationsProvider>();
    final bookings = context.read<BookingsProvider>();
    expect(stays.items, isNotEmpty);
    expect(bookings.items, isNotEmpty);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(stays.items, isEmpty);
    expect(bookings.items, isEmpty);
  });
}
