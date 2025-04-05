import 'dart:convert';
import 'dart:math' show sin, cos, sqrt, asin, pi;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
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
  final List<LatLng> _locations = []; // Will store uncollected locations
  final List<int> _reportIds = []; // Will store uncollected report IDs
  final List<String> _wasteTypes = []; // Will store uncollected waste types
  List<LatLng> _route = [];
  List<LatLng> _completeRoute = [];
  double _currentZoom = 14.0;
  LatLng _currentCenter = const LatLng(10.235865, 76.405676);
  LatLng? _workerLocation;
  double? _workerHeading; // New: Store the worker's heading in degrees
  bool _isLoading = false;
  String _errorMessage = '';
  final storage = const FlutterSecureStorage();

  // Collection state
  bool _collectionStarted = false;
  Set<int> _collectedReports = {}; // Track collected report IDs
  LatLng? _currentCollectionPoint;
  String? _currentWasteType;

  // Route info
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
        setState(() => _errorMessage = 'Location permissions are permanently denied');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied')),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _workerLocation = LatLng(position.latitude, position.longitude);
        _workerHeading = position.heading; // Initialize heading
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
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _workerLocation = LatLng(position.latitude, position.longitude);
          _workerHeading = position.heading; // Update heading in real-time
          _currentCenter = _workerLocation!; // Center map on worker
          _mapController.move(_currentCenter, _currentZoom); // Update map position
        });
        _updateCompleteRoute();
        _calculateDistances();
        _updateDirectionsBasedOnLocation();
      }
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

        // Parse locations, report IDs, and waste types, excluding collected reports
        if (data['locations'] != null && data['locations'] is List) {
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
            setState(() => _errorMessage = 'Failed to fetch route from OSRM. Showing straight-line path.');
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
          setState(() => _errorMessage = 'Missing worker location or collection points');
        }
      } else {
        setState(() => _errorMessage = 'Failed to fetch task data: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch task data: ${response.statusCode}')),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error fetching task data: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching task data: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _parseRouteFromJson(Map<String, dynamic> routeData) {
    _locations.clear();
    _route.clear();
    _reportIds.clear();
    _wasteTypes.clear();

    // Add start point
    if (routeData['start'] != null &&
        routeData['start']['lat'] != null &&
        routeData['start']['lng'] != null) {
      final startPoint = LatLng(
        routeData['start']['lat'],
        routeData['start']['lng'],
      );
      _locations.add(startPoint);
      _route.add(startPoint);
    }

    // Add waypoints (these are the report locations), excluding collected ones
    if (routeData['waypoints'] != null && routeData['waypoints'] is List) {
      for (var waypoint in routeData['waypoints']) {
        if (waypoint['lat'] != null && waypoint['lng'] != null && waypoint['reportid'] != null) {
          final latLng = LatLng(waypoint['lat'], waypoint['lng']);
          if (!_collectedReports.contains(waypoint['reportid'])) {
            _locations.add(latLng);
            _route.add(latLng);
            _reportIds.add(waypoint['reportid']);
            _wasteTypes.add(waypoint['wastetype'] ?? 'Unknown');
          }
        }
      }
    }

    // Add end point
    if (routeData['end'] != null &&
        routeData['end']['lat'] != null &&
        routeData['end']['lng'] != null) {
      final endPoint = LatLng(routeData['end']['lat'], routeData['end']['lng']);
      _locations.add(endPoint);
      _route.add(endPoint);
    }

    if (_locations.isEmpty) {
      setState(() => _errorMessage = 'No valid waypoints found in route');
    }
  }

  void _parseLocations(List<dynamic> data) {
    _locations.clear();
    _reportIds.clear();
    _wasteTypes.clear();
    for (var item in data) {
      if (item['lat'] != null && item['lng'] != null && item['reportid'] != null) {
        try {
          final LatLng latLng = LatLng(
            double.parse(item['lat'].toString()),
            double.parse(item['lng'].toString()),
          );
          if (!_collectedReports.contains(item['reportid'])) {
            _locations.add(latLng);
            _reportIds.add(item['reportid']);
            _wasteTypes.add(item['wastetype'] ?? 'Unknown');
          }
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
    if (_workerLocation == null || _locations.isEmpty) {
      return [];
    }

    List<LatLng> waypoints = [_workerLocation!, ..._locations];
    final String osrmBaseUrl = 'http://router.project-osrm.org/route/v1/driving/';
    String coordinates = waypoints.map((point) => '${point.longitude},${point.latitude}').join(';');
    final String osrmUrl = '$osrmBaseUrl$coordinates?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(Uri.parse(osrmUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final routeGeometry = data['routes'][0]['geometry']['coordinates'];
          List<LatLng> routePoints = routeGeometry.map<LatLng>((coord) => LatLng(coord[1], coord[0])).toList();

          _turnByTurnInstructions.clear();
          final legs = data['routes'][0]['legs'];
          for (var leg in legs) {
            for (var step in leg['steps']) {
              if (step['maneuver'] != null && step['maneuver']['instruction'] != null) {
                _turnByTurnInstructions.add(step['maneuver']['instruction']);
              }
            }
          }
          _currentInstructionIndex = 0;
          _directions = _turnByTurnInstructions.isNotEmpty ? _turnByTurnInstructions[0] : "Proceed to the first collection point";

          return routePoints;
        } else {
          throw Exception('OSRM API error: ${data['message']}');
        }
      } else {
        throw Exception('Failed to fetch route from OSRM: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching route from OSRM: $e');
      setState(() {
        _errorMessage = 'Error fetching route from OSRM: $e';
        _directions = 'Proceed to the collection point (straight-line path)';
      });
      return _locations;
    }
  }

  void _updateCompleteRoute() {
    if (_workerLocation == null || _route.isEmpty) {
      _completeRoute = _route;
      return;
    }
    _completeRoute = [_workerLocation!, ..._route];
  }

  double _haversineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371.0;
    final double dLat = _degreesToRadians(end.latitude - start.latitude);
    final double dLon = _degreesToRadians(end.longitude - start.longitude);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) * cos(_degreesToRadians(end.latitude)) * sin(dLon / 2) * sin(dLon / 2);
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

    _distanceToNearest = _haversineDistance(_workerLocation!, _completeRoute[1]);
    _totalDistance = 0.0;
    for (int i = 0; i < _completeRoute.length - 1; i++) {
      _totalDistance += _haversineDistance(_completeRoute[i], _completeRoute[i + 1]);
    }
    setState(() {});
  }

  void _updateDirectionsBasedOnLocation() {
    if (_workerLocation == null || _completeRoute.isEmpty || _turnByTurnInstructions.isEmpty) return;

    double minDistance = double.infinity;
    int closestIndex = 0;
    for (int i = 0; i < _completeRoute.length; i++) {
      final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    if (minDistance < 0.05 && _currentInstructionIndex < _turnByTurnInstructions.length - 1) {
      _currentInstructionIndex++;
      _directions = _turnByTurnInstructions[_currentInstructionIndex];
      setState(() {});
    }
  }

  void _startCollection() async {
  setState(() => _isLoading = true);

  try {
    final token = await storage.read(key: 'jwt_token');
    print('Token: $token'); // Debug token
    if (token == null) throw Exception('No authentication token found');

    print('Starting collection for taskId: ${widget.taskid}'); // Debug taskId
    final response = await http.post(
      Uri.parse('$apiBaseUrl/worker/start-task'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'taskId': widget.taskid}),
    );

    print('Response status: ${response.statusCode}, Body: ${response.body}'); // Debug response
    if (response.statusCode == 200) {
      setState(() {
        _collectionStarted = true;
        _errorMessage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Collection started! Tap on locations to mark as collected'),
        ),
      );
    } else {
      throw Exception('Failed to start task: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    setState(() => _errorMessage = 'Error starting collection: $e');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error starting collection: $e')));
  } finally {
    setState(() => _isLoading = false);
  }
}

  Future<void> _markAsCollected(LatLng location, int reportId, String wasteType) async {
    setState(() {
      _currentCollectionPoint = location;
      _currentWasteType = wasteType;
      _isLoading = true;
    });

    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) throw Exception('No authentication token found');

      final response = await http.post(
        Uri.parse('$apiBaseUrl/worker/mark-collected'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'taskId': widget.taskid, 'reportId': reportId}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _collectedReports.add(reportId);
          _currentCollectionPoint = null;
          _currentWasteType = null;
          // Refresh locations to exclude collected reports
          _fetchCollectionRequestData(); // Re-fetch to update uncollected locations
        });

        if (responseData['taskStatus'] == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All locations collected! Task completed')),
          );
          Navigator.pop(context); // Return to previous screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${responseData['message']} (${responseData['remainingReports']} remaining)')),
          );
        }
      } else {
        throw Exception(responseData['error'] ?? 'Failed to mark collected');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error marking collected: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error marking collected: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  int _getReportIdForIndex(int index) {
    return index < _reportIds.length ? _reportIds[index] : -1;
  }

  String _getWasteTypeForIndex(int index) {
    return index < _wasteTypes.length ? _wasteTypes[index] : 'Unknown';
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
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
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
                      child: Transform.rotate(
                        // Rotate marker based on heading
                        angle: _workerHeading != null ? -_degreesToRadians(_workerHeading!) : 0.0,
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.blue,
                          size: 40,
                        ),
                      ),
                    ),
                  ..._locations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final loc = entry.value;
                    final reportId = _getReportIdForIndex(index);
                    final wasteType = _getWasteTypeForIndex(index);

                    return Marker(
                      point: loc,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () {
                          if (_collectionStarted && !_collectedReports.contains(reportId)) {
                            _markAsCollected(loc, reportId, wasteType);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Location: ${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)}\nWaste Type: $wasteType',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: Icon(
                          _collectedReports.contains(reportId) ? Icons.check_circle : Icons.location_pin,
                          color: _collectedReports.contains(reportId) ? Colors.green : (_collectionStarted ? Colors.orangeAccent : Colors.redAccent),
                          size: 40,
                        ),
                      ),
                    );
                  }),
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
                  if (_workerHeading != null)
                    Text(
                      'Heading: ${_workerHeading!.toStringAsFixed(1)}°',
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
          if (_currentCollectionPoint != null && _currentWasteType != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Current Collection Point',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Waste Type: $_currentWasteType',
                      style: TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Location: ${_currentCollectionPoint!.latitude.toStringAsFixed(6)}, '
                      '${_currentCollectionPoint!.longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: Colors.white),
                    ),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_collectionStarted)
            FloatingActionButton.extended(
              onPressed: _startCollection,
              backgroundColor: Colors.green.shade700,
              label: const Text(
                'Start Collection',
                style: TextStyle(color: Colors.white),
              ),
              icon: const Icon(Icons.play_arrow, color: Colors.white),
            ),
          const SizedBox(height: 16),
          FloatingActionButton(
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
        ],
      ),
    );
  }
}