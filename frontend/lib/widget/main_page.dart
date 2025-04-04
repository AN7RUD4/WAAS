import 'package:flutter/material.dart';
import 'package:waas/user/home_page.dart';
import 'package:waas/widget/bottom_nav.dart';
import 'package:waas/widget/profile.dart';
import 'package:waas/worker/home_worker.dart';
import 'package:waas/worker/pick_map.dart';

class MainPage extends StatelessWidget {
  final String role; // Add email parameter
  final List<Widget> _pages; // Define pages list
  int userID;

  MainPage({super.key, required this.userID, required this.role})
    : _pages = [
        role == 'worker' ? WorkerApp() : UserApp(),
        MapScreen(),
        ProfilePage(userID: userID),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main Content
          SafeArea(
            child: ValueListenableBuilder(
              valueListenable: indexChangeNotifier,
              builder: (context, int index, _) => _pages[index],
            ),
          ),

          // Overlay Bottom Navigation Bar
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
