import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';
import 'tafrigh_screen.dart';
import 'field_check_screen.dart';
import 'faroz_screen.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth  = context.watch<AuthService>();
    final pages = _buildPages(auth.isAdmin);
    final items = _buildNavItems(auth.isAdmin);

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kSurf,
          border: Border(top: BorderSide(color: kBorder)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: kSurf,
          indicatorColor: kSky.withOpacity(.18),
          destinations: items,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          animationDuration: const Duration(milliseconds: 200),
        ),
      ),
    );
  }

  List<Widget> _buildPages(bool isAdmin) => [
    const TafrighScreen(),
    const FieldCheckScreen(),
    const FarozScreen(),
    const SettingsScreen(),
    if (isAdmin) const AdminScreen(),
  ];

  List<NavigationDestination> _buildNavItems(bool isAdmin) => [
    const NavigationDestination(
      icon:          Icon(Icons.mic_none),
      selectedIcon:  Icon(Icons.mic),
      label: 'التفريغ',
    ),
    const NavigationDestination(
      icon:          Icon(Icons.search_outlined),
      selectedIcon:  Icon(Icons.search),
      label: 'التشيك',
    ),
    const NavigationDestination(
      icon:          Icon(Icons.compare_arrows_outlined),
      selectedIcon:  Icon(Icons.compare_arrows),
      label: 'الفرز',
    ),
    const NavigationDestination(
      icon:          Icon(Icons.settings_outlined),
      selectedIcon:  Icon(Icons.settings),
      label: 'الإعدادات',
    ),
    if (isAdmin)
      const NavigationDestination(
        icon:          Icon(Icons.admin_panel_settings_outlined),
        selectedIcon:  Icon(Icons.admin_panel_settings),
        label: 'Admin',
      ),
  ];
}
