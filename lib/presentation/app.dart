import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/app_providers.dart';

class WakeyAlarmApp extends StatelessWidget {
  const WakeyAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wakey-Wakey',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _selectedIndex = 0;

  static const _tabs = <_ShellTab>[
    _ShellTab(
      title: 'Alarms',
      icon: Icons.alarm,
      emptyMessage: 'No alarms yet',
    ),
    _ShellTab(
      title: 'Stopwatch',
      icon: Icons.timer_outlined,
      emptyMessage: 'Stopwatch ready',
    ),
    _ShellTab(
      title: 'Timer',
      icon: Icons.hourglass_empty,
      emptyMessage: 'No timers yet',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(alarmsProvider);
    ref.watch(timersProvider);
    ref.watch(permissionStatusProvider);

    final selectedTab = _tabs[_selectedIndex];

    return Scaffold(
      appBar: AppBar(title: Text(selectedTab.title)),
      body: _EmptyTabView(tab: selectedTab),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.title),
        ],
      ),
    );
  }
}

class _EmptyTabView extends StatelessWidget {
  const _EmptyTabView({required this.tab});

  final _ShellTab tab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tab.icon, size: 48),
          const SizedBox(height: 12),
          Text(
            tab.emptyMessage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _ShellTab {
  const _ShellTab({
    required this.title,
    required this.icon,
    required this.emptyMessage,
  });

  final String title;
  final IconData icon;
  final String emptyMessage;
}
