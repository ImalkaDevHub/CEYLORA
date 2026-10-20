import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Home tab body. Shows who is signed in; name, email and role come from the
/// same /api/auth endpoints the React app uses (shared identity).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthProvider>().session;
    if (session == null) return const SizedBox.shrink();

    return Center(
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
    );
  }
}
