import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  List<Map<String, dynamic>> savedWords = [];
  final FlutterTts flutterTts = FlutterTts();

  final String baseUrl = 'http://192.168.1.19:8000';

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? wordsString = prefs.getString('saved_words');

    if (wordsString != null) {
      setState(() {
        savedWords = List<Map<String, dynamic>>.from(jsonDecode(wordsString));
      });
    } else {
      setState(() {
        savedWords = [];
      });
    }
  }

  Future<void> _deleteWord(int index) async {
    setState(() {
      savedWords.removeAt(index);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_words', jsonEncode(savedWords));
  }

  Future<void> _speakWord(String word) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.speak(word);
  }

  void _showAddWordDialog() {
    final TextEditingController wordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kelime Ekle'),
        content: TextField(
          controller: wordController,
          decoration: const InputDecoration(
            labelText: 'İngilizce kelime',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (wordController.text.trim().isNotEmpty) {
                await _addWord(wordController.text.trim());
                Navigator.of(context).pop();
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<void> _addWord(String word) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/define'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'word': word}),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final newWord = {
          'word': result['word'],
          'meaning': result['meaning'],
          'meaning_tr': result['meaning_tr'],
          'example': result['example'],
          'example_tr': result['example_tr'],
        };

        setState(() {
          savedWords.add(newWord);
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_words', jsonEncode(savedWords));
      }
    } catch (e) {
      print('Kelime eklenemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vocabulary'),
        backgroundColor: Colors.purple[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddWordDialog,
          ),
        ],
      ),
      body: savedWords.isEmpty
          ? const Center(
              child: Text(
                'Henüz kelime eklenmemiş.\n+ butonuna basarak kelime ekleyin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: savedWords.length,
              itemBuilder: (context, index) {
                final word = savedWords[index];
                return _buildWordCard(word, index);
              },
            ),
    );
  }

  Widget _buildWordCard(Map<String, dynamic> word, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    word['word'],
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.volume_up),
                      onPressed: () => _speakWord(word['word']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteWord(index),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (word['meaning'] != null && word['meaning'].isNotEmpty) ...[
              Text(
                word['meaning'],
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),
            ],
            if (word['meaning_tr'] != null && word['meaning_tr'].isNotEmpty) ...[
              Text(
                word['meaning_tr'],
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (word['example'] != null && word['example'].isNotEmpty) ...[
              Text(
                word['example'],
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
