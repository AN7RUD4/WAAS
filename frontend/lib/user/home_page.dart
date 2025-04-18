import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../colors/colors.dart';
import 'package:waas/assets/constants.dart';
import 'package:google_fonts/google_fonts.dart';

// Main user dashboard page
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../colors/colors.dart';
import 'package:waas/assets/constants.dart';
import 'package:google_fonts/google_fonts.dart';

// Main user dashboard page (unchanged)
class UserApp extends StatelessWidget {
  const UserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Welcome Back!",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        "Manage your waste reports",
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
              // Actions
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Report Waste Fill',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We help keep your home clean by collecting waste fill.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const BinFillPage(),
                              ),
                            );
                          },
                          child: const Text('Bin Fill'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'Report Public Waste',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Help keep your community clean by reporting waste.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ReportPage(),
                              ),
                            );
                          },
                          child: const Text('Report Waste'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        'View Collection Requests',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check the status of your waste collection requests.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => const CollectionRequestsPage(),
                              ),
                            );
                          },
                          child: const Text('View Requests'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  File? _image;
  final TextEditingController locationController = TextEditingController();
  bool _isLoading = false;
  final storage = const FlutterSecureStorage();
  String? _errorMessage;
  bool? _hasWaste;
  String? _backgroundRemovedImage;
  List<dynamic>? _detectionDetails;

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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permissions are permanently denied'),
        ),
      );
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          locationController.text =
              '${position.latitude},${position.longitude}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: ${e.toString()}')),
      );
    }
  }

  Future<String?> _getToken() async {
    return await storage.read(key: 'jwt_token');
  }

  Future<void> _handleTokenExpiration() async {
    await storage.delete(key: 'jwt_token');
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session expired. Please log in again.')),
    );
  }

  Future<void> _detectWaste() async {
    if (_image == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasWaste = null;
      _backgroundRemovedImage = null;
      _detectionDetails = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        await _handleTokenExpiration();
        return;
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/user/detect-waste'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          _image!.path,
          contentType: _getImageContentType(_image!.path),
        ),
      );

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseBody);

      if (response.statusCode == 200) {
        setState(() {
          _hasWaste = jsonResponse['hasWaste'] ?? false;
          _backgroundRemovedImage = jsonResponse['backgroundRemoved'];
          _detectionDetails = jsonResponse['detailedResults'];
        });
      } else if (response.statusCode == 403 &&
          jsonResponse['message'] == 'Invalid token') {
        await _handleTokenExpiration();
      } else {
        throw Exception(jsonResponse['error'] ?? 'Failed to detect waste');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error detecting waste: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildImagePreview() {
    if (_image == null) {
      return const Text(
        "No Image Selected",
        style: TextStyle(color: Colors.black54),
      );
    }

    return Column(
      children: [
        // Original image
        Text(
          "Original Image",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            _image!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),

        // Background removed image
        if (_backgroundRemovedImage != null) ...[
          const SizedBox(height: 16),
          Text(
            "Background Removed",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              base64Decode(_backgroundRemovedImage!.split(',').last),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],

        // Detection results
        if (_hasWaste != null) ...[
          const SizedBox(height: 16),
          Text(
            _hasWaste! ? "🚯 Waste Detected" : "✅ Clean Area",
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: _hasWaste! ? Colors.orange : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (_detectionDetails != null && _detectionDetails!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._detectionDetails!.map(
              (detail) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "${detail['class']}: ${(detail['confidence'] * 100).toStringAsFixed(1)}%",
                  style: GoogleFonts.poppins(fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  MediaType? _getImageContentType(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'bmp':
        return MediaType('image', 'bmp');
      default:
        return null;
    }
  }

  Future<void> _submitReport() async {
    if (_image == null || locationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a photo and provide a location!"),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        await _handleTokenExpiration();
        return;
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/user/report-waste'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['location'] = locationController.text;

      // Add original image
      request.files.add(
        await http.MultipartFile.fromPath('image', _image!.path),
      );

      // Add background-removed image if available
      if (_backgroundRemovedImage != null) {
        String base64Data = _backgroundRemovedImage!;
        if (_backgroundRemovedImage!.contains(',')) {
          base64Data = _backgroundRemovedImage!.split(',').last;
        }

        request.files.add(
          http.MultipartFile.fromString(
            'processed_image',
            base64Data,
            contentType: MediaType('image', 'png'),
          ),
        );
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseBody);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Report submitted successfully!")),
        );
        Navigator.pop(context);
      } else if (response.statusCode == 403 &&
          jsonResponse['message'] == 'Invalid token') {
        await _handleTokenExpiration();
      } else {
        throw Exception(jsonResponse['message'] ?? 'Failed to submit report');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Submission failed: ${e.toString()}")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _takePicture() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedImage = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );

      if (pickedImage != null && mounted) {
        setState(() {
          _image = File(pickedImage.path);
          _errorMessage = null;
          _hasWaste = null;
          _backgroundRemovedImage = null;
        });
        await _detectWaste();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error taking picture: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedImage = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );

      if (pickedImage != null && mounted) {
        setState(() {
          _image = File(pickedImage.path);
          _errorMessage = null;
          _hasWaste = null;
          _backgroundRemovedImage = null;
        });
        await _detectWaste();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error picking image: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Report Public Waste"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Report Public Waste",
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Help keep your community clean",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "Select a Picture",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Column(
                            children: [
                              _buildImagePreview(),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.camera_alt),
                                      label: const Text("Open Camera"),
                                      onPressed: _takePicture,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.photo_library),
                                      label: const Text("Pick from Gallery"),
                                      onPressed: _pickImageFromGallery,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: locationController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: "Location",
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: GoogleFonts.poppins(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                _hasWaste == true &&
                                        _image != null &&
                                        locationController.text.isNotEmpty
                                    ? _submitReport
                                    : null, // Disable button if no waste or missing fields
                            child: const Text("Submit Report"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              disabledBackgroundColor:
                                  Colors.grey, // Visual cue for disabled state
                              disabledForegroundColor: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}

// Bin Fill Page for submitting bin fill requests
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
  final storage = FlutterSecureStorage();

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please provide location")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('No token found');

      final fillLevel = is80Checked ? 80 : 100;

      final response = await http.post(
        Uri.parse('$apiBaseUrl/user/bin-fill'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'location': locationController.text,
          'fillLevel': fillLevel,
        }),
      );

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Bin Fill details submitted!")),
        );
        Navigator.pop(context);
      } else {
        throw Exception(
          jsonDecode(response.body)['message'] ?? 'Failed to submit',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Report Bin Fill")),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          "Report Bin Fill",
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Help us collect waste efficiently",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Location Field
                        TextFormField(
                          controller: locationController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: "User Location",
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Bin Fill Level
                        Text(
                          "Bin Fill Level",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: is80Checked,
                              onChanged: (val) => _updateCheckbox(true),
                              activeColor: AppColors.primaryColor,
                            ),
                            Text(
                              "80% Bin Fill",
                              style: GoogleFonts.poppins(color: Colors.black87),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: is100Checked,
                              onChanged: (val) => _updateCheckbox(false),
                              activeColor: AppColors.primaryColor,
                            ),
                            Text(
                              "100% Bin Fill",
                              style: GoogleFonts.poppins(color: Colors.black87),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitBinFill,
                            child: const Text("Submit"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}

// Collection Requests Page to view submitted requests
class CollectionRequestsPage extends StatefulWidget {
  const CollectionRequestsPage({super.key});

  @override
  _CollectionRequestsPageState createState() => _CollectionRequestsPageState();
}

class _CollectionRequestsPageState extends State<CollectionRequestsPage> {
  List<Map<String, dynamic>> garbageReports = [];
  bool _isLoading = false;
  final storage = FlutterSecureStorage();

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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          garbageReports = List<Map<String, dynamic>>.from(
            data['garbageReports'] ?? [],
          );
        });
      } else {
        throw Exception(
          jsonDecode(response.body)['message'] ?? 'Failed to fetch requests',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Collection Requests")),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: RefreshIndicator(
                    onRefresh: _fetchRequests,
                    color: AppColors.primaryColor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          "Collection Requests",
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "View your submitted requests",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Garbage Reports
                        Expanded(
                          child:
                              garbageReports.isEmpty
                                  ? const Center(
                                    child: Text(
                                      "No garbage reports found.",
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  )
                                  : ListView.builder(
                                    itemCount: garbageReports.length,
                                    itemBuilder: (context, index) {
                                      final report = garbageReports[index];
                                      return Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    "Report ID: ${report['reportid']}",
                                                    style: GoogleFonts.poppins(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                "Location: ${report['location']}",
                                                style: GoogleFonts.poppins(
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Text(
                                                "Time: ${report['datetime']}",
                                                style: GoogleFonts.poppins(
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Text(
                                                "Waste Type: ${report['wastetype']}",
                                                style: GoogleFonts.poppins(
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              if (report['comments'] != null)
                                                Text(
                                                  "Comments: ${report['comments']}",
                                                  style: GoogleFonts.poppins(
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              if (report['imageurl'] !=
                                                  null) ...[
                                                const SizedBox(height: 8),
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: Image.network(
                                                    report['imageurl'],
                                                    height: 150,
                                                    width: double.infinity,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => Container(
                                                          height: 150,
                                                          width:
                                                              double.infinity,
                                                          color:
                                                              Colors
                                                                  .grey
                                                                  .shade200,
                                                          child: const Center(
                                                            child: Text(
                                                              "Image unavailable",
                                                              style: TextStyle(
                                                                color:
                                                                    Colors
                                                                        .black54,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ],
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
                ),
              ),
    );
  }
}
