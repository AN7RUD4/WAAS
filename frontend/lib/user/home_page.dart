import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Use FlutterSecureStorage
import '../colors/colors.dart'; // Import your theme colors
import 'package:waas/assets/constants.dart';

// Utility widget for buttons
Widget buildButton(String text, Color color, VoidCallback onPressed) {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    onPressed: onPressed,
    child: Text(text, style: const TextStyle(color: Colors.black)),
  );
}

// Utility widget for text fields
Widget buildTextField(
  String label,
  TextEditingController controller, {
  bool readOnly = false,
}) {
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
        readOnly: readOnly,
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

// Main user dashboard page
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
                const CircleAvatar(radius: 25),
                const SizedBox(width: 20),
                Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textColor,
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
                        color: AppColors.textColor,
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
                        backgroundColor: AppColors.accentColor,
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
                        color: AppColors.textColor,
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
                        backgroundColor: AppColors.accentColor,
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
                        color: AppColors.textColor,
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CollectionRequestsPage(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentColor,
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

// Report Page for submitting public waste reports
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  File? _image;
  final TextEditingController locationController = TextEditingController();
  bool _isLoading = false;
  final storage = FlutterSecureStorage(); // Initialize FlutterSecureStorage

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      locationController.text = '${position.latitude},${position.longitude}';
    });
  }

  Future<String?> _getToken() async {
    return await storage.read(key: 'jwt_token');
  }

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

  Future<void> _submitReport() async {
    if (_image == null || locationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please take a photo and provide a location!"),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No token found');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/user/report-waste'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['location'] = locationController.text;
      request.files.add(
        await http.MultipartFile.fromPath('image', _image!.path),
      );

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      print('Response status: ${response.statusCode}');
      print('Response body: $responseBody');

      if (response.statusCode == 201) {
        final data = jsonDecode(responseBody);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Report submitted successfully!")),
        );
        Navigator.pop(context);
      } else {
        try {
          final error =
              jsonDecode(responseBody)['message'] ??
              'Failed to submit report with status ${response.statusCode}';
          throw Exception(error);
        } catch (parseError) {
          throw Exception('Invalid server response: $responseBody');
        }
      }
    } catch (e) {
      print('Error during submit report: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Issue"),
        backgroundColor: AppColors.accentColor,
      ),
      backgroundColor: AppColors.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Take a Picture",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textColor,
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
                          AppColors.buttonColor,
                          _takePicture,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  buildTextField(
                    "Location",
                    locationController,
                    readOnly: true,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: buildButton(
                      "Submit Report",
                      AppColors.accentColor,
                      _submitReport,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// Bin Fill Page for submitting bin fill requests (Updated: Removed availableTime)
class BinFillPage extends StatefulWidget {
  const BinFillPage({super.key});

  @override
  _BinFillPageState createState() => _BinFillPageState();
}

class _BinFillPageState extends State<BinFillPage> {
  bool is80Checked = false;
  bool is100Checked = false;
  final TextEditingController locationController = TextEditingController();
  bool _isLoading = false;
  final storage = FlutterSecureStorage(); // Initialize FlutterSecureStorage

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      locationController.text = '${position.latitude},${position.longitude}';
    });
  }

  Future<String?> _getToken() async {
    return await storage.read(key: 'jwt_token');
  }

  void _updateCheckbox(bool is80Selected) {
    setState(() {
      is80Checked = is80Selected;
      is100Checked = !is80Selected;
    });
  }

  Future<void> _submitBinFill() async {
    if (!is80Checked && !is100Checked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a bin fill level")),
      );
      return;
    }
    if (locationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please provide location"),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No token found');

      final response = await http.post(
        Uri.parse('$apiBaseUrl/user/bin-fill'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'location': locationController.text,
        }),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bin Fill details submitted!")),
        );
        Navigator.pop(context);
      } else {
        try {
          final error =
              jsonDecode(response.body)['message'] ??
              'Failed to submit bin fill with status ${response.statusCode}';
          throw Exception(error);
        } catch (parseError) {
          throw Exception('Invalid server response: ${response.body}');
        }
      }
    } catch (e) {
      print('Error during submit bin fill: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bin Fill Details"),
        backgroundColor: AppColors.accentColor,
      ),
      backgroundColor: AppColors.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTextField(
                    "User Location",
                    locationController,
                    readOnly: true,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Bin Fill Level",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textColor,
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
                  Center(
                    child: buildButton(
                      "Submit",
                      AppColors.accentColor,
                      _submitBinFill,
                    ),
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
          activeColor: AppColors.accentColor,
        ),
        Text(label, style: TextStyle(color: AppColors.textColor)),
      ],
    );
  }
}

// Collection Requests Page to view submitted requests (Updated: Removed availableTime)
class CollectionRequestsPage extends StatefulWidget {
  const CollectionRequestsPage({super.key});

  @override
  _CollectionRequestsPageState createState() => _CollectionRequestsPageState();
}

class _CollectionRequestsPageState extends State<CollectionRequestsPage> {
  List<Map<String, dynamic>> collectionRequests = [];
  List<Map<String, dynamic>> garbageReports = [];
  bool _isLoading = false;
  final storage = FlutterSecureStorage(); // Initialize FlutterSecureStorage

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<String?> _getToken() async {
    return await storage.read(key: 'jwt_token');
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No token found');

      final response = await http.get(
        Uri.parse('$apiBaseUrl/user/collection-requests'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          collectionRequests = List<Map<String, dynamic>>.from(
            data['collectionRequests'],
          );
          garbageReports = List<Map<String, dynamic>>.from(
            data['garbageReports'],
          );
        });
      } else {
        try {
          final error =
              jsonDecode(response.body)['message'] ??
              'Failed to fetch requests with status ${response.statusCode}';
          throw Exception(error);
        } catch (parseError) {
          throw Exception('Invalid server response: ${response.body}');
        }
      }
    } catch (e) {
      print('Error during fetch requests: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Collection Requests"),
        backgroundColor: AppColors.accentColor,
      ),
      backgroundColor: AppColors.backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Collection Requests",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  collectionRequests.isEmpty
                      ? const Text(
                          "No collection requests found.",
                          style: TextStyle(color: AppColors.textColor),
                        )
                      : Expanded(
                          child: ListView.builder(
                            itemCount: collectionRequests.length,
                            itemBuilder: (context, index) {
                              final request = collectionRequests[index];
                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: ListTile(
                                  title: Text(
                                    "Request ID: ${request['requestid']}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Location: ${request['location']}"),
                                      Text("Status: ${request['status']}"),
                                      Text("Time: ${request['datetime']}"),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                  const SizedBox(height: 20),
                  const Text(
                    "Garbage Reports",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  garbageReports.isEmpty
                      ? const Text(
                          "No garbage reports found.",
                          style: TextStyle(color: AppColors.textColor),
                        )
                      : Expanded(
                          child: ListView.builder(
                            itemCount: garbageReports.length,
                            itemBuilder: (context, index) {
                              final report = garbageReports[index];
                              return Card(
                                elevation: 2,
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: ListTile(
                                  title: Text(
                                    "Report ID: ${report['reportid']}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Location: ${report['location']}"),
                                      Text("Status: ${report['status']}"),
                                      Text("Time: ${report['datetime']}"),
                                      report['imageurl'] != null
                                          ? Image.network(
                                              report['imageurl'],
                                              height: 100,
                                              errorBuilder: (context, error, stackTrace) =>
                                                  const Text("Image unavailable"),
                                            )
                                          : const Text("No Image"),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}