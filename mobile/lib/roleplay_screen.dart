import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RoleplayScreen extends StatelessWidget {
  final Function(String) onScenarioSelected;

  const RoleplayScreen({super.key, required this.onScenarioSelected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text(
          'Roleplay Arena',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildCard(
              context,
              'Teacher (Default)',
              'default',
              Icons.school,
              Colors.indigo,
            ),
            _buildCard(
              context,
              'Small Talk',
              'smalltalk',
              Icons.forum,
              Colors.teal,
            ),
            _buildCard(
              context,
              'Coffee Shop',
              'cafe',
              Icons.local_cafe,
              Colors.brown,
            ),
            _buildCard(
              context,
              'Restaurant',
              'restaurant',
              Icons.restaurant,
              Colors.deepPurple,
            ),
            _buildCard(
              context,
              'Job Interview',
              'interview',
              Icons.business_center,
              Colors.blueGrey,
            ),
            _buildCard(
              context,
              'Hotel Check-in',
              'hotel',
              Icons.hotel,
              Colors.indigo,
            ),
            _buildCard(
              context,
              'Airport Control',
              'airport',
              Icons.airplanemode_active,
              Colors.deepOrange,
            ),
            _buildCard(
              context,
              'Doctor Visit',
              'doctor',
              Icons.local_hospital,
              Colors.redAccent,
            ),
            _buildCard(
              context,
              'Shopping',
              'shopping',
              Icons.shopping_bag,
              Colors.green,
            ),
            _buildCard(
              context,
              'Taxi Ride',
              'taxi',
              Icons.local_taxi,
              Colors.amber,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    String title,
    String id,
    IconData icon,
    Color color,
  ) {
    return GestureDetector(
      onTap: () => onScenarioSelected(id),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
