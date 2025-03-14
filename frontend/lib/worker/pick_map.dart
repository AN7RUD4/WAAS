import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _locations = [];

  @override
  void initState() {
    super.initState();
    _fetchCollectionRequestData();
  }

  // Fetch data from the backend API
  Future<void> _fetchCollectionRequestData() async {
    const String apiUrl = 'http://192.168.164.53:3000/collectionrequest';

    try {
      final response = await http.get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _parseLocations(data);
      } else {
        print('Failed to fetch data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  // Parse the location field
  void _parseLocations(List<dynamic> data) {
    for (var item in data) {
      final String? location = item['location'];
      if (location != null) {
        try {
          final LatLng latLng = parseLocation(location);
          _locations.add(latLng);
        } catch (e) {
          print('Error parsing location: $e');
        }
      }
    }

    print('Parsed locations: $_locations');
    setState(() {});
  }

  LatLng parseLocation(String location) {
    final parts = location.split(',');
    if (parts.length == 2) {
      final double latitude = double.tryParse(parts[0]) ?? 0.0;
      final double longitude = double.tryParse(parts[1]) ?? 0.0;
      return LatLng(latitude, longitude);
    }
    throw FormatException('Invalid location format: $location');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(10.8505, 76.2711), // Default center in Kerala
          initialZoom: 14,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers:
                _locations.map((loc) {
                  return Marker(
                    point: loc,
                    child: const Icon(Icons.location_on, color: Colors.red),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}
