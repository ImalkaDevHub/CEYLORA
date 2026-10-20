import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ai_workflows_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/destinations_provider.dart';
import '../providers/trips_provider.dart';
import 'ai_plans_screen.dart';
import 'destinations_screen.dart';
import 'home_screen.dart';
import 'trips_screen.dart';

/// Signed-in frame: app bar with sign-out and bottom navigation.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = <_Tab>[
    _Tab('Home', Icons.home_outlined, Icons.home, HomeScreen()),
    _Tab('Explore', Icons.explore_outlined, Icons.explore, DestinationsScreen()),
    _Tab('My trips', Icons.luggage_outlined, Icons.luggage, TripsScreen()),
    _Tab('AI plans', Icons.auto_awesome_outlined, Icons.auto_awesome,
        AiPlansScreen()),
  ];

  @override
  void initState() {
    super.initState();
    // Fetch after the first frame so the provider notifies outside of build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TripsProvider>().load();
      context.read<DestinationsProvider>().load();
      context.read<AiWorkflowsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'CEYLORA' : tab.label),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [for (final t in _tabs) t.body],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget body;
  const _Tab(this.label, this.icon, this.selectedIcon, this.body);
}
