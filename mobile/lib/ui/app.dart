import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/store.dart';
import 'custom_foods.dart';
import 'diary.dart';
import 'recipes.dart';
import 'settings.dart';
import 'theme.dart';
import 'updates.dart';

class NutrimeterApp extends StatelessWidget {
  const NutrimeterApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'Nutrimeter',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: const AutoUpdater(child: HomeShell()),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Flush pending writes when the app goes to the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) AppScope.read(context).save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [DiaryPage(), RecipesPage(), CustomFoodsPage(), SettingsPage()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(LucideIcons.calendarDays), selectedIcon: Icon(LucideIcons.calendarDays), label: 'Diary'),
            NavigationDestination(icon: Icon(LucideIcons.bookOpen), selectedIcon: Icon(LucideIcons.bookOpen), label: 'Recipes'),
            NavigationDestination(icon: Icon(LucideIcons.apple), selectedIcon: Icon(LucideIcons.apple), label: 'Foods'),
            NavigationDestination(icon: _Marked(Icon(LucideIcons.target)), selectedIcon: _Marked(Icon(LucideIcons.target)), label: 'Targets'),
          ],
        ),
      );
}

/// A tab icon with the update dot while a newer build waits (the Updates panel is in Settings, on this tab).
class _Marked extends StatelessWidget {
  const _Marked(this.icon);

  final Widget icon;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: updateAvailable,
        builder: (context, r, _) => Stack(clipBehavior: Clip.none, children: [
          icon,
          if (r != null) const Positioned(top: -2, right: -4, child: UpdateDot()),
        ]),
      );
}
