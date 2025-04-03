
import 'dart:convert';

import 'package:http/http.dart' as http;

class ChatbotService {
  final String agentId;
  final String apiKey;

  ChatbotService({required this.agentId, required this.apiKey});

  Future<String> sendMessage(String message) async {
    final url = Uri.parse('https://www.chatbase.co/api/v1/chat');
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'agentId': agentId,
        'message': message,
        'stream': false,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['text'];
    } else {
      throw Exception('Failed to get chatbot response: ${response.statusCode}');
    }
  }
}