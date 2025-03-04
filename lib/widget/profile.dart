// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'dart:io';


// class Profile extends StatefulWidget {
//   const Profile({super.key});

//   @override
//   _ProfileState createState() => _ProfileState();
// }

// class _ProfileState extends State<Profile> {
//   File? _image;
//   final picker = ImagePicker();

//   // Dummy Data
//   TextEditingController nameController = TextEditingController(text: "Vijay");
//   TextEditingController emailController = TextEditingController(text: "vijay@email.com");
//   TextEditingController addressController = TextEditingController(text: "123 Street, City, Country");
//   TextEditingController passwordController = TextEditingController();

//   List<String> reportHistory = [
//     "Blood Test - 01 Jan 2024",
//     "X-Ray - 15 Feb 2024",
//     "MRI Scan - 10 Mar 2024",
//   ];

//   // Pick Image Function
//   Future getImage() async {
//     final pickedFile = await picker.pickImage(source: ImageSource.gallery);
//     if (pickedFile != null) {
//       setState(() {
//         _image = File(pickedFile.path);
//       });
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text("Profile Page")),
//       body: SingleChildScrollView(
//         padding: EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Profile Image
//             Center(
//               child: GestureDetector(
//                 onTap: getImage,
//                 child: CircleAvatar(
//                   radius: 50,
//                   backgroundImage: _image != null ? FileImage(_image!) : AssetImage("assets/default_avatar.png") as ImageProvider,
//                   child: _image == null ? Icon(Icons.camera_alt, size: 50, color: Colors.grey) : null,
//                 ),
//               ),
//             ),
//             SizedBox(height: 20),

//             // Name Field
//             TextField(
//               controller: nameController,
//               decoration: InputDecoration(labelText: "Name", border: OutlineInputBorder()),
//             ),
//             SizedBox(height: 10),

//             // Email Field
//             TextField(
//               controller: emailController,
//               decoration: InputDecoration(labelText: "Email", border: OutlineInputBorder()),
//             ),
//             SizedBox(height: 10),

//             // Address Field
//             TextField(
//               controller: addressController,
//               decoration: InputDecoration(labelText: "Address", border: OutlineInputBorder()),
//             ),
//             SizedBox(height: 20),

//             // Password Change
//             TextField(
//               controller: passwordController,
//               obscureText: true,
//               decoration: InputDecoration(labelText: "New Password", border: OutlineInputBorder()),
//             ),
//             SizedBox(height: 10),

//             ElevatedButton(
//               onPressed: () {
//                 // Logic to update password
//                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Password Updated")));
//               },
//               child: Text("Change Password"),
//             ),
//             SizedBox(height: 20),

           
//           ],
//         ),
//      ),
// );
// }
// }
