import 'package:flutter/material.dart';
import 'package:waas/user/home_page.dart';
import 'package:waas/widget/bottom_nav.dart';
import 'package:waas/widget/profile.dart';
import 'package:waas/worker/home_worker.dart';
import 'package:waas/worker/pick_map.dart';

class MainPage extends StatelessWidget {
  final String email; // Add email parameter
  final List<Widget> _pages; // Define pages list

  MainPage({super.key, required this.email})
    : _pages = [
        email.toLowerCase().startsWith('w') ? WorkerApp() : UserApp(),
        MapScreen(),
        ProfilePage(userID: 1),
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
