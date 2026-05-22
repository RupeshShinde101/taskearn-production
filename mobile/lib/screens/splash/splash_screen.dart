import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.gradient),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x446366F1),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.work_outline, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Workmate4u',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Find • Work • Earn',
              style: TextStyle(color: AppColors.gray, fontSize: 14),
            ),
            const SizedBox(height: 52),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
