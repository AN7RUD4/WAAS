import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:waas/widget/main_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:waas/assets/constants.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart'; // Added geolocator package

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

  Future<void> _updateStatus(String token, String status) async {
    try {
      final response = await http.put(
        Uri.parse('$apiBaseUrl/profile/update-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
      if (response.statusCode != 200) {
        print('Failed to update status: ${response.body}');
      } else {
        print('Status updated to: $status');
      }
    } catch (e) {
      print('Error updating status: $e');
    }
  }

  // New method to get device location
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable them.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permissions are permanently denied. Please enable them in settings.');
    }

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  // New method to update worker location
// Enhanced with better error handling
Future<void> _updateWorkerLocation(String token, int userId) async {
  try {
    final position = await _determinePosition();
    print('📍 Obtained device location: ${position.latitude},${position.longitude}');

    final response = await http.post(
      Uri.parse('$apiBaseUrl/worker/update-worker-location'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'userId': userId,
        'lat': position.latitude,    // Y coordinate
        'lng': position.longitude,   // X coordinate
      }),
    );

    print('🔁 Update response: ${response.statusCode} - ${response.body}');
    
    if (response.statusCode != 200) {
      throw Exception('Failed to update: ${response.body}');
    }

    // Verify update by querying new location
    final verifyResponse = await http.get(
      Uri.parse('$apiBaseUrl/worker/location?userId=$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    
    print('✅ Verified location: ${verifyResponse.body}');
  } catch (e) {
    print('❌ Location update failed: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Location update failed: ${e.toString()}')),
    );
    rethrow;
  }
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
    print('Login process started for email: ${usernameController.text.trim()}');

    try {
      final jsonData = {
        'email': usernameController.text.trim(),
        'password': passwordController.text.trim(),
      };
      print('Sending login request with email: ${jsonData['email']}');
      final response = await http.post(
        Uri.parse('$apiBaseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(jsonData),
      );

      print('Login response status: ${response.statusCode}');
      if (!mounted) {
        print('Widget unmounted during login response');
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        print('Login response received, token: $token');
        if (token != null) {
          await storage.write(key: 'jwt_token', value: token);
          print('Token stored: $token');

          // Attempt to update status to 'available'
          print('Attempting to update status to available with token: $token');
          final statusResponse = await http.put(
            Uri.parse('$apiBaseUrl/profile/update-status'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'status': 'available'}),
          );

          print('Status update response status: ${statusResponse.statusCode}');
          print('Status update response body: ${statusResponse.body}');
          if (statusResponse.statusCode == 200) {
            print('Status updated to: available');
          } else {
            print(
              'Failed to update status: ${statusResponse.statusCode} - ${statusResponse.body}',
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to set status: ${statusResponse.body}'),
              ),
            );
            return; // Stop if status update fails
          }
        } else {
          throw Exception('No token received from server');
        }

        final user = data['user'];
        if (user == null) throw Exception('No user data in response');
        final userID =
            user['userid'] as int? ?? (throw Exception('No userid in response'));
        final role = user['role'] as String? ?? 'user';
        print('User logged in: userid=$userID, role=$role');

        // Update location if the user is a worker
        if (role == 'worker') {
          await _updateWorkerLocation(token, userID);
          try {
            print('Initiating assignment for worker $userID');
            final assignResponse = await http.post(
              Uri.parse('$apiBaseUrl/worker/group-and-assign-reports'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'workerId': userID,
                'maxDistance': 30,
                'maxReportsPerWorker': 3,
                'urgencyWindow': '24 hours',
              }),
            );
            print('Assignment Response Status: ${assignResponse.statusCode}');
            print('Assignment Response Body: ${assignResponse.body}');
            if (assignResponse.statusCode != 200) {
              throw Exception('Assignment failed: ${assignResponse.body}');
            }
          } catch (e) {
            print('🔥 Critical Assignment Error: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Task assignment failed: $e')),
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
        print('Login failed: $errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      print('Login error caught: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Network error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
      print('Login process completed');
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
                Text(
                  "wAAS",
                  style: GoogleFonts.poppins(
                    fontSize: screenWidth * 0.12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                SizedBox(height: screenHeight * 0.05),
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
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed('/signup');
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

class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
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