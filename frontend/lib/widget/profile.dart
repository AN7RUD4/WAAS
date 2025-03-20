import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:waas/assets/constants.dart';

class ApiService {
  static const storage = FlutterSecureStorage();

  static Future<String?> getToken() async {
    return await storage.read(key: 'jwt_token');
  }

  Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    if (token == null) {
      throw Exception('No token found. Please log in again.');
    }

    print('Token: $token');
    print('Requesting URL: $apiBaseUrl/profile/profile');

    final response = await http.get(
      Uri.parse('$apiBaseUrl/profile/profile'),
      headers: {'Authorization': 'Bearer $token'},
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 403 || response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception(
        'Failed to load profile: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> updateProfile(String name, String email) async {
    // Input validation
    if (name.trim().isEmpty || email.trim().isEmpty) {
      throw Exception('Name and email are required');
    }
    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      throw Exception('Invalid email format');
    }

    final token = await getToken();
    if (token == null) {
      throw Exception('No token found. Please log in again.');
    }

    print('Token: $token');
    print('Requesting URL: $apiBaseUrl/profile/profile');

    final response = await http.put(
      Uri.parse('$apiBaseUrl/profile/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'name': name, 'email': email}),
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      final newToken = responseData['token'];
      if (newToken != null) {
        await storage.write(key: 'jwt_token', value: newToken);
        print('New token stored: $newToken');
      }
      return responseData;
    } else if (response.statusCode == 403 || response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception(
        'Failed to update profile: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<void> changePassword(String newPassword) async {
    // Input validation
    if (newPassword.isEmpty) {
      throw Exception('New password is required');
    }
    if (newPassword.length < 8 ||
        !RegExp(r'^(?=.*[A-Z])(?=.*[0-9])').hasMatch(newPassword)) {
      throw Exception(
        'Password must be at least 8 characters with one uppercase letter and one number',
      );
    }

    final token = await getToken();
    if (token == null) {
      throw Exception('No token found. Please log in again.');
    }

    print('Token: $token');
    print('Requesting URL: $apiBaseUrl/profile/change-password');

    final response = await http.put(
      Uri.parse('$apiBaseUrl/profile/change-password'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'newPassword': newPassword}),
    );

    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      final newToken = responseData['token'];
      if (newToken != null) {
        await storage.write(key: 'jwt_token', value: newToken);
        print('New token stored: $newToken');
      }
      return;
    } else if (response.statusCode == 403 || response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception(
        'Failed to change password: ${response.statusCode} - ${response.body}',
      );
    }
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = "Loading...";
  String email = "Loading...";
  final apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await apiService.getProfile();
      setState(() {
        name = profile['user']['name'] ?? 'Unknown';
        email = profile['user']['email'] ?? 'Unknown';
      });
    } catch (e) {
      if (e.toString().contains('Session expired')) {
        await ApiService.storage.delete(key: 'jwt_token');
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      } else {
        setState(() {
          name = 'Error';
          email = 'Error';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to load profile: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile Page',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 30),
            onPressed: () async {
              final updatedData = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => EditProfilePage(
                        currentName: name,
                        currentEmail: email,
                      ),
                ),
              );

              if (updatedData != null) {
                setState(() {
                  name = updatedData['name'];
                  email = updatedData['email'];
                });
                await _loadProfile(); // Refresh from database
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text("Name"),
                    subtitle: Text(name, style: const TextStyle(fontSize: 18)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.email),
                    title: const Text("Email"),
                    subtitle: Text(email, style: const TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ChangePasswordPage(),
                  ),
                ); // Removed .then((_) => _loadProfile())
              },
              child: const Text('Change Password'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(builder: (context) => const CollectionRequestsPage()),
                // );
              },
              child: const Text("View Report History"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await ApiService.storage.delete(key: 'jwt_token');
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (route) => false,
                );
              },
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final String currentName;
  final String currentEmail;

  const EditProfilePage({
    required this.currentName,
    required this.currentEmail,
    super.key,
  });

  @override
  _EditProfilePageState createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController nameController;
  late TextEditingController emailController;
  final apiService = ApiService();

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    emailController = TextEditingController(text: widget.currentEmail);
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "Email",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  await apiService.updateProfile(
                    nameController.text.trim(),
                    emailController.text.trim(),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Profile updated successfully"),
                    ),
                  );
                  Navigator.pop(context, {
                    'name': nameController.text.trim(),
                    'email': emailController.text.trim(),
                  });
                } catch (e) {
                  if (e.toString().contains('Session expired')) {
                    await ApiService.storage.delete(key: 'jwt_token');
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to update profile: $e")),
                    );
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  _ChangePasswordPageState createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final apiService = ApiService();

  @override
  void dispose() {
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Change Password"),
        backgroundColor: Colors.green,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "New Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Confirm Password",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () async {
                String newPassword = newPasswordController.text.trim();
                String confirmPassword = confirmPasswordController.text.trim();

                if (newPassword.isEmpty || confirmPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill in both fields")),
                  );
                  return;
                }

                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Passwords do not match")),
                  );
                  return;
                }

                try {
                  await apiService.changePassword(newPassword);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Password Changed Successfully"),
                    ),
                  );
                  Navigator.pop(context);
                } catch (e) {
                  if (e.toString().contains('Session expired')) {
                    await ApiService.storage.delete(key: 'jwt_token');
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/login',
                      (route) => false,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Failed to change password: $e")),
                    );
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportHistoryPage extends StatelessWidget {
  const ReportHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report History"),
        backgroundColor: Colors.green,
      ),
      body: const Center(
        child: Text(
          "Report History Page",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
