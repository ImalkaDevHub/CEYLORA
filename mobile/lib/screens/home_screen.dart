import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Placeholder landing screen shown after sign-in. Proves the shared identity:
/// the name, email and role come from the same /api/auth endpoints React uses.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final session = auth.session;
    if (session == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('CEYLORA'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome, ${session.fullName}',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(session.email),
              const SizedBox(height: 12),
              Chip(label: Text(session.role)),
            ],
          ),
        ),
      ),
    );
  }
}
