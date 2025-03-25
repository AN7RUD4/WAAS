import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:math' show sin, cos, sqrt, asin;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MapScreen extends StatefulWidget {
  final int taskid;
  const MapScreen({
    super.key,
    required this.taskid,
  });

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _locations = [];
  List<LatLng> _route = []; // Route from taskrequests
  List<LatLng> _completeRoute = []; // Complete route including worker's location
  double _currentZoom = 14.0;
  LatLng _currentCenter = const LatLng(10.1860, 76.3765); // Default center
  LatLng? _workerLocation; // Worker's location
  bool _isLoading = false;
  final storage = const FlutterSecureStorage();

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
              'Location permissions are permanently denied, please enable them in settings',
            ),
          ),
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
      _updateCompleteRoute();
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
      _updateCompleteRoute();
      _calculateDistances();
    }
  }

  // Fetch data from the backend API for the specific taskid
  Future<void> _fetchCollectionRequestData() async {
    setState(() => _isLoading = true);
    final String apiUrl = 'http://192.168.164.53:3000/api/worker/task-route/${widget.taskid}';

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) {
        throw Exception('No authentication token found');
      }

      print('Fetching data from $apiUrl');
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        print('Parsed data: $data');
        _parseLocations(data['locations']);
        _route = _parseRoute(data['route']);
        print('Updated _route: $_route');
        _updateCompleteRoute();
        _calculateDistances();
      } else {
        print('Failed to fetch data: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch task data: ${response.statusCode}')),
        );
      }
    } catch (e) {
      print('Error fetching data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching task data: $e')),
      );
    }
    setState(() => _isLoading = false);
  }

  // Parse the locations field (collection points from garbagereports)
  void _parseLocations(List<dynamic> data) {
    _locations.clear();
    for (var item in data) {
      if (item['lat'] != null && item['lng'] != null) {
        try {
          final LatLng latLng = LatLng(
            double.parse(item['lat'].toString()),
            double.parse(item['lng'].toString()),
          );
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

  // Parse the route from the backend (from taskrequests.route)
  List<LatLng> _parseRoute(List<dynamic> routeData) {
    List<LatLng> route = [];
    for (var point in routeData) {
      if (point['lat'] != null && point['lng'] != null) {
        try {
          final LatLng latLng = LatLng(
            double.parse(point['lat'].toString()),
            double.parse(point['lng'].toString()),
          );
          route.add(latLng);
        } catch (e) {
          print('Error parsing route point: $e');
        }
      }
    }
    return route;
  }

  // Update the complete route by prepending the worker's location
  void _updateCompleteRoute() {
    if (_workerLocation == null || _route.isEmpty) {
      _completeRoute = _route;
      return;
    }
    // Prepend worker's location to the route
    _completeRoute = [_workerLocation!, ..._route];
    print('Updated _completeRoute: $_completeRoute');
  }

  // Custom Haversine distance calculation
  double _haversineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371.0; // Radius of the Earth in kilometers
    final double dLat = _degreesToRadians(end.latitude - start.latitude);
    final double dLon = _degreesToRadians(end.longitude - start.longitude);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
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
    print('Complete Route: $_completeRoute');
    if (_workerLocation == null || _completeRoute.isEmpty) {
      print('Cannot calculate distances: workerLocation or completeRoute are empty');
      return;
    }

    // Find the nearest pickup spot (first point after worker's location)
    LatLng nearestSpot = _completeRoute[1]; // First point after worker's location
    _distanceToNearest = _haversineDistance(_workerLocation!, nearestSpot);
    print('Nearest spot: $nearestSpot, Distance: $_distanceToNearest km');

    // Calculate total distance of the complete route
    _totalDistance = 0.0;
    for (int i = 0; i < _completeRoute.length - 1; i++) {
      final segmentDistance = _haversineDistance(_completeRoute[i], _completeRoute[i + 1]);
      print('Segment distance from ${_completeRoute[i]} to ${_completeRoute[i + 1]}: $segmentDistance km');
      _totalDistance += segmentDistance;
    }
    print('Total distance: $_totalDistance km');

    // Simple directions
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
                    _currentCenter = position.center;
                    _currentZoom = position.zoom;
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
              if (_completeRoute.isNotEmpty) // Use _completeRoute for the polyline
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _completeRoute,
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0,2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Directions: $_directions',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
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