// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'dart:convert';
// import 'package:waas/assets/constants.dart';
// import 'package:google_fonts/google_fonts.dart';

// class ApiService {
//   static const storage = FlutterSecureStorage();

//   static Future<String?> getToken() async {
//     return await storage.read(key: 'jwt_token');
//   }

//   Future<Map<String, dynamic>> getProfile() async {
//     final token = await getToken();
//     if (token == null) throw Exception('No token found. Please log in again.');
//     final response = await http.get(
//       Uri.parse('$apiBaseUrl/profile/profile'),
//       headers: {'Authorization': 'Bearer $token'},
//     );
//     if (response.statusCode == 200) {
//       return jsonDecode(response.body);
//     } else if (response.statusCode == 403 || response.statusCode == 401) {
//       throw Exception('Session expired. Please log in again.');
//     } else {
//       throw Exception(
//         'Failed to load profile: ${response.statusCode} - ${response.body}',
//       );
//     }
//   }

//   Future<void> updateStatus(String status) async {
//     final token = await getToken();
//     if (token == null) return;
//     try {
//       final response = await http.put(
//         Uri.parse('$apiBaseUrl/profile/update-status'),
//         headers: {
//           'Authorization': 'Bearer $token',
//           'Content-Type': 'application/json',
//         },
//         body: jsonEncode({'status': status}),
//       );
//       if (response.statusCode != 200) {
//         print('Failed to update status: ${response.body}');
//       } else {
//         print('Status updated to: $status');
//       }
//     } catch (e) {
//       print('Error updating status: $e');
//     }
//   }

//   Future<Map<String, dynamic>> updateProfile(String name, String email) async {
//     if (name.trim().isEmpty || email.trim().isEmpty) {
//       throw Exception('Name and email are required');
//     }
//     if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
//       throw Exception('Invalid email format');
//     }

//     final token = await getToken();
//     if (token == null) throw Exception('No token found. Please log in again.');

//     final response = await http.put(
//       Uri.parse('$apiBaseUrl/profile/profile'),
//       headers: {
//         'Authorization': 'Bearer $token',
//         'Content-Type': 'application/json',
//       },
//       body: json.encode({'name': name, 'email': email}),
//     );

//     if (response.statusCode == 200) {
//       final responseData = json.decode(response.body);
//       final newToken = responseData['token'];
//       if (newToken != null) {
//         await storage.write(key: 'jwt_token', value: newToken);
//       }
//       return responseData;
//     } else if (response.statusCode == 403 || response.statusCode == 401) {
//       throw Exception('Session expired. Please log in again.');
//     } else {
//       throw Exception(
//         'Failed to update profile: ${response.statusCode} - ${response.body}',
//       );
//     }
//   }

//   Future<void> changePassword(String newPassword) async {
//     if (newPassword.isEmpty) throw Exception('New password is required');
//     if (newPassword.length < 8 ||
//         !RegExp(r'^(?=.*[A-Z])(?=.*[0-9])').hasMatch(newPassword)) {
//       throw Exception(
//         'Password must be at least 8 characters with one uppercase letter and one number',
//       );
//     }

//     final token = await getToken();
//     if (token == null) throw Exception('No token found. Please log in again.');

//     final response = await http.put(
//       Uri.parse('$apiBaseUrl/profile/change-password'),
//       headers: {
//         'Authorization': 'Bearer $token',
//         'Content-Type': 'application/json',
//       },
//       body: json.encode({'newPassword': newPassword}),
//     );

//     if (response.statusCode == 200) {
//       final responseData = json.decode(response.body);
//       final newToken = responseData['token'];
//       if (newToken != null) {
//         await storage.write(key: 'jwt_token', value: newToken);
//       }
//       return;
//     } else if (response.statusCode == 403 || response.statusCode == 401) {
//       throw Exception('Session expired. Please log in again.');
//     } else {
//       throw Exception(
//         'Failed to change password: ${response.statusCode} - ${response.body}',
//       );
//     }
//   }
// }

// class ProfilePage extends StatefulWidget {
//   const ProfilePage({super.key});

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
//         name = profile['user']['name'] ?? 'Unknown';
//         email = profile['user']['email'] ?? 'Unknown';
//       });
//     } catch (e) {
//       if (e.toString().contains('Session expired')) {
//         await ApiService.storage.delete(key: 'jwt_token');
//         Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
//       } else {
//         setState(() {
//           name = 'Error';
//           email = 'Error';
//         });
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text("Failed to load profile: $e")));
//       }
//     }
//   }

