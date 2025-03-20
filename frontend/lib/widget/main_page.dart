import 'package:flutter/material.dart';
import 'package:waas/user/home_page.dart';
import 'package:waas/widget/bottom_nav.dart';
import 'package:waas/widget/profile.dart';
import 'package:waas/worker/home_worker.dart';
import 'package:waas/worker/pick_map.dart';

// Define indexChangeNotifier if not defined in bottom_nav.dart
final ValueNotifier<int> indexChangeNotifier = ValueNotifier<int>(0);

class MainPage extends StatelessWidget {
  final String role;
  final List<Widget> _pages;
  final int userID;

  MainPage({super.key, required this.userID, required this.role})
      : _pages = [
          role == 'worker' ? const WorkerApp() : const UserApp(),
          const MapScreen(),
          const ProfilePage(),
        ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ValueListenableBuilder<int>(
              valueListenable: indexChangeNotifier,
              builder: (context, index, _) {
                if (index < 0 || index >= _pages.length) {
                  return const Center(child: Text('Page not found'));
                }
                return _pages[index];
              },
            ),
          ),
          Positioned(
            left: MediaQuery.of(context).size.width * 0.2,
            right: MediaQuery.of(context).size.width * 0.2,
            bottom: 20,
            child: const BottomNavigationWidget(),
          ),
        ],
      ),
    );
  }
}