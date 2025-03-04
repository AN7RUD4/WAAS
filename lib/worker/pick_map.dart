import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  Position? _currentPosition;
  CircleMarker? _currentLocationCircle;
  List<List<LatLng>> _routePolylines = []; // Store multiple polylines
  String? _nextDirection; // Store the next direction
  String? _nextDirectionArrow; // Store the arrow for the next direction
  List<LatLng> _sortedLocations = []; // Store locations sorted by distance

  // Predefined locations in Kerala, India
  final List<LatLng> _locations = [
    const LatLng(9.9312, 76.2673), // Kochi
    const LatLng(8.5241, 76.9366), // Thiruvananthapuram
    const LatLng(11.2588, 75.7804), // Kozhikode
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are disabled.");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print("Location permissions are denied.");
        return;
      }
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;

      // Circle to show user's location
      _currentLocationCircle = CircleMarker(
        point: LatLng(position.latitude, position.longitude),
        color: Colors.blue.withOpacity(0.3),
        borderStrokeWidth: 2,
        borderColor: Colors.blue,
        radius: 50, // 50 meters radius
      );
    });

    // Move map to user's location
    _mapController.move(LatLng(position.latitude, position.longitude), 14);

    // Sort locations by distance and fetch routes
    await _sortLocationsByDistance(position);
    await _fetchRoutes(position);
  }

  // Sort locations by distance from current position
  Future<void> _sortLocationsByDistance(Position position) async {
    final LatLng currentLatLng = LatLng(position.latitude, position.longitude);

    // Calculate distances and sort locations
    _sortedLocations =
        _locations..sort((a, b) {
          final double distanceA = _calculateDistance(currentLatLng, a);
          final double distanceB = _calculateDistance(currentLatLng, b);
          return distanceA.compareTo(distanceB);
        });

    print('Sorted Locations: $_sortedLocations');
  }

  // Calculate distance between two LatLng points
  double _calculateDistance(LatLng start, LatLng end) {
    const Distance distance = Distance();
    return distance(start, end);
  }

  // Fetch road route from OpenRouteService API
  Future<void> _fetchRoutes(Position position) async {
    final String apiKey =
        '5b3ce3597851110001cf6248e68ff6961bda443cb32582c25c6689a5'; // Replace with your OpenRouteService API key
    final String url =
        'https://api.openrouteservice.org/v2/directions/driving-car/geojson';

    // Clear previous route polylines and directions
    setState(() {
      _routePolylines.clear();
      _nextDirection = null;
      _nextDirectionArrow = null;
    });

    LatLng currentLocation = LatLng(position.latitude, position.longitude);

    for (LatLng destination in _sortedLocations) {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Authorization': apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({
          "coordinates": [
            [currentLocation.longitude, currentLocation.latitude], // Start
            [destination.longitude, destination.latitude], // Destination
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> coordinates =
            data['features'][0]['geometry']['coordinates'];
        final List<dynamic> instructions =
            data['features'][0]['properties']['segments'][0]['steps'];

        // Add road-based polyline points to _routePolylines
        setState(() {
          _routePolylines.add(
            coordinates.map((coord) => LatLng(coord[1], coord[0])).toList(),
          );

          // Get the next direction and arrow
          if (instructions.isNotEmpty) {
            _nextDirection = instructions[0]['instruction'];
            _nextDirectionArrow = _getDirectionArrow(instructions[0]['type']);
          }
        });

        // Update current location to the destination
        currentLocation = destination;
      } else {
        print('Failed to load route: ${response.body}');
      }
    }
  }

  // Helper function to get direction arrow based on instruction type
  String _getDirectionArrow(int type) {
    switch (type) {
      case 0: // Continue
        return '↑';
      case 1: // Slight right
        return '↗';
      case 2: // Right
        return '→';
      case 3: // Sharp right
        return '↘';
      case 4: // U-turn
        return '↻';
      case 5: // Sharp left
        return '↙';
      case 6: // Left
        return '←';
      case 7: // Slight left
        return '↖';
      default:
        return '↑';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Worker's Map")),
      body: Column(
        children: [
          // Next Direction Box
          if (_nextDirection != null)
            Container(
              height: 60, // Adjust height as needed
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(
                    _nextDirectionArrow ?? '',
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _nextDirection!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          // Map
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _currentPosition != null
                        ? LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        )
                        : LatLng(10.8505, 76.2711), // Default center in Kerala
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: ['a', 'b', 'c'],
                ),
                if (_currentLocationCircle != null)
                  CircleLayer(
                    circles: [_currentLocationCircle!],
                  ), // Show user location
                MarkerLayer(
                  markers:
                      _sortedLocations.map((loc) {
                        return Marker(
                          point: loc,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                          ),
                        );
                      }).toList(),
                ),
                PolylineLayer(
                  polylines:
                      _routePolylines
                          .map(
                            (points) => Polyline(
                              points: points,
                              strokeWidth: 4.0,
                              color: Colors.blue,
                            ),
                          )
                          .toList(), // Render all road-based polylines
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
