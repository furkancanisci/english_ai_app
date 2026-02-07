import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chat_screen.dart';
import 'quiz_screen.dart';

class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});

  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  List<dynamic> units = [];
  bool isLoading = true;

  final String baseUrl = 'http://192.168.1.19:8000';

  @override
  void initState() {
    super.initState();
    _fetchRoadmap();
  }

  Future<void> _fetchRoadmap() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/roadmap'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          units = (data['units'] as List?) ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _startUnit(Map<String, dynamic> unit) async {
    if (unit['status'] == 'locked') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complete previous units first!")),
      );
      return;
    }

    final type = (unit['type'] ?? 'chat').toString();
    if (type == 'quiz') {
      final topic = (unit['quiz_topic'] ?? 'General English').toString();
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => QuizScreen(topic: topic)),
      );
    } else {
      final scenarioId = (unit['scenario_id'] ?? 'default').toString();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(scenario: scenarioId),
        ),
      );
    }

    if (!mounted) return;
    await _fetchRoadmap();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text(
          'Learning Path',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchRoadmap),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              itemCount: units.length,
              itemBuilder: (context, index) {
                final u = units[index];
                if (u is! Map) return const SizedBox.shrink();
                return _buildUnitCard(Map<String, dynamic>.from(u), index);
              },
            ),
    );
  }

  Widget _buildUnitCard(Map<String, dynamic> unit, int index) {
    final status = (unit['status'] ?? 'locked').toString();
    Color nodeColor = Colors.grey.shade300;
    Color textColor = Colors.black87;
    IconData statusIcon = Icons.lock;

    if (status == 'active') {
      nodeColor = Colors.indigo;
      textColor = Colors.white;
      statusIcon = Icons.play_arrow_rounded;
    } else if (status == 'completed') {
      nodeColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return GestureDetector(
      onTap: () => _startUnit(unit),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Row(
          children: [
            Column(
              children: [
                if (index != 0)
                  Container(width: 4, height: 30, color: Colors.grey.shade300),
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: nodeColor,
                    shape: BoxShape.circle,
                    boxShadow: status == 'active'
                        ? [
                            BoxShadow(
                              color: Colors.indigo.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            )
                          ]
                        : [],
                  ),
                  child: Icon(
                    _getIconData((unit['icon'] ?? '').toString()),
                    color: status == 'active'
                        ? Colors.white
                        : (status == 'completed'
                            ? Colors.white
                            : Colors.grey.shade700),
                  ),
                ),
                if (index != units.length - 1)
                  Container(width: 4, height: 30, color: Colors.grey.shade300),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                elevation: status == 'active' ? 4 : 1,
                color: status == 'active' ? Colors.indigo : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "UNIT ${unit['id']}",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: status == 'active'
                                  ? Colors.white70
                                  : Colors.grey,
                            ),
                          ),
                          Icon(
                            statusIcon,
                            color: status == 'active'
                                ? Colors.white
                                : (status == 'completed'
                                    ? Colors.green
                                    : Colors.grey.shade600),
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (unit['title'] ?? '').toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Text(
                        (unit['description'] ?? '').toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: status == 'active'
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'coffee':
        return Icons.coffee;
      case 'business':
        return Icons.business_center;
      case 'plane':
        return Icons.flight;
      case 'quiz':
        return Icons.quiz;
      default:
        return Icons.handshake;
    }
  }
}
