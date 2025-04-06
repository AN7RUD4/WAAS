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
  LatLng? _currentCollectionPoint;
  String? _currentWasteType;

  double _totalDistance = 0.0;
  List<Map<String, dynamic>> _directionSteps = [];
  int _currentInstructionIndex = 0;

  @override
  void initState() {
    super.initState();
    print('Task ID from widget: ${widget.taskid}');
    _getWorkerLocation().then((_) => _fetchCollectionRequestData());
  }

  Future<void> _getWorkerLocation() async {
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
          _currentCenter =
              _workerLocation!; // Update map center with worker movement
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
  final String apiUrl =
      '$apiBaseUrl/worker/task-route/${widget.taskid}?workerLat=${_workerLocation?.latitude ?? 10.235865}&workerLng=${_workerLocation?.longitude ?? 76.405676}';

  try {
    final token = await storage.read(key: 'jwt_token');
    if (token == null) throw Exception('No authentication token found');

    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      print('Fetched data: $data'); // Debug log
      if (data['route'] != null && data['route'] is Map) {
        _parseRouteFromJson(data['route']);
      } else {
        setState(() => _errorMessage = 'No route data found in task');
      }

      if (data['locations'] != null && data['locations'] is List) {
        _parseLocations(data['locations']);
      }

      if (_workerLocation == null && data['workerLocation'] != null) {
        _workerLocation = LatLng(
          data['workerLocation']['lat'],
          data['workerLocation']['lng'],
        );
        _currentCenter = _workerLocation!;
      }

      // Safely convert collected report IDs to Set<int>
      if (data['locations'] != null && data['locations'] is List) {
        setState(() {
          _collectionStarted = data['status'] == 'in-progress';
          _collectedReports = (data['locations']
                  .where((loc) => loc['status'] == 'collected')
                  .map((loc) => int.tryParse(loc['reportid'].toString()) ?? -1)
                  .where((id) => id != -1)
                  .toSet()) as Set<int>; // Ensure Set<int>
        });
      }

      if (_workerLocation != null && _locations.isNotEmpty) {
        _route = await _fetchRouteFromOSRM();
        if (_route.isEmpty) {
          _route = [_workerLocation!, ..._locations];
          setState(
            () => _errorMessage =
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
        setState(() => _errorMessage = 'Missing worker location or collection points');
      }
    } else {
      setState(
        () =>
            _errorMessage =
                'Failed to fetch task data: ${response.statusCode} - ${response.body}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to fetch task data: ${response.statusCode} - ${response.body}',
          ),
        ),
      );
    }
  } catch (e) {
    setState(() => _errorMessage = 'Error fetching task data: $e');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error fetching task data: $e')));
  } finally {
    setState(() => _isLoading = false);
  }
}

  void _parseRouteFromJson(Map<String, dynamic> routeData) {
    _locations.clear();
    _route.clear();
    _reportIds.clear();
    _wasteTypes.clear();

    if (_workerLocation != null) {
      _locations.add(_workerLocation!); // Start from worker's current location
      _route.add(_workerLocation!);
    }

    if (routeData['waypoints'] != null && routeData['waypoints'] is List) {
      for (var waypoint in routeData['waypoints']) {
        if (waypoint['lat'] != null &&
            waypoint['lng'] != null &&
            waypoint['reportid'] != null) {
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
      if (item['lat'] != null &&
          item['lng'] != null &&
          item['reportid'] != null) {
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
    final String osrmBaseUrl =
        'http://router.project-osrm.org/route/v1/driving/';
    String coordinates = waypoints
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final String osrmUrl =
        '$osrmBaseUrl$coordinates?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(Uri.parse(osrmUrl));
      print('OSRM Response: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final routeGeometry = route['geometry']['coordinates'];

          if (routeGeometry is! List || routeGeometry.isEmpty) {
            throw Exception('Invalid route geometry data from OSRM');
          }

          List<LatLng> routePoints = [];
          for (var coord in routeGeometry) {
            if (coord is List &&
                coord.length >= 2 &&
                coord[0] is num &&
                coord[1] is num) {
              routePoints.add(LatLng(coord[1].toDouble(), coord[0].toDouble()));
            } else {
              print('Skipping invalid coordinate: $coord');
            }
          }

          if (routePoints.isEmpty) {
            throw Exception('No valid coordinates found in route geometry');
          }

          _directionSteps.clear();
          final legs = route['legs'];
          double cumulativeDistance = 0.0;
          for (var leg in legs) {
            for (var step in leg['steps']) {
              if (step['maneuver'] != null &&
                  step['maneuver']['instruction'] != null) {
                String symbol = _convertInstructionToSymbol(
                  step['maneuver']['instruction'],
                );
                if (symbol.isNotEmpty) {
                  cumulativeDistance += (step['distance'] ?? 0.0) / 1000;
                  _directionSteps.add({
                    'symbol': symbol,
                    'distance': cumulativeDistance.toStringAsFixed(2),
                  });
                }
              }
            }
          }
          _currentInstructionIndex = 0;
          _directions =
              _directionSteps.isNotEmpty
                  ? '${_directionSteps[0]['symbol']} (${_directionSteps[0]['distance']} km)'
                  : "🡺 (0.00 km)";

          return routePoints;
        } else {
          throw Exception(
            'OSRM API error: ${data['message'] ?? 'No routes found'}',
          );
        }
      } else {
        throw Exception(
          'Failed to fetch route from OSRM: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Error fetching route from OSRM: $e');
      setState(() {
        _errorMessage =
            'Error fetching route from OSRM: $e. Falling back to straight-line path.';
        _directions = '🡺 (0.00 km)';
      });
      return [
        _workerLocation!,
        ..._locations,
      ]; // Fallback with worker location first
    }
  }

  String _convertInstructionToSymbol(String instruction) {
    if (instruction.toLowerCase().contains('turn left')) return '⬅️';
    if (instruction.toLowerCase().contains('turn right')) return '➡️';
    if (instruction.toLowerCase().contains('continue')) return '🡺';
    if (instruction.toLowerCase().contains('uturn')) return '↺';
    if (instruction.toLowerCase().contains('arrive')) return '🏁';
    return '🡺';
  }

  void _updateCompleteRoute() {
    if (_workerLocation == null || _route.isEmpty) {
      _completeRoute = _route;
      return;
    }
    // Only include uncollected locations in the route
    _completeRoute = [
      _workerLocation!,
      ..._route
          .sublist(1)
          .where(
            (loc) =>
                !_locations.contains(loc) ||
                !_collectedReports.contains(
                  _getReportIdForIndex(_locations.indexOf(loc) + 1),
                ),
          ),
    ];
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
    return earthRadius * c * 1000; // Return in meters
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180.0);

  void _calculateDistances() {
    if (_workerLocation == null || _completeRoute.isEmpty) {
      setState(() {
        _totalDistance = 0.0;
      });
      return;
    }

    _totalDistance = 0.0;
    for (int i = 0; i < _completeRoute.length - 1; i++) {
      _totalDistance +=
          _haversineDistance(_completeRoute[i], _completeRoute[i + 1]) /
          1000; // Convert to km
    }
    setState(() {});
  }

  void _updateDirectionsBasedOnLocation() {
    if (_workerLocation == null ||
        _completeRoute.isEmpty ||
        _directionSteps.isEmpty)
      return;

    double minDistance = double.infinity;
    int closestIndex = 0;
    for (int i = 0; i < _completeRoute.length; i++) {
      final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    if (minDistance < 0.05 * 1000 &&
        _currentInstructionIndex < _directionSteps.length - 1) {
      _currentInstructionIndex++;
      _directions =
          '${_directionSteps[_currentInstructionIndex]['symbol']} (${_directionSteps[_currentInstructionIndex]['distance']} km)';
      setState(() {});
    }
  }

  void _startCollection() async {
    setState(() => _isLoading = true);

    try {
      final token = await storage.read(key: 'jwt_token');
      print('Token: $token');
      if (token == null) throw Exception('No authentication token found');

      print('Starting collection for taskId: ${widget.taskid}');
      final response = await http.post(
        Uri.parse('$apiBaseUrl/worker/start-task'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'taskId': widget.taskid}),
      );

      print('Response status: ${response.statusCode}, Body: ${response.body}');
      if (response.statusCode == 200) {
        setState(() {
          _collectionStarted = true;
          _errorMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Collection started! Tap on locations to mark as collected',
            ),
          ),
        );
      } else if (response.statusCode == 403) {
        throw Exception('Access denied: ${response.body}');
      } else {
        throw Exception(
          'Failed to start task: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error starting collection: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting collection: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsCollected(
    LatLng location,
    int reportId,
    String wasteType,
  ) async {
    if (_collectedReports.contains(reportId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This report is already collected')),
      );
      return;
    }

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
          final index = _locations.indexWhere((loc) => loc == location);
          if (index != -1) {
            _locations.removeAt(index);
            _route.removeAt(index); // Remove from route
            _reportIds.removeAt(index - 1); // Adjust for worker location
            _wasteTypes.removeAt(index - 1);
          }
          _currentCollectionPoint = null;
          _currentWasteType = null;
          _updateCompleteRoute(); // Recalculate route
          _calculateDistances();
          _updateDirectionsBasedOnLocation();
        });

        if (responseData['taskStatus'] == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All locations collected! Task completed'),
            ),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${responseData['message']} (${responseData['remainingReports']} remaining)',
              ),
            ),
          );
        }
      } else {
        throw Exception(responseData['error'] ?? 'Failed to mark collected');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error marking collected: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error marking collected: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  int _getReportIdForIndex(int index) {
    return index < _reportIds.length + 1
        ? _reportIds[index - 1]
        : -1; // Adjust for worker location
  }

  String _getWasteTypeForIndex(int index) {
    return index < _wasteTypes.length + 1
        ? _wasteTypes[index - 1]
        : 'Unknown'; // Adjust for worker location
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_currentCollectionPoint != null) {
          setState(() {
            _currentCollectionPoint = null;
            _currentWasteType = null;
          });
        }
      },
      child: Scaffold(
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
                // Removed PolylineLayer to hide worker's path
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
                      final reportId = _getReportIdForIndex(
                        index + 1,
                      ); // +1 to skip worker location
                      final wasteType = _getWasteTypeForIndex(index + 1);

                      return Marker(
                        point: loc,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            if (_collectionStarted &&
                                !_collectedReports.contains(reportId)) {
                              setState(() {
                                _currentCollectionPoint = loc;
                                _currentWasteType = wasteType;
                              });
                            }
                          },
                          child: Icon(
                            _collectedReports.contains(reportId)
                                ? Icons.check_circle
                                : Icons.location_pin,
                            color:
                                _collectedReports.contains(reportId)
                                    ? Colors.green
                                    : (_collectionStarted
                                        ? Colors.orangeAccent
                                        : Colors.redAccent),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Total Distance: ${_totalDistance.toStringAsFixed(2)} km',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    if (_currentCollectionPoint != null &&
                        _currentWasteType != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Selected Location Details:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            'Waste Type: $_currentWasteType',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            'Location: ${_currentCollectionPoint!.latitude.toStringAsFixed(6)}, '
                            '${_currentCollectionPoint!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed:
                                _collectionStarted &&
                                        !_collectedReports.contains(
                                          _getReportIdForIndex(
                                            _locations.indexOf(
                                                  _currentCollectionPoint!,
                                                ) +
                                                1,
                                          ),
                                        )
                                    ? () => _markAsCollected(
                                      _currentCollectionPoint!,
                                      _getReportIdForIndex(
                                        _locations.indexOf(
                                              _currentCollectionPoint!,
                                            ) +
                                            1,
                                      ),
                                      _currentWasteType!,
                                    )
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Collected'),
                          ),
                        ],
                      ),
                    if (_errorMessage.isNotEmpty)
                      Column(
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Error: $_errorMessage',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.green),
              ),
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
      ),
    );
  }
}

