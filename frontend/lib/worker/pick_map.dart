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
        _erasePolylineAtWorkerLocation();
      }
    });
  }

  Future<void> _fetchCollectionRequestData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    final String apiUrl = '$apiBaseUrl/worker/task-route/${widget.taskid}?workerLat=${_workerLocation?.latitude ?? 10.235865}&workerLng=${_workerLocation?.longitude ?? 76.405676}';

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

        setState(() {
          _collectionStarted = data['status'] == 'in-progress';
          _collectedReports = data['locations']
              .where((loc) => loc['status'] == 'collected')
              .map((loc) => loc['reportid'] as int)
              .toSet();
        });

        if (_workerLocation != null && _locations.isNotEmpty) {
          _route = await _fetchRouteFromOSRM();
          if (_route.isEmpty) {
            _route = _locations;
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
        setState(() => _errorMessage = 'Failed to fetch task data: ${response.statusCode} - ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch task data: ${response.statusCode} - ${response.body}')),
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

    if (routeData['start'] != null && routeData['start']['lat'] != null && routeData['start']['lng'] != null) {
      final startPoint = LatLng(routeData['start']['lat'], routeData['start']['lng']);
      _locations.add(startPoint);
      _route.add(startPoint);
    }

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

    if (routeData['end'] != null && routeData['end']['lat'] != null && routeData['end']['lng'] != null) {
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
          final LatLng latLng = LatLng(double.parse(item['lat'].toString()), double.parse(item['lng'].toString()));
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

          _directionSteps.clear();
          final legs = data['routes'][0]['legs'];
          double cumulativeDistance = 0.0;
          for (var leg in legs) {
            for (var step in leg['steps']) {
              if (step['maneuver'] != null && step['maneuver']['instruction'] != null) {
                String symbol = _convertInstructionToSymbol(step['maneuver']['instruction']);
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
          _directions = _directionSteps.isNotEmpty
              ? '${_directionSteps[0]['symbol']} (${_directionSteps[0]['distance']} km)'
              : "🡺 (0.00 km)";

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
        _directions = '🡺 (0.00 km)';
      });
      return _locations;
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
    _completeRoute = [_workerLocation!, ..._route];
  }

  double _haversineDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371.0;
    final double dLat = _degreesToRadians(end.latitude - start.latitude);
    final double dLon = _degreesToRadians(end.longitude - start.longitude);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) * cos(_degreesToRadians(end.latitude)) * sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * asin(sqrt(a));
    return earthRadius * c * 1000;
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
      _totalDistance += _haversineDistance(_completeRoute[i], _completeRoute[i + 1]) / 1000;
    }
    setState(() {});
  }

  void _updateDirectionsBasedOnLocation() {
    if (_workerLocation == null || _completeRoute.isEmpty || _directionSteps.isEmpty) return;

    double minDistance = double.infinity;
    int closestIndex = 0;
    for (int i = 0; i < _completeRoute.length; i++) {
      final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    if (minDistance < 0.05 * 1000 && _currentInstructionIndex < _directionSteps.length - 1) {
      _currentInstructionIndex++;
      _directions = '${_directionSteps[_currentInstructionIndex]['symbol']} (${_directionSteps[_currentInstructionIndex]['distance']} km)';
      setState(() {});
    }
  }

  void _erasePolylineAtWorkerLocation() {
    if (_workerLocation == null || _completeRoute.length <= 1) return;

    for (int i = 0; i < _completeRoute.length - 1; i++) {
      double distanceToPoint = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distanceToPoint < 50) {
        _completeRoute = _completeRoute.sublist(i + 1);
        _route = _route.sublist(i);
        _directionSteps = _directionSteps.sublist(_currentInstructionIndex + 1);
        _currentInstructionIndex = 0;
        _directions = _directionSteps.isNotEmpty
            ? '${_directionSteps[0]['symbol']} (${_directionSteps[0]['distance']} km)'
            : "🏁 (0.00 km)";
        _calculateDistances();
        break;
      }
    }
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
        setState(() {
          _collectionStarted = true;
          _errorMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collection started! Tap on locations to mark as collected'),
          ),
        );
      } else if (response.statusCode == 403) {
        throw Exception('Access denied: ${response.body}');
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
          final index = _locations.indexWhere((loc) => loc == location);
          if (index != -1) {
            _locations.removeAt(index);
            _route.removeAt(index + 1); // +1 to skip worker location at index 0
            _reportIds.removeAt(index);
            _wasteTypes.removeAt(index);
            _updateCompleteRoute();
            _calculateDistances();
            _fetchRouteFromOSRM(); // Re-fetch route to update polyline
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${responseData['message']} (${responseData['remainingReports']} remaining)')),
        );

        if (responseData['taskStatus'] == 'completed') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All locations collected! Task completed')),
          );
          Navigator.popUntil(context, (route) => route.isFirst); // Return to home page
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
                      final reportId = _getReportIdForIndex(index);
                      final wasteType = _getWasteTypeForIndex(index);

                      return Marker(
                        point: loc,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            if (_collectionStarted && !_collectedReports.contains(reportId)) {
                              setState(() {
                                _currentCollectionPoint = loc;
                                _currentWasteType = wasteType;
                              });
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
                    if (_currentCollectionPoint != null && _currentWasteType != null)
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
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _collectionStarted && !_collectedReports.contains(_getReportIdForIndex(_locations.indexOf(_currentCollectionPoint!)))
                                ? () => _markAsCollected(_currentCollectionPoint!, _getReportIdForIndex(_locations.indexOf(_currentCollectionPoint!)), _currentWasteType!)
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
      ),
    );
  }
}