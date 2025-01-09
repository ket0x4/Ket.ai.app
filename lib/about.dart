import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment
              .center, // Changed from CrossAxisAlignment.start
          children: [
            const Text(
              'Ket.AI is a chatbot application powered KacakAPI LTD.',
              textAlign: TextAlign.center, // Added textAlign
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.telegram),
              label: const Text('Telegram'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(200, 50), // Increased button size
              ),
              onPressed: () {
                _launchURL('https://t.me/ketsblog');
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.code),
              label: const Text('GitHub'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(200, 50), // Increased button size
              ),
              onPressed: () {
                _launchURL('https://github.com/ket0x4');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }
}
