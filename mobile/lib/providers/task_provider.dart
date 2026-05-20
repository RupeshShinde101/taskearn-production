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
    notifyListeners();

    try {
      final params = <String, String>{
        'page': '$_currentPage',
        'per_page': '20',
        if (category != null && category != 'all') 'category': category,
        if (lat != null) 'lat': '$lat',
        if (lng != null) 'lng': '$lng',
        if (radiusKm != null) 'radius': '$radiusKm',
        if (minBudget != null) 'min_budget': '$minBudget',
        if (maxBudget != null) 'max_budget': '$maxBudget',
      };

      final data = await ApiService.get('/tasks', queryParams: params);
      final tasks = (data['tasks'] as List? ?? data as List? ?? [])
          .map((j) => Task.fromJson(j))
          .toList();

      _browseTasks.addAll(tasks);
      _hasMore = tasks.length == 20;
      _currentPage++;
    } on ApiException catch (e) {
      _error = e.message;
    }

    _loadingBrowse = false;
    notifyListeners();
  }

  Future<void> fetchMyTasks() async {
    _loadingMy = true;
    notifyListeners();

    try {
      final data = await ApiService.get('/user/tasks');
      final posted = (data['posted'] as List? ?? [])
          .map((j) => Task.fromJson(j))
          .toList();
      final accepted = (data['accepted'] as List? ?? [])
          .map((j) => Task.fromJson(j))
          .toList();
      final completed = (data['completed'] as List? ?? [])
          .map((j) => Task.fromJson(j))
          .toList();

      _myPostedTasks = posted;
      _myAcceptedTasks = accepted;
      _myCompletedTasks = completed;
    } on ApiException catch (e) {
      _error = e.message;
    }

    _loadingMy = false;
    notifyListeners();
  }

  Future<Task?> getTaskDetail(String id) async {
    try {
      final data = await ApiService.get('/tasks/$id/details');
      return Task.fromJson(data['task'] ?? data);
    } on ApiException {
      return null;
    }
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
      await fetchBrowseTasks(refresh: true);
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
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
