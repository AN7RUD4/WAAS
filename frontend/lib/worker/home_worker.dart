import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:waas/assets/constants.dart';

import 'package:waas/worker/pick_map.dart';

class WorkerApp extends StatelessWidget {
  const WorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WorkerHomePage(
        workerName: "Worker",
        workerId: "201", // Used for display only; backend uses JWT token
      ),
      routes: {'/pickup-map': (context) => const MapScreen(taskid: 0)},
    );
  }
}

class WorkerHomePage extends StatefulWidget {
  final String workerName;
  final String workerId;

  const WorkerHomePage({
    super.key,
    required this.workerName,
    required this.workerId,
  });

  @override
  _WorkerHomePageState createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends State<WorkerHomePage> {
  late Future<List<Map<String, dynamic>>> _assignedWorksFuture;
  final storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _assignedWorksFuture = fetchAssignedWorks();
  }

  Future<List<Map<String, dynamic>>> fetchAssignedWorks() async {
    final token = await storage.read(key: 'jwt_token');
    if (token == null) {
      throw Exception('No authentication token found');
    }

    final response = await http.get(
      Uri.parse('$apiBaseUrl/worker/assigned-tasks'), // Updated URL
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['assignedWorks']);
    } else {
      throw Exception('Failed to load assigned works: ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Hi, ${widget.workerName}",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            "Welcome Back 👋",
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.notifications,
                          color: Colors.white,
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Assigned Works",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _assignedWorksFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text(
                            "No tasks currently assigned",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        );
                      } else {
                        return Column(
                          children:
                              snapshot.data!
                                  .map(
                                    (work) => WorkListItem(
                                      taskId: work['taskId'],
                                      title: work['title'],
                                      distance: "5km", // Placeholder
                                      time: "15min", // Placeholder
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (context) => MapScreen(
                                                  taskid: int.parse(
                                                    work['taskId'],
                                                  ),
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                  .toList(),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.info, color: Colors.grey),
                onPressed: () {
                  // Navigate to past work details if needed
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkListItem extends StatelessWidget {
  final String taskId;
  final String title;
  final String distance;
  final String time;
  final VoidCallback onTap;

  const WorkListItem({
    super.key,
    required this.taskId,
    required this.title,
    required this.distance,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "Distance: $distance",
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  "Time: $time",
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
