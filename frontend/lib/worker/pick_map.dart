import 'dart:convert';
import 'dart:math' show asin, atan2, cos, pi, sin, sqrt;
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
  final List<LatLng> _locations = [];
  final List<int> _reportIds = [];
  final List<String> _wasteTypes = [];
  List<LatLng> _route = [];
  List<LatLng> _completeRoute = [];
  var _directions = "START";
  double _currentZoom = 14.0;
  LatLng _currentCenter = const LatLng(10.235865, 76.405676);
  LatLng? _workerLocation;
  bool _isLoading = false;
  String _errorMessage = '';
  final storage = const FlutterSecureStorage();

  bool _collectionStarted = false;
  Set<int> _collectedReports = {};
  LatLng? _selectedLocation;
  String? _selectedWasteType;
  int? _selectedReportId;

  double _totalDistance = 0.0;
  List<Map<String, dynamic>> _directionSteps = [];
  int _currentInstructionIndex = 0;

  @override
  void initState() {
    super.initState();
    _getWorkerLocation();
    _fetchCollectionRequestData();
  }

  // Add these constants at the top of your class
 Map<int, String> _directionSymbols = {
  0: '🛣️', // Continue straight
  1: '⬅️', // Sharp left
  2: '↖️', // Left
  3: '↪️', // Slight left
  4: '➡️', // Sharp right
  5: '↗️', // Right
  6: '↩️', // Slight right
  7: '↗️', // Merge right
  8: '↖️', // Merge left
  9: '🔄', // Roundabout
  10: '🏁', // Destination reached
};

String _getDirectionSymbol(double bearing) {
  if (bearing < 0) bearing += 360;
  
  if (bearing >= 337.5 || bearing < 22.5) return '🛣️'; // Straight
  if (bearing >= 22.5 && bearing < 67.5) return '↗️'; // Right
  if (bearing >= 67.5 && bearing < 112.5) return '➡️'; // Sharp right
  if (bearing >= 112.5 && bearing < 157.5) return '↘️'; // Slight right
  if (bearing >= 157.5 && bearing < 202.5) return '🛣️'; // Straight (reverse)
  if (bearing >= 202.5 && bearing < 247.5) return '↙️'; // Slight left
  if (bearing >= 247.5 && bearing < 292.5) return '⬅️'; // Left
  if (bearing >= 292.5 && bearing < 337.5) return '↖️'; // Sharp left
  
  return '🛣️';
}

double _calculateBearing(LatLng start, LatLng end) {
  final startLat = _degreesToRadians(start.latitude);
  final startLng = _degreesToRadians(start.longitude);
  final endLat = _degreesToRadians(end.latitude);
  final endLng = _degreesToRadians(end.longitude);

  final y = sin(endLng - startLng) * cos(endLat);
  final x = cos(startLat) * sin(endLat) -
      sin(startLat) * cos(endLat) * cos(endLng - startLng);
  final bearing = atan2(y, x);
  return (_radiansToDegrees(bearing) + 360) % 360;
}

