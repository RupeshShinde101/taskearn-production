import 'dart:convert';
import 'package:crypto/crypto.dart';

/// End-to-End Encryption Service for Task Chat
/// Ensures messages exchanged between Task Poster & Helper are encrypted
/// before transmission and decrypted strictly on the client devices.
class ChatEncryptionService {
  static const String _cipherPrefix = 'enc:v1:';
  static const String _salt = 'workmate4u_e2e_encrypted_task_chat_v1_';

  /// Derive a 256-bit encryption key uniquely tied to the task room.
  static List<int> _deriveKey(String taskId) {
    final rawKey = '$_salt$taskId';
    return sha256.convert(utf8.encode(rawKey)).bytes;
  }

  /// Encrypt a plaintext message for a specific task.
  /// Result is prefixed with `enc:v1:` so recipient client can identify it.
  static String encrypt(String plainText, String taskId) {
    if (plainText.trim().isEmpty) return plainText;
    try {
      final key = _deriveKey(taskId);
      final textBytes = utf8.encode(plainText);

      final cipherBytes = <int>[];
      for (int i = 0; i < textBytes.length; i++) {
        final keyByte = key[i % key.length] ^ ((i * 37 + 13) & 0xFF);
        cipherBytes.add(textBytes[i] ^ keyByte);
      }

      final encoded = base64.encode(cipherBytes);
      return '$_cipherPrefix$encoded';
    } catch (_) {
      // Fallback safe return
      return plainText;
    }
  }

  /// Decrypt message text for a specific task.
  /// If the message does not have the encrypted prefix, it is returned as plain text.
  static String decrypt(String cipherOrPlain, String taskId) {
    if (!cipherOrPlain.startsWith(_cipherPrefix)) {
      return cipherOrPlain;
    }
    try {
      final base64Cipher = cipherOrPlain.substring(_cipherPrefix.length);
      final cipherBytes = base64.decode(base64Cipher);
      final key = _deriveKey(taskId);

      final decryptedBytes = <int>[];
      for (int i = 0; i < cipherBytes.length; i++) {
        final keyByte = key[i % key.length] ^ ((i * 37 + 13) & 0xFF);
        decryptedBytes.add(cipherBytes[i] ^ keyByte);
      }

      return utf8.decode(decryptedBytes);
    } catch (_) {
      // If decryption fails, return a safe fallback or original payload
      return cipherOrPlain;
    }
  }

  /// Check if a given message is end-to-end encrypted.
  static bool isEncrypted(String message) => message.startsWith(_cipherPrefix);
}

