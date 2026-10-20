import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/models/trip_photo.dart';
import 'package:mobile/providers/trip_photos_provider.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/photo_picker.dart';
import 'package:mobile/services/token_storage.dart';
import 'package:mobile/services/trip_photo_store.dart';
import 'package:path/path.dart' as p;
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

const _tripId = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _trip({String status = 'Draft'}) => {
      'id': _tripId,
      'title': 'Kandy escape',
      'startDate': '2026-11-01T00:00:00Z',
      'endDate': '2026-11-04T00:00:00Z',
      'budget': 150000,
      'status': status,
      'travelerName': 'Sam Traveler',
    };

/// A picker that waits until the test releases it.
class _SlowPicker implements PhotoPicker {
  final Completer<String?> gate = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> pick(PhotoSource source) {
    calls++;
    return gate.future;
  }
}

void main() {
  group('FileTripPhotoStore', () {
    late Directory root;
    late Directory scratch; // where "picked" source files live
    late FileTripPhotoStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('trip_photos_root');
      scratch = await Directory.systemTemp.createTemp('trip_photos_src');
      store = FileTripPhotoStore(rootProvider: () async => root);
    });

    tearDown(() async {
      await root.delete(recursive: true);
      await scratch.delete(recursive: true);
    });

    Future<String> source(String name, [String content = 'img']) async {
      final f = File(p.join(scratch.path, name));
      await f.writeAsString(content);
      return f.path;
    }

    test('lists nothing for a trip with no photos', () async {
      expect(await store.list(_tripId), isEmpty);
    });

    test('add copies the file into the trip folder and keeps the extension',
        () async {
      final added = await store.add(_tripId, await source('IMG_001.PNG', 'abc'));

      expect(p.isWithin(p.join(root.path, _tripId), added.path), isTrue);
      expect(p.extension(added.path), '.png');
      expect(await File(added.path).readAsString(), 'abc');
      // The original stays where it was.
      expect(await File(p.join(scratch.path, 'IMG_001.PNG')).exists(), isTrue);
    });

    test('an unknown extension is stored as .jpg', () async {
      final added = await store.add(_tripId, await source('camera.tmp'));
      expect(p.extension(added.path), '.jpg');
    });

    test('lists newest first and gives every photo its own file', () async {
      final a = await store.add(_tripId, await source('a.jpg', 'a'));
      final b = await store.add(_tripId, await source('b.jpg', 'b'));
      final c = await store.add(_tripId, await source('c.jpg', 'c'));
      expect({a.path, b.path, c.path}, hasLength(3));

      final listed = await store.list(_tripId);

      expect(listed.map((e) => e.path).toList(), [c.path, b.path, a.path]);
      expect(listed.first.takenAt.isAfter(listed.last.takenAt), isTrue);
    });

    test('keeps each trip\'s photos separate', () async {
      const other = '22222222-2222-2222-2222-222222222222';
      await store.add(_tripId, await source('a.jpg'));
      await store.add(other, await source('b.jpg'));

      expect(await store.list(_tripId), hasLength(1));
      expect(await store.list(other), hasLength(1));
    });

    test('ignores files that are not images and sub-folders', () async {
      await store.add(_tripId, await source('a.jpg'));
      final dir = Directory(p.join(root.path, _tripId));
      await File(p.join(dir.path, 'notes.txt')).writeAsString('x');
      await Directory(p.join(dir.path, 'nested.jpg')).create();

      expect(await store.list(_tripId), hasLength(1));
    });

    test('add fails clearly when the picked file has disappeared', () async {
      await expectLater(
          store.add(_tripId, p.join(scratch.path, 'gone.jpg')),
          throwsA(isA<FileSystemException>()));
      expect(await store.list(_tripId), isEmpty);
    });

    test('trip ids that could escape the photos folder are rejected',
        () async {
      final src = await source('a.jpg');
      for (final bad in ['../evil', 'a/b', r'a\b', '', '..', 'x' * 65]) {
        await expectLater(store.list(bad), throwsArgumentError, reason: bad);
        await expectLater(store.add(bad, src), throwsArgumentError,
            reason: bad);
      }
      // Nothing was written outside (or inside) the root.
      expect(await root.list().toList(), isEmpty);
    });

    test('remove deletes the file, and removing it again is harmless',
        () async {
      final added = await store.add(_tripId, await source('a.jpg'));

      await store.remove(added);
      expect(await File(added.path).exists(), isFalse);
      expect(await store.list(_tripId), isEmpty);

      await store.remove(added); // already gone
    });

    test('remove refuses files outside the trip folder', () async {
      final outside = File(p.join(scratch.path, 'precious.jpg'));
      await outside.writeAsString('keep me');
      const other = '22222222-2222-2222-2222-222222222222';
      final inOtherTrip = await store.add(other, await source('b.jpg'));

      await expectLater(
          store.remove(TripPhoto(
              tripId: _tripId, path: outside.path, takenAt: DateTime.now())),
          throwsArgumentError);
      await expectLater(
          store.remove(TripPhoto(
              tripId: _tripId,
              path: inOtherTrip.path,
              takenAt: DateTime.now())),
          throwsArgumentError);
      await expectLater(
          store.remove(TripPhoto(
              tripId: _tripId,
              path: p.join(root.path, _tripId, '..', other, 'x.jpg'),
              takenAt: DateTime.now())),
          throwsArgumentError);

      expect(await outside.exists(), isTrue);
      expect(await File(inOtherTrip.path).exists(), isTrue);
    });
  });

  group('ImagePickerPhotoPicker.messageFor', () {
    String message(String code, PhotoSource s) => ImagePickerPhotoPicker
        .messageFor(PlatformException(code: code), s)
        .message;

    test('explains a denied camera permission', () {
      expect(message('camera_access_denied', PhotoSource.camera),
          contains('Camera access is turned off'));
    });

    test('explains a denied photo permission', () {
      expect(message('photo_access_denied', PhotoSource.gallery),
          contains('Photo access is turned off'));
    });

    test('falls back to a plain message for anything else', () {
      expect(message('boom', PhotoSource.camera), 'Could not open the camera.');
      expect(message('boom', PhotoSource.gallery),
          'Could not open your photos.');
    });
  });

  group('TripPhotosProvider', () {
    late FakeTripPhotoStore store;
    late FakePhotoPicker picker;
    late TripPhotosProvider provider;

    setUp(() {
      store = FakeTripPhotoStore({
        _tripId: [photo(_tripId, 2), photo(_tripId, 1)],
      });
      picker = FakePhotoPicker();
      provider = TripPhotosProvider(store, picker);
    });

    test('load reads the stored photos', () async {
      expect(provider.hasLoaded(_tripId), isFalse);

      await provider.load(_tripId);

      expect(provider.hasLoaded(_tripId), isTrue);
      expect(provider.photosFor(_tripId), hasLength(2));
    });

    test('unreadable storage loads as "no photos" instead of failing',
        () async {
      store.failList = const FileSystemException('denied');

      await provider.load(_tripId);

      expect(provider.hasLoaded(_tripId), isTrue);
      expect(provider.photosFor(_tripId), isEmpty);
    });

    test('add attaches the picked photo to the front', () async {
      await provider.load(_tripId);
      picker.result = '/picked/new.jpg';

      final error = await provider.add(_tripId, PhotoSource.camera);

      expect(error, isNull);
      expect(picker.requested, [PhotoSource.camera]);
      expect(store.addedSources, ['/picked/new.jpg']);
      expect(provider.photosFor(_tripId), hasLength(3));
      expect(provider.photosFor(_tripId).first.path, contains('/fake/'));
      expect(provider.isBusy(_tripId), isFalse);
    });

    test('add uses the gallery when asked', () async {
      await provider.add(_tripId, PhotoSource.gallery);
      expect(picker.requested, [PhotoSource.gallery]);
    });

    test('a cancelled pick changes nothing and is not an error', () async {
      await provider.load(_tripId);
      picker.result = null;

      final error = await provider.add(_tripId, PhotoSource.camera);

      expect(error, isNull);
      expect(store.addedSources, isEmpty);
      expect(provider.photosFor(_tripId), hasLength(2));
      expect(provider.isBusy(_tripId), isFalse);
    });

    test('the picker\'s message is passed on when it cannot open', () async {
      picker.failure = const PhotoPickerException('Camera access is turned off.');

      expect(await provider.add(_tripId, PhotoSource.camera),
          'Camera access is turned off.');
      expect(provider.isBusy(_tripId), isFalse);
    });

    test('a storage failure while saving gets a friendly message', () async {
      store.failAdd = const FileSystemException('disk full');

      final error = await provider.add(_tripId, PhotoSource.camera);

      expect(error, contains('Could not save the photo'));
      expect(provider.photosFor(_tripId), isEmpty);
      expect(provider.isBusy(_tripId), isFalse);
    });

    test('stops at the per-trip limit without opening the camera', () async {
      store = FakeTripPhotoStore({
        _tripId: [
          for (var i = 1; i <= TripPhotosProvider.maxPerTrip; i++)
            photo(_tripId, i)
        ],
      });
      provider = TripPhotosProvider(store, picker);
      await provider.load(_tripId);

      final error = await provider.add(_tripId, PhotoSource.camera);

      expect(error, contains('up to ${TripPhotosProvider.maxPerTrip}'));
      expect(picker.requested, isEmpty);
    });

    test('a second add while one is in progress is ignored', () async {
      final slow = _SlowPicker();
      provider = TripPhotosProvider(store, slow);

      final first = provider.add(_tripId, PhotoSource.camera);
      expect(provider.isBusy(_tripId), isTrue);
      expect(await provider.add(_tripId, PhotoSource.camera), isNull);
      expect(slow.calls, 1);

      slow.gate.complete('/picked/a.jpg');
      await first;
      expect(provider.isBusy(_tripId), isFalse);
      expect(provider.photosFor(_tripId), hasLength(1));
    });

    test('remove deletes the photo', () async {
      await provider.load(_tripId);
      final target = provider.photosFor(_tripId).first;

      final error = await provider.remove(target);

      expect(error, isNull);
      expect(provider.photosFor(_tripId), isNot(contains(target)));
      expect(provider.photosFor(_tripId), hasLength(1));
    });

    test('a failed delete keeps the photo and says so', () async {
      await provider.load(_tripId);
      store.failRemove = const FileSystemException('locked');

      final error = await provider.remove(provider.photosFor(_tripId).first);

      expect(error, contains('Could not delete'));
      expect(provider.photosFor(_tripId), hasLength(2));
    });

    test('clear forgets everything, even work that finishes afterwards',
        () async {
      final slow = _SlowPicker();
      provider = TripPhotosProvider(store, slow);
      await provider.load(_tripId);
      final pending = provider.add(_tripId, PhotoSource.camera);

      provider.clear(); // e.g. the user signs out mid-pick
      slow.gate.complete('/picked/late.jpg');
      await pending;

      expect(provider.photosFor(_tripId), isEmpty);
      expect(provider.hasLoaded(_tripId), isFalse);
      expect(provider.isBusy(_tripId), isFalse);
    });
  });

  group('Trip photos UI', () {
    late FakeTripPhotoStore store;
    late FakePhotoPicker picker;

    setUp(() {
      store = FakeTripPhotoStore();
      picker = FakePhotoPicker();
    });

    Future<void> openTrip(WidgetTester tester,
        {PhotoPicker? withPicker, String status = 'Draft'}) async {
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/api/trips/mine') {
          return _json([_trip(status: status)], 200);
        }
        return _json({}, 404);
      });
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      await tester.pumpWidget(CeyloraApp(
        api: api,
        store: _MemoryStore(_session()),
        photoStore: store,
        photoPicker: withPicker ?? picker,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kandy escape'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add photo'));
      await tester.pumpAndSettle();
    }

    Finder thumb(int n) => find.byKey(ValueKey('/fake/$_tripId/$n.jpg'));

    testWidgets('shows an empty state with the storage note', (tester) async {
      await openTrip(tester);

      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('No photos yet. Add some to remember this trip.'),
          findsOneWidget);
      expect(find.text('Photos are saved on this device only.'),
          findsOneWidget);
    });

    testWidgets('shows the saved photos with a count', (tester) async {
      store = FakeTripPhotoStore({
        _tripId: [photo(_tripId, 2), photo(_tripId, 1)],
      });
      await openTrip(tester);

      expect(find.text('Photos (2)'), findsOneWidget);
      expect(thumb(1), findsOneWidget);
      expect(thumb(2), findsOneWidget);
      expect(find.textContaining('No photos yet'), findsNothing);
    });

    testWidgets('unreadable storage shows the empty state, not a spinner',
        (tester) async {
      store.failList = const FileSystemException('denied');
      await openTrip(tester);

      expect(find.textContaining('No photos yet'), findsOneWidget);
    });

    testWidgets('photos are available on trips of any status', (tester) async {
      await openTrip(tester, status: 'Confirmed');

      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('Add photo offers camera and gallery, and takes a photo',
        (tester) async {
      await openTrip(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);

      picker.result = '/picked/from-camera.jpg';
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(picker.requested, [PhotoSource.camera]);
      expect(store.addedSources, ['/picked/from-camera.jpg']);
      expect(find.text('Photos (1)'), findsOneWidget);
      expect(thumb(1), findsOneWidget);
    });

    testWidgets('choosing from the gallery uses the gallery source',
        (tester) async {
      await openTrip(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();

      expect(picker.requested, [PhotoSource.gallery]);
      expect(find.text('Photos (1)'), findsOneWidget);
    });

    testWidgets('dismissing the sheet does not open the camera',
        (tester) async {
      await openTrip(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // outside the sheet
      await tester.pumpAndSettle();

      expect(picker.requested, isEmpty);
      expect(find.text('Take a photo'), findsNothing);
    });

    testWidgets('a cancelled pick adds nothing and shows no error',
        (tester) async {
      picker.result = null;
      await openTrip(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No photos yet'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a denied camera permission is explained', (tester) async {
      picker.failure = const PhotoPickerException(
          'Camera access is turned off. Allow it in Settings to take photos.');
      await openTrip(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Camera access is turned off'),
          findsOneWidget);
      expect(find.textContaining('No photos yet'), findsOneWidget);
    });

    testWidgets('a storage failure while saving is explained', (tester) async {
      store.failAdd = const FileSystemException('disk full');
      await openTrip(tester);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save the photo'), findsOneWidget);
    });

    testWidgets('the Add button is disabled while a photo is being picked',
        (tester) async {
      final slow = _SlowPicker();
      await openTrip(tester, withPicker: slow);

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Add photo'));
      expect(button.onPressed, isNull);

      slow.gate.complete('/picked/a.jpg');
      await tester.pumpAndSettle();
      final after = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Add photo'));
      expect(after.onPressed, isNotNull);
      expect(find.text('Photos (1)'), findsOneWidget);
    });

    group('viewer', () {
      setUp(() {
        store = FakeTripPhotoStore({
          _tripId: [photo(_tripId, 3), photo(_tripId, 2), photo(_tripId, 1)],
        });
      });

      testWidgets('opens on the tapped photo and swipes between photos',
          (tester) async {
        await openTrip(tester);

        await tester.tap(thumb(2)); // second in the grid (newest first)
        await tester.pumpAndSettle();
        expect(find.text('2 of 3'), findsOneWidget);

        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
        await tester.pumpAndSettle();
        expect(find.text('3 of 3'), findsOneWidget);
      });

      testWidgets('cancelling the delete dialog keeps the photo',
          (tester) async {
        await openTrip(tester);
        await tester.tap(thumb(3));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Delete photo'));
        await tester.pumpAndSettle();
        expect(find.text('Delete this photo?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('1 of 3'), findsOneWidget);
        expect(store.photos[_tripId], hasLength(3));
      });

      testWidgets('deleting removes the photo and updates the count',
          (tester) async {
        await openTrip(tester);
        await tester.tap(thumb(3));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Delete photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('1 of 2'), findsOneWidget);
        expect(store.photos[_tripId], hasLength(2));

        // Back on the trip, the grid matches.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Photos (2)'), findsOneWidget);
        expect(thumb(3), findsNothing);
      });

      testWidgets('deleting the last photo leaves an empty viewer',
          (tester) async {
        store = FakeTripPhotoStore({
          _tripId: [photo(_tripId, 1)],
        });
        await openTrip(tester);
        await tester.tap(thumb(1));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Delete photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('No photos.'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.textContaining('No photos yet'), findsOneWidget);
      });

      testWidgets('a failed delete keeps the photo and says why',
          (tester) async {
        store.failRemove = const FileSystemException('locked');
        await openTrip(tester);
        await tester.tap(thumb(3));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Delete photo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Could not delete'), findsOneWidget);
        expect(find.text('1 of 3'), findsOneWidget);
      });
    });

    testWidgets('signing out clears the in-memory photos', (tester) async {
      store = FakeTripPhotoStore({
        _tripId: [photo(_tripId, 1)],
      });
      await openTrip(tester);
      final provider = tester
          .element(find.byType(Scaffold).first)
          .read<TripPhotosProvider>();
      expect(provider.photosFor(_tripId), hasLength(1));

      await tester.pageBack(); // trip -> My trips
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(provider.photosFor(_tripId), isEmpty);
    });
  });
}
