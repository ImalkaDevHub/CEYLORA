import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/destinations_provider.dart';
import 'providers/trips_provider.dart';
import 'screens/main_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/destination_service.dart';
import 'services/token_storage.dart';
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

  const CeyloraApp({super.key, required this.api, required this.store});

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
