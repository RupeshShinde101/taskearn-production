import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class TaskProvider extends ChangeNotifier {
  List<Task> _browseTasks = [];
  List<Task> _myPostedTasks = [];
  List<Task> _myAcceptedTasks = [];
  List<Task> _myCompletedTasks = [];
  /// Stores fully-fetched task details (includes posterPhone etc.)
  final Map<String, Task> _detailCache = {};
  /// Poster phone numbers captured at accept time.
  /// Backed by StorageService so they survive app restarts.
  final Map<String, String> _savedPosterPhones = {};
  /// Poster names captured at accept time.
  final Map<String, String> _savedPosterNames = {};

  /// Persist a poster phone to both the in-memory map and SharedPreferences.
  void _savePhone(String taskId, String phone) {
    if (phone.trim().isEmpty) return;
    _savedPosterPhones[taskId] = phone.trim();
    StorageService.setString('pp_$taskId', phone.trim());
  }

  /// Persist a poster name to both the in-memory map and SharedPreferences.
  void _saveName(String taskId, String name) {
    if (name.trim().isEmpty || name.trim() == 'Anonymous') return;
    _savedPosterNames[taskId] = name.trim();
    StorageService.setString('pn_$taskId', name.trim());
  }

  /// Load any previously persisted poster phone for [taskId].
  String? _loadPhone(String taskId) =>
      _savedPosterPhones[taskId] ?? StorageService.getString('pp_$taskId');

  /// Load any previously persisted poster name for [taskId].
  String? _loadName(String taskId) =>
      _savedPosterNames[taskId] ?? StorageService.getString('pn_$taskId');
  bool _loadingBrowse = false;
  bool _loadingMy = false;
  bool _disposed = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;
  int _browseFetchVersion = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<Task> get browseTasks => _browseTasks;
  List<Task> get myPostedTasks => _myPostedTasks;
  List<Task> get myAcceptedTasks => _myAcceptedTasks;
  List<Task> get myCompletedTasks => _myCompletedTasks;
  bool get isLoadingBrowse => _loadingBrowse;
  bool get isLoadingMy => _loadingMy;
  String? get error => _error;
  bool get hasMore => _hasMore;

  /// True once tasks have been fetched at least once.
  bool get hasMyTasksData =>
      _myPostedTasks.isNotEmpty ||
      _myAcceptedTasks.isNotEmpty ||
      _myCompletedTasks.isNotEmpty;

  /// Cache a list of tasks into [_browseTasks] so getTaskDetail can find them.
  void cacheTasksForBrowse(List<Task> tasks) {
    for (final t in tasks) {
      if (!_browseTasks.any((b) => b.id == t.id)) {
        _browseTasks.add(t);
      }
    }
  }

  /// Returns true if the user currently has an accepted task that is not
  /// yet fully completed. Used to enforce one-task-at-a-time rule.
  bool get hasActiveAcceptedTask {
    const activeStatuses = {
      'accepted', 'in_progress', 'verify_pending',
      'completed', 'payment_released',
    };
    return _myAcceptedTasks.any((t) => activeStatuses.contains(t.status));
  }

  /// Returns the first active accepted task, or null.
  Task? get activeAcceptedTask {
    const activeStatuses = {
      'accepted', 'in_progress', 'verify_pending',
      'completed', 'payment_released',
    };
    try {
      return _myAcceptedTasks.firstWhere((t) => activeStatuses.contains(t.status));
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchBrowseTasks({
    String? category,
    String? search,
    double? lat,
    double? lng,
    double? radiusKm,
    double? minBudget,
    double? maxBudget,
    String? excludePosterId,
    String? sort,
    bool expiringSoon = false,
    bool refresh = false,
  }) async {
    if (refresh) {
      _browseFetchVersion++;
      _currentPage = 1;
      _hasMore = true;
      _browseTasks = [];
    }

    if (!_hasMore) return;

    // Capture token before await so stale responses can be detected and dropped
    final _myVersion = _browseFetchVersion;
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
        if (excludePosterId != null && excludePosterId.isNotEmpty)
          'exclude_poster_id': excludePosterId,
        if (sort != null && sort.isNotEmpty) 'sort': sort,
        if (expiringSoon) 'expiring_soon': '1',
      };

      final data = await ApiService.get('/tasks', queryParams: params);
      final rawList = data['tasks'] as List? ?? [];
      final tasks = rawList.whereType<Map<String, dynamic>>().map((j) {
        try { return Task.fromJson(j); } catch (_) { return null; }
      }).whereType<Task>().toList();

      // Use backend pagination metadata when available, fall back to count heuristic
      final pagination = data['pagination'] as Map?;
      if (pagination != null) {
        final page = (pagination['page'] as num?)?.toInt() ?? _currentPage;
        final totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;
        _hasMore = page < totalPages;
      } else {
        _hasMore = tasks.length >= 20;
      }

      // Discard stale response — a newer refresh has reset the list
      if (_myVersion != _browseFetchVersion) {
        _loadingBrowse = false;
        _notify();
        return;
      }

      _browseTasks.addAll(tasks);
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
      // Auto-persist any phone numbers the backend included in list responses.
      for (final t in [..._myAcceptedTasks, ..._myPostedTasks]) {
        if (t.posterPhone != null && t.posterPhone!.trim().isNotEmpty) {
          _savePhone(t.id, t.posterPhone!);
        }
        if (t.posterName.isNotEmpty && t.posterName != 'Anonymous') {
          _saveName(t.id, t.posterName);
        }
      }
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

  /// Find a task by ID in all local caches (detail cache has highest priority)
  Task? _findCached(String id) {
    if (_detailCache.containsKey(id)) return _detailCache[id];
    for (final list in [_browseTasks, _myPostedTasks, _myAcceptedTasks, _myCompletedTasks]) {
      for (final t in list) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  /// Search every list cache for a non-empty posterPhone for [id].
  String? _findPhoneInAllLists(String id) {
    for (final list in [_browseTasks, _myAcceptedTasks, _myPostedTasks, _myCompletedTasks]) {
      for (final t in list) {
        if (t.id == id && t.posterPhone != null && t.posterPhone!.trim().isNotEmpty) {
          return t.posterPhone!.trim();
        }
      }
    }
    return null;
  }

  /// Search every list cache for a non-empty, non-Anonymous posterName for [id].
  String? _findNameInAllLists(String id) {
    for (final list in [_browseTasks, _myAcceptedTasks, _myPostedTasks, _myCompletedTasks]) {
      for (final t in list) {
        if (t.id == id && t.posterName.isNotEmpty && t.posterName != 'Anonymous') {
          return t.posterName;
        }
      }
    }
    return null;
  }

  /// Try to parse and store a task from an API response into the detail cache.
  /// Only caches if the parsed task has real poster info (not Anonymous).
  void _cacheDetailFromResponse(dynamic response, String taskId) {
    try {
      // Accept endpoint may wrap the task under various keys
      final Map<String, dynamic>? json = response is Map<String, dynamic>
          ? (response['task'] ?? response['data'] ?? response['acceptedTask'] ??
              response['result'] ?? response)
                  as Map<String, dynamic>?
          : null;
      if (json != null && json.isNotEmpty) {
        final task = Task.fromJson(json);
        // Only cache if we got real poster info
        if (task.posterName != 'Anonymous' || task.posterPhone != null) {
          _detailCache[taskId] = task;
        }
      }
    } catch (_) {}
  }

  Future<Task?> getTaskDetail(String id) async {
    if (id.isEmpty) return null;

    // For accepted/in-progress tasks, always fetch fresh from the API so we
    // get the full poster info (phone, avatar) that list endpoints omit.
    final cachedForType = _findCached(id);
    final isActivePoster =
        cachedForType != null && (cachedForType.status == 'posted' || cachedForType.status == 'active');

    // For open/browse tasks, use the detail cache or list cache.
    if (isActivePoster) {
      final cachedDetail = _detailCache[id];
      if (cachedDetail != null &&
          (cachedDetail.posterName != 'Anonymous' ||
              cachedDetail.posterPhone != null)) {
        return cachedDetail;
      }
      return cachedForType;
    }

    // For accepted/in-progress tasks always hit the network to get full poster info.
    for (final path in ['/tasks/$id/details', '/tasks/$id']) {
      try {
        final data = await ApiService.get(path);
        final taskJson = data is Map<String, dynamic>
            ? (data['task'] ?? data['data'] ?? data)
            : null;
        if (taskJson is Map<String, dynamic>) {
          var task = Task.fromJson(taskJson);

          // If the API response omitted posterPhone or posterName, inject
          // them from our persisted sources (browse list snapshot saved at
          // accept time, or any remaining list cache entry that has it).
          final enriched = Map<String, dynamic>.from(taskJson);
          bool needsReparse = false;

          if (task.posterPhone == null || task.posterPhone!.trim().isEmpty) {
            final phone = _loadPhone(id) ?? _findPhoneInAllLists(id);
            if (phone != null) {
              enriched['poster_phone'] = phone;
              needsReparse = true;
            }
          }

          if (task.posterName.isEmpty || task.posterName == 'Anonymous') {
            final name = _loadName(id) ?? _findNameInAllLists(id);
            if (name != null) {
              enriched['poster_name'] = name;
              needsReparse = true;
            }
          }

          if (needsReparse) {
            task = Task.fromJson(enriched);
          }

          _detailCache[id] = task;
          return task;
        }
      } catch (_) {
        // try next endpoint
      }
    }

    // Fallback: return whatever we have in cache.
    // Prefer a version that has a phone number.
    final cachedWithPhone = (() {
      final phone = _loadPhone(id) ?? _findPhoneInAllLists(id);
      if (phone == null) return null;
      // If the detailCache entry lacks the phone, prefer cachedForType if it has it
      if (cachedForType != null &&
          cachedForType.posterPhone != null &&
          cachedForType.posterPhone!.trim().isNotEmpty) {
        return cachedForType;
      }
      return null;
    })();
    if (cachedWithPhone != null) return cachedWithPhone;

    // Even if we must return a cached entry without phone, inject the
    // persisted phone so the call/WhatsApp buttons work.
    Task? result;
    if (_detailCache.containsKey(id)) result = _detailCache[id];
    result ??= cachedForType;
    if (result != null) {
      final phone = _loadPhone(id) ?? _findPhoneInAllLists(id);
      if (phone != null &&
          (result.posterPhone == null || result.posterPhone!.trim().isEmpty)) {
        result = Task.fromJson({
          ...result.toJson(),
          'poster_phone': phone,
        });
      }
    }

    // Last resort: refresh MY tasks list to get fresh status for
    // in-progress / completed tasks — this hits /user/tasks which works.
    try {
      await fetchMyTasks();
      final myRefreshed = _findCached(id);
      if (myRefreshed != null) return myRefreshed;
    } catch (_) {}

    // Also try browse list for open tasks.
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
      // Snapshot the poster phone AND name from the browse list NOW, before
      // the task is removed from _browseTasks after fetchMyTasks(). This
      // ensures they are available when getTaskDetail() is called from the
      // in-progress screen, even if the API detail endpoint omits them.
      final browsePhone = _findPhoneInAllLists(taskId);
      if (browsePhone != null) {
        _savePhone(taskId, browsePhone);
      }
      final browseName = _findNameInAllLists(taskId);
      if (browseName != null) {
        _saveName(taskId, browseName);
      }

      final response = await ApiService.post('/tasks/$taskId/accept');
      // Cache the full task returned by the accept endpoint – it may include
      // posterPhone and other details that the list endpoints omit.
      _cacheDetailFromResponse(response, taskId);

      // If the accept response didn't include a phone but we saved one above,
      // inject it into the detail cache entry now.
      if (browsePhone != null) {
        final cached = _detailCache[taskId];
        if (cached != null &&
            (cached.posterPhone == null || cached.posterPhone!.trim().isEmpty)) {
          _savePhone(taskId, browsePhone);
        }
      }

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

  /// Helper submits proof for verification (Step 1 of completion flow).
  /// POSTs complete to notify poster; proof upload is handled server-side.
  Future<bool> markCompleted(String taskId, {String? proofPath}) async {
    try {
      await ApiService.post('/tasks/$taskId/complete');
      // Invalidate detail cache so next load gets fresh status.
      _detailCache.remove(taskId);
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Network error. Please check your connection and try again.';
      notifyListeners();
      return false;
    }
  }

  /// Helper confirms completion after payment is released (Step 3 of flow).
  Future<bool> finalMarkComplete(String taskId) async {
    try {
      await ApiService.post('/tasks/$taskId/mark-completed');
      // Optimistically remove from accepted list so hasActiveAcceptedTask
      // becomes false immediately — lets the helper accept a new task at once.
      _myAcceptedTasks.removeWhere((t) => t.id == taskId);
      _detailCache.remove(taskId);
      notifyListeners();
      // Sync with backend in background (don't await — let UI navigate first).
      fetchMyTasks();
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

  Future<bool> payHelper(String taskId) async {
    try {
      await ApiService.post('/tasks/$taskId/pay-helper');
      _detailCache.remove(taskId);
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<List<String>> fetchTaskProofs(String taskId) async {
    try {
      final data = await ApiService.get('/tasks/$taskId/proofs');
      if (data == null) return [];
      final list = data is List ? data : (data['proofs'] as List? ?? []);
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
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

  Future<bool> updateTask(String taskId, Map<String, dynamic> data) async {
    try {
      await ApiService.put('/tasks/$taskId', body: data);
      _detailCache.remove(taskId);
      await fetchMyTasks();
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