//   Future<void> _logout() async {
//     await apiService.updateStatus('busy'); // Set status to "busy" on logout
//     await ApiService.storage.delete(key: 'jwt_token');
//     Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Profile')),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Profile Header with Edit Button
//             Row(
//               children: [
//                 const CircleAvatar(
//                   radius: 40,
//                   backgroundColor: Colors.grey,
//                   child: Icon(Icons.person, size: 50, color: Colors.white),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           Text(
//                             name,
//                             style: GoogleFonts.poppins(
//                               fontSize: 24,
//                               fontWeight: FontWeight.bold,
//                               color: Colors.black87,
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           IconButton(
//                             icon: const Icon(Icons.edit, size: 20),
//                             onPressed: () => _navigateToEditProfile(),
//                           ),
//                         ],
//                       ),
//                       Text(
//                         email,
//                         style: GoogleFonts.poppins(
//                           fontSize: 16,
//                           color: Colors.black54,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 24),

//             // Profile Details Card
//             Card(
//               child: Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Column(
//                   children: [
//                     ListTile(
//                       leading: const Icon(Icons.person, color: Colors.black54),
//                       title: const Text("Name"),
//                       subtitle: Text(
//                         name,
//                         style: const TextStyle(fontSize: 16),
//                       ),
//                     ),
//                     const Divider(),
//                     ListTile(
//                       leading: const Icon(Icons.email, color: Colors.black54),
//                       title: const Text("Email"),
//                       subtitle: Text(
//                         email,
//                         style: const TextStyle(fontSize: 16),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             const SizedBox(height: 16),

//             // Action Buttons
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton.icon(
//                 icon: const Icon(Icons.logout),
//                 label: const Text('Logout'),
//                 onPressed: () async {
//                   _logout();
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _navigateToEditProfile() {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder:
//             (context) =>
//                 EditProfilePage(currentName: name, currentEmail: email),
//       ),
//     ).then((_) => _loadProfile());
//   }
// }

// class EditProfilePage extends StatefulWidget {
//   final String currentName;
//   final String currentEmail;

//   const EditProfilePage({
//     required this.currentName,
//     required this.currentEmail,
//     super.key,
//   });

//   @override
//   _EditProfilePageState createState() => _EditProfilePageState();
// }

// class _EditProfilePageState extends State<EditProfilePage> {
//   late TextEditingController nameController;
//   late TextEditingController emailController;
//   final _formKey = GlobalKey<FormState>();
//   final apiService = ApiService();

//   @override
//   void initState() {
//     super.initState();
//     nameController = TextEditingController(text: widget.currentName);
//     emailController = TextEditingController(text: widget.currentEmail);
//   }

//   @override
//   void dispose() {
//     nameController.dispose();
//     emailController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Edit Profile"),
//         actions: [
//           TextButton(
//             onPressed: _saveProfile,
//             child: const Text('SAVE', style: TextStyle(color: Colors.white)),
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16.0),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             children: [
//               TextFormField(
//                 controller: nameController,
//                 decoration: const InputDecoration(
//                   labelText: "Name",
//                   prefixIcon: Icon(Icons.person),
//                 ),
//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return 'Please enter your name';
//                   }
//                   return null;
//                 },
//               ),
//               const SizedBox(height: 20),
//               TextFormField(
//                 controller: emailController,
//                 decoration: const InputDecoration(
//                   labelText: "Email",
//                   prefixIcon: Icon(Icons.email),
//                 ),
//                 keyboardType: TextInputType.emailAddress,
//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return 'Please enter your email';
//                   }
//                   if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
//                     return 'Please enter a valid email';
//                   }
//                   return null;
//                 },
//               ),
//               const SizedBox(height: 30),
//               Divider(color: Colors.grey[300]),
//               ListTile(
//                 leading: const Icon(Icons.lock),
//                 title: const Text('Change Password'),
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () {
//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(
//                       builder: (context) => const ChangePasswordPage(),
//                     ),
//                   );
//                 },
//               ),
//               Divider(color: Colors.grey[300]),
//               const SizedBox(height: 20),
//               SizedBox(
//                 width: double.infinity,
//                 height: 50,
//                 child: ElevatedButton(
//                   style: ElevatedButton.styleFrom(
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                   ),
//                   onPressed: _saveProfile,
//                   child: const Text('Save Changes'),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Future<void> _saveProfile() async {
//     if (_formKey.currentState!.validate()) {
//       try {
//         await apiService.updateProfile(
//           nameController.text.trim(),
//           emailController.text.trim(),
//         );
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(content: Text("Profile updated successfully")),
//         );
//         Navigator.pop(context);
//       } catch (e) {
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text("Failed to update profile: $e")));
//       }
//     }
//   }
// }

// class ChangePasswordPage extends StatefulWidget {
//   const ChangePasswordPage({super.key});

//   @override
//   _ChangePasswordPageState createState() => _ChangePasswordPageState();
// }

// class _ChangePasswordPageState extends State<ChangePasswordPage> {
//   final TextEditingController newPasswordController = TextEditingController();
//   final TextEditingController confirmPasswordController =
//       TextEditingController();
//   final apiService = ApiService();

//   @override
//   void dispose() {
//     newPasswordController.dispose();
//     confirmPasswordController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Change Password")),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             TextFormField(
//               controller: newPasswordController,
//               obscureText: true,
//               decoration: const InputDecoration(
//                 labelText: "New Password",
//                 prefixIcon: Icon(Icons.lock),
//               ),
//             ),
//             const SizedBox(height: 16),
//             TextFormField(
//               controller: confirmPasswordController,
//               obscureText: true,
//               decoration: const InputDecoration(
//                 labelText: "Confirm Password",
//                 prefixIcon: Icon(Icons.lock),
//               ),
//             ),
//             const SizedBox(height: 24),
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton(
//                 onPressed: () async {
//                   String newPassword = newPasswordController.text.trim();
//                   String confirmPassword =
//                       confirmPasswordController.text.trim();

//                   if (newPassword.isEmpty || confirmPassword.isEmpty) {
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       const SnackBar(
//                         content: Text("Please fill in both fields"),
//                       ),
//                     );
//                     return;
//                   }

//                   if (newPassword != confirmPassword) {
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       const SnackBar(content: Text("Passwords do not match")),
//                     );
//                     return;
//                   }

//                   try {
//                     await apiService.changePassword(newPassword);
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       const SnackBar(
//                         content: Text("Password Changed Successfully"),
//                       ),
//                     );
//                     Navigator.pop(context);
//                   } catch (e) {
//                     if (e.toString().contains('Session expired')) {
//                       await ApiService.storage.delete(key: 'jwt_token');
//                       Navigator.pushNamedAndRemoveUntil(
//                         context,
//                         '/login',
//                         (route) => false,
//                       );
//                     } else {
//                       ScaffoldMessenger.of(context).showSnackBar(
//                         SnackBar(
//                           content: Text("Failed to change password: $e"),
//                         ),
//                       );
//                     }
//                   }
//                 },
//                 child: const Text("Save"),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // class ReportHistoryPage extends StatelessWidget {
// //   const ReportHistoryPage({super.key});

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(title: const Text("Report History")),
// //       body: const Center(
// //         child: Text(
// //           "Report History Page",
// //           style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
// //         ),
// //       ),
// //     );
// //   }
// // }





// // import 'package:flutter/material.dart';
// // import 'package:http/http.dart' as http;
// // import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// // import 'dart:convert';
// // import 'package:waas/assets/constants.dart';
// // import 'package:google_fonts/google_fonts.dart';

// // class ApiService {
// //   static const storage = FlutterSecureStorage();

// //   static Future<String?> getToken() async {
// //     return await storage.read(key: 'jwt_token');
// //   }

// //   Future<Map<String, dynamic>> getProfile() async {
// //     final token = await getToken();
// //     if (token == null) throw Exception('No token found. Please log in again.');

// //     final response = await http.get(
// //       Uri.parse('$apiBaseUrl/profile/profile'),
// //       headers: {'Authorization': 'Bearer $token'},
// //     );

// //     if (response.statusCode == 200) {
// //       return json.decode(response.body);
// //     } else if (response.statusCode == 403 || response.statusCode == 401) {
// //       throw Exception('Session expired. Please log in again.');
// //     } else {
// //       throw Exception('Failed to load profile: ${response.statusCode} - ${response.body}');
// //     }
// //   }

// //   Future<Map<String, dynamic>> updateProfile(String name, String email) async {
// //     if (name.trim().isEmpty || email.trim().isEmpty) {
// //       throw Exception('Name and email are required');
// //     }
// //     if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
// //       throw Exception('Invalid email format');
// //     }

// //     final token = await getToken();
// //     if (token == null) throw Exception('No token found. Please log in again.');

// //     final response = await http.put(
// //       Uri.parse('$apiBaseUrl/profile/profile'),
// //       headers: {
// //         'Authorization': 'Bearer $token',
// //         'Content-Type': 'application/json',
// //       },
// //       body: json.encode({'name': name, 'email': email}),
// //     );

// //     if (response.statusCode == 200) {
// //       final responseData = json.decode(response.body);
// //       final newToken = responseData['token'];
// //       if (newToken != null) {
// //         await storage.write(key: 'jwt_token', value: newToken);
// //       }
// //       return responseData;
// //     } else if (response.statusCode == 403 || response.statusCode == 401) {
// //       throw Exception('Session expired. Please log in again.');
// //     } else {
// //       throw Exception('Failed to update profile: ${response.statusCode} - ${response.body}');
// //     }
// //   }

// //   Future<void> changePassword(String newPassword) async {
// //     if (newPassword.isEmpty) throw Exception('New password is required');
// //     if (newPassword.length < 8 || !RegExp(r'^(?=.*[A-Z])(?=.*[0-9])').hasMatch(newPassword)) {
// //       throw Exception('Password must be at least 8 characters with one uppercase letter and one number');
// //     }

// //     final token = await getToken();
// //     if (token == null) throw Exception('No token found. Please log in again.');

// //     final response = await http.put(
// //       Uri.parse('$apiBaseUrl/profile/change-password'),
// //       headers: {
// //         'Authorization': 'Bearer $token',
// //         'Content-Type': 'application/json',
// //       },
// //       body: json.encode({'newPassword': newPassword}),
// //     );

// //     if (response.statusCode == 200) {
// //       final responseData = json.decode(response.body);
// //       final newToken = responseData['token'];
// //       if (newToken != null) {
// //         await storage.write(key: 'jwt_token', value: newToken);
// //       }
// //       return;
// //     } else if (response.statusCode == 403 || response.statusCode == 401) {
// //       throw Exception('Session expired. Please log in again.');
// //     } else {
// //       throw Exception('Failed to change password: ${response.statusCode} - ${response.body}');
// //     }
// //   }
// // }

// // class ProfilePage extends StatefulWidget {
// //   const ProfilePage({super.key});

// //   @override
// //   _ProfilePageState createState() => _ProfilePageState();
// // }

// // class _ProfilePageState extends State<ProfilePage> {
// //   String name = "Loading...";
// //   String email = "Loading...";
// //   final apiService = ApiService();

// //   @override
// //   void initState() {
// //     super.initState();
// //     _loadProfile();
// //   }

// //   Future<void> _loadProfile() async {
// //     try {
// //       final profile = await apiService.getProfile();
// //       setState(() {
// //         name = profile['user']['name'] ?? 'Unknown';
// //         email = profile['user']['email'] ?? 'Unknown';
// //       });
// //     } catch (e) {
// //       if (e.toString().contains('Session expired')) {
// //         await ApiService.storage.delete(key: 'jwt_token');
// //         Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
// //       } else {
// //         setState(() {
// //           name = 'Error';
// //           email = 'Error';
// //         });
// //         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load profile: $e")));
// //       }
// //     }
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text('Profile'),
// //       ),
// //       body: Padding(
// //         padding: const EdgeInsets.all(16.0),
// //         child: Column(
// //           crossAxisAlignment: CrossAxisAlignment.start,
// //           children: [
// //             // Profile Header
// //             Row(
// //               children: [
// //                 const CircleAvatar(
// //                   radius: 40,
// //                   backgroundColor: Colors.grey,
// //                   child: Icon(Icons.person, size: 50, color: Colors.white),
// //                 ),
// //                 const SizedBox(width: 16),
// //                 Column(
// //                   crossAxisAlignment: CrossAxisAlignment.start,
// //                   children: [
// //                     Text(
// //                       name,
// //                       style: GoogleFonts.poppins(
// //                         fontSize: 24,
// //                         fontWeight: FontWeight.bold,
// //                         color: Colors.black87,
// //                       ),
// //                     ),
// //                     Text(
// //                       email,
// //                       style: GoogleFonts.poppins(
// //                         fontSize: 16,
// //                         color: Colors.black54,
// //                       ),
// //                     ),
// //                   ],
// //                 ),
// //               ],
// //             ),
// //             const SizedBox(height: 24),
// //             // Profile Details Card
// //             Card(
// //               child: Padding(
// //                 padding: const EdgeInsets.all(16.0),
// //                 child: Column(
// //                   children: [
// //                     ListTile(
// //                       leading: const Icon(Icons.person, color: Colors.black54),
// //                       title: const Text("Name"),
// //                       subtitle: Text(name, style: const TextStyle(fontSize: 16)),
// //                     ),
// //                     const Divider(),
// //                     ListTile(
// //                       leading: const Icon(Icons.email, color: Colors.black54),
// //                       title: const Text("Email"),
// //                       subtitle: Text(email, style: const TextStyle(fontSize: 16)),
// //                     ),
// //                   ],
// //                 ),
// //               ),
// //             ),
// //             const SizedBox(height: 16),
// //             // Action Buttons
// //             SizedBox(
// //               width: double.infinity,
// //               child: ElevatedButton.icon(
// //                 icon: const Icon(Icons.edit),
// //                 label: const Text('Edit Profile'),
// //                 onPressed: () async {
// //                   final updatedData = await Navigator.push(
// //                     context,
// //                     MaterialPageRoute(
// //                       builder: (context) => EditProfilePage(
// //                         currentName: name,
// //                         currentEmail: email,
// //                       ),
// //                     ),
// //                   );

// //                   if (updatedData != null) {
// //                     setState(() {
// //                       name = updatedData['name'];
// //                       email = updatedData['email'];
// //                     });
// //                     await _loadProfile();
// //                   }
// //                 },
// //               ),
// //             ),
// //             const SizedBox(height: 8),
// //             SizedBox(
// //               width: double.infinity,
// //               child: ElevatedButton.icon(
// //                 icon: const Icon(Icons.lock),
// //                 label: const Text('Change Password'),
// //                 onPressed: () {
// //                   Navigator.push(
// //                     context,
// //                     MaterialPageRoute(builder: (context) => const ChangePasswordPage()),
// //                   );
// //                 },
// //               ),
// //             ),
// //             const SizedBox(height: 8),
// //             SizedBox(
// //               width: double.infinity,
// //               child: ElevatedButton.icon(
// //                 icon: const Icon(Icons.history),
// //                 label: const Text('View Report History'),
// //                 onPressed: () {
// //                   // Navigator.push(
// //                   //   context,
// //                   //   MaterialPageRoute(builder: (context) => const CollectionRequestsPage()),
// //                   // );
// //                 },
// //               ),
// //             ),
// //             const SizedBox(height: 8),
// //             SizedBox(
// //               width: double.infinity,
// //               child: ElevatedButton.icon(
// //                 icon: const Icon(Icons.logout),
// //                 label: const Text('Logout'),
// //                 onPressed: () async {
// //                   await ApiService.storage.delete(key: 'jwt_token');
// //                   Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
// //                 },
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// // }

// // class EditProfilePage extends StatefulWidget {
// //   final String currentName;
// //   final String currentEmail;

// //   const EditProfilePage({
// //     required this.currentName,
// //     required this.currentEmail,
// //     super.key,
// //   });

// //   @override
// //   _EditProfilePageState createState() => _EditProfilePageState();
// // }

// // class _EditProfilePageState extends State<EditProfilePage> {
// //   late TextEditingController nameController;
// //   late TextEditingController emailController;
// //   final apiService = ApiService();

// //   @override
// //   void initState() {
// //     super.initState();
// //     nameController = TextEditingController(text: widget.currentName);
// //     emailController = TextEditingController(text: widget.currentEmail);
// //   }

// //   @override
// //   void dispose() {
// //     nameController.dispose();
// //     emailController.dispose();
// //     super.dispose();
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text("Edit Profile"),
// //       ),
// //       body: Padding(
// //         padding: const EdgeInsets.all(16.0),
// //         child: Column(
// //           crossAxisAlignment: CrossAxisAlignment.start,
// //           children: [
// //             TextFormField(
// //               controller: nameController,
// //               decoration: const InputDecoration(
// //                 labelText: "Name",
// //                 prefixIcon: Icon(Icons.person),
// //               ),
// //             ),
// //             const SizedBox(height: 16),
// //             TextFormField(
// //               controller: emailController,
// //               decoration: const InputDecoration(
// //                 labelText: "Email",
// //                 prefixIcon: Icon(Icons.email),
// //               ),
// //               keyboardType: TextInputType.emailAddress,
// //             ),
// //             const SizedBox(height: 24),
// //             SizedBox(
// //               width: double.infinity,
// //               child: ElevatedButton(
// //                 onPressed: () async {
// //                   try {
// //                     await apiService.updateProfile(
// //                       nameController.text.trim(),
// //                       emailController.text.trim(),
// //                     );
// //                     ScaffoldMessenger.of(context).showSnackBar(
// //                       const SnackBar(content: Text("Profile updated successfully")),
// //                     );
// //                     Navigator.pop(context, {
// //                       'name': nameController.text.trim(),
// //                       'email': emailController.text.trim(),
// //                     });
// //                   } catch (e) {
// //                     if (e.toString().contains('Session expired')) {
// //                       await ApiService.storage.delete(key: 'jwt_token');
// //                       Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
// //                     } else {
// //                       ScaffoldMessenger.of(context).showSnackBar(
// //                         SnackBar(content: Text("Failed to update profile: $e")),
// //                       );
// //                     }
// //                   }
// //                 },
// //                 child: const Text("Save"),
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// // }

// // class ChangePasswordPage extends StatefulWidget {
// //   const ChangePasswordPage({super.key});

// //   @override
// //   _ChangePasswordPageState createState() => _ChangePasswordPageState();
// // }

// // class _ChangePasswordPageState extends State<ChangePasswordPage> {
// //   final TextEditingController newPasswordController = TextEditingController();
// //   final TextEditingController confirmPasswordController = TextEditingController();
// //   final apiService = ApiService();

// //   @override
// //   void dispose() {
// //     newPasswordController.dispose();
// //     confirmPasswordController.dispose();
// //     super.dispose();
// //   }

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text("Change Password"),
// //       ),
// //       body: Padding(
// //         padding: const EdgeInsets.all(16.0),
// //         child: Column(
// //           crossAxisAlignment: CrossAxisAlignment.start,
// //           children: [
// //             TextFormField(
// //               controller: newPasswordController,
// //               obscureText: true,
// //               decoration: const InputDecoration(
// //                 labelText: "New Password",
// //                 prefixIcon: Icon(Icons.lock),
// //               ),
// //             ),
// //             const SizedBox(height: 16),
// //             TextFormField(
// //               controller: confirmPasswordController,
// //               obscureText: true,
// //               decoration: const InputDecoration(
// //                 labelText: "Confirm Password",
// //                 prefixIcon: Icon(Icons.lock),
// //               ),
// //             ),
// //             const SizedBox(height: 24),
// //             SizedBox(
// //               width: double.infinity,
// //               child: ElevatedButton(
// //                 onPressed: () async {
// //                   String newPassword = newPasswordController.text.trim();
// //                   String confirmPassword = confirmPasswordController.text.trim();

// //                   if (newPassword.isEmpty || confirmPassword.isEmpty) {
// //                     ScaffoldMessenger.of(context).showSnackBar(
// //                       const SnackBar(content: Text("Please fill in both fields")),
// //                     );
// //                     return;
// //                   }

// //                   if (newPassword != confirmPassword) {
// //                     ScaffoldMessenger.of(context).showSnackBar(
// //                       const SnackBar(content: Text("Passwords do not match")),
// //                     );
// //                     return;
// //                   }

// //                   try {
// //                     await apiService.changePassword(newPassword);
// //                     ScaffoldMessenger.of(context).showSnackBar(
// //                       const SnackBar(content: Text("Password Changed Successfully")),
// //                     );
// //                     Navigator.pop(context);
// //                   } catch (e) {
// //                     if (e.toString().contains('Session expired')) {
// //                       await ApiService.storage.delete(key: 'jwt_token');
// //                       Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
// //                     } else {
// //                       ScaffoldMessenger.of(context).showSnackBar(
// //                         SnackBar(content: Text("Failed to change password: $e")),
// //                       );
// //                     }
// //                   }
// //                 },
// //                 child: const Text("Save"),
// //               ),
// //             ),
// //           ],
// //         ),
// //       ),
// //     );
// //   }
// // }

// // class ReportHistoryPage extends StatelessWidget {
// //   const ReportHistoryPage({super.key});

// //   @override
// //   Widget build(BuildContext context) {
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: const Text("Report History"),
// //       ),
// //       body: const Center(
// //         child: Text(
// //           "Report History Page",
// //           style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
// //         ),
// //       ),
// //     );
// //   }
// // }

//anirudh  07 04 7 manikk ayachath
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:waas/assets/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class ApiService {
  static const storage = FlutterSecureStorage();

  static Future<String?> getToken() async {
    return await storage.read(key: 'jwt_token');
  }

  Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    if (token == null) throw Exception('No token found. Please log in again.');

    final response = await http.get(
      Uri.parse('$apiBaseUrl/profile/profile'),
      headers: {'Authorization': 'Bearer $token'},
    );

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
    if (name.trim().isEmpty || email.trim().isEmpty) {
      throw Exception('Name and email are required');
    }
    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      throw Exception('Invalid email format');
    }

    final token = await getToken();
    if (token == null) throw Exception('No token found. Please log in again.');

    final response = await http.put(
      Uri.parse('$apiBaseUrl/profile/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'name': name, 'email': email}),
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      final newToken = responseData['token'];
      if (newToken != null) {
        await storage.write(key: 'jwt_token', value: newToken);
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
    if (newPassword.isEmpty) throw Exception('New password is required');
    if (newPassword.length < 8 ||
        !RegExp(r'^(?=.*[A-Z])(?=.*[0-9])').hasMatch(newPassword)) {
      throw Exception(
        'Password must be at least 8 characters with one uppercase letter and one number',
      );
    }

    final token = await getToken();
    if (token == null) throw Exception('No token found. Please log in again.');

    final response = await http.put(
      Uri.parse('$apiBaseUrl/profile/change-password'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'newPassword': newPassword}),
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      final newToken = responseData['token'];
      if (newToken != null) {
        await storage.write(key: 'jwt_token', value: newToken);
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

  Future<void> updateStatus(String status) async {
    final token = await getToken();
    if (token == null) return; // Silently fail if no token

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
      }
    } catch (e) {
      print('Error updating status: $e');
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

  Future<void> _logout() async {
    await apiService.updateStatus('busy');
    await ApiService.storage.delete(key: 'jwt_token');
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      email,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person, color: Colors.black54),
                      title: const Text("Name"),
                      subtitle: Text(
                        name,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.email, color: Colors.black54),
                      title: const Text("Email"),
                      subtitle: Text(
                        email,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Edit Profile'),
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
                    await _loadProfile();
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.lock),
                label: const Text('Change Password'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChangePasswordPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // SizedBox(
            //   width: double.infinity,
            //   child: ElevatedButton.icon(
            //     icon: const Icon(Icons.history),
            //     label: const Text('View Report History'),
            //     onPressed: () {
            //       // Navigator.push(context, MaterialPageRoute(builder: (context) => const CollectionRequestsPage()));
            //     },
            //   ),
            // ),
            // const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                onPressed: _logout,
              ),
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
      appBar: AppBar(title: const Text("Edit Profile")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "Name",
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "Email",
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
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
      appBar: AppBar(title: const Text("Change Password")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "New Password",
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Confirm Password",
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  String newPassword = newPasswordController.text.trim();
                  String confirmPassword =
                      confirmPasswordController.text.trim();

                  if (newPassword.isEmpty || confirmPassword.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please fill in both fields"),
                      ),
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
                        SnackBar(
                          content: Text("Failed to change password: $e"),
                        ),
                      );
                    }
                  }
                },
                child: const Text("Save"),
              ),
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
      appBar: AppBar(title: const Text("Report History")),
      body: const Center(
        child: Text(
          "Report History Page",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}