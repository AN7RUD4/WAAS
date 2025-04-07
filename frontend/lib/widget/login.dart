import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:waas/widget/main_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:waas/assets/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  final storage = const FlutterSecureStorage();

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }


  Future<void> login() async {
    if (usernameController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both username and password'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final jsonData = {
        'email': usernameController.text.trim(),
        'password': passwordController.text.trim(),
      };
      final response = await http.post(
        Uri.parse('$apiBaseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(jsonData),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        if (token != null) {
          await storage.write(key: 'jwt_token', value: token);
        } else {
          throw Exception('No token received from server');
        }

        final user = data['user'];
        if (user == null) throw Exception('No user data in response');
        final userID =
            user['userid'] as int? ??
            (throw Exception('No userid in response'));
        final role =
            user['role'] as String? ?? (throw Exception('No role in response'));

        if (role == 'worker') {
          try {
            final assignResponse = await http.post(
              Uri.parse('$apiBaseUrl/worker/group-and-assign-reports'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'workerId': data['user']['userid']}),
            );

            print('Assignment Response Status: ${assignResponse.statusCode}');
            print('Assignment Response Body: ${assignResponse.body}');

            if (assignResponse.statusCode != 200) {
              throw Exception('Assignment failed: ${assignResponse.body}');
            }
          } catch (e) {
            print('🔥 Critical Assignment Error: $e');
            // Optional: Show error to user if critical
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Task assignment failed: ${e.toString()}'),
              ),
            );
          }
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainPage(userID: userID, role: role),
          ),
        );
      } else {
        final errorMessage =
            jsonDecode(response.body)['message'] ?? 'Login failed';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Network error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Green Triangle (Top Left)
                Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    width: screenWidth * 0.4,
                    height: screenWidth * 0.4,
                    child: CustomPaint(
                      painter: TrianglePainter(color: Colors.green),
                      size: Size(screenWidth * 0.4, screenWidth * 0.4),
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.1),

                // App Name
                Text(
                  "wAAS",
                  style: GoogleFonts.poppins(
                    fontSize: screenWidth * 0.12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),

                SizedBox(height: screenHeight * 0.05),

                // Login Form
                Container(
                  width: screenWidth * 0.85,
                  padding: EdgeInsets.all(screenWidth * 0.05),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Username Field
                      TextField(
                        controller: usernameController,
                        decoration: InputDecoration(
                          labelText: "Username",
                          labelStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                          suffixIcon: Icon(
                            Icons.person_outline,
                            color: Colors.black,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.green),
                          ),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.02),

                      // Password Field
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: "password",
                          labelStyle: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                          suffixIcon: Icon(
                            Icons.lock_outline,
                            color: Colors.black,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.green),
                          ),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.05),

                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        height: screenHeight * 0.06,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: _isLoading ? null : login,
                          child: Text(
                            "LOGIN",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: screenHeight * 0.02),

                      // Sign Up Link
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushReplacementNamed('/signup');
                          },
                          child: Text(
                            "Don't have an account? Sign Up",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

// Custom painter to create a green triangle in the top left
class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

