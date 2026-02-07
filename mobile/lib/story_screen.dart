import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  final TextEditingController _topicController = TextEditingController();

  String selectedLevel = 'A2';
  final List<String> levels = ['A1', 'A2', 'B1', 'B2', 'C1'];

  Map<String, dynamic>? storyData;
  bool isLoading = false;

  bool showTranslation = false;
  String? storyTranslation;

  final String baseUrl = 'http://192.168.1.19:8000/story';
  final String apiBase = 'http://192.168.1.19:8000';

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _toggleTranslation() async {
    final data = storyData;
    if (data == null) return;
    final story = (data['story'] ?? '').toString();
    if (story.isEmpty) return;

    if (showTranslation) {
      setState(() => showTranslation = false);
      return;
    }

    if (storyTranslation != null && storyTranslation!.isNotEmpty) {
      setState(() => showTranslation = true);
      return;
    }

    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBase/translate'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"text": story}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          storyTranslation = (data['translation'] ?? '').toString();
          showTranslation = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Translate error: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Translate failed: $e')),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveWordFromStory(String raw) async {
    final word = raw
        .replaceAll(RegExp(r"[^A-Za-z']"), '')
        .trim();
    if (word.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saving "$word"...')),
    );

    try {
      final response = await http.post(
        Uri.parse('$apiBase/define'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"word": word}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! Map) return;

        final newItem = Map<String, dynamic>.from(data);
        final prefs = await SharedPreferences.getInstance();
        final existingData = prefs.getString('saved_words');
        List<Map<String, dynamic>> currentWords = [];
        if (existingData != null) {
          currentWords = List<Map<String, dynamic>>.from(
            jsonDecode(existingData),
          );
        }

        final newWord = (newItem['word'] ?? word).toString().toLowerCase();
        final exists = currentWords.any(
          (w) => (w['word'] ?? '').toString().toLowerCase() == newWord,
        );
        if (!exists) {
          currentWords.add(newItem);
          await prefs.setString('saved_words', jsonEncode(currentWords));
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to vocab: ${newItem['word']}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Define error: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  Widget _buildTappableStory(String story) {
    // Metni cümlelere böl (nokta, soru işareti, ünlem işareti ile)
    final sentences = story.split(RegExp(r'(?<=[.!?])\s+'));
    final baseStyle = GoogleFonts.poppins(fontSize: 16, height: 1.6);
    final linkStyle = baseStyle.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: Colors.indigo.shade200,
      color: Colors.indigo.shade700,
    );

    final spans = <InlineSpan>[];
    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i].trim();
      if (sentence.isNotEmpty) {
        spans.add(
          TextSpan(
            text: sentence,
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = () => _saveSentenceFromStory(sentence),
          ),
        );
        // Cümleler arasına boşluk ekle (son cümle hariç)
        if (i < sentences.length - 1) {
          spans.add(TextSpan(text: ' ', style: baseStyle));
        }
      }
    }

    return RichText(
      text: TextSpan(children: spans, style: baseStyle),
    );
  }

  Future<void> _saveSentenceFromStory(String sentence) async {
    // Cümleyi kelimelere ayır ve her kelimeyi kaydet
    final words = sentence.split(RegExp(r'\s+'));
    for (final word in words) {
      final cleanWord = word
          .replaceAll(RegExp(r"[^A-Za-z']"), '')
          .trim();
      if (cleanWord.isNotEmpty) {
        await _saveWordFromStory(cleanWord);
      }
    }
  }

  Future<void> _generateStory() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) return;

    setState(() {
      isLoading = true;
      storyData = null;
    });

    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "topic": topic,
          "level": selectedLevel,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic>) {
          setState(() {
            storyData = data;
            showTranslation = false;
            storyTranslation = null;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid response format')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata: ${response.statusCode}")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bağlantı hatası: $e")),
      );
    } finally {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Widget _buildStoryContent() {
    final data = storyData;
    if (data == null) return const SizedBox.shrink();

    final title = (data['title'] ?? '').toString();
    final story = (data['story'] ?? '').toString();

    final keywordsRaw = data['keywords'];
    final quizRaw = data['quiz'];

    final keywords = (keywordsRaw is List) ? keywordsRaw : const [];
    final quiz = (quizRaw is List) ? quizRaw : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Kelimeyi kaydetmek için kelimenin üstüne dokunabilirsin.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
        ],
        if (story.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                )
              ],
            ),
            child: _buildTappableStory(story),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: isLoading ? null : _toggleTranslation,
              icon: Icon(
                showTranslation ? Icons.visibility_off : Icons.translate,
                size: 18,
              ),
              label: Text(showTranslation ? 'Çeviriyi Gizle' : 'Türkçesini Gör'),
            ),
          ),
          if (showTranslation && (storyTranslation ?? '').isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                storyTranslation!,
                style: GoogleFonts.poppins(
                  color: Colors.brown,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
        if (keywords.isNotEmpty) ...[
          const Text(
            'Key Vocabulary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: keywords.map<Widget>((kw) {
              if (kw is Map) {
                final word = (kw['word'] ?? '').toString();
                final meaning = (kw['meaning'] ?? '').toString();
                final label = (word.isNotEmpty && meaning.isNotEmpty)
                    ? '$word = $meaning'
                    : (word.isNotEmpty ? word : meaning);

                return Chip(
                  label: Text(label),
                  backgroundColor: Colors.indigo.shade50,
                  avatar: const CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.translate, size: 14, color: Colors.white),
                  ),
                );
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
        if (quiz.isNotEmpty) ...[
          const Text(
            'Quick Quiz',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...quiz.map<Widget>((q) {
            if (q is! Map) return const SizedBox.shrink();

            final question = (q['question'] ?? '').toString();
            final answer = (q['answer'] ?? '').toString();
            final optionsRaw = q['options'];
            final options = (optionsRaw is List) ? optionsRaw : const [];

            return Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (question.isNotEmpty)
                      Text(
                        'Q: $question',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 8),
                    ...options.map<Widget>((opt) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(opt.toString()),
                      );
                    }).toList(),
                    if (answer.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Answer: $answer',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            );
          }).toList(),
        ]
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text(
          'Story Generator',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _topicController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => isLoading ? null : _generateStory(),
                      decoration: InputDecoration(
                        labelText: 'Topic (e.g. Football, Space, Love)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.topic),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Level:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedLevel,
                            items: levels
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() => selectedLevel = val);
                            },
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _generateStory,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Generate Story',
                                style:
                                    TextStyle(color: Colors.white, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildStoryContent(),
          ],
        ),
      ),
    );
  }
}
