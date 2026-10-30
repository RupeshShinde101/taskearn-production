import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

Future<bool> showProfileModeSwitchDialog(
  BuildContext context, {
  required String targetMode, // 'poster' or 'helper'
  String? title,
  String? message,
  String? actionLabel,
}) async {
  final isPoster = targetMode == 'poster';
  final defaultTitle =
      isPoster ? 'Switch to Poster Profile' : 'Switch to Helper Profile';
  final defaultMessage = isPoster
      ? 'Posting tasks requires switching to your Poster profile. Would you like to switch to Poster mode now?'
      : 'Accepting tasks requires switching to your Helper profile. Would you like to switch to Helper mode now?';
  final defaultAction = isPoster ? 'Switch to Poster' : 'Switch to Helper';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPoster
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : const Color(0xFF10B981).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPoster ? Icons.assignment_add : Icons.handshake_rounded,
              color: isPoster ? AppColors.primary : const Color(0xFF10B981),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title ?? defaultTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message ?? defaultMessage,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.gray,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.gray,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isPoster ? AppColors.primary : const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(actionLabel ?? defaultAction),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await context.read<AuthProvider>().setProfileMode(targetMode);
    return true;
  }
  return false;
}
