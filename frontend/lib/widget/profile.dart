// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'dart:convert';

// import 'package:waas/assets/constants.dart';



// class ApiService {
//   static const String baseUrl = apiBaseUrl;
//   static const storage = FlutterSecureStorage();

//   static Future<String?> getToken() async {
//     return await storage.read(key: 'jwt_token');
//   }

//   Future<Map<String, dynamic>> getProfile() async {
//     final token = await getToken();
//     final response = await http.get(
//       Uri.parse('$baseUrl/profile'),
//       headers: {'Authorization': 'Bearer $token'},
//     );

//     if (response.statusCode == 200) {
//       return json.decode(response.body);
//     } else {
//       throw Exception('Failed to load profile: ${response.body}');
//     }
//   }

//   Future<Map<String, dynamic>> updateProfile(String name, String email) async {
//     final token = await getToken();
//     final response = await http.put(
//       Uri.parse('$baseUrl/profile'),
//       headers: {
//         'Authorization': 'Bearer $token',
//         'Content-Type': 'application/json',
//       },
//       body: json.encode({'name': name, 'email': email}),
//     );

//     if (response.statusCode == 200) {
//       return json.decode(response.body);
//     } else {
//       throw Exception('Failed to update profile: ${response.body}');
//     }
//   }

//   Future<void> changePassword(String newPassword) async {
//     final token = await getToken();
//     final response = await http.put(
//       Uri.parse('$baseUrl/change-password'),
//       headers: {
//         'Authorization': 'Bearer $token',
//         'Content-Type': 'application/json',
//       },
//       body: json.encode({'newPassword': newPassword}),
//     );

//     if (response.statusCode != 200) {
//       throw Exception('Failed to change password: ${response.body}');
//     }
//   }
// }

// class ProfilePage extends StatefulWidget {
//   @override
//   _ProfilePageState createState() => _ProfilePageState();
// }

// class _ProfilePageState extends State<ProfilePage> {
//   String name = "Loading...";
//   String email = "Loading...";
//   final apiService = ApiService();

//   @override
//   void initState() {
//     super.initState();
//     _loadProfile();
//   }

//   Future<void> _loadProfile() async {
//     try {
//       final profile = await apiService.getProfile();
//       setState(() {
//         name = profile['name'];
//         email = profile['email'];
//       });
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text("Failed to load profile: $e")),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Profile Page', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
//         backgroundColor: Colors.green,
//         actions: [
//           IconButton(
//             icon: Icon(Icons.edit, size: 30),
//             onPressed: () async {
//               final updatedData = await Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (context) => EditProfilePage(
//                     currentName: name,
//                     currentEmail: email,
//                   ),
//                 ),
//               );

//               if (updatedData != null) {
//                 setState(() {
//                   name = updatedData['name'];
//                   email = updatedData['email'];
//                 });
//                 await _loadProfile(); // Refresh from database
//               }
//             },
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Card(
//               elevation: 2,
//               child: Column(
//                 children: [
//                   ListTile(
//                     leading: Icon(Icons.person),
//                     title: Text("Name"),
//                     subtitle: Text(name, style: TextStyle(fontSize: 18)),
//                   ),
//                   Divider(),
//                   ListTile(
//                     leading: Icon(Icons.email),
//                     title: Text("Email"),
//                     subtitle: Text(email, style: TextStyle(fontSize: 18)),
//                   ),
//                 ],
//               ),
//             ),
//             SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(builder: (context) => ChangePasswordPage()),
//                 ).then((_) => _loadProfile()); // Refresh after password change
//               },
//               child: Text('Change Password'),
//             ),
//             SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(builder: (context) => ReportHistoryPage()),
//                 );
//               },
//               child: Text("View Report History"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class EditProfilePage extends StatefulWidget {
//   final String currentName;
//   final String currentEmail;

//   EditProfilePage({required this.currentName, required this.currentEmail});

//   @override
//   _EditProfilePageState createState() => _EditProfilePageState();
// }

// class _EditProfilePageState extends State<EditProfilePage> {
//   late TextEditingController nameController;
//   late TextEditingController emailController;
//   final apiService = ApiService();

//   @override
//   void initState() {
//     super.initState();
//     nameController = TextEditingController(text: widget.currentName);
//     emailController = TextEditingController(text: widget.currentEmail);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text("Edit Profile"),
//         backgroundColor: Colors.green,
//       ),
//       body: Padding(
//         padding: EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.start,
//           children: [
//             TextField(
//               controller: nameController,
//               decoration: InputDecoration(
//                 labelText: "Name",
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 20),
//             TextField(
//               controller: emailController,
//               decoration: InputDecoration(
//                 labelText: "Email",
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: () async {
//                 try {
//                   await apiService.updateProfile(
//                     nameController.text,
//                     emailController.text,
//                   );
//                   Navigator.pop(context, {
//                     'name': nameController.text,
//                     'email': emailController.text,
//                   });
//                 } catch (e) {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(content: Text("Failed to update profile: $e")),
//                   );
//                 }
//               },
//               child: Text("Save"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class ChangePasswordPage extends StatelessWidget {
//   final TextEditingController newPasswordController = TextEditingController();
//   final TextEditingController confirmPasswordController = TextEditingController();
//   final apiService = ApiService();

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text("Change Password"),
//         backgroundColor: Colors.green,
//       ),
//       body: Padding(
//         padding: EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.start,
//           children: [
//             TextField(
//               controller: newPasswordController,
//               obscureText: true,
//               decoration: InputDecoration(
//                 labelText: "New Password",
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 20),
//             TextField(
//               controller: confirmPasswordController,
//               obscureText: true,
//               decoration: InputDecoration(
//                 labelText: "Confirm Password",
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 30),
//             ElevatedButton(
//               onPressed: () async {
//                 String newPassword = newPasswordController.text;
//                 String confirmPassword = confirmPasswordController.text;

//                 if (newPassword.isEmpty || confirmPassword.isEmpty) {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(content: Text("Please fill in both fields")),
//                   );
//                   return;
//                 }

//                 if (newPassword != confirmPassword) {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(content: Text("Passwords do not match")),
//                   );
//                   return;
//                 }

//                 try {
//                   await apiService.changePassword(newPassword);
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(content: Text("Password Changed Successfully")),
//                   );
//                   Navigator.pop(context);
//                 } catch (e) {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(content: Text("Failed to change password: $e")),
//                   );
//                 }
//               },
//               child: Text("Save"),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class ReportHistoryPage extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text("Report History"),
//         backgroundColor: Colors.green,
//       ),
//       body: Center(
//         child: Text(
//           "Report History Page",
//           style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//         ),
//      ),
// );
// }
// }
