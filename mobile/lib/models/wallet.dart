class WalletBalance {
  final double balance;
  final double totalEarned;
  final double totalSpent;
  final double totalAdded;
  final double totalCashback;
  final double pendingWithdrawal;

  WalletBalance({
    required this.balance,
    required this.totalEarned,
    required this.totalSpent,
    required this.totalAdded,
    required this.totalCashback,
    required this.pendingWithdrawal,
  });

  static double _parseDouble(dynamic v) =>
      double.tryParse((v ?? 0).toString()) ?? 0.0;

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    return WalletBalance(
      balance: _parseDouble(json['balance']),
      totalEarned: _parseDouble(json['total_earned']),
      totalSpent: _parseDouble(json['total_spent']),
      totalAdded: _parseDouble(json['total_added']),
      totalCashback: _parseDouble(json['total_cashback']),
      pendingWithdrawal: _parseDouble(json['pending_withdrawal']),
    );
  }

  factory WalletBalance.empty() => WalletBalance(
        balance: 0,
        totalEarned: 0,
        totalSpent: 0,
        totalAdded: 0,
        totalCashback: 0,
        pendingWithdrawal: 0,
      );
}

class Transaction {
  final String id;
  final String type;
  final double amount;
  final String description;
  final String status;
  final DateTime createdAt;
  final String? taskId;
  final String? taskTitle;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.status,
    required this.createdAt,
    this.taskId,
    this.taskTitle,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? '',
      amount: double.tryParse((json['amount'] ?? 0).toString()) ?? 0.0,
      description: json['description'] ?? '',
      status: json['status'] ?? 'completed',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at']) ?? DateTime.now()
          : DateTime.now(),
      taskId: json['task_id']?.toString(),
      taskTitle: json['task_title'],
    );
  }

  bool get isCredit =>
      type == 'earn' || type == 'add' || type == 'cashback' || type == 'refund';
  bool get isDebit =>
      type == 'pay' || type == 'penalty' || type == 'withdrawal';

  String get typeLabel {
    switch (type) {
      case 'earn':
        return 'Earned';
      case 'add':
        return 'Added';
      case 'pay':
        return 'Paid';
      case 'penalty':
        return 'Penalty';
      case 'cashback':
        return 'Cashback';
      case 'withdrawal':
        return 'Withdrawal';
      case 'refund':
        return 'Refund';
      default:
        return type;
    }
  }
}

class WithdrawalRequest {
  final String id;
  final double amount;
  final String status;
  final String bankAccount;
  final String ifscCode;
  final String accountHolder;
  final DateTime requestedAt;
  final DateTime? processedAt;

  WithdrawalRequest({
    required this.id,
    required this.amount,
    required this.status,
    required this.bankAccount,
    required this.ifscCode,
    required this.accountHolder,
    required this.requestedAt,
    this.processedAt,
  });

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: json['id']?.toString() ?? '',
      amount: double.tryParse((json['amount'] ?? 0).toString()) ?? 0.0,
      status: json['status'] ?? 'pending',
      bankAccount: json['bank_account'] ?? '',
      ifscCode: json['ifsc_code'] ?? '',
      accountHolder: json['account_holder'] ?? '',
      requestedAt: json['requested_at'] != null
          ? DateTime.tryParse(json['requested_at']) ?? DateTime.now()
          : DateTime.now(),
      processedAt: json['processed_at'] != null
          ? DateTime.tryParse(json['processed_at'])
          : null,
    );
  }
}
