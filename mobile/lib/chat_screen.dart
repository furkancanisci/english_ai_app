import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatScreen extends StatefulWidget {
  final String scenario;

  const ChatScreen({super.key, this.scenario = 'default'});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();

  final FlutterTts flutterTts = FlutterTts();

  bool isRecording = false;
  bool isLoading = false;
  String? _recordedFilePath;

  String selectedLanguage = 'en';

  final String baseUrl = 'http://192.168.1.19:8000';

  Future<void> _completeUnit() async {
    try {
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
        
        Navigator.pop(context);
        
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
      } else {
        _showError("Complete unit failed: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showError("Complete unit failed: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _initTts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScenario();
    });
  }

  Future<void> _startScenario() async {
    if (messages.isNotEmpty) return;

    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/start_chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"scenario": widget.scenario}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is Map<String, dynamic>) {
          _handleResponseData(data);
        }
      }
    } catch (e) {
      _showError("Başlangıç hatası: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _getTitle() {
    switch (widget.scenario) {
      case 'intro':
        return 'Introduction';
      case 'interview':
        return 'Job Interview';
      case 'cafe':
        return 'Coffee Shop';
      case 'restaurant':
        return 'Restaurant';
      case 'hotel':
        return 'Hotel Check-in';
      case 'doctor':
        return 'Doctor Visit';
      case 'shopping':
        return 'Shopping';
      case 'taxi':
        return 'Taxi Ride';
      case 'smalltalk':
        return 'Small Talk';
      case 'airport':
        return 'Passport Control';
      default:
        return 'English Buddy';
    }
  }

  Future<void> _saveWordDialog() async {
    String wordToSave = "";

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save Word"),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter word (e.g. legacy)"),
          onChanged: (val) => wordToSave = val,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final w = wordToSave.trim();
              if (w.isNotEmpty) {
                await _fetchAndSaveWord(w);
              }
            },
            child: const Text("Save & Define"),
          )
        ],
      ),
    );
  }

  Future<void> _fetchAndSaveWord(String word) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Looking up definition...")),
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/define'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"word": word}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! Map) return;

        final prefs = await SharedPreferences.getInstance();
        List<Map<String, dynamic>> currentWords = [];
        final String? existingData = prefs.getString('saved_words');
        if (existingData != null) {
          currentWords =
              List<Map<String, dynamic>>.from(jsonDecode(existingData));
        }

        currentWords.add(Map<String, dynamic>.from(data));
        await prefs.setString('saved_words', jsonEncode(currentWords));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved: ${data['word']}")),
        );
      } else {
        _showError("Define error: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Could not save word: $e");
    }
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setPitch(1.0);
    await flutterTts.setSpeechRate(0.5);

    await flutterTts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker]);
  }

  Future<void> _speak(String text) async {
    if (selectedLanguage == 'tr') {
      await flutterTts.setLanguage("tr-TR");
    } else {
      await flutterTts.setLanguage("en-US");
    }

    await flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await flutterTts.stop();
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    flutterTts.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;
    _stopSpeaking();
    _addMessage("user", text);
    _controller.clear();
    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": text,
          "scenario": widget.scenario,
        }),
      );
      _handleResponse(response);
    } catch (e) {
      _showError("Bağlantı hatası: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> toggleRecording() async {
    _stopSpeaking();
    if (isRecording) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _showError("Mikrofon izni gerekli!");
      return;
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/audio_record.m4a';

    await _audioRecorder.start(const RecordConfig(), path: filePath);

    setState(() {
      isRecording = true;
      _recordedFilePath = filePath;
    });
  }

  Future<void> _stopRecordingAndSend() async {
    final path = await _audioRecorder.stop();
    setState(() => isRecording = false);

    if (path == null) return;

    setState(() => isLoading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/voice'));
      request.files.add(await http.MultipartFile.fromPath('file', path));
      request.fields['lang'] = selectedLanguage;

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        _addMessage("user", "${data['user_text']} 🎙️");
        _handleResponseData(data);
      } else {
        _showError("Ses hatası: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Ses gönderme hatası: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      _handleResponseData(data);
    } else {
      _showError("Hata: ${response.statusCode}");
    }
  }

  void _handleResponseData(Map<String, dynamic> data) {
    final response = data['response'];

    if (response is Map) {
      final String reply = (response['reply'] ?? '').toString();
      final bool hasMistake = response['has_mistake'] == true;
      final String correction = (response['correction'] ?? '').toString();
      final String explanation = (response['explanation_tr'] ?? '').toString();

      _addMessage("ai", reply);

      if (hasMistake) {
        setState(() {
          messages.add({
            "role": "teacher_note",
            "content": "Teacher's Note",
            "correction": correction,
            "explanation": explanation,
          });
        });
        _scrollToBottom();
      }

      _speak(reply);
      return;
    }

    final fallback = (response ?? '').toString();
    _addMessage("ai", fallback);
    _speak(fallback);
  }

  void _addMessage(String role, String content) {
    setState(() {
      messages.add({"role": role, "content": content});
    });
    _scrollToBottom();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text(
          _getTitle(),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (widget.scenario != 'default')
            IconButton(
              icon: const Icon(Icons.check_circle_outline,
                  color: Colors.green),
              tooltip: "Finish Unit",
              onPressed: _completeUnit,
            ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, color: Colors.indigo),
            tooltip: "Save a Word",
            onPressed: _saveWordDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      widget.scenario == 'default'
                          ? 'Start chatting...'
                          : 'Conversation starting...',
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final role = msg['role'];

                      if (role == 'teacher_note') {
                        final correction =
                            (msg['correction'] ?? '').toString();
                        final explanation =
                            (msg['explanation'] ?? '').toString();

                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(
                                bottom: 12, left: 40, right: 20),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5),
                              border: Border.all(color: Colors.orangeAccent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.lightbulb_outline,
                                        color: Colors.orange, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Correction (Düzeltme)",
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "✅ $correction",
                                  style: GoogleFonts.poppins(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "ℹ️ $explanation",
                                  style: GoogleFonts.poppins(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final isUser = role == 'user';
                      final content = (msg['content'] ?? '').toString();

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: isUser
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            if (!isUser)
                              IconButton(
                                icon: const Icon(Icons.volume_up_rounded,
                                    size: 20, color: Colors.grey),
                                onPressed: () => _speak(content),
                              ),
                            Flexible(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? const Color(0xFF6C63FF)
                                      : Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(20).copyWith(
                                    bottomRight: isUser ? Radius.zero : null,
                                    bottomLeft: !isUser ? Radius.zero : null,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 5,
                                      offset: Offset(0, 2),
                                    )
                                  ],
                                ),
                                child: Text(
                                  content,
                                  style: GoogleFonts.poppins(
                                    color:
                                        isUser ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (isLoading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedLanguage = selectedLanguage == 'en' ? 'tr' : 'en';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(selectedLanguage == 'en'
                            ? "Mod: İngilizce 🇬🇧"
                            : "Mod: Türkçe 🇹🇷"),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            selectedLanguage == 'en' ? Colors.indigo : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      selectedLanguage == 'en' ? "🇬🇧 EN" : "🇹🇷 TR",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          isRecording ? Colors.redAccent : Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRecording ? Icons.stop : Icons.mic,
                      color: isRecording
                          ? Colors.white
                          : const Color(0xFF6C63FF),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: isRecording ? 'Dinliyorum...' : 'Mesaj...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: sendTextMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
