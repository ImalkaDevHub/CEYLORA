import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/accommodations_provider.dart';
import 'providers/ai_workflows_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/bookings_provider.dart';
import 'providers/destinations_provider.dart';
import 'providers/reviews_provider.dart';
import 'providers/trip_photos_provider.dart';
import 'providers/trips_provider.dart';
import 'screens/main_shell.dart';
import 'screens/login_screen.dart';
import 'services/ai_workflow_service.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/destination_service.dart';
import 'services/photo_picker.dart';
import 'services/stay_services.dart';
import 'services/token_storage.dart';
import 'services/trip_photo_store.dart';
import 'services/trip_service.dart';

void main() {
  final api = ApiClient();
  runApp(CeyloraApp(
    api: api,
    store: SecureSessionStore(),
  ));
}

class CeyloraApp extends StatelessWidget {
  final ApiClient api;
  final SessionStore store;

  /// Camera/gallery and on-device photo storage; tests pass fakes.
  final PhotoPicker? photoPicker;
  final TripPhotoStore? photoStore;

  const CeyloraApp({
    super.key,
    required this.api,
    required this.store,
    this.photoPicker,
    this.photoStore,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            api: api,
            service: AuthService(api),
            store: store,
          )..restore(),
        ),
        // Rebuilt around the signed-in user: cached trips are dropped on sign-out.
        ChangeNotifierProxyProvider<AuthProvider, TripsProvider>(
          create: (_) => TripsProvider(TripService(api)),
          update: (_, auth, trips) {
            if (auth.status != AuthStatus.signedIn) trips!.clear();
            return trips!;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, DestinationsProvider>(
          create: (_) => DestinationsProvider(DestinationService(api)),
          update: (_, auth, destinations) {
            if (auth.status != AuthStatus.signedIn) destinations!.clear();
            return destinations!;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, TripPhotosProvider>(
          create: (_) => TripPhotosProvider(
            photoStore ?? FileTripPhotoStore(),
            photoPicker ?? ImagePickerPhotoPicker(),
          ),
          update: (_, auth, photos) {
            if (auth.status != AuthStatus.signedIn) photos!.clear();
            return photos!;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, AccommodationsProvider>(
          create: (_) => AccommodationsProvider(AccommodationService(api)),
          update: (_, auth, stays) {
            if (auth.status != AuthStatus.signedIn) stays!.clear();
            return stays!;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, BookingsProvider>(
          create: (_) => BookingsProvider(BookingService(api)),
          update: (_, auth, bookings) {
            if (auth.status != AuthStatus.signedIn) bookings!.clear();
            return bookings!;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, ReviewsProvider>(
          create: (_) => ReviewsProvider(ReviewService(api)),
          update: (_, auth, reviews) {
            if (auth.status != AuthStatus.signedIn) reviews!.clear();
            return reviews!;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, AiWorkflowsProvider>(
          create: (_) => AiWorkflowsProvider(AiWorkflowService(api)),
          update: (_, auth, workflows) {
            if (auth.status != AuthStatus.signedIn) workflows!.clear();
            return workflows!;
          },
        ),
      ],
      child: MaterialApp(
        title: 'CEYLORA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

/// Chooses the screen from the auth state: splash -> login -> home.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final status = context.select<AuthProvider, AuthStatus>((a) => a.status);
    switch (status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const LoginScreen();
      case AuthStatus.signedIn:
        return const MainShell();
    }
  }
}
