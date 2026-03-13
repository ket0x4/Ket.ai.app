// lib/main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'model': model,
      'generationTime': generationTime,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      content: json['content'],
      isUser: json['isUser'],
      timestamp: DateTime.parse(json['timestamp']),
      model: json['model'],
      generationTime: json['generationTime']?.toDouble(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String _selectedModel = "openai-fast";

  final List<String> _availableModels = [
    "openai-fast",
    "gpt-4o",
    "claude-3-opus",
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String? messagesJson = prefs.getString('chat_messages');
    if (messagesJson != null) {
      final List<dynamic> decodedList = jsonDecode(messagesJson);
      if (mounted) {
        setState(() {
          _messages = decodedList.map((e) => Message.fromJson(e)).toList();
        });
      }
    }
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedList =
        jsonEncode(_messages.map((e) => e.toJson()).toList());
    await prefs.setString('chat_messages', encodedList);
  }

  Future<Map<String, dynamic>> _invokePollinationsChat() async {
    final startTime = DateTime.now();
    final uri = Uri.parse('https://text.pollinations.ai/');

    try {
      // Build the message history for context
      // Note: _messages already contains the new prompt at the 0th index before this is called
      List<Map<String, String>> history = _messages.reversed.map((m) {
        return {
          "role": m.isUser ? "user" : "assistant",
          "content": m.content
        };
      }).toList();

      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/plain",
        },
        body: json.encode({
          "model": _selectedModel,
          "messages": history,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Connection timed out.');
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to get response. Status code: ${response.statusCode}');
      }

      final endTime = DateTime.now();
      final generationTime =
          endTime.difference(startTime).inMilliseconds / 1000;

      return {
        'response': utf8.decode(response.bodyBytes),
        'generationTime': generationTime,
      };
    } on SocketException catch (e) {
      throw Exception('Network error: Unable to reach Pollinations API (${e.message}).');
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
    _saveMessages();

    try {
      final response = await _invokePollinationsChat();

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
      _saveMessages();
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
              _saveMessages();
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
                            ? Colors.blueGrey[800]
                            : Colors.blueGrey[100])
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue[900]
                            : Colors.blue[50]),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      message.isUser
                          ? Text(message.content)
                          : MarkdownBody(
                              data: message.content,
                              selectable: true,
                            ),
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
