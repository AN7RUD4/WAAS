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
  double _currentZoom = 14.0; // Track zoom level manually
  LatLng _currentCenter = const LatLng(
    10.1860,
    76.3765,
  ); // Default center (Angamaly)

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchCollectionRequestData();
  }

  // Fetch data from the backend API
  Future<void> _fetchCollectionRequestData() async {
    setState(() => _isLoading = true);
    const String apiUrl = 'http://192.168.164.53:3000/api/collectionrequest';

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
    setState(() => _isLoading = false);
  }

  // Parse the location field
  void _parseLocations(List<dynamic> data) {
    _locations.clear();
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
    if (_locations.isNotEmpty) {
      _currentCenter = _locations[0]; // Update center to first location
      _mapController.move(_currentCenter, _currentZoom);
    }
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
      appBar: AppBar(
        title: const Text(
          'Collection Points',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700,
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchCollectionRequestData,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter, 
              initialZoom: _currentZoom, 
              minZoom: 10,
              maxZoom: 18,
              onPositionChanged: (position, hasGesture) {
                // Update tracked state when map moves
                if (hasGesture) {
                  setState(() {
                    _currentCenter = position.center ?? _currentCenter;
                    _currentZoom = position.zoom ?? _currentZoom;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
                tileProvider: NetworkTileProvider(),
                additionalOptions: {'alpha': '0.9'},
              ),
              MarkerLayer(
                markers:
                    _locations.map((loc) {
                      return Marker(
                        point: loc,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Location: ${loc.latitude}, ${loc.longitude}',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.redAccent,
                            size: 40,
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: () {
                    _currentZoom = (_currentZoom + 1).clamp(10, 18);
                    _mapController.move(_currentCenter, _currentZoom);
                  },
                  mini: true,
                  backgroundColor: Colors.green.shade700,
                  child: const Icon(Icons.zoom_in, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: () {
                    _currentZoom = (_currentZoom - 1).clamp(10, 18);
                    _mapController.move(_currentCenter, _currentZoom);
                  },
                  mini: true,
                  backgroundColor: Colors.green.shade700,
                  child: const Icon(Icons.zoom_out, color: Colors.white),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.green)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_locations.isNotEmpty) {
            _currentCenter = _locations[0];
            _currentZoom = 14;
            _mapController.move(_currentCenter, _currentZoom);
          }
        },
        backgroundColor: Colors.green.shade700,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }
}
