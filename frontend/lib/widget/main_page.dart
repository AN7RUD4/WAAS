import 'package:flutter/material.dart';
import 'package:waas/user/home_page.dart';
import 'package:waas/widget/bottom_nav.dart';
import 'package:waas/widget/profile.dart';
import 'package:waas/worker/home_worker.dart';

class MainPage extends StatelessWidget {
  final String role;
  final List<Widget> _pages;
  final int userID;

  const MainPage({super.key, required this.userID, required this.role})
    : _pages = const [
        UserApp(), // Default to UserApp
        ProfilePage(),
      ];

  @override
  Widget build(BuildContext context) {
    // Override the first page based on role
    final pages = [
      role == 'worker' ? const WorkerApp() : const UserApp(),
      ..._pages.sublist(1),
    ];

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ValueListenableBuilder<int>(
              valueListenable: indexChangeNotifier,
              builder: (context, index, _) {
                if (index < 0 || index >= pages.length) {
                  return const Center(child: Text('Page not found'));
                }
                return pages[index];
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
