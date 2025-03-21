import 'package:flutter/material.dart';
import 'package:waas/widget/login.dart';
import 'package:waas/widget/signup_page.dart';
import 'colors/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Need to remove before submission
// Token migration function to move tokens from SharedPreferences to FlutterSecureStorage
Future<void> migrateToken() async {
  final prefs = await SharedPreferences.getInstance();
  final storage = const FlutterSecureStorage();

  // Check if a token exists in SharedPreferences
  String? oldToken = prefs.getString('token');
  if (oldToken != null) {
    // Migrate the token to FlutterSecureStorage
    await storage.write(key: 'jwt_token', value: oldToken);
    // Remove the token from SharedPreferences
    await prefs.remove('token');
    print('Token migrated from SharedPreferences to FlutterSecureStorage');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await migrateToken();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waste Management App',
      theme: ThemeData(
        primaryColor: AppColors.primaryColor,
        colorScheme: ColorScheme.light(
          primary: AppColors.primaryColor,
          secondary: AppColors.secondaryColor,
          background: AppColors.backgroundColor,
          onBackground: AppColors.textColor,
          error: AppColors.errorColor,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.backgroundColor,
          foregroundColor: AppColors.textColor,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.textColor),
          bodyMedium: TextStyle(color: AppColors.textColor),
          titleLarge: TextStyle(
            color: AppColors.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const LoginPage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
      },
      initialRoute: '/login',
    );
  }
}