import 'package:flutter/material.dart';
import 'package:user_samp/widget/bottom_nav.dart';
import 'package:user_samp/worker/home_worker.dart';
import 'package:user_samp/worker/pick_map.dart';

// import 'package:user/widget/profile.dart';

class MainPage extends StatelessWidget {
  MainPage({super.key});

  final _pages = [
    const WorkerHome(),
    MapScreen(),
    //  Profile(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: indexChangeNotifier,
          builder: (context, int index, _) => _pages[index],
        ),
      ),
      bottomNavigationBar: const BottomNavigationWidget(),
    );
  }
}
