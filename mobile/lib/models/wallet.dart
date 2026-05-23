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
  /// Raw JSON direction field from backend (may be 'credit'/'debit'/'in'/'out')
  final String? direction;
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
    this.direction,
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
      direction: (json['direction'] ?? json['credit_type'] ?? json['flow'] ?? '')
          ?.toString()
          .toLowerCase(),
    );
  }

  bool get isCredit {
    // Check direction/flow field first (most reliable when present)
    if (direction == 'credit' || direction == 'in') return true;
    if (direction == 'debit' || direction == 'out') return false;
    // Fall back to type-based check — covers many backend naming conventions
    const creditTypes = {
      'earn', 'earned', 'add', 'added', 'credit', 'credited',
      'cashback', 'refund', 'refunded', 'topup', 'top_up', 'wallet_topup',
      'wallet_add', 'received', 'task_earning', 'task_earned', 'earning',
      'bonus', 'reward',
    };
    const debitTypes = {
      'pay', 'paid', 'debit', 'debited', 'penalty', 'withdrawal',
      'withdraw', 'task_payment', 'deducted', 'charge',
    };
    final t = type.toLowerCase();
    if (creditTypes.contains(t)) return true;
    if (debitTypes.contains(t)) return false;
    // Substring heuristic as last resort
    return t.contains('credit') || t.contains('earn') ||
           t.contains('add') || t.contains('refund') ||
           t.contains('topup') || t.contains('top_up');
  }

  bool get isDebit => !isCredit;

  String get typeLabel {
    switch (type.toLowerCase()) {
      case 'earned':
      case 'earn':
      case 'task_earning':
      case 'task_earned':
      case 'earning':
        return 'Earned';
      case 'add':
      case 'added':
      case 'credit':
      case 'credited':
      case 'topup':
      case 'top_up':
      case 'wallet_topup':
      case 'wallet_add':
        return 'Added';
      case 'pay':
      case 'paid':
      case 'debit':
      case 'debited':
      case 'task_payment':
        return 'Paid';
      case 'penalty':
        return 'Penalty';
      case 'cashback':
      case 'bonus':
      case 'reward':
        return 'Cashback';
      case 'withdrawal':
      case 'withdraw':
        return 'Withdrawal';
      case 'refund':
      case 'refunded':
        return 'Refund';
      default:
        // Capitalise the raw type as a readable fallback
        return type.isEmpty ? 'Transaction'
            : type[0].toUpperCase() + type.substring(1);
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
