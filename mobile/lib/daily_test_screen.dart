import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class DailyTestScreen extends StatefulWidget {
  const DailyTestScreen({super.key});

  @override
  State<DailyTestScreen> createState() => _DailyTestScreenState();
}

class _DailyTestScreenState extends State<DailyTestScreen> {
  List<Map<String, dynamic>> questions = [];
  List<TextEditingController> answerControllers = [];
  List<String> userAnswers = [];
  List<bool> questionResults = [];
  List<String> correctAnswerList = [];
  bool isLoading = true;
  int currentQuestionIndex = 0;
  int correctAnswersCount = 0;
  int dailyProgress = 0;
  bool showResults = false;
  String selectedLanguage = 'tr';

  final String baseUrl = 'http://192.168.1.19:8000';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _fetchDailyTest();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedLanguage = prefs.getString('selected_language') ?? 'tr';
    });
  }

  Future<void> _fetchDailyTest() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');
    dailyProgress = prefs.getInt('daily_test_progress') ?? 0;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/daily_test'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> questionsData = data['questions'] ?? [];
        
        setState(() {
          questions = questionsData.cast<Map<String, dynamic>>();
          answerControllers = List.generate(
            questions.length,
            (index) => TextEditingController(),
          );
          userAnswers = List.filled(questions.length, '');
          questionResults = List.filled(questions.length, false);
          correctAnswerList = List.filled(questions.length, '');
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test yüklenemedi: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test hatası: $e')),
      );
    }
  }

  void _nextQuestion() {
    // Mevcut cevabı kaydet
    final userAnswer = answerControllers[currentQuestionIndex].text.trim().toLowerCase();
    final correctAnswer = questions[currentQuestionIndex]['answer'].toString().toLowerCase();
    
    setState(() {
      userAnswers[currentQuestionIndex] = userAnswer;
      correctAnswerList[currentQuestionIndex] = correctAnswer;
      questionResults[currentQuestionIndex] = (userAnswer == correctAnswer);
    });
    
    if (currentQuestionIndex < questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
      });
    } else {
      _submitTest();
    }
  }

  void _previousQuestion() {
    if (currentQuestionIndex > 0) {
      setState(() {
        currentQuestionIndex--;
      });
    }
  }

  Future<void> _submitTest() async {
    int correct = 0;
    
    // Son soruyu da kontrol et
    if (userAnswers[currentQuestionIndex].isEmpty) {
      final userAnswer = answerControllers[currentQuestionIndex].text.trim().toLowerCase();
      final correctAnswer = questions[currentQuestionIndex]['answer'].toString().toLowerCase();
      
      setState(() {
        userAnswers[currentQuestionIndex] = userAnswer;
        correctAnswerList[currentQuestionIndex] = correctAnswer;
        questionResults[currentQuestionIndex] = (userAnswer == correctAnswer);
      });
    }
    
    for (int i = 0; i < questions.length; i++) {
      if (questionResults[i]) {
        correct++;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final newProgress = dailyProgress + questions.length;
    await prefs.setInt('daily_test_progress', newProgress);

    // Her 100 soruda XP ekle
    if (newProgress >= 100) {
      await _addXPAndReset();
    }

    setState(() {
      correctAnswersCount = correct;
      showResults = true;
    });
  }

  Future<void> _addXPAndReset() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/complete_daily_test'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        await prefs.setInt('daily_test_progress', 0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 100 Soru Tamamlandı! +50 XP!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('XP ekleme hatası: $e');
    }
  }

  Widget _buildQuestionCard(Map<String, dynamic> question) {
    final sentence = question['sentence'] as String;
    final answer = question['answer'] as String;
    final turkish = question['turkish'] as String;
    
    // Cümleyi boşluklu kısıma ayır
    final parts = sentence.split('___');
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Soru numarası ve ilerleme
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedLanguage == 'tr' ? 'Soru ${currentQuestionIndex + 1}/${questions.length}' : 'Question ${currentQuestionIndex + 1}/${questions.length}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  selectedLanguage == 'tr' ? 'Günlük İlerleme: $dailyProgress/100' : 'Daily Progress: $dailyProgress/100',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // İngilizce cümle
            Text(
              selectedLanguage == 'tr' ? 'İngilizce Cümle:' : 'English Sentence:',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            
            // Cümle ve boşluk
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.black87,
                    height: 1.6,
                  ),
                  children: [
                    TextSpan(text: parts[0]),
                    WidgetSpan(
                      child: Container(
                        width: 120,
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextField(
                          controller: answerControllers[currentQuestionIndex],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo,
                          ),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.indigo[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.indigo, width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            hintText: '???',
                            hintStyle: GoogleFonts.poppins(
                              color: Colors.grey[400],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (parts.length > 1) TextSpan(text: parts[1]),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Türkçe çeviri
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedLanguage == 'tr' ? 'Türkçe Çeviri:' : 'Turkish Translation:',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    turkish,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.blue[900],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            
            // Sonuç gösterimi (eğer cevaplandıysa)
            if (userAnswers[currentQuestionIndex].isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: questionResults[currentQuestionIndex] ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: questionResults[currentQuestionIndex] ? Colors.green[300]! : Colors.red[300]!,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          questionResults[currentQuestionIndex] ? Icons.check_circle : Icons.cancel,
                          color: questionResults[currentQuestionIndex] ? Colors.green[700] : Colors.red[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          questionResults[currentQuestionIndex] ? 'Doğru!' : 'Yanlış!',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: questionResults[currentQuestionIndex] ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                    if (!questionResults[currentQuestionIndex]) ...[
                      const SizedBox(height: 8),
                      Text(
                        selectedLanguage == 'tr' ? 'Doğru Cevap: ${questions[currentQuestionIndex]['answer']}' : 'Correct Answer: ${questions[currentQuestionIndex]['answer']}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        selectedLanguage == 'tr' ? 'Senin Cevabın: ${userAnswers[currentQuestionIndex]}' : 'Your Answer: ${userAnswers[currentQuestionIndex]}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.red[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            
            const SizedBox(height: 30),
            
            // Navigasyon butonları
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (currentQuestionIndex > 0)
                  ElevatedButton.icon(
                  onPressed: _previousQuestion,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(selectedLanguage == 'tr' ? 'Önceki' : 'Previous'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                  ),
                )
                else
                  const SizedBox(width: 100),
                
                ElevatedButton.icon(
                  onPressed: _nextQuestion,
                  icon: Icon(currentQuestionIndex < questions.length - 1 
                      ? Icons.arrow_forward 
                      : Icons.check_circle),
                  label: Text(currentQuestionIndex < questions.length - 1 
                      ? (selectedLanguage == 'tr' ? 'Sonraki' : 'Next')
                      : (selectedLanguage == 'tr' ? 'Testi Bitir' : 'Finish Test')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsScreen() {
    final percentage = (correctAnswersCount / questions.length * 100).round();
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Başarı göstergesi
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: percentage >= 70 ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$percentage%',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '$correctAnswersCount/${questions.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            Text(
              percentage >= 70 
                  ? (selectedLanguage == 'tr' ? 'Harika İş!' : 'Great Job!') 
                  : (selectedLanguage == 'tr' ? 'Devam Et!' : 'Keep Going!'),
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: percentage >= 70 ? Colors.green : Colors.orange,
              ),
            ),
            
            const SizedBox(height: 10),
            
            Text(
              selectedLanguage == 'tr' ? 'Günlük İlerlemen: ${dailyProgress + questions.length}/100' : 'Your Daily Progress: ${dailyProgress + questions.length}/100',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Detaylı sonuçlar
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedLanguage == 'tr' ? 'Soru Detayları:' : 'Question Details:',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Tüm soruların sonuçları
                    ...List.generate(questions.length, (index) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: questionResults[index] ? Colors.green[50] : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: questionResults[index] ? Colors.green[300]! : Colors.red[300]!,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  questionResults[index] ? Icons.check_circle : Icons.cancel,
                                  color: questionResults[index] ? Colors.green[700] : Colors.red[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  selectedLanguage == 'tr' ? 'Soru ${index + 1}' : 'Question ${index + 1}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: questionResults[index] ? Colors.green[700] : Colors.red[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              questions[index]['sentence'].replaceAll('___', '(${questions[index]['answer']})'),
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            if (!questionResults[index]) ...[
                              const SizedBox(height: 4),
                              Text(
                                selectedLanguage == 'tr' ? 'Doğru: ${questions[index]['answer']} | Senin: ${userAnswers[index]}' : 'Correct: ${questions[index]['answer']} | Your: ${userAnswers[index]}',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.red[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.home),
              label: Text(selectedLanguage == 'tr' ? 'Ana Sayfa' : 'Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text(
          selectedLanguage == 'tr' ? 'Günlük Test' : 'Daily Test',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                isLoading = true;
                showResults = false;
                currentQuestionIndex = 0;
              });
              _fetchDailyTest();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : showResults
              ? _buildResultsScreen()
              : questions.isEmpty
                  ? Center(child: Text(selectedLanguage == 'tr' ? 'Soru bulunamadı.' : 'No questions found.'))
                  : SingleChildScrollView(
                      child: _buildQuestionCard(questions[currentQuestionIndex]),
                    ),
    );
  }

  @override
  void dispose() {
    for (final controller in answerControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
