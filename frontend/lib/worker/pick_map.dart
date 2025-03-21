import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:math' show sin, cos, sqrt, asin, pi;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _locations = [];
  List<LatLng> _route = []; // To store the shortest route
  double _currentZoom = 14.0;
  LatLng _currentCenter = const LatLng(10.1860, 76.3765); // Default center
  LatLng? _workerLocation; // Worker's location
  bool _isLoading = false;

  // For the info box
  double _distanceToNearest = 0.0;
  double _totalDistance = 0.0;
  String _directions = "Calculating directions...";

  @override
  void initState() {
    super.initState();
    _getWorkerLocation(); // Get worker's location
    _fetchCollectionRequestData();
  }

  // Get worker's location using Geolocator
  void _getWorkerLocation() async {
    try {
      print('Checking location services...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
        return;
      }

      print('Checking location permissions...');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied.');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Location permissions are permanently denied, please enable them in settings')),
        );
        return;
      }

      print('Getting current position...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('Position: ${position.latitude}, ${position.longitude}');
      setState(() {
        _workerLocation = LatLng(position.latitude, position.longitude);
        _currentCenter = _workerLocation!; // Center the map on the worker's location
        _mapController.move(_currentCenter, _currentZoom);
        print('Worker location set: $_workerLocation');
      });
      _calculateDistances();
    } catch (e) {
      print('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
      // Fallback to default location if location retrieval fails
      setState(() {
        _workerLocation = const LatLng(10.1865, 76.3770); // Default fallback location
        _currentCenter = _workerLocation!;
        _mapController.move(_currentCenter, _currentZoom);
        print('Using fallback location: $_workerLocation');
      });
      _calculateDistances();
    }
  }

  // Fetch data from the backend API
  Future<void> _fetchCollectionRequestData() async {
    setState(() => _isLoading = true);
    const String apiUrl = 'http://192.168.164.53:3000/api/collectionrequest/route';

    try {
      print('Fetching data from $apiUrl');
      final response = await http.get(Uri.parse(apiUrl));
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        print('Parsed data: $data');
        _parseLocations(data['locations']);
        _route = _parseRoute(data['route']); // Parse the optimized route
        print('Updated _route: $_route');
        _calculateDistances();
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
    if (_locations.isNotEmpty && _workerLocation == null) {
      _currentCenter = _locations[0];
      _mapController.move(_currentCenter, _currentZoom);
    }
    setState(() {});
  }

  // Parse the route from the backend
  List<LatLng> _parseRoute(List<dynamic> routeData) {
    List<LatLng> route = [];
    for (var loc in routeData) {
      final String? location = loc['location'];
      if (location != null) {
        try {
          final LatLng latLng = parseLocation(location);
          route.add(latLng);
        } catch (e) {
          print('Error parsing route location: $e');
        }
      }
    }
    return route;
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

  // Custom Haversine distance calculation
  double _haversineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371.0; // Radius of the Earth in kilometers
    final double dLat = _degreesToRadians(end.latitude - start.latitude);
    final double dLon = _degreesToRadians(end.longitude - start.longitude);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) *
            cos(_degreesToRadians(end.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  // Calculate distances and directions
  void _calculateDistances() {
    print('Calculating distances...');
    print('Worker Location: $_workerLocation');
    print('Route: $_route');
    if (_workerLocation == null || _locations.isEmpty) {
      print('Cannot calculate distances: workerLocation or locations are empty');
      return;
    }

    // Find the nearest pickup spot
    LatLng nearestSpot = _route[0];
    double minDistance = double.infinity;
    for (var loc in _route) {
      final distance = _haversineDistance(_workerLocation!, loc);
      print('Distance to $loc: $distance km');
      if (distance < minDistance) {
        minDistance = distance;
        nearestSpot = loc;
      }
    }
    _distanceToNearest = minDistance;
    print('Nearest spot: $nearestSpot, Distance: $_distanceToNearest km');

    // Calculate total distance of the route
    _totalDistance = 0.0;
    for (int i = 0; i < _route.length - 1; i++) {
      final segmentDistance = _haversineDistance(_route[i], _route[i + 1]);
      print('Segment distance from ${_route[i]} to ${_route[i + 1]}: $segmentDistance km');
      _totalDistance += segmentDistance;
    }
    print('Total distance: $_totalDistance km');

    // Simple directions (for demo purposes; replace with actual directions API if needed)
    _directions = "Head towards ${nearestSpot.latitude}, ${nearestSpot.longitude}";

    setState(() {});
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
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
                tileProvider: NetworkTileProvider(),
                additionalOptions: {'alpha': '0.9'},
              ),
              if (_route.isNotEmpty) // Only render PolylineLayer if _route is not empty
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Worker location marker
                  if (_workerLocation != null)
                    Marker(
                      point: _workerLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  // Collection points markers
                  ..._locations.map((loc) {
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
                ],
              ),
            ],
          ),
          // Info box at the top
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Directions: $_directions',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Distance to Nearest Spot: ${_distanceToNearest.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Total Distance: ${_totalDistance.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
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
            _currentCenter = _workerLocation ?? _locations[0];
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