import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5F6FF), Color(0xFFEEF0FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 220,
              ),
              const SizedBox(height: 12),
              const Text(
                'Find • Work • Earn',
                style: TextStyle(color: AppColors.gray, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
