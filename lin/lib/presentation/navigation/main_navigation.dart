import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pages/home_page.dart';
import '../pages/contacts_page.dart';
import '../pages/record_interaction_screen.dart';
import '../pages/metrics_screen.dart';
import '../pages/settings_screen.dart';

/// Main navigation shell with bottom navigation
class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    HomePage(),
    RecordInteractionScreen(),
    ContactsPage(),
    MetricsScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'record',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.contacts),
            label: 'contacts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'metrics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'settings',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
