import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:math' show sin, cos, sqrt, asin, pi;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:waas/assets/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class MapScreen extends StatefulWidget {
  final int taskid;
  const MapScreen({super.key, required this.taskid});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _locations = []; // Collection points
  List<LatLng> _route = []; // Road-based route from OSRM
  List<LatLng> _completeRoute =
      []; // Complete route including worker's location
  double _currentZoom = 14.0;
  LatLng _currentCenter = const LatLng(10.235865, 76.405676); // Default center
  LatLng? _workerLocation; // Worker's location
  bool _isLoading = false;
  String _errorMessage = ''; // To display error messages to the user
  final storage = const FlutterSecureStorage();

  // For the info box
  double _distanceToNearest = 0.0;
  double _totalDistance = 0.0;
  String _directions = "Calculating directions...";
  List<String> _turnByTurnInstructions = []; // Store all instructions from OSRM
  int _currentInstructionIndex = 0; // Track the current instruction

  @override
  void initState() {
    super.initState();
    _getWorkerLocation();
    _fetchCollectionRequestData();
  }

  // Get worker's location using Geolocator
  void _getWorkerLocation() async {
    try {
      print('Checking location services...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        setState(() {
          _errorMessage = 'Please enable location services';
        });
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
          setState(() {
            _errorMessage = 'Location permissions are denied';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied.');
        setState(() {
          _errorMessage =
              'Location permissions are permanently denied, please enable them in settings';
        });
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
        _currentCenter = _workerLocation!;
        _errorMessage = '';
        print('Worker location set: $_workerLocation');
      });
      _updateCompleteRoute();
      _calculateDistances();
      _startLocationUpdates();
    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        _errorMessage = 'Error getting location: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
      setState(() {
        _workerLocation = const LatLng(10.235865, 76.405676);
        _currentCenter = _workerLocation!;
        _mapController.move(_currentCenter, _currentZoom);
        print('Using fallback location: $_workerLocation');
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
      if (token == null) {
        throw Exception('No authentication token found');
      }

      print('Fetching data from $apiUrl with token: $token');
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        print('Parsed data: $data');

        if (data['locations'] != null && data['locations'].isNotEmpty) {
          print('Parsing locations from "locations" field');
          _parseLocations(data['locations']);
        } else if (data['route'] != null && data['route'].isNotEmpty) {
          print('No locations found, falling back to "route" field');
          _parseLocations(data['route']);
        } else {
          print('No locations or route found in the response');
          setState(() {
            _errorMessage = 'No collection points found for this task';
            _directions = 'No directions available';
          });
          return;
        }

        if (_workerLocation != null && _locations.isNotEmpty) {
          final distanceToFirstPoint = _haversineDistance(
            _workerLocation!,
            _locations[0],
          );
          if (distanceToFirstPoint > 100) {
            print(
              'Error: Collection point is too far from worker location: $distanceToFirstPoint km',
            );
            setState(() {
              _errorMessage =
                  'Collection point is too far (${distanceToFirstPoint.toStringAsFixed(2)} km). Please verify the task data.';
              _directions = 'No directions available';
              _currentCenter = _workerLocation!;
              _mapController.move(_currentCenter, _currentZoom);
            });
            return;
          }
        }

        if (_workerLocation != null && _locations.isNotEmpty) {
          _route = await _fetchRouteFromOSRM();
          if (_route.isEmpty) {
            print(
              'OSRM route fetch failed, falling back to straight-line route',
            );
            _route = _locations;
            setState(() {
              _errorMessage =
                  'Failed to fetch route from OSRM. Showing straight-line path.';
              _directions =
                  'Proceed to the collection point (straight-line path)';
            });
          }
          _updateCompleteRoute();
          _calculateDistances();
          _updateDirectionsBasedOnLocation();

          if (_locations.isNotEmpty) {
            final bounds = LatLngBounds.fromPoints([
              _workerLocation!,
              ..._locations,
            ]);
            _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
          }
        } else {
          print('Worker location or locations list is empty');
          setState(() {
            _errorMessage =
                'Unable to fetch route: Worker location or collection points missing';
            _directions = 'No directions available';
          });
        }
      } else {
        print('Failed to fetch data: ${response.statusCode}');
        setState(() {
          _errorMessage = 'Failed to fetch task data: ${response.statusCode}';
          _directions = 'No directions available';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch task data: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      print('Error fetching data: $e');
      setState(() {
        _errorMessage = 'Error fetching task data: $e';
        _directions = 'No directions available';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching task data: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<LatLng>> _fetchRouteFromOSRM() async {
    if (_workerLocation == null || _locations.isEmpty) {
      print(
        'Cannot fetch OSRM route: Worker location or locations list is empty',
      );
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
      print('Fetching route from OSRM: $osrmUrl');
      final response = await http.get(Uri.parse(osrmUrl));
      print('OSRM Response status: ${response.statusCode}');
      print('OSRM Response body: ${response.body}');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final routeGeometry = data['routes'][0]['geometry']['coordinates'];
          List<LatLng> routePoints =
              routeGeometry.map<LatLng>((coord) {
                return LatLng(coord[1], coord[0]);
              }).toList();

          _turnByTurnInstructions.clear();
          final legs = data['routes'][0]['legs'];
          for (var leg in legs) {
            for (var step in leg['steps']) {
              _turnByTurnInstructions.add(step['maneuver']['instruction']);
            }
          }
          print('Turn-by-turn instructions: $_turnByTurnInstructions');
          _currentInstructionIndex = 0;
          _directions =
              _turnByTurnInstructions.isNotEmpty
                  ? _turnByTurnInstructions[0]
                  : "Proceed to the first collection point";

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
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching route from OSRM: $e')),
      );
      return [];
    }
  }

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
    } else if (_locations.isEmpty) {
      print('No valid locations parsed');
      setState(() {
        _errorMessage = 'No valid collection points found';
        _directions = 'No directions available';
      });
    }
    setState(() {});
  }

  void _updateCompleteRoute() {
    if (_workerLocation == null || _route.isEmpty) {
      _completeRoute = _route;
      return;
    }
    _completeRoute = [_workerLocation!, ..._route];
    print('Updated _completeRoute: $_completeRoute');
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

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  void _calculateDistances() {
    print('Calculating distances...');
    print('Worker Location: $_workerLocation');
    print('Complete Route: $_completeRoute');
    if (_workerLocation == null || _completeRoute.isEmpty) {
      print(
        'Cannot calculate distances: workerLocation or completeRoute are empty',
      );
      setState(() {
        _distanceToNearest = 0.0;
        _totalDistance = 0.0;
      });
      return;
    }

    LatLng nearestSpot = _completeRoute[1];
    _distanceToNearest = _haversineDistance(_workerLocation!, nearestSpot);
    print('Nearest spot: $nearestSpot, Distance: $_distanceToNearest km');

    _totalDistance = 0.0;
    for (int i = 0; i < _completeRoute.length - 1; i++) {
      final segmentDistance = _haversineDistance(
        _completeRoute[i],
        _completeRoute[i + 1],
      );
      print(
        'Segment distance from ${_completeRoute[i]} to ${_completeRoute[i + 1]}: $segmentDistance km',
      );
      _totalDistance += segmentDistance;
    }
    print('Total distance: $_totalDistance km');

    setState(() {});
  }

  void _updateDirectionsBasedOnLocation() {
    if (_workerLocation == null ||
        _completeRoute.isEmpty ||
        _turnByTurnInstructions.isEmpty) {
      return;
    }

    double minDistance = double.infinity;
    int closestPointIndex = 0;
    for (int i = 0; i < _completeRoute.length; i++) {
      final distance = _haversineDistance(_workerLocation!, _completeRoute[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestPointIndex = i;
      }
    }

    if (minDistance < 0.05 &&
        _currentInstructionIndex < _turnByTurnInstructions.length - 1) {
      _currentInstructionIndex++;
      _directions = _turnByTurnInstructions[_currentInstructionIndex];
      print('Updated direction: $_directions');
    }

    setState(() {});
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
                tileProvider: NetworkTileProvider(),
                additionalOptions: {'alpha': '0.9'},
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
          // Info box with glassmorphism effect
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
          // Map controls
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
