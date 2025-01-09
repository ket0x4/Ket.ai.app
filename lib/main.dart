// lib/main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'about.dart';

void main() {
  runApp(const ChatbotApp());
}

class ChatbotApp extends StatelessWidget {
  const ChatbotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ket.AI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const ChatScreen(),
    );
  }
}

// Data model for chat messages
class Message {
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final String? model;
  final double? generationTime;

  Message({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.model,
    this.generationTime,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String _selectedModel = "gpt-4o-mini";

  final List<String> _availableModels = [
    "Mixtral-8x7B-Instruct-v0.1",
    "Llama-3-70b-chat-hf",
    "claude-3-haiku-20240307",
    "gpt-3.5-turbo-0125",
    "gpt-4o-mini"
  ];

  Future<Map<String, dynamic>> _invokeDuckDuckGoChat(String prompt) async {
    final startTime = DateTime.now();

    // Validate the URI
    final statusUri = Uri.parse('https://duckduckgo.com/duckchat/v1/status');
    final chatUri = Uri.parse('https://duckduckgo.com/duckchat/v1/chat');

    //print('Status URI: $statusUri');
    //print('Chat URI: $chatUri');

    try {
      // Check internet connectivity
      final result = await InternetAddress.lookup('duckduckgo.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw Exception('No internet connection detected.');
      }

      // First request to get the token
      final statusResponse = await http.get(
        statusUri,
        headers: {
          "User-Agent":
              "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0",
          "Accept": "text/event-stream",
          "Accept-Language": "en-US;q=0.7,en;q=0.3",
          "Accept-Encoding": "gzip, deflate, br",
          "Referer": "https://duckduckgo.com/",
          "Origin": "https://duckduckgo.com",
          "Connection": "keep-alive",
          "Cookie": "dcm=1",
          "Sec-Fetch-Dest": "empty",
          "Sec-Fetch-Mode": "cors",
          "Sec-Fetch-Site": "same-origin",
          "Pragma": "no-cache",
          "TE": "trailers",
          "x-vqd-accept": "1",
          "Cache-Control": "no-store",
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Connection timed out while getting token.');
        },
      );

      if (statusResponse.statusCode != 200) {
        throw Exception(
            'Failed to get token. Status code: ${statusResponse.statusCode}');
      }

      final token =
          statusResponse.headers['x-vqd'] ?? statusResponse.headers['x-vqd-4'];
      if (token == null) {
        throw Exception('Token not found in response headers.');
      }

      //print('Received token: $token');

      // Chat request
      final chatResponse = await http
          .post(
        chatUri,
        headers: {
          "User-Agent":
              "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0",
          "Accept": "text/event-stream",
          "Accept-Language": "en-US;q=0.7,en;q=0.3",
          "Accept-Encoding": "gzip, deflate, br",
          "Referer": "https://duckduckgo.com/",
          "Content-Type": "application/json",
          "Origin": "https://duckduckgo.com",
          "Connection": "keep-alive",
          "Cookie": "dcm=1",
          "x-vqd-4": token,
          "Sec-Fetch-Dest": "empty",
          "Sec-Fetch-Mode": "cors",
          "Sec-Fetch-Site": "same-origin",
          "Pragma": "no-cache",
          "TE": "trailers",
          "x-vqd-accept": "1",
          "Cache-Control": "no-store",
        },
        body: json.encode({
          "model": _selectedModel,
          "messages": [
            {"role": "user", "content": prompt}
          ],
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
              'Connection timed out while sending chat request.');
        },
      );

      if (chatResponse.statusCode != 200) {
        throw Exception(
            'Failed to get chat response. Status code: ${chatResponse.statusCode}');
      }

      // Decode using UTF-8
      final decodedBody = utf8.decode(chatResponse.bodyBytes);
      final lines = decodedBody.split('\n');

      String responseText = '';
      for (var line in lines) {
        if (line.length > 6 && line[6] == '{') {
          try {
            final data = json.decode(line.substring(6));
            if (data.containsKey('message')) {
              responseText += data['message'].replaceAll(r'\n', '\n');
            }
          } catch (e) {
            //print('Error parsing line: $e');
          }
        }
      }

      final endTime = DateTime.now();
      final generationTime =
          endTime.difference(startTime).inMilliseconds / 1000;

      return {
        'response': responseText,
        'generationTime': generationTime,
      };
    } on SocketException catch (e) {
      throw Exception(
          'Network error: Unable to reach DuckDuckGo (${e.message}).');
    } on TimeoutException catch (e) {
      throw Exception('Timeout error: ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error: ${e.toString()}');
    }
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    _textController.clear();
    final userMessage = Message(
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.insert(0, userMessage);
      _isLoading = true;
    });

    try {
      final response = await _invokeDuckDuckGoChat(text);

      final botMessage = Message(
        content: response['response'],
        isUser: false,
        timestamp: DateTime.now(),
        model: _selectedModel,
        generationTime: response['generationTime'],
      );

      setState(() {
        _isLoading = false;
        _messages.insert(0, botMessage);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ket.ai preview'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.model_training),
            onSelected: (String model) {
              setState(() {
                _selectedModel = model;
              });
            },
            itemBuilder: (BuildContext context) {
              return _availableModels.map((String model) {
                return PopupMenuItem<String>(
                  value: model,
                  child: Text(model),
                );
              }).toList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                _messages.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return MessageBubble(message: message);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[850]
                  : Colors.grey[300],
            ),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewPadding.bottom + 8.0, // Added bottom padding
        left: 8.0,
        right: 8.0,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              onSubmitted: _handleSubmitted,
              decoration: const InputDecoration(
                hintText: 'Send a message',
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(width: 8.0), // Added spacing between TextField and button
          ElevatedButton(
            onPressed: () => _handleSubmitted(_textController.text),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20.0),
              ),
              backgroundColor: Colors.blue,
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            ),
            child: Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser)
            Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.smart_toy, color: Colors.white),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]
                            : Colors.grey[200])
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue[800]
                            : Colors.blue[200]),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.content),
                      if (message.model != null &&
                          message.generationTime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Model: ${message.model} | Time: ${message.generationTime!.toStringAsFixed(2)}s',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (message.isUser)
            Container(
              margin: const EdgeInsets.only(left: 16.0),
              child: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.person, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
