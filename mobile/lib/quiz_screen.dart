import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class QuizScreen extends StatefulWidget {
  final String topic;
  const QuizScreen({super.key, required this.topic});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<dynamic> questions = [];
  int currentQuestionIndex = 0;
  int correctAnswers = 0;
  bool isLoading = true;
  bool isCompleted = false;

  final String baseUrl = 'http://192.168.1.19:8000';

  @override
  void initState() {
    super.initState();
    _fetchQuiz();
  }

  Future<void> _fetchQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/generate_quiz'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"topic": widget.topic}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          questions = data['questions'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Quiz yüklenemedi: ${response.statusCode}")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _answerQuestion(String selectedOption) {
    final currentQ = questions[currentQuestionIndex];
    if (selectedOption == currentQ['correct_answer']) {
      correctAnswers++;
    }

    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    setState(() => isCompleted = true);

    final bool isPassed = correctAnswers >= 3;

    if (isPassed) {
      await _completeUnitBackend();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isPassed ? "Unit Completed!" : "Try Again"),
        content: Text("Score: $correctAnswers / ${questions.length}"),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text("Done"),
          )
        ],
      ),
    );
  }

  Future<void> _completeUnitBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    final response = await http.post(
      Uri.parse('$baseUrl/complete_unit'),
      headers: {"Authorization": "Bearer $token"},
    );

    if (!mounted) return;
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final bool levelUp = data['level_up'] ?? false;
      final int newLevel = data['new_level'] ?? 1;
      
      if (levelUp) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 LEVEL UP! Now Level $newLevel! +50 XP'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unit Completed! +50 XP')),
        );
      }
    }
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
      appBar: AppBar(title: const Text("Quick Quiz"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (currentQuestionIndex + 1) / questions.length,
              color: Colors.orange,
              backgroundColor: Colors.orange.shade100,
            ),
            const SizedBox(height: 40),
            Text(
              (question['question'] ?? '').toString(),
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ...((question['options'] as List?) ?? const []).map((option) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: ElevatedButton(
                  onPressed: isCompleted ? null : () => _answerQuestion(option),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 2,
                  ),
                  child: Text(option.toString()),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
