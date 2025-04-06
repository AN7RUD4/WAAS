// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';
// import 'package:waas/widget/login.dart';
// import 'package:waas/widget/signup_page.dart';
// import 'colors/colors.dart';

//  void main() async {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Waste Management App',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         useMaterial3: true,
//         colorScheme: ColorScheme.fromSeed(
//           seedColor: AppColors.primaryColor,
//           brightness: Brightness.light,
//           primary: AppColors.primaryColor,
//           secondary: AppColors.secondaryColor,
//           background: AppColors.backgroundColor,
//           onBackground: AppColors.textColor,
//           error: AppColors.errorColor,
//           surface: Colors.white,
//         ),
//         scaffoldBackgroundColor: AppColors.backgroundColor,
//         textTheme: GoogleFonts.poppinsTextTheme(
//           const TextTheme(
//             displayLarge: TextStyle(
//               fontSize: 32,
//               fontWeight: FontWeight.bold,
//               color: Colors.black87,
//             ),
//             displayMedium: TextStyle(
//               fontSize: 24,
//               fontWeight: FontWeight.w600,
//               color: Colors.black87,
//             ),
//             bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
//             bodyMedium: TextStyle(fontSize: 14, color: Colors.black54),
//             labelLarge: TextStyle(
//               fontSize: 16,
//               fontWeight: FontWeight.w600,
//               color: Colors.black87,
//             ),
//           ),
//         ),
//         appBarTheme: AppBarTheme(
//           backgroundColor: AppColors.primaryColor,
//           foregroundColor: Colors.white,
//           elevation: 0,
//           titleTextStyle: GoogleFonts.poppins(
//             fontSize: 20,
//             fontWeight: FontWeight.w600,
//             color: Colors.white,
//           ),
//           iconTheme: const IconThemeData(color: Colors.white),
//         ),
//         cardTheme: CardTheme(
//           color: Colors.white,
//           elevation: 2,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//           margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
//         ),
//         elevatedButtonTheme: ElevatedButtonThemeData(
//           style: ElevatedButton.styleFrom(
//             backgroundColor: AppColors.primaryColor,
//             foregroundColor: Colors.white,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//             padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
//             textStyle: GoogleFonts.poppins(
//               fontSize: 16,
//               fontWeight: FontWeight.w600,
//             ),
//             elevation: 2,
//           ),
//         ),
//         inputDecorationTheme: InputDecorationTheme(
//           filled: true,
//           fillColor: Colors.grey.shade100,
//           border: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12), // Rounded text fields
//             borderSide: BorderSide.none,
//           ),
//           enabledBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: Colors.grey.shade300),
//           ),
//           focusedBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
//           ),
//           errorBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: AppColors.errorColor, width: 2),
//           ),
//           focusedErrorBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: AppColors.errorColor, width: 2),
//           ),
//           labelStyle: const TextStyle(color: Colors.black54),
//           hintStyle: const TextStyle(color: Colors.black38),
//           prefixIconColor: Colors.black54,
//         ),
//       ),
//       home: const LoginPage(),
//       routes: {
//         '/login': (context) => const LoginPage(),
//         '/signup': (context) => const SignUpPage(),
//       },
//       initialRoute: '/login',
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:waas/colors/colors.dart';
import 'package:waas/widget/login.dart';
import 'package:waas/widget/signup_page.dart';
import 'package:waas/widget/main_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:waas/assets/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final storage = const FlutterSecureStorage();
  Widget? initialPage;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    print('Starting login status check');
    try {
      final token = await storage.read(key: 'jwt_token');
      print('Token on startup: $token');
      if (token != null) {
        print('Token found, fetching profile');
        final response = await http.get(
          Uri.parse('$apiBaseUrl/profile/profile'),
          headers: {'Authorization': 'Bearer $token'},
        );
        print('Profile fetch status: ${response.statusCode}');
        print('Profile fetch body: ${response.body}');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          print('Profile data: $data');
          final user = data['user'];
          if (user == null) throw Exception('No user object in response');
          final userID =
              user['userid'] as int? ??
              (throw Exception('No userid in response'));
          final role =
              user['role'] as String? ??
              (throw Exception('No role in response'));
          print(
            'Setting initialPage to MainPage with userID: $userID, role: $role',
          );
          setState(() {
            initialPage = MainPage(userID: userID, role: role);
          });
        } else {
          print(
            'Profile fetch failed, clearing token and redirecting to login',
          );
          await storage.delete(key: 'jwt_token');
          setState(() {
            initialPage = const LoginPage();
          });
        }
      } else {
        print('No token found, setting initialPage to LoginPage');
        setState(() {
          initialPage = const LoginPage();
        });
      }
    } catch (e) {
      print('Error during login check: $e');
      setState(() {
        initialPage = const LoginPage();
      });
    }
    print('Initial page set to: ${initialPage.runtimeType}');
  }

  @override
  Widget build(BuildContext context) {
    print('Building MyApp, initialPage: ${initialPage.runtimeType}');
    if (initialPage == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'Waste Management App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryColor,
          brightness: Brightness.light,
          primary: AppColors.primaryColor,
          secondary: AppColors.secondaryColor,
          background: AppColors.backgroundColor,
          onBackground: AppColors.textColor,
          error: AppColors.errorColor,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.backgroundColor,
        textTheme: GoogleFonts.poppinsTextTheme(
          const TextTheme(
            displayLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            displayMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
            bodyMedium: TextStyle(fontSize: 14, color: Colors.black54),
            labelLarge: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            textStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            elevation: 2,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.errorColor, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.errorColor, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.black54),
          hintStyle: const TextStyle(color: Colors.black38),
          prefixIconColor: Colors.black54,
        ),
      ),
      home: initialPage,
      routes: {
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const SignUpPage(),
      },
    );
  }
}

