import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  static const _steps = [
    _TutorialStep(
      emoji: '👋',
      title: 'Welcome to Workmate4u',
      description:
          'Workmate4u connects people who need tasks done with skilled helpers nearby. '
          'Whether you need something done or want to earn money, we\'ve got you covered.',
    ),
    _TutorialStep(
      emoji: '🔍',
      title: 'Browse Tasks',
      description:
          'Tap the Browse tab to explore tasks posted near you. '
          'Filter by category, budget, or distance to find the perfect match for your skills.',
    ),
    _TutorialStep(
      emoji: '📋',
      title: 'Post a Task',
      description:
          'Need help? Tap the + button to post a task. '
          'Add a title, description, budget, and location. AI will suggest the best helpers for you.',
    ),
    _TutorialStep(
      emoji: '🤝',
      title: 'Accept & Complete',
      description:
          'Helpers apply to your task — you pick the best one. '
          'Once the task is done, confirm completion and the payment is released automatically.',
    ),
    _TutorialStep(
      emoji: '💰',
      title: 'Wallet & Payments',
      description:
          'Top up your wallet using Razorpay. Payments are held securely until '
          'you confirm the task is complete. Helpers can withdraw earnings anytime.',
    ),
    _TutorialStep(
      emoji: '⭐',
      title: 'Ratings & Trust',
      description:
          'After every task, both parties leave a review. '
          'Build your reputation to unlock higher ranks — Bronze, Silver, Gold, Platinum, and Elite.',
    ),
    _TutorialStep(
      emoji: '🎉',
      title: 'You\'re All Set!',
      description:
          'That\'s everything you need to get started. '
          'Explore, post tasks, earn money, and grow your rank on Workmate4u!',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _steps.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      context.pop();
    }
  }

  void _prev() {
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutorial'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Page indicator ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),

          // ── Pages ────────────────────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemCount: _steps.length,
              itemBuilder: (_, i) => _StepPage(step: _steps[i]),
            ),
          ),

          // ── Navigation buttons ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _prev,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentPage > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isLast ? 'Get Started 🚀' : 'Next',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
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

// ── Single tutorial step page ─────────────────────────────────────────────────

class _StepPage extends StatelessWidget {
  final _TutorialStep step;
  const _StepPage({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji illustration
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  const Color(0xFF7C3AED).withValues(alpha: 0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(step.emoji, style: const TextStyle(fontSize: 52)),
            ),
          ),

          const SizedBox(height: 36),

          Text(
            step.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.dark,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            step.description,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.gray,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _TutorialStep {
  final String emoji;
  final String title;
  final String description;
  const _TutorialStep({
    required this.emoji,
    required this.title,
    required this.description,
  });
}
