import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:math' show sin, cos, sqrt, asin;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:waas/assets/constants.dart';

class MapScreen extends StatefulWidget {
  final int taskid;
  const MapScreen({super.key, required this.taskid});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final List<LatLng> _locations = []; // Collection points from reports or route
  List<LatLng> _route = []; // Route points (from JSONB or OSRM)
  List<LatLng> _completeRoute =
      []; // Complete route including worker's location
  double _currentZoom = 14.0;
  LatLng _currentCenter = const LatLng(10.235865, 76.405676); // Default center
  LatLng? _workerLocation; // Worker's real-time location
  bool _isLoading = false;
  String _errorMessage = '';
  final storage = const FlutterSecureStorage();

  // Info box data
  double _distanceToNearest = 0.0;
  double _totalDistance = 0.0;
  String _directions = "Calculating directions...";
  final List<String> _turnByTurnInstructions = [];
  int _currentInstructionIndex = 0;

  @override
  void initState() {
    super.initState();
    _getWorkerLocation();
    _fetchCollectionRequestData();
  }

  // Get worker's real-time location
  void _getWorkerLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _errorMessage = 'Please enable location services');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _errorMessage = 'Location permissions are denied');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(
          () => _errorMessage = 'Location permissions are permanently denied',
        );
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
        _workerLocation = LatLng(position.latitude, position.longitude);
        _currentCenter = _workerLocation!;
        _errorMessage = '';
      });
      _updateCompleteRoute();
      _calculateDistances();
      _startLocationUpdates();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error getting location: $e';
        _workerLocation = const LatLng(10.235865, 76.405676); // Fallback
        _currentCenter = _workerLocation!;
        _mapController.move(_currentCenter, _currentZoom);
      });
      _updateCompleteRoute();
      _calculateDistances();
    }
  }

  void _startLocationUpdates() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      setState(() {
        _workerLocation = LatLng(position.latitude, position.longitude);
      });
      _updateCompleteRoute();
      _calculateDistances();
      _updateDirectionsBasedOnLocation();
    });
  }

  Future<void> _fetchCollectionRequestData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    final String apiUrl = '$apiBaseUrl/worker/task-route/${widget.taskid}';

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) throw Exception('No authentication token found');

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        // Parse route from JSONB
        if (data['route'] != null && data['route'] is Map) {
          _parseRouteFromJson(data['route']);
        } else {
          setState(() => _errorMessage = 'No route data found in task');
        }

        // Optionally use locations from reports if route is incomplete
        if (_locations.isEmpty &&
            data['locations'] != null &&
            data['locations'].isNotEmpty) {
          _parseLocations(data['locations']);
        }

        // Set worker location from response if not already set
        if (_workerLocation == null && data['workerLocation'] != null) {
          _workerLocation = LatLng(
            data['workerLocation']['lat'],
            data['workerLocation']['lng'],
          );
          _currentCenter = _workerLocation!;
        }

        if (_workerLocation != null && _locations.isNotEmpty) {
          _route = await _fetchRouteFromOSRM();
          if (_route.isEmpty) {
            _route = _locations; // Fallback to straight-line route
            setState(
              () =>
                  _errorMessage =
                      'Failed to fetch route from OSRM. Showing straight-line path.',
            );
          }
          _updateCompleteRoute();
          _calculateDistances();
          _updateDirectionsBasedOnLocation();

          final bounds = LatLngBounds.fromPoints([
            _workerLocation!,
            ..._locations,
          ]);
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
        } else {
          setState(
            () =>
                _errorMessage = 'Missing worker location or collection points',
          );
        }
      } else {
        setState(
          () =>
              _errorMessage =
                  'Failed to fetch task data: ${response.statusCode}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch task data: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error fetching task data: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching task data: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _parseRouteFromJson(Map<String, dynamic> routeData) {
    _locations.clear();
    _route.clear();

    // Add start point
    if (routeData['start'] != null &&
        routeData['start']['lat'] != null &&
        routeData['start']['lng'] != null) {
      _route.add(LatLng(routeData['start']['lat'], routeData['start']['lng']));
    }

    // Add waypoints (these are the report locations)
    if (routeData['waypoints'] != null && routeData['waypoints'] is List) {
      for (var waypoint in routeData['waypoints']) {
        if (waypoint['lat'] != null && waypoint['lng'] != null) {
          final latLng = LatLng(waypoint['lat'], waypoint['lng']);
          _locations.add(latLng); // Treat waypoints as report locations
          _route.add(latLng);
        }
      }
    }

    // Add end point
    if (routeData['end'] != null &&
        routeData['end']['lat'] != null &&
        routeData['end']['lng'] != null) {
      _route.add(LatLng(routeData['end']['lat'], routeData['end']['lng']));
    }

    if (_locations.isEmpty) {
      setState(() => _errorMessage = 'No valid waypoints found in route');
    }
  }

  void _parseLocations(List<dynamic> data) {
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
    if (_locations.isEmpty) {
      setState(() => _errorMessage = 'No valid collection points found');
    }
  }

  Future<List<LatLng>> _fetchRouteFromOSRM() async {
    if (_workerLocation == null || _locations.isEmpty) return [];

    List<LatLng> waypoints = [_workerLocation!, ..._locations];
    final String osrmUrl =
        'http://router.project-osrm.org/route/v1/driving/${waypoints.map((p) => '${p.longitude},${p.latitude}').join(';')}?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(Uri.parse(osrmUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final routeGeometry = data['routes'][0]['geometry']['coordinates'];
          List<LatLng> routePoints =
              routeGeometry
                  .map<LatLng>((coord) => LatLng(coord[1], coord[0]))
                  .toList();

          _turnByTurnInstructions.clear();
          final legs = data['routes'][0]['legs'];
          for (var leg in legs) {
            for (var step in leg['steps']) {
              _turnByTurnInstructions.add(step['maneuver']['instruction']);
            }
          }
          _currentInstructionIndex = 0;
          _directions =
              _turnByTurnInstructions.isNotEmpty
                  ? _turnByTurnInstructions[0]
                  : "Proceed to the first collection point";

          return routePoints;
        }
      }
      return [];
    } catch (e) {
      setState(() => _errorMessage = 'Error fetching route from OSRM: $e');
      return [];
    }
  }

  void _updateCompleteRoute() {
    if (_workerLocation == null) {
      _completeRoute = _route;
    } else {
      _completeRoute = [_workerLocation!, ..._route];
    }
  }

  double _haversineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371.0;
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

  double _degreesToRadians(double degrees) => degrees * (pi / 180.0);

  void _calculateDistances() {
    if (_workerLocation == null || _completeRoute.isEmpty) {
      setState(() {
        _distanceToNearest = 0.0;
        _totalDistance = 0.0;
      });
      return;
    }

    _distanceToNearest = _haversineDistance(
      _workerLocation!,
      _completeRoute[1],
    );
    _totalDistance = 0.0;
    for (int i = 0; i < _completeRoute.length - 1; i++) {
      _totalDistance += _haversineDistance(
        _completeRoute[i],
        _completeRoute[i + 1],
      );
    }
    setState(() {});
  }

  void _updateDirectionsBasedOnLocation() {
    if (_workerLocation == null ||
        _completeRoute.isEmpty ||
        _turnByTurnInstructions.isEmpty)
      return;

    double minDistance = double.infinity;
    for (int i = 0; i < _completeRoute.length; i++) {
      final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }

    if (minDistance < 0.05 &&
        _currentInstructionIndex < _turnByTurnInstructions.length - 1) {
      _currentInstructionIndex++;
      _directions = _turnByTurnInstructions[_currentInstructionIndex];
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Collection Points',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
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
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
              ),
              if (_completeRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _completeRoute,
                      strokeWidth: 4.0,
                      color: Colors.green.shade700,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
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
                  ..._locations.map(
                    (loc) => Marker(
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
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Directions: $_directions',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Distance to Nearest: ${_distanceToNearest.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total Distance: ${_totalDistance.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Error: $_errorMessage',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            right: 16,
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
                const SizedBox(height: 8),
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
          if (_workerLocation != null) {
            _currentCenter = _workerLocation!;
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
