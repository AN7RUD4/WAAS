import 'package:flutter/material.dart';
import '../colors/colors.dart';

// Define indexChangeNotifier here as a global variable
final ValueNotifier<int> indexChangeNotifier = ValueNotifier<int>(0);

class BottomNavigationWidget extends StatelessWidget {
  const BottomNavigationWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60, // Height of the navigation bar
      decoration: BoxDecoration(
        color: Colors.white, // Background color
        borderRadius: BorderRadius.circular(30), // Rounded corners
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          30,
        ), // Match container's rounded corners
        child: ValueListenableBuilder<int>(
          valueListenable: indexChangeNotifier,
          builder: (context, newIndex, _) {
            return BottomNavigationBar(
              currentIndex: newIndex,
              onTap: (index) {
                indexChangeNotifier.value = index;
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent, // Transparent background
              selectedItemColor: AppColors.primaryColor, // Selected icon color
              unselectedItemColor: Colors.grey[400], // Unselected icon color
              showSelectedLabels: false, // Hide labels
              showUnselectedLabels: false, // Hide labels
              iconSize: 24, // Icon size
              elevation: 0, // Remove default shadow
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined), // Outline icon
                  activeIcon: Icon(Icons.home), // Filled icon when selected
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined), // Outline icon
                  activeIcon: Icon(Icons.map), // Filled icon when selected
                  label: 'Map',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outlined), // Outline icon
                  activeIcon: Icon(Icons.person), // Filled icon when selected
                  label: 'Profile',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
