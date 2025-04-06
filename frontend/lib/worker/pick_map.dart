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

    double minDistance = double.infinity;
    for (final point in _completeRoute) {
      final distance = _haversineDistance(_workerLocation!, point);
      if (distance < minDistance) minDistance = distance;
    }

    setState(() {
      _directions = 'Distance to nearest point: ${minDistance.toStringAsFixed(2)} km';
    });
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
        setState(() {
          _collectedReports.add(_selectedReportId!);
          _selectedLocation = null;
          _selectedReportId = null;
          _selectedWasteType = null;
        });

        if (responseData['taskStatus'] == 'completed') {
          Navigator.pop(context);
        } else {
          _fetchCollectionRequestData();
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error marking collected: $e');
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