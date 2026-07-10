import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/api_service.dart';

class WalletProvider extends ChangeNotifier {
  WalletBalance _balance = WalletBalance.empty();
  List<Transaction> _transactions = [];
  List<WithdrawalRequest> _withdrawals = [];
  bool _loading = false;
  String? _error;
  /// Amount (in paise) from the most recently created top-up order.
  /// Stored here so [verifyTopUp] can include it in the verify request.
  int _pendingTopUpAmountPaise = 0;

  WalletBalance get balance => _balance;
  List<Transaction> get transactions => _transactions;
  List<WithdrawalRequest> get withdrawals => _withdrawals;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> fetchWallet() async {
    _loading = true;
    notifyListeners();

    try {
      final data = await ApiService.get('/wallet');
      _balance = WalletBalance.fromJson(data['wallet'] ?? data);
    } on ApiException catch (e) {
      _error = e.message;
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> fetchTransactions() async {
    try {
      final data = await ApiService.get('/wallet/transactions');
      _transactions = (data['transactions'] as List? ?? [])
          .map((j) => Transaction.fromJson(j))
          .toList();
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  Future<void> fetchWithdrawals() async {
    try {
      final data = await ApiService.get('/wallet/withdrawals');
      _withdrawals = (data['withdrawals'] as List? ?? [])
          .map((j) => WithdrawalRequest.fromJson(j))
          .toList();
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  // Returns Razorpay order data for wallet top-up.
  // Amount must be in RUPEES (the backend auto-converts to paise and returns
  // the order amount in paise in the 'amount' field of the response).
  Future<Map<String, dynamic>?> createTopUpOrder(double amountRupees) async {
    try {
      // Send amount as integer rupees. The backend converts to paise internally
      // and returns the Razorpay order with 'amount' in paise.
      final data = await ApiService.post('/payments/wallet-topup-order',
          body: {'amount': amountRupees.toInt()});
      if (data is Map && data['success'] == false) {
        _error = data['message']?.toString() ?? 'Failed to create order';
        notifyListeners();
        return null;
      }
      // Store the paise amount from the Razorpay order for the verify step.
      final rawAmount = data['amount'];
      _pendingTopUpAmountPaise =
          int.tryParse(rawAmount?.toString() ?? '0') ?? 0;
      return Map<String, dynamic>.from(data as Map);
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  /// Verify a completed Razorpay top-up payment.
  /// [paymentId] = Razorpay payment ID (always present)
  /// [orderId]   = Razorpay order ID (from the order we created)
  /// [signature] = HMAC signature from Razorpay (present for order payments)
  Future<bool> verifyTopUp({
    required String paymentId,
    required String orderId,
    required String signature,
  }) async {
    try {
      final body = <String, dynamic>{
        'paymentId': paymentId,
        'orderId': orderId,
        'signature': signature,
        'amount': _pendingTopUpAmountPaise,
      };
      final result = await ApiService.post('/payments/wallet-topup-verify',
          body: body);
      if (result is Map && result['success'] == false) {
        _error = result['message']?.toString() ?? 'Payment verification failed';
        notifyListeners();
        return false;
      }
      _pendingTopUpAmountPaise = 0;
      await fetchWallet();
      await fetchTransactions();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestWithdrawal({
    required double amount,
    required String bankName,
    required String bankAccount,
    required String ifscCode,
    required String accountHolder,
  }) async {
    try {
      await ApiService.post('/wallet/withdraw', body: {
        'amount': amount,
        'bankName': bankName,
        'accountNumber': bankAccount,
        'ifscCode': ifscCode,
        'accountHolder': accountHolder,
      });
      await fetchWallet();
      await fetchWithdrawals();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
