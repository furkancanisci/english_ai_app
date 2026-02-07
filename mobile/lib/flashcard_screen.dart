import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<dynamic> cards = [];
  bool isLoading = true;

  final Set<int> _flippedIndexes = <int>{};
  late final PageController _pageController;

  final String baseUrl = 'http://192.168.1.19:8000';

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _fetchCards();
  }

  Future<void> _fetchCards() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/generate_flashcards'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          cards = data['cards'] ?? [];
          isLoading = false;
          _flippedIndexes.clear();
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text('Daily Idioms',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => isLoading = true);
              _fetchCards();
            },
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : cards.isEmpty
              ? const Center(child: Text("No cards found."))
              : PageView.builder(
                  controller: _pageController,
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final raw = cards[index];
                    if (raw is! Map) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 40),
                      child: FlashcardItem(
                        cardData: Map<String, dynamic>.from(raw),
                        onFirstFlipToBack: () {
                          if (_flippedIndexes.contains(index)) return;
                          _flippedIndexes.add(index);

                          if (_flippedIndexes.length == cards.length) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Yeni kartlar yükleniyor...'),
                              ),
                            );
                            _pageController.jumpToPage(0);
                            setState(() => isLoading = true);
                            _fetchCards();
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

class FlashcardItem extends StatefulWidget {
  final Map<String, dynamic> cardData;
  final VoidCallback? onFirstFlipToBack;
  const FlashcardItem({
    super.key,
    required this.cardData,
    this.onFirstFlipToBack,
  });

  @override
  State<FlashcardItem> createState() => _FlashcardItemState();
}

class _FlashcardItemState extends State<FlashcardItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool isFront = true;
  bool _reportedFlip = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  void _flipCard() {
    if (isFront) {
      _controller.forward();
      if (!_reportedFlip) {
        _reportedFlip = true;
        widget.onFirstFlipToBack?.call();
      }
    } else {
      _controller.reverse();
    }
    setState(() => isFront = !isFront);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flipCard,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * pi;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: _animation.value < 0.5
                ? _buildFront()
                : Transform(
                    transform: Matrix4.identity()..rotateY(pi),
                    alignment: Alignment.center,
                    child: _buildBack(),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFront() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF4B43D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.touch_app, color: Colors.white54, size: 40),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                (widget.cardData['term'] ?? '').toString(),
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            Text("Tap to flip",
                style: GoogleFonts.poppins(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() {
    final meaningEn = (widget.cardData['meaning'] ?? '').toString();
    final meaningTr = (widget.cardData['meaning_tr'] ?? '').toString();
    final exampleEn = (widget.cardData['example'] ?? '').toString();
    final exampleTr = (widget.cardData['example_tr'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF6C63FF), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              (meaningTr.isNotEmpty ? meaningTr : meaningEn),
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6C63FF),
              ),
              textAlign: TextAlign.center,
            ),
            if (meaningTr.isNotEmpty && meaningEn.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  meaningEn,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 20),
            Container(width: 50, height: 2, color: Colors.grey.shade300),
            const SizedBox(height: 20),
            Text(
              '"${exampleEn}"',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontStyle: FontStyle.italic,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            if (exampleTr.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '"$exampleTr"',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.brown,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