/*require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const KMeans = require('kmeans-js');
const munkres = require('munkres').default;
const twilio = require('twilio');

const router = express.Router();
router.use(cors());
router.use(express.json());

// Initialize Twilio client
const twilioClient = new twilio(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
);

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
});

pool.connect((err, client, release) => {
    if (err) {
        console.error('Error connecting to the database in worker.js:', err.stack);
        process.exit(1);
    } else {
        console.log('Worker.js successfully connected to the database');
        release();
    }
});

// Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    console.log('Auth header:', authHeader);

    if (!token) {
        console.log('No token provided');
        return res.status(401).json({ message: 'Authentication token required' });
    }

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || 'passwordKey');
        console.log('Decoded token:', decoded);
        if (!decoded.userid || !decoded.role) {
            console.log('Invalid token: missing userid or role');
            return res.status(403).json({ message: 'Invalid token: Missing userid or role' });
        }
        req.user = decoded;
        next();
    } catch (err) {
        console.error('Token verification error:', err.message);
        return res.status(403).json({ message: 'Invalid or expired token' });
    }
};

// Role check middleware
const checkWorkerOrAdminRole = (req, res, next) => {
    console.log('Checking role for user:', req.user);
    if (!req.user || (req.user.role.toLowerCase() !== 'worker' && req.user.role.toLowerCase() !== 'admin')) {
        console.log('Access denied: role not worker or admin');
        return res.status(403).json({ message: 'Access denied: Only workers or admins can access this endpoint' });
    }
    next();
};

// Haversine distance function
function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

// Distance calculation for clustering
function calculateDistance(point1, point2) {
    const latDiff = point1[0] - point2[0];
    const lngDiff = point1[1] - point2[1];
    return Math.sqrt(latDiff * latDiff + lngDiff * lngDiff);
}

// Ensure unique centroids
function uniqueCentroids(centroids) {
    const unique = [];
    const seen = new Set();

    centroids.forEach((centroid) => {
        const key = centroid.join(",");
        if (!seen.has(key)) {
            seen.add(key);
            unique.push(centroid);
        }
    });

    return unique;
}

// K-Means clustering function
function kmeansClustering(points, k) {
    if (!Array.isArray(points) || points.length === 0) {
        console.log('kmeansClustering: Invalid or empty points array, returning empty clusters');
        return [];
    }
    if (points.length < k) {
        console.log(`kmeansClustering: Fewer points (${points.length}) than clusters (${k}), returning single-point clusters`);
        return points.map(point => [point]);
    }

    console.log('kmeansClustering: Starting with points:', points);
    const kmeans = new KMeans();
    const data = points.map(p => [p.lat, p.lng]);
    console.log('kmeansClustering: Data for clustering:', data);

    try {
        let centroids;
        let attempts = 0;
        const maxAttempts = 5;

        do {
            centroids = kmeans.cluster(data, k, "kmeans++");
            centroids = uniqueCentroids(centroids);
            attempts++;
            console.log(`kmeansClustering: Attempt ${attempts}, Centroids:`, centroids);
        } while (centroids.length < k && attempts < maxAttempts);

        k = Math.min(k, centroids.length);
        console.log('kmeansClustering: Final centroids after unique filtering:', centroids);

        if (!Array.isArray(centroids) || centroids.length === 0) {
            console.log('kmeansClustering: No valid centroids, returning single-point clusters');
            return points.map(point => [point]);
        }

        const clusters = Array.from({ length: k }, () => []);
        points.forEach((point) => {
            const pointCoords = [point.lat, point.lng];
            let closestCentroidIdx = 0;
            let minDistance = calculateDistance(pointCoords, centroids[0]);

            for (let i = 1; i < centroids.length; i++) {
                const distance = calculateDistance(pointCoords, centroids[i]);
                if (distance < minDistance) {
                    minDistance = distance;
                    closestCentroidIdx = i;
                }
            }

            if (closestCentroidIdx >= clusters.length) {
                console.error(`⚠️ Invalid centroid index ${closestCentroidIdx} for point ${point.reportid}`);
                return;
            }

            clusters[closestCentroidIdx].push(point);
        });

        const validClusters = clusters.filter(cluster => cluster.length > 0);
        console.log('kmeansClustering: Resulting clusters:', validClusters);
        return validClusters;
    } catch (error) {
        console.error('kmeansClustering: Clustering failed:', error.message);
        return points.map(point => [point]);
    }
}

// Updated assignWorkersToClusters function (using munkres)
function assignWorkersToClusters(clusters, workers) {
    if (!clusters.length || !workers.length) {
        console.log('assignWorkersToClusters: No clusters or workers, returning empty assignments');
        return [];
    }

    console.log('assignWorkersToClusters: Clusters:', clusters);
    console.log('assignWorkersToClusters: Workers:', workers);

    const costMatrix = clusters.map(cluster => {
        const centroid = {
            lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
            lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length,
        };
        return workers.map(worker => {
            const distance = haversineDistance(worker.lat, worker.lng, centroid.lat, centroid.lng);
            return distance + Math.random() * 0.0001;
        });
    });
    console.log('assignWorkersToClusters: Cost matrix:', costMatrix);

    const maxDim = Math.max(clusters.length, workers.length);
    const paddedMatrix = costMatrix.map(row => [...row]);
    paddedMatrix.forEach(row => {
        while (row.length < maxDim) row.push(Number.MAX_SAFE_INTEGER);
    });
    while (paddedMatrix.length < maxDim) {
        paddedMatrix.push(Array(maxDim).fill(Number.MAX_SAFE_INTEGER));
    }
    console.log('assignWorkersToClusters: Padded cost matrix:', paddedMatrix);

    try {
        const indices = munkres(paddedMatrix);
        console.log('assignWorkersToClusters: Munkres indices:', indices);

        const assignments = [];
        const usedWorkers = new Set();

        indices.forEach(([clusterIdx, workerIdx]) => {
            if (clusterIdx < clusters.length && workerIdx < workers.length && !usedWorkers.has(workerIdx)) {
                assignments.push({
                    cluster: clusters[clusterIdx],
                    worker: workers[workerIdx],
                });
                usedWorkers.add(workerIdx);
            }
        });

        console.log('assignWorkersToClusters: Assignments:', assignments);
        return assignments;
    } catch (error) {
        console.error('assignWorkersToClusters: Munkres failed:', error.message);
        const assignments = [];
        const availableWorkers = [...workers];
        for (const cluster of clusters) {
            if (availableWorkers.length === 0) break;
            const centroid = {
                lat: cluster.reduce((sum, r) => sum + r.lat, 0) / cluster.length,
                lng: cluster.reduce((sum, r) => sum + r.lng, 0) / cluster.length,
            };
            const bestWorkerIdx = availableWorkers.reduce((best, w, idx) => {
                const dist = haversineDistance(w.lat, w.lng, centroid.lat, centroid.lng);
                return dist < best.dist ? { idx, dist } : best;
            }, { idx: 0, dist: Infinity }).idx;
            assignments.push({
                cluster,
                worker: availableWorkers[bestWorkerIdx],
            });
            availableWorkers.splice(bestWorkerIdx, 1);
        }
        console.log('assignWorkersToClusters: Fallback assignments:', assignments);
        return assignments;
    }
}

// Solve TSP for route optimization
function solveTSP(points, worker) {
    if (points.length === 0) return {
        start: { lat: worker.lat, lng: worker.lng },
        waypoints: [],
        end: { lat: worker.lat, lng: worker.lng }
    };

    const route = [{ lat: worker.lat, lng: worker.lng }];
    const unvisited = [...points];
    let current = { lat: worker.lat, lng: worker.lng };

    while (unvisited.length > 0) {
        const nearest = unvisited.reduce((closest, point) => {
            const distance = haversineDistance(current.lat, current.lng, point.lat, point.lng);
            return (!closest || distance < closest.distance) ? { point, distance } : closest;
        }, null);

        route.push({ lat: nearest.point.lat, lng: nearest.point.lng });
        current = { lat: nearest.point.lat, lng: nearest.point.lng };
        unvisited.splice(unvisited.indexOf(nearest.point), 1);
    }
    route.push({ lat: worker.lat, lng: worker.lng });

    return {
        start: { lat: route[0].lat, lng: route[0].lng },
        waypoints: route.slice(1, -1).map(point => ({ lat: point.lat, lng: point.lng })),
        end: { lat: route[route.length - 1].lat, lng: route[route.length - 1].lng }
    };
}

// Send SMS notification function
async function sendSMS(phoneNumber, messageBody) {
    try {
        await twilioClient.messages.create({
            body: messageBody,
            from: process.env.TWILIO_PHONE_NUMBER,
            to: phoneNumber,
        });
        console.log(`SMS sent to ${phoneNumber}: ${messageBody}`);
    } catch (smsError) {
        console.error('Error sending SMS:', smsError.message, smsError.stack);
        throw new Error('Failed to send SMS notification');
    }
}

// Group and assign reports endpoint with SMS notification
router.post('/group-and-assign-reports', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    console.log('Reached /group-and-assign-reports endpoint');
    try {
        console.log('Starting /group-and-assign-reports execution');
        const { startDate } = req.body;
        const k = 3;
        console.log('Request body:', req.body);

        console.log('Fetching unassigned reports from garbagereports...');
        let result = await pool.query(
            `SELECT reportid, wastetype, ST_AsText(location) AS location, datetime, userid
             FROM garbagereports
             WHERE reportid NOT IN (
               SELECT unnest(reportids) FROM taskrequests
             )
             ORDER BY datetime ASC`
        );
        console.log('Fetched reports:', result.rows);

        let reports = result.rows.map(row => {
            const locationMatch = row.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
            return {
                reportid: row.reportid,
                wastetype: row.wastetype,
                lat: locationMatch ? parseFloat(locationMatch[2]) : null,
                lng: locationMatch ? parseFloat(locationMatch[1]) : null,
                created_at: new Date(row.datetime),
                userid: row.userid,
            };
        });

        if (!reports.length) {
            console.log('No unassigned reports found, exiting endpoint');
            return res.status(200).json({ message: 'No unassigned reports found' });
        }
        console.log('Reports with user IDs:', reports);

        reports = reports.filter(r => r.lat !== null && r.lng !== null);
        console.log('Filtered reports with valid locations:', reports);

        const processedReports = new Set();
        const assignments = [];

        while (reports.length > 0) {
            console.log('Entering temporal filtering loop, remaining reports:', reports.length);
            const T0 = startDate ? new Date(startDate) : reports[0].created_at;
            const T0Plus2Days = new Date(T0);
            T0Plus2Days.setDate(T0.getDate() + 2);
            console.log('Temporal window - T0:', T0, 'T0Plus2Days:', T0Plus2Days);

            const timeFilteredReports = reports.filter(
                report => report.created_at >= T0 && report.created_at <= T0Plus2Days && !processedReports.has(report.reportid)
            );
            console.log('Time-filtered reports:', timeFilteredReports);

            if (timeFilteredReports.length === 0) {
                console.log('No reports within temporal window, breaking loop');
                break;
            }

            console.log('Performing K-Means clustering...');
            const clusters = kmeansClustering(timeFilteredReports, Math.min(k, timeFilteredReports.length));
            console.log('Clusters formed:', clusters);

            console.log('Fetching available workers...');
            let workerResult = await pool.query(
                `SELECT userid, ST_AsText(location) AS location
                 FROM users
                 WHERE role = 'worker'
                 AND userid NOT IN (
                   SELECT assignedworkerid
                   FROM taskrequests
                   WHERE status != 'completed'
                   GROUP BY assignedworkerid
                   HAVING COUNT(*) >= 5
                 )`
            );
            let workers = workerResult.rows.map(row => {
                const locMatch = row.location ? row.location.match(/POINT\(([^ ]+) ([^)]+)\)/) : null;
                return {
                    userid: row.userid,
                    lat: locMatch ? parseFloat(locMatch[2]) : 10.235865,
                    lng: locMatch ? parseFloat(locMatch[1]) : 76.405676,
                };
            });
            console.log('Available workers:', workers);

            if (workers.length === 0) {
                console.log('No workers available, breaking loop');
                break;
            }

            console.log('Assigning workers to clusters...');
            const clusterAssignments = assignWorkersToClusters(clusters, workers);
            console.log('Cluster assignments:', clusterAssignments);

            if (clusterAssignments.length === 0) {
                console.log('No assignments made, skipping insertion');
                break;
            }

            for (const { cluster, worker } of clusterAssignments) {
                console.log(`Processing cluster for worker ${worker.userid}, reports:`, cluster);
                const route = solveTSP(cluster, worker);
                console.log('TSP Route:', route);

                const reportIds = cluster.map(report => report.reportid);
                console.log('Report IDs for task:', reportIds);

                console.log('Inserting task into taskrequests...');
                let taskResult = await pool.query(
                    `INSERT INTO taskrequests (reportids, assignedworkerid, status, starttime, route)
                     VALUES ($1, $2, 'assigned', NOW(), $3)
                     RETURNING taskid`,
                    [reportIds, worker.userid, route]
                );
                const taskId = taskResult.rows[0].taskid;
                console.log(`Task inserted successfully with taskId: ${taskId}`);

                const uniqueUserIds = [...new Set(cluster.map(report => report.userid))];
                for (const userId of uniqueUserIds) {
                    try {
                        const userResult = await pool.query(
                            `SELECT phone FROM users WHERE userid = $1`,
                            [userId]
                        );
                        if (userResult.rows.length > 0 && userResult.rows[0].phone) {
                            const phoneNumber = userResult.rows[0].phone;
                            const messageBody = `Your garbage report has been assigned to a worker (Task ID: ${taskId}).`;
                            await sendSMS(phoneNumber, messageBody);
                        } else {
                            console.warn(`No phone number found for user ${userId}`);
                        }
                    } catch (error) {
                        console.error(`Failed to send SMS for user ${userId}:`, error.message);
                    }
                }

                cluster.forEach(report => processedReports.add(report.reportid));
                assignments.push({
                    taskId: taskId,
                    reportIds: reportIds,
                    assignedWorkerId: worker.userid,
                    route: route,
                });
            }

            reports = reports.filter(r => !processedReports.has(r.reportid));
        }

        console.log('Endpoint completed successfully, assignments:', assignments);
        res.status(200).json({
            message: 'Reports grouped and assigned successfully, SMS notifications sent where possible',
            assignments,
        });
    } catch (error) {
        console.error('Error in group-and-align-reports:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Fetch Assigned Tasks for Worker
router.get('/assigned-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const tasksResult = await pool.query(
            `SELECT taskid, reportids, status, starttime, route 
             FROM taskrequests 
             WHERE assignedworkerid = $1 AND status != 'completed'`,
            [workerId]
        );

        if (tasksResult.rows.length === 0) {
            return res.json({ assignedWorks: [] });
        }

        const assignedWorks = [];

        for (const task of tasksResult.rows) {
            const reportsResult = await pool.query(
                `SELECT reportid, wastetype, location 
                 FROM garbagereports 
                 WHERE reportid = ANY($1) 
                 LIMIT 1`,
                [task.reportids]
            );

            if (reportsResult.rows.length > 0) {
                const report = reportsResult.rows[0];
                const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
                const reportLat = locationMatch ? parseFloat(locationMatch[2]) : null;
                const reportLng = locationMatch ? parseFloat(locationMatch[1]) : null;

                const workerLat = 10.235865;
                const workerLng = 76.405676;

                let distance = '0km';
                if (reportLat && reportLng) {
                    distance = (haversineDistance(workerLat, workerLng, reportLat, reportLng)).toFixed(2) + 'km';
                }

                assignedWorks.push({
                    taskId: task.taskid.toString(),
                    title: report.wastetype ?? 'Unknown',
                    reportCount: task.reportids.length,
                    firstLocation: report.location,
                    distance: distance,
                    time: task.starttime ? task.starttime.toISOString() : 'Not Started',
                    status: task.status,
                });
            }
        }

        res.json({ assignedWorks });
    } catch (error) {
        console.error('Error fetching assigned tasks in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Map endpoint
router.get('/task-route/:taskid', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    const taskId = parseInt(req.params.taskid, 10);
    const workerId = req.user.userid;
    const workerLat = parseFloat(req.query.workerLat) || 10.235865;
    const workerLng = parseFloat(req.query.workerLng) || 76.405676;

    try {
        const taskResult = await pool.query(
            `SELECT taskid, reportids, assignedworkerid, status, route, starttime, endtime
             FROM taskrequests
             WHERE taskid = $1 AND assignedworkerid = $2`,
            [taskId, workerId]
        );

        if (taskResult.rows.length === 0) {
            return res.status(404).json({ message: 'Task not found or not assigned to this worker' });
        }

        const task = taskResult.rows[0];

        const reportsResult = await pool.query(
            `SELECT reportid, wastetype, ST_AsText(location) AS location 
             FROM garbagereports 
             WHERE reportid = ANY($1)`,
            [task.reportids]
        );

        const collectionPoints = reportsResult.rows.map(report => {
            const locationMatch = report.location.match(/POINT\(([^ ]+) ([^)]+)\)/);
            return {
                reportid: report.reportid,
                wastetype: report.wastetype,
                lat: locationMatch ? parseFloat(locationMatch[2]) : null,
                lng: locationMatch ? parseFloat(locationMatch[1]) : null,
            };
        }).filter(point => point.lat !== null && point.lng !== null);

        const routeData = task.route || { start: {}, waypoints: [], end: {} };

        res.status(200).json({
            taskid: task.taskid,
            reportids: task.reportids,
            status: task.status,
            route: routeData,
            locations: collectionPoints,
            wasteTypes: [...new Set(collectionPoints.map(p => p.wastetype))],
            workerLocation: { lat: workerLat, lng: workerLng }
        });
    } catch (error) {
        console.error('Error fetching task route:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Update Task Progress
router.patch('/update-progress', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, progress, status } = req.body;
        if (!taskId || progress === undefined || !status) {
            return res.status(400).json({ error: 'Task ID, progress, and status are required' });
        }

        const taskIdInt = parseInt(taskId, 10);
        if (isNaN(taskIdInt)) {
            return res.status(400).json({ error: 'Invalid Task ID' });
        }

        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const progressFloat = parseFloat(progress);
        if (isNaN(progressFloat) || progressFloat < 0 || progressFloat > 1) {
            return res.status(400).json({ error: 'Progress must be a number between 0 and 1' });
        }

        const validStatuses = ['pending', 'assigned', 'in-progress', 'completed', 'failed'];
        if (!validStatuses.includes(status)) {
            return res.status(400).json({ error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` });
        }

        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
            [taskIdInt, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({ error: 'Task not assigned to this worker' });
        }

        const updateFields = ['progress = $1', 'status = $2'];
        const updateValues = [progressFloat, status];

        if (status === 'completed') {
            updateFields.push('endtime = NOW()');
        }

        await pool.query(
            `UPDATE taskrequests SET ${updateFields.join(', ')} WHERE taskid = $${updateFields.length + 1}`,
            updateValues.concat([taskIdInt])
        );

        res.json({ message: 'Task updated successfully' });
    } catch (error) {
        console.error('Error updating task progress in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Fetch Completed Tasks
router.get('/completed-tasks', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const workerId = parseInt(req.user.userid, 10);
        if (isNaN(workerId)) {
            return res.status(400).json({ error: 'Invalid worker ID in token' });
        }

        const tasksResult = await pool.query(
            `SELECT taskid, reportids, endtime 
             FROM taskrequests 
             WHERE assignedworkerid = $1 AND status = 'completed'`,
            [workerId]
        );

        const completedWorks = [];

        for (const task of tasksResult.rows) {
            const reportsResult = await pool.query(
                `SELECT array_agg(DISTINCT wastetype) as wastetypes, COUNT(reportid) as report_count
                 FROM garbagereports 
                 WHERE reportid = ANY($1)`,
                [task.reportids]
            );
            if (reportsResult.rows.length > 0) {
                const report = reportsResult.rows[0];
                completedWorks.push({
                    taskId: task.taskid.toString(),
                    title: report.wastetypes.join(', '),
                    reportCount: report.report_count,
                    endTime: task.endtime ? task.endtime.toISOString() : null,
                });
            }
        }

        res.json({ completedWorks });
    } catch (error) {
        console.error('Error fetching completed tasks in worker.js:', error.message, error.stack);
        res.status(500).json({ error: 'Internal Server Error', details: error.message });
    }
});

// Start task endpoint
router.post('/start-task', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId } = req.body;
        const workerId = req.user.userid;

        console.log(`Attempting to start task with taskId: ${taskId}, workerId: ${workerId}`);

        const taskCheck = await pool.query(
            `SELECT 1 FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2 AND status = 'assigned'`,
            [taskId, workerId]
        );
        console.log(`Task check query result: ${JSON.stringify(taskCheck.rows)}`);

        if (taskCheck.rows.length === 0) {
            const taskState = await pool.query(
                `SELECT status FROM taskrequests WHERE taskid = $1 AND assignedworkerid = $2`,
                [taskId, workerId]
            );
            console.log(`Task state for taskId ${taskId}: ${JSON.stringify(taskState.rows)}`);
            return res.status(403).json({
                error: 'Task not assigned to this worker or not in assigned state',
                taskState: taskState.rows.length > 0 ? taskState.rows[0].status : 'not found'
            });
        }

        await pool.query(
            `UPDATE taskrequests 
             SET status = 'in-progress', 
                 starttime = NOW()
             WHERE taskid = $1`,
            [taskId]
        );

        console.log(`Task ${taskId} started by worker ${workerId}, status updated to in-progress`);
        res.status(200).json({
            message: 'Task started successfully',
            status: 'in-progress'
        });
    } catch (error) {
        console.error('Error starting task:', error.message, error.stack);
        res.status(500).json({
            error: 'Internal Server Error',
            details: error.message
        });
    }
});

// Mark collected endpoint
router.post('/mark-collected', authenticateToken, checkWorkerOrAdminRole, async (req, res) => {
    try {
        const { taskId, reportId } = req.body;
        const workerId = req.user.userid;

        const taskCheck = await pool.query(
            `SELECT reportids FROM taskrequests 
             WHERE taskid = $1 AND assignedworkerid = $2 AND status = 'in-progress'`,
            [taskId, workerId]
        );

        if (taskCheck.rows.length === 0) {
            return res.status(403).json({
                error: 'Task not assigned to this worker or not in progress'
            });
        }

        const reportIds = taskCheck.rows[0].reportids;

        if (!reportIds.includes(reportId)) {
            return res.status(404).json({
                error: 'Report not found in this task'
            });
        }

        await pool.query(
            `UPDATE garbagereports 
             SET status = 'collected' 
             WHERE reportid = $1`,
            [reportId]
        );

        const uncollectedCount = await pool.query(
            `SELECT COUNT(*) FROM garbagereports 
             WHERE reportid = ANY($1) AND status != 'collected'`,
            [reportIds]
        );

        const remaining = uncollectedCount.rows[0].count;

        if (remaining === 0) {
            await pool.query(
                `UPDATE taskrequests 
                 SET status = 'completed', 
                     endtime = NOW()
                 WHERE taskid = $1`,
                [taskId]
            );
            return res.status(200).json({
                message: 'All reports collected! Task completed',
                taskStatus: 'completed'
            });
        }

        res.status(200).json({
            message: 'Report marked as collected successfully',
            remainingReports: remaining,
            taskStatus: 'in-progress'
        });
    } catch (error) {
        console.error('Error marking report as collected:', error);
        res.status(500).json({
            error: 'Internal Server Error',
            details: error.message
        });
    }
});

module.exports = router;


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
  LatLng? _currentCollectionPoint;
  String? _currentWasteType;

  double _totalDistance = 0.0;
  List<Map<String, dynamic>> _directionSteps =
      []; // Store symbol and distance for each step
  int _currentInstructionIndex = 0;

  @override
  void initState() {
    super.initState();
    print('Task ID from widget: ${widget.taskid}'); // Debug taskId
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
        if (data['route'] != null && data['route'] is Map) {
          _parseRouteFromJson(data['route']);
        } else {
          setState(() => _errorMessage = 'No route data found in task');
        }

        if (data['locations'] != null && data['locations'] is List) {
          _parseLocations(data['locations']);
        }

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
            _route = _locations;
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
                  'Failed to fetch task data: ${response.statusCode} - ${response.body}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to fetch task data: ${response.statusCode} - ${response.body}',
            ),
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
    _reportIds.clear();
    _wasteTypes.clear();

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

    if (routeData['waypoints'] != null && routeData['waypoints'] is List) {
      for (var waypoint in routeData['waypoints']) {
        if (waypoint['lat'] != null &&
            waypoint['lng'] != null &&
            waypoint['reportid'] != null) {
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
      if (item['lat'] != null &&
          item['lng'] != null &&
          item['reportid'] != null) {
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
    final String osrmBaseUrl =
        'http://router.project-osrm.org/route/v1/driving/';
    String coordinates = waypoints
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final String osrmUrl =
        '$osrmBaseUrl$coordinates?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(Uri.parse(osrmUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final routeGeometry = data['routes'][0]['geometry']['coordinates'];
          List<LatLng> routePoints =
              routeGeometry
                  .map<LatLng>((coord) => LatLng(coord[1], coord[0]))
                  .toList();

          _directionSteps.clear();
          final legs = data['routes'][0]['legs'];
          double cumulativeDistance = 0.0;
          for (var leg in legs) {
            for (var step in leg['steps']) {
              if (step['maneuver'] != null &&
                  step['maneuver']['instruction'] != null) {
                String symbol = _convertInstructionToSymbol(
                  step['maneuver']['instruction'],
                );
                if (symbol.isNotEmpty) {
                  cumulativeDistance +=
                      (step['distance'] ?? 0.0) / 1000; // Convert meters to km
                  _directionSteps.add({
                    'symbol': symbol,
                    'distance': cumulativeDistance.toStringAsFixed(2),
                  });
                }
              }
            }
          }
          _currentInstructionIndex = 0;
          _directions =
              _directionSteps.isNotEmpty
                  ? '${_directionSteps[0]['symbol']} (${_directionSteps[0]['distance']} km)'
                  : "🡺 (0.00 km)";

          return routePoints;
        } else {
          throw Exception('OSRM API error: ${data['message']}');
        }
      } else {
        throw Exception(
          'Failed to fetch route from OSRM: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error fetching route from OSRM: $e');
      setState(() {
        _errorMessage = 'Error fetching route from OSRM: $e';
        _directions = '🡺 (0.00 km)';
      });
      return _locations;
    }
  }

  // Convert text instructions to symbols
  String _convertInstructionToSymbol(String instruction) {
    if (instruction.toLowerCase().contains('turn left')) return '⬅️';
    if (instruction.toLowerCase().contains('turn right')) return '➡️';
    if (instruction.toLowerCase().contains('continue')) return '🡺';
    if (instruction.toLowerCase().contains('uturn')) return '↺';
    if (instruction.toLowerCase().contains('arrive')) return '🏁';
    return '🡺'; // Default straight arrow
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
      setState(() {
        _totalDistance = 0.0;
      });
      return;
    }

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
        _directionSteps.isEmpty)
      return;

    double minDistance = double.infinity;
    int closestIndex = 0;
    for (int i = 0; i < _completeRoute.length; i++) {
      final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    if (minDistance < 0.05 &&
        _currentInstructionIndex < _directionSteps.length - 1) {
      _currentInstructionIndex++;
      _directions =
          '${_directionSteps[_currentInstructionIndex]['symbol']} (${_directionSteps[_currentInstructionIndex]['distance']} km)';
      setState(() {});
    }
  }

  void _startCollection() async {
    setState(() => _isLoading = true);

    try {
      final token = await storage.read(key: 'jwt_token');
      print('Token: $token');
      if (token == null) throw Exception('No authentication token found');

      print('Starting collection for taskId: ${widget.taskid}');
      final response = await http.post(
        Uri.parse('$apiBaseUrl/worker/start-task'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'taskId': widget.taskid}),
      );

      print('Response status: ${response.statusCode}, Body: ${response.body}');
      if (response.statusCode == 200) {
        setState(() {
          _collectionStarted = true;
          _errorMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Collection started! Tap on locations to mark as collected',
            ),
          ),
        );
      } else if (response.statusCode == 403) {
        throw Exception('Access denied: ${response.body}');
      } else {
        throw Exception(
          'Failed to start task: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error starting collection: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting collection: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsCollected(
    LatLng location,
    int reportId,
    String wasteType,
  ) async {
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
          _fetchCollectionRequestData();
        });

        if (responseData['taskStatus'] == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All locations collected! Task completed'),
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${responseData['message']} (${responseData['remainingReports']} remaining)',
              ),
            ),
          );
        }
      } else {
        throw Exception(responseData['error'] ?? 'Failed to mark collected');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error marking collected: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error marking collected: $e')));
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
                          if (_collectionStarted &&
                              !_collectedReports.contains(reportId)) {
                            _markAsCollected(loc, reportId, wasteType);
                          } else {
                            setState(() {
                              _currentCollectionPoint = loc;
                              _currentWasteType = wasteType;
                            });
                          }
                        },
                        child: Icon(
                          _collectedReports.contains(reportId)
                              ? Icons.check_circle
                              : Icons.location_pin,
                          color:
                              _collectedReports.contains(reportId)
                                  ? Colors.green
                                  : (_collectionStarted
                                      ? Colors.orangeAccent
                                      : Colors.redAccent),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total Distance: ${_totalDistance.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  if (_currentCollectionPoint != null &&
                      _currentWasteType != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Selected Location Details:',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                        Text(
                          'Waste Type: $_currentWasteType',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                        Text(
                          'Location: ${_currentCollectionPoint!.latitude.toStringAsFixed(6)}, '
                          '${_currentCollectionPoint!.longitude.toStringAsFixed(6)}',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  if (_errorMessage.isNotEmpty)
                    Column(
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          'Error: $_errorMessage',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
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
make changes when a location is pressed a button 'collected' should appear to the side of its details shown
when pressed elsewhere the location details should not be shown
map should get updated as and when the worker moves 
when pressed collected the route to that location and location marker should be erased*/
