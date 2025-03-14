import 'package:flutter/material.dart';
import '../colors/colors.dart'; // Import your theme colors
import 'package:image_picker/image_picker.dart';
import 'dart:io';

Widget buildButton(String text, Color color, VoidCallback onPressed) {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    onPressed: onPressed,
    child: Text(
      text,
      style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0)),
    ),
  );
}

Widget buildTextField(String label, TextEditingController controller) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey.shade800,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          hintText: "Enter $label",
          hintStyle: const TextStyle(color: Colors.white70),
        ),
      ),
    ],
  );
}

class UserApp extends StatelessWidget {
  const UserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(26.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 25),
                SizedBox(width: 20),
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textColor, // Use theme text color
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Report Waste Fill',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textColor, // Use theme text color
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We help keep your home clean by collecting waste fill.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textColor.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BinFillPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.accentColor, // Use theme accent color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Bin Fill'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Report Public Waste',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textColor, // Use theme text color
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Help keep your community clean by reporting waste.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textColor.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReportPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.accentColor, // Use theme accent color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Report Waste'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'View Collection Requests',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textColor, // Use theme text color
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Check the status of your waste collection requests.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textColor.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        // Navigate to collection requests screen
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.accentColor, // Use theme secondary color
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('View Requests'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------- Report Page ---------------------
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  File? _image;
  final TextEditingController locationController = TextEditingController();

  Future<void> _takePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedImage = await picker.pickImage(
      source: ImageSource.camera,
    );

    if (pickedImage != null) {
      setState(() {
        _image = File(pickedImage.path);
      });
    }
  }

  void _submitReport() {
    if (_image == null || locationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please take a photo and enter location!"),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Report submitted successfully!")),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Issue"),
        backgroundColor: AppColors.accentColor, // Use theme accent color
      ),
      backgroundColor: AppColors.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Take a Picture",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textColor, // Use theme text color
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Column(
                children: [
                  _image == null
                      ? const Text(
                        "No Image Taken",
                        style: TextStyle(color: AppColors.textColor),
                      )
                      : Image.file(_image!, height: 200),
                  const SizedBox(height: 10),
                  buildButton(
                    "Open Camera",
                    AppColors.buttonColor, // Use theme button color
                    _takePicture,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            buildTextField("Location", locationController),
            const SizedBox(height: 20),
            Center(
              child: buildButton(
                "Submit Report",
                AppColors.accentColor, // Use theme accent color
                _submitReport,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------- Bin Fill Page ---------------------
class BinFillPage extends StatefulWidget {
  const BinFillPage({super.key});

  @override
  _BinFillPageState createState() => _BinFillPageState();
}

class _BinFillPageState extends State<BinFillPage> {
  bool is80Checked = false;
  bool is100Checked = false;
  final TextEditingController locationController = TextEditingController();
  final TextEditingController timeController = TextEditingController();

  void _updateCheckbox(bool is80Selected) {
    setState(() {
      is80Checked = is80Selected;
      is100Checked = !is80Selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bin Fill Details"),
        backgroundColor: AppColors.accentColor, // Use theme accent color
      ),
      backgroundColor: AppColors.backgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildTextField("User Location", locationController),
            const SizedBox(height: 20),
            const Text(
              "Bin Fill Level",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textColor, // Use theme text color
              ),
            ),
            buildCheckbox(
              "80% Bin Fill",
              is80Checked,
              () => _updateCheckbox(true),
            ),
            buildCheckbox(
              "100% Bin Fill",
              is100Checked,
              () => _updateCheckbox(false),
            ),
            const SizedBox(height: 20),
            buildTextField("Available Time", timeController),
            const SizedBox(height: 20),
            Center(
              child: buildButton("Submit", AppColors.accentColor, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Bin Fill details submitted!")),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildCheckbox(String label, bool value, VoidCallback onChanged) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: (val) => onChanged(),
          activeColor: AppColors.accentColor, // Use theme accent color
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.textColor),
        ), // Use theme text color
      ],
    );
  }
}
