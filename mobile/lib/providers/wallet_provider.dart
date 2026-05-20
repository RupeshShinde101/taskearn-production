import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/api_service.dart';

class WalletProvider extends ChangeNotifier {
  WalletBalance _balance = WalletBalance.empty();
  List<Transaction> _transactions = [];
  List<WithdrawalRequest> _withdrawals = [];
  bool _loading = false;
  String? _error;

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

  // Returns Razorpay order data for wallet top-up
  Future<Map<String, dynamic>?> createTopUpOrder(double amount) async {
    try {
      final data = await ApiService.post('/payments/wallet-topup-order',
          body: {'amount': amount});
      return data;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> verifyTopUp(Map<String, dynamic> paymentData) async {
    try {
      await ApiService.post('/payments/wallet-topup-verify', body: paymentData);
      await fetchWallet();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestWithdrawal({
    required double amount,
    required String bankAccount,
    required String ifscCode,
    required String accountHolder,
  }) async {
    try {
      await ApiService.post('/wallet/withdraw', body: {
        'amount': amount,
        'bank_account': bankAccount,
        'ifsc_code': ifscCode,
        'account_holder': accountHolder,
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
