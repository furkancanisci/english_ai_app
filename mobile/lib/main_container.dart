import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'flashcard_screen.dart';
import 'profile_screen.dart';
import 'roadmap_screen.dart';
import 'roleplay_screen.dart';
import 'story_screen.dart';
import 'vocabulary_screen.dart';
import 'daily_test_screen.dart';

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;
  String selectedLanguage = 'tr';

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  Future<void> _loadLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedLanguage = prefs.getString('selected_language') ?? 'tr';
    });
  }

  void _startChat(String scenarioId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(scenario: scenarioId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      RoleplayScreen(onScenarioSelected: _startChat),
      const RoadmapScreen(),
      const StoryScreen(),
      const FlashcardScreen(),
      const VocabularyScreen(),
      const DailyTestScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: tabs[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: selectedLanguage == 'tr' ? 'Sohbet' : 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: selectedLanguage == 'tr' ? 'Yol' : 'Path',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: selectedLanguage == 'tr' ? 'Hikaye' : 'Story',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: selectedLanguage == 'tr' ? 'Kartlar' : 'Cards',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: selectedLanguage == 'tr' ? 'Sözlük' : 'Vocab',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: selectedLanguage == 'tr' ? 'Test' : 'Test',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: selectedLanguage == 'tr' ? 'Profil' : 'Profile',
          ),
        ],
      ),
    );
  }
}
