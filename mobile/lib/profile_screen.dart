import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String selectedLanguage = 'tr'; // 'tr' or 'en'

  final String baseUrl = 'http://192.168.1.19:8000';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _fetchUserData();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedLanguage = prefs.getString('selected_language') ?? 'tr';
    });
  }

  Future<void> _saveLanguagePreference(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', language);
    setState(() {
      selectedLanguage = language;
    });
  }

  Future<void> _fetchUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('user_token');

    if (token == null || token.isEmpty) {
      await _logout();
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/profile'),
        headers: {"Authorization": "Bearer $token"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          userData = jsonDecode(response.body);
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        await _logout();
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_token');
    await prefs.remove('username');

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  String _getLevelTitle(int level) {
    if (selectedLanguage == 'tr') {
      if (level == 1) return "A1 - Başlangıç";
      if (level == 2) return "A2 - Temel";
      if (level == 3) return "B1 - Orta";
      if (level == 4) return "B2 - Üst Orta";
      if (level == 5) return "C1 - İleri";
      return "Yeni Başlayan";
    } else {
      if (level == 1) return "A1 - Beginner";
      if (level == 2) return "A2 - Elementary";
      if (level == 3) return "B1 - Intermediate";
      if (level == 4) return "B2 - Upper Inter.";
      if (level == 5) return "C1 - Advanced";
      return "Newbie";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final username = userData?['username'] ?? 'User';
    final xp = userData?['xp'] ?? 0;
    final level = userData?['level'] ?? 1;
    final streak = userData?['streak'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text(
          selectedLanguage == 'tr' ? 'Profilim' : 'My Profile',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _logout,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF8B85FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 50, color: Color(0xFF6C63FF)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username.toString(),
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _getLevelTitle(int.tryParse(level.toString()) ?? 1),
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(Icons.bolt, "$xp", selectedLanguage == 'tr' ? "XP" : "XP"),
                      Container(width: 1, height: 40, color: Colors.white24),
                      _buildStatItem(Icons.local_fire_department, "$streak", selectedLanguage == 'tr' ? "Seri" : "Streak"),
                      Container(width: 1, height: 40, color: Colors.white24),
                      _buildStatItem(Icons.verified, "Lvl $level", selectedLanguage == 'tr' ? "Seviye" : "Level"),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 30),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectedLanguage == 'tr' ? 'Mevcut İlerleme' : "Current Progress",
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        selectedLanguage == 'tr' ? 'Sonraki Seviye' : "Next Level",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        "$xp / 1000 XP",
                        style: GoogleFonts.poppins(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: ((xp is int ? xp : int.tryParse(xp.toString()) ?? 0) %
                            1000) /
                        1000,
                    backgroundColor: Colors.grey.shade100,
                    color: Colors.orange,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    selectedLanguage == 'tr' 
                        ? "Daha fazla XP kazanmak ve yeni senaryoları açmak için pratik yapmaya devam et!"
                        : "Keep practicing to earn more XP and unlock new scenarios!",
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Language Picker
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedLanguage == 'tr' ? 'Dil Seçimi' : 'Language Selection',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _saveLanguagePreference('tr'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedLanguage == 'tr' 
                                  ? Colors.indigo 
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Türkçe',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: selectedLanguage == 'tr' 
                                    ? Colors.white 
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _saveLanguagePreference('en'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedLanguage == 'en' 
                                  ? Colors.indigo 
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'English',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: selectedLanguage == 'en' 
                                    ? Colors.white 
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            _buildMenuItem(Icons.settings, selectedLanguage == 'tr' ? "Ayarlar" : "Settings", () {}),
            _buildMenuItem(Icons.help_outline, selectedLanguage == 'tr' ? "Yardım ve Destek" : "Help & Support", () {}),
            _buildMenuItem(Icons.privacy_tip, selectedLanguage == 'tr' ? "Gizlilik Politikası" : "Privacy Policy", () {}),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.indigo),
        ),
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
