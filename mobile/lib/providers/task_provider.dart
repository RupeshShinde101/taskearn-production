import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';

class TaskProvider extends ChangeNotifier {
  List<Task> _browseTasks = [];
  List<Task> _myPostedTasks = [];
  List<Task> _myAcceptedTasks = [];
  List<Task> _myCompletedTasks = [];
  bool _loadingBrowse = false;
  bool _loadingMy = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;

  List<Task> get browseTasks => _browseTasks;
  List<Task> get myPostedTasks => _myPostedTasks;
  List<Task> get myAcceptedTasks => _myAcceptedTasks;
  List<Task> get myCompletedTasks => _myCompletedTasks;
  bool get isLoadingBrowse => _loadingBrowse;
  bool get isLoadingMy => _loadingMy;
  String? get error => _error;
  bool get hasMore => _hasMore;

  Future<void> fetchBrowseTasks({
    String? category,
    String? search,
    double? lat,
    double? lng,
    double? radiusKm,
    double? minBudget,
    double? maxBudget,
    bool refresh = false,
  }) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _browseTasks = [];
    }

    if (!_hasMore) return;

    _loadingBrowse = true;
    _error = null;
    // Use microtask so notifyListeners doesn't fire synchronously during build
    Future.microtask(notifyListeners);

    try {
      final params = <String, String>{
        'page': '$_currentPage',
        'per_page': '20',
        if (category != null && category != 'all') 'category': category,
        if (search != null && search.isNotEmpty) 'search': search,
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
        if (radiusKm != null) 'radius': '$radiusKm',
        if (minBudget != null) 'min_budget': '$minBudget',
        if (maxBudget != null) 'max_budget': '$maxBudget',
      };

      final data = await ApiService.get('/tasks', queryParams: params);
      final rawList = data['tasks'] as List? ?? [];
      final tasks = rawList.whereType<Map<String, dynamic>>().map((j) {
        try { return Task.fromJson(j); } catch (_) { return null; }
      }).whereType<Task>().toList();

      _browseTasks.addAll(tasks);
      _hasMore = tasks.length == 20;
      _currentPage++;
    } catch (e) {
      _error = e.toString();
    }

    _loadingBrowse = false;
    notifyListeners();
  }

  Future<void> fetchMyTasks() async {
    _loadingMy = true;
    Future.microtask(notifyListeners);

    try {
      final data = await ApiService.get('/user/tasks');
      // API returns 'postedTasks' and 'acceptedTasks' (not 'posted'/'accepted')
      _myPostedTasks = _parseTaskList(data['postedTasks'] ?? data['posted']);
      _myAcceptedTasks = _parseTaskList(data['acceptedTasks'] ?? data['accepted']);
      _myCompletedTasks = _parseTaskList(data['completedTasks'] ?? data['completed']);
    } catch (e) {
      _error = e.toString();
    }

    _loadingMy = false;
    notifyListeners();
  }

  List<Task> _parseTaskList(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map((j) {
      try {
        return Task.fromJson(j);
      } catch (_) {
        return null;
      }
    }).whereType<Task>().toList();
  }

  /// Find a task by ID in all local caches
  Task? _findCached(String id) {
    for (final list in [_browseTasks, _myPostedTasks, _myAcceptedTasks, _myCompletedTasks]) {
      for (final t in list) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  Future<Task?> getTaskDetail(String id) async {
    if (id.isEmpty) return null;

    // Check local cache first.
    final cached = _findCached(id);
    if (cached != null && (cached.status == 'posted' || cached.status == 'active')) {
      // Return cached immediately for browse/open tasks
      return cached;
    }

    // For accepted/completed tasks, try the detail endpoint
    try {
      final data = await ApiService.get('/tasks/$id/details');
      final taskJson = data is Map<String, dynamic>
          ? (data['task'] ?? data['data'] ?? data)
          : null;
      if (taskJson is Map<String, dynamic>) {
        return Task.fromJson(taskJson);
      }
    } catch (_) {
      // fall through
    }

    // Return cached value if available
    if (cached != null) return cached;

    // Last resort: refresh browse list and search
    try {
      await fetchBrowseTasks(refresh: true);
      final refreshed = _findCached(id);
      if (refreshed != null) return refreshed;
    } catch (_) {}

    return null;
  }

  Future<bool> postTask(Map<String, dynamic> taskData) async {
    try {
      await ApiService.post('/tasks', body: taskData);
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> acceptTask(String taskId) async {
    try {
      await ApiService.post('/tasks/$taskId/accept');
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Cancel / delete a task posted by the current user.
  /// For active tasks (no helper): DELETE /tasks/:id
  /// For accepted tasks (poster cancels after helper accepted): POST /tasks/:id/poster-cancel
  Future<bool> cancelTask(String taskId, {bool hasHelper = false}) async {
    try {
      if (hasHelper) {
        await ApiService.post('/tasks/$taskId/poster-cancel');
      } else {
        await ApiService.delete('/tasks/$taskId');
      }
      _myPostedTasks.removeWhere((t) => t.id == taskId);
      _browseTasks.removeWhere((t) => t.id == taskId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> abandonTask(String taskId) async {
    try {
      await ApiService.post('/tasks/$taskId/abandon');
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> markCompleted(String taskId, {String? proofPath}) async {
    try {
      if (proofPath != null) {
        await ApiService.uploadFile(
          '/tasks/$taskId/upload-proof',
          proofPath,
          'proof',
        );
      }
      await ApiService.post('/tasks/$taskId/mark-completed');
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyTask(String taskId, String otp) async {
    try {
      await ApiService.post('/tasks/$taskId/verify', body: {'otp': otp});
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> rateTask(String taskId, double rating, String? comment) async {
    try {
      await ApiService.post('/tasks/$taskId/rate', body: {
        'rating': rating,
        if (comment != null) 'comment': comment,
      });
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteTask(String taskId) async {
    try {
      await ApiService.delete('/tasks/$taskId');
      _myPostedTasks.removeWhere((t) => t.id == taskId);
      notifyListeners();
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