double _radiansToDegrees(double radians) => radians * (180.0 / pi);

  void _getWorkerLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _errorMessage = 'Please enable location services');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _errorMessage = 'Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _errorMessage = 'Location permissions are permanently denied');
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
        _workerLocation = const LatLng(10.235865, 76.405676);
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
      if (mounted) {
        setState(() {
          _workerLocation = LatLng(position.latitude, position.longitude);
          _currentCenter = _workerLocation!;
          _mapController.move(_currentCenter, _currentZoom);
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
        _parseRouteFromJson(data);
        
        if (_workerLocation == null && data['workerLocation'] != null) {
          _workerLocation = LatLng(
            data['workerLocation']['lat'],
            data['workerLocation']['lng'],
          );
          _currentCenter = _workerLocation!;
        }

        if (_workerLocation != null && _locations.isNotEmpty) {
          _route = await _fetchRouteFromOSRM();
          _updateCompleteRoute();
          _calculateDistances();
          _updateDirectionsBasedOnLocation();

          final bounds = LatLngBounds.fromPoints([
            _workerLocation!,
            ..._locations,
          ]);
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
        }
      } else {
        throw Exception('Failed to fetch task data: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error fetching task data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _parseRouteFromJson(Map<String, dynamic> data) {
    _locations.clear();
    _route.clear();
    _reportIds.clear();
    _wasteTypes.clear();

    if (data['locations'] != null && data['locations'] is List) {
      for (var item in data['locations']) {
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
    }
  }

  Future<List<LatLng>> _fetchRouteFromOSRM() async {
  if (_workerLocation == null || _locations.isEmpty) return [];

  List<LatLng> waypoints = [_workerLocation!, ..._locations];
  final String osrmBaseUrl = 'http://router.project-osrm.org/route/v1/driving/';
  String coordinates = waypoints
      .map((point) => '${point.longitude},${point.latitude}')
      .join(';');
  final String osrmUrl = '$osrmBaseUrl$coordinates?overview=full&geometries=geojson&steps=true';

  try {
    final response = await http.get(Uri.parse(osrmUrl));

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
        // Parse steps for turn-by-turn directions
        _directionSteps = [];
        final steps = data['routes'][0]['legs'][0]['steps'];
        for (var step in steps) {
          _directionSteps.add({
            'distance': step['distance'],
            'instruction': step['maneuver']['instruction'],
            'type': step['maneuver']['type'],
            'modifier': step['maneuver']['modifier'],
            'location': LatLng(
              step['maneuver']['location'][1],
              step['maneuver']['location'][0],
            ),
          });
        }

        final routeGeometry = data['routes'][0]['geometry']['coordinates'];
        return routeGeometry
            .map<LatLng>((coord) => LatLng(coord[1], coord[0]))
            .toList();
      }
    }
  } catch (e) {
    print('Error fetching route from OSRM: $e');
  }
  return _locations;
}


String _getCurrentInstruction() {
  if (_workerLocation == null || _directionSteps.isEmpty) return 'Calculating route...';

  // Find the closest step
  int closestStepIndex = 0;
  double minDistance = double.infinity;
  
  for (int i = 0; i < _directionSteps.length; i++) {
    final stepLocation = _directionSteps[i]['location'] as LatLng;
    final distance = _haversineDistance(_workerLocation!, stepLocation);
    if (distance < minDistance) {
      minDistance = distance;
      closestStepIndex = i;
    }
  }

  // Get the next instruction
  final nextStepIndex = closestStepIndex < _directionSteps.length - 1 
      ? closestStepIndex + 1 
      : closestStepIndex;
      
  final nextStep = _directionSteps[nextStepIndex];
  final distanceToNext = _haversineDistance(
    _workerLocation!,
    nextStep['location'] as LatLng,
  );

  String instruction = nextStep['instruction'];
  String symbol = '🛣️';
  
  switch (nextStep['type']) {
    case 'turn':
      switch (nextStep['modifier']) {
        case 'left': symbol = '⬅️'; break;
        case 'right': symbol = '➡️'; break;
        case 'sharp left': symbol = '↖️'; break;
        case 'sharp right': symbol = '↗️'; break;
        case 'slight left': symbol = '↩️'; break;
        case 'slight right': symbol = '↪️'; break;
      }
      break;
    case 'arrive':
      symbol = '🏁';
      instruction = 'Destination reached';
      break;
    case 'roundabout':
      symbol = '🔄';
      break;
    case 'depart':
      symbol = '🚦';
      break;
  }

  return '$symbol ${nextStep['instruction']} (${distanceToNext.toStringAsFixed(2)} km)';
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
      setState(() => _totalDistance = 0.0);
      return;
    }

    _totalDistance = 0.0;
    for (int i = 0; i < _completeRoute.length - 1; i++) {
      _totalDistance += _haversineDistance(_completeRoute[i], _completeRoute[i + 1]);
    }
    setState(() {});
  }

  void _updateDirectionsBasedOnLocation() {
  if (_workerLocation == null || _completeRoute.isEmpty) return;

  // Find the nearest point on the route
  int nearestIndex = 0;
  double minDistance = double.infinity;
  
  for (int i = 0; i < _completeRoute.length; i++) {
    final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
    if (distance < minDistance) {
      minDistance = distance;
      nearestIndex = i;
    }
  }

  // Get the next significant point (skip very close points)
  int nextPointIndex = nearestIndex + 1;
  while (nextPointIndex < _completeRoute.length - 1 && 
         _haversineDistance(_completeRoute[nearestIndex], _completeRoute[nextPointIndex]) < 0.05) {
    nextPointIndex++;
  }

  if (nextPointIndex >= _completeRoute.length) {
    setState(() => _directions = '🏁 Destination reached');
    return;
  }

  final nextPoint = _completeRoute[nextPointIndex];
  final distanceToNext = _haversineDistance(_workerLocation!, nextPoint);
  final bearing = _calculateBearing(_workerLocation!, nextPoint);
  final directionSymbol = _getDirectionSymbol(bearing);

  String instruction;
  if (distanceToNext < 0.1) {
    instruction = 'Approaching next point';
  } else {
    instruction = '$directionSymbol In ${distanceToNext.toStringAsFixed(2)} km';
    
    // Add more specific instructions based on bearing
    if (bearing >= 22.5 && bearing < 67.5) {
      instruction += ' (Turn slight right)';
    } else if (bearing >= 67.5 && bearing < 112.5) {
      instruction += ' (Turn right)';
    } else if (bearing >= 112.5 && bearing < 157.5) {
      instruction += ' (Turn sharp right)';
    } else if (bearing >= 157.5 && bearing < 202.5) {
      instruction += ' (Continue straight)';
    } else if (bearing >= 202.5 && bearing < 247.5) {
      instruction += ' (Turn slight left)';
    } else if (bearing >= 247.5 && bearing < 292.5) {
      instruction += ' (Turn left)';
    } else if (bearing >= 292.5 && bearing < 337.5) {
      instruction += ' (Turn sharp left)';
    }
  }

  setState(() => _directions = instruction);

  if (_workerLocation == null || _completeRoute.isEmpty) return;
  setState(() => _directions = _getCurrentInstruction());
}

  void _startCollection() async {
    setState(() => _isLoading = true);
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) throw Exception('No authentication token found');

      final response = await http.post(
        Uri.parse('$apiBaseUrl/worker/start-task'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'taskId': widget.taskid}),
      );

      if (response.statusCode == 200) {
        setState(() => _collectionStarted = true);
      } else {
        throw Exception('Failed to start task: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error starting collection: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsCollected() async {
  if (_selectedLocation == null || _selectedReportId == null) return;

  setState(() => _isLoading = true);
  try {
    final token = await storage.read(key: 'jwt_token');
    if (token == null) throw Exception('No authentication token found');

    final response = await http.post(
      Uri.parse('$apiBaseUrl/worker/mark-collected'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'taskId': widget.taskid,
        'reportId': _selectedReportId,
      }),
    );

    final responseData = jsonDecode(response.body);

    if (response.statusCode == 200) {
      // Immediately update the UI
      setState(() {
        _collectedReports.add(_selectedReportId!);
        _locations.removeWhere((loc) => loc == _selectedLocation);
        _reportIds.remove(_selectedReportId);
        _wasteTypes.remove(_selectedWasteType);
        _selectedLocation = null;
        _selectedReportId = null;
        _selectedWasteType = null;
      });

      // Refresh the route
      if (_workerLocation != null && _locations.isNotEmpty) {
        _route = await _fetchRouteFromOSRM();
        _updateCompleteRoute();
        _calculateDistances();
      }

      if (responseData['taskStatus'] == 'completed') {
        // Show success message and navigate back
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task completed successfully!')),
        );
        Navigator.pop(context, true); // Pass true to indicate completion
      }
    } else {
      throw Exception('Failed to mark collected: ${response.body}');
    }
  } catch (e) {
    setState(() => _errorMessage = 'Error marking collected: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  } finally {
    setState(() => _isLoading = false);
  }
}

  void _selectLocation(int index) {
    if (index >= _locations.length) return;
    
    setState(() {
      _selectedLocation = _locations[index];
      _selectedReportId = _reportIds[index];
      _selectedWasteType = _wasteTypes[index];
    });
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
              onTap: (_, __) {
                setState(() {
                  _selectedLocation = null;
                  _selectedReportId = null;
                  _selectedWasteType = null;
                });
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
                      child: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  ..._locations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final loc = entry.value;
                    final isCollected = _collectedReports.contains(_reportIds[index]);

                    return Marker(
                      point: loc,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _selectLocation(index),
                        child: Icon(
                          isCollected ? Icons.check_circle : Icons.location_pin,
                          color: isCollected
                              ? Colors.green
                              : (_collectionStarted ? Colors.orange : Colors.red),
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
  _directions,
  style: const TextStyle(
    fontSize: 18, // Slightly larger for better visibility
    fontWeight: FontWeight.w600,
    color: Colors.white,
  ),
),
                  const SizedBox(height: 8),
                  Text(
                    'Total Distance: ${_totalDistance.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  if (_selectedLocation != null && _selectedWasteType != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Selected Location:',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                        Text(
                          'Waste Type: $_selectedWasteType',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                        Text(
                          'Coordinates: ${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                          '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                        if (_collectionStarted && !_collectedReports.contains(_selectedReportId))
                          ElevatedButton(
                            onPressed: _markAsCollected,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Mark as Collected'),
                          ),
                      ],
                    ),
                  if (_errorMessage.isNotEmpty)
                    Text(
                      'Error: $_errorMessage',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.redAccent,
                      ),
                    ),
                ],
              ),
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
                _mapController.move(_workerLocation!, 14);
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