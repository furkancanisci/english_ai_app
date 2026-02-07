import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'main_container.dart';

class PlacementScreen extends StatefulWidget {
  const PlacementScreen({super.key});

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> {
  List<dynamic> questions = [];
  int currentQuestionIndex = 0;
  int correctAnswers = 0;
  bool isLoading = true;
  bool isSubmitting = false;
  bool showTranslation = false;

  final String baseUrl = 'https://english-ai-app-s4ed.onrender.com';

  @override
  void initState() {
    super.initState();
    _fetchTest();
  }

  Future<void> _fetchTest() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/generate_placement_test'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          questions = data['questions'] ?? [];
          isLoading = false;
        });
      } else {
        _showError("Test yüklenemedi: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showError("Bağlantı hatası: $e");
    }
  }

  void _answerQuestion(String selectedOption) {
    final currentQ = questions[currentQuestionIndex];

    if (selectedOption == currentQ['correct_answer']) {
      correctAnswers++;
    }

    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        showTranslation = false;
        currentQuestionIndex++;
      });
    } else {
      _submitResult();
    }
  }

  Future<void> _submitResult() async {
    setState(() => isSubmitting = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/submit_placement_test'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"correct_count": correctAnswers}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final level = data['assigned_level'];

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Tebrikler!"),
            content: Text(
              "Testi tamamladın.\nSeviyen: $level\n+100 XP kazandın!",
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const MainContainer(),
                    ),
                  );
                },
                child: const Text("Başla"),
              )
            ],
          ),
        );
      } else {
        _showError("Sonuç gönderilemedi: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showError("Sonuç gönderilemedi: $e");
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (questions.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions.')));
    }

    final question = questions[currentQuestionIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Level Test ${currentQuestionIndex + 1}/10"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (currentQuestionIndex + 1) / questions.length,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFF6C63FF),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 40),
            Text(
              (question['question'] ?? '').toString(),
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    showTranslation = !showTranslation;
                  });
                },
                icon: Icon(
                  showTranslation ? Icons.visibility_off : Icons.translate,
                  size: 18,
                ),
                label: Text(showTranslation ? "Çeviriyi Gizle" : "Türkçesini Gör"),
              ),
            ),
            if (showTranslation)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  (question['question_tr'] ?? '').toString(),
                  style: GoogleFonts.poppins(
                    color: Colors.brown,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 40),
            ...((question['options'] as List?) ?? const []).map((option) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton(
                  onPressed:
                      isSubmitting ? null : () => _answerQuestion(option),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Text(
                    option.toString(),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
