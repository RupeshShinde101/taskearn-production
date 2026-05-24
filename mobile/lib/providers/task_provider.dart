import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  /// Task IDs the helper has locally marked as complete but the backend may
  /// still echo back in /user/tasks (due to propagation delay). We filter
  /// these from _myAcceptedTasks inside fetchMyTasks() so that
  /// hasActiveAcceptedTask never goes true again after the helper is done.
  final Set<String> _locallyCompletedTaskIds = {};
  /// Poster phone numbers captured at accept time.
  /// Backed by StorageService so they survive app restarts.
  final Map<String, String> _savedPosterPhones = {};
  /// Poster names captured at accept time.
  final Map<String, String> _savedPosterNames = {};

  /// Locally persisted completedAt timestamps — backed by SharedPreferences
  /// so the 48-h expiry timer survives app restarts.
  final Map<String, DateTime> _savedCompletedAt = {};
  bool _completedAtLoaded = false;

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

  /// Persist a completedAt timestamp so it survives app restarts.
  void _saveCompletedAt(String taskId, DateTime completedAt) {
    _savedCompletedAt[taskId] = completedAt;
    _flushCompletedAtMap();
  }

  /// Write the full completedAt map to SharedPreferences as JSON.
  void _flushCompletedAtMap() {
    final encoded = jsonEncode({
      for (final e in _savedCompletedAt.entries)
        e.key: e.value.toIso8601String(),
    });
    StorageService.setString('_completedAtMap', encoded);
  }

  /// Load all persisted completedAt timestamps once from SharedPreferences.
  void _loadSavedCompletedAt() {
    if (_completedAtLoaded) return;
    _completedAtLoaded = true;
    final raw = StorageService.getString('_completedAtMap');
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final dt = DateTime.tryParse(e.value.toString());
        if (dt != null) _savedCompletedAt[e.key] = dt;
      }
    } catch (_) {}
    // Drop entries older than 48 h (no longer relevant).
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    _savedCompletedAt.removeWhere((_, dt) => dt.isBefore(cutoff));
  }

  bool _loadingBrowse = false;
  bool _loadingMy = false;
  bool _disposed = false;
  String? _error;
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    // If we're in a build/layout phase, defer to avoid the 'dependents.isEmpty' assertion.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  List<Task> get browseTasks => _browseTasks;
  List<Task> get myPostedTasks => _myPostedTasks;
  List<Task> get myAcceptedTasks => _myAcceptedTasks;
  List<Task> get myCompletedTasks => _myCompletedTasks;
  bool get isLoadingBrowse => _loadingBrowse;
  bool get isLoadingMy => _loadingMy;
  String? get error => _error;
  bool get hasMore => _hasMore;

  /// Returns true if the user currently has an accepted task that is not
  /// yet fully completed. Used to enforce one-task-at-a-time rule.
  bool get hasActiveAcceptedTask {
    const activeStatuses = {
      'accepted', 'in_progress', 'verify_pending',
      'completed', 'payment_released', 'verified',
    };
    return _myAcceptedTasks.any(
      (t) => activeStatuses.contains(t.status) || t.isPaid,
    );
  }

  /// Returns the first active accepted task, or null.
  Task? get activeAcceptedTask {
    const activeStatuses = {
      'accepted', 'in_progress', 'verify_pending',
      'completed', 'payment_released', 'verified',
    };
    try {
      return _myAcceptedTasks.firstWhere(
        (t) => activeStatuses.contains(t.status) || t.isPaid,
      );
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
    Future.microtask(_notify);

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
      // Posted tasks expire after 24 h — filter client-side in case the backend
      // doesn't clean them up immediately.
      final expiryCutoff = DateTime.now().subtract(const Duration(hours: 24));
      final tasks = rawList.whereType<Map<String, dynamic>>().map((j) {
        try { return Task.fromJson(j); } catch (_) { return null; }
      }).whereType<Task>()
          .where((t) => t.createdAt.isAfter(expiryCutoff))
          .toList();

      _browseTasks.addAll(tasks);
      _hasMore = tasks.length == 20;
      _currentPage++;
    } catch (e) {
      _error = e.toString();
    }

    _loadingBrowse = false;
    _notify();
  }

  Future<void> fetchMyTasks() async {
    _loadingMy = true;
    Future.microtask(_notify);

    try {
      final data = await ApiService.get('/user/tasks');

      // Statuses that mean the task is truly done from the helper's perspective.
      // NOTE: 'completed' and 'verify_pending' are NOT here — they mean the
      // helper submitted proof but is still waiting for the poster to pay.
      // 'payment_released' and 'paid' are excluded — helper still needs to
      // click "Mark as Completed" before the task moves to the Completed tab.
      // Only 'done'/'finished' mean the helper has truly confirmed completion.
      const completedStatuses = {
        'verified', 'done', 'finished',
      };

      // Statuses that mean a posted task is fully done — remove from Posted tab.
      const postedDoneStatuses = {
        'verified', 'paid', 'done', 'finished', 'payment_released',
        'cancelled',
      };
      final postedExpiryCutoff =
          DateTime.now().subtract(const Duration(hours: 24));
      _myPostedTasks = _parseTaskList(data['postedTasks'] ?? data['posted'])
          .where((t) => !postedDoneStatuses.contains(t.status))
          // Remove tasks still in 'posted' status that have passed the 24-h window
          .where((t) =>
              t.status != 'posted' ||
              t.createdAt.isAfter(postedExpiryCutoff))
          .toList();
      final rawAccepted = _parseTaskList(data['acceptedTasks'] ?? data['accepted']);

      // Backend may return a dedicated completedTasks field OR may include
      // completed-status tasks inside acceptedTasks.  Handle both.
      final backendCompleted =
          _parseTaskList(data['completedTasks'] ?? data['completed']);
      // Extract any completed-status tasks that the backend put in acceptedTasks
      final completedFromAccepted = rawAccepted
          .where((t) => completedStatuses.contains(t.status))
          .toList();
      // Preserve locally-stamped completedAt values before overwriting the list.
      // The backend often omits completed_at, so we keep timestamps from memory
      // AND from SharedPreferences (survives app restarts).
      _loadSavedCompletedAt();
      final prevCompletedAt = Map<String, DateTime>.fromEntries(
        _myCompletedTasks
            .where((t) => t.completedAt != null)
            .map((t) => MapEntry(t.id, t.completedAt!)),
      );
      // Merge persisted stamps for tasks not yet in in-memory list.
      for (final e in _savedCompletedAt.entries) {
        prevCompletedAt.putIfAbsent(e.key, () => e.value);
      }

      // Merge both sources (dedup by id)
      _myCompletedTasks = List<Task>.from(backendCompleted);
      for (final t in completedFromAccepted) {
        if (!_myCompletedTasks.any((c) => c.id == t.id)) {
          _myCompletedTasks.add(t);
        }
      }

      // Re-add tasks that the helper confirmed locally (clicked "Mark as Completed")
      // but whose status is still 'completed' / 'verify_pending' / 'payment_released'
      // (not yet in completedStatuses). Without this they would vanish from the
      // Completed tab after the next fetchMyTasks() rebuild.
      for (final id in _locallyCompletedTaskIds) {
        if (!_myCompletedTasks.any((t) => t.id == id)) {
          final rawTask = rawAccepted.cast<Task?>().firstWhere((t) => t!.id == id, orElse: () => null);
          if (rawTask != null) {
            final stamp = prevCompletedAt[id] ?? _savedCompletedAt[id] ?? DateTime.now();
            _myCompletedTasks.insert(0, rawTask.copyWith(completedAt: stamp));
          }
        }
      }

      // Restore locally-stamped completedAt where backend returned null.
      for (int i = 0; i < _myCompletedTasks.length; i++) {
        if (_myCompletedTasks[i].completedAt == null &&
            prevCompletedAt.containsKey(_myCompletedTasks[i].id)) {
          _myCompletedTasks[i] = _myCompletedTasks[i]
              .copyWith(completedAt: prevCompletedAt[_myCompletedTasks[i].id]);
        }
      }

      debugPrint('[TaskProvider] /user/tasks keys=${data.keys.toList()}');
      debugPrint('[TaskProvider] completedTasks(backend)=${backendCompleted.length}  '
          'completedFromAccepted=${completedFromAccepted.length}  '
          'total=${_myCompletedTasks.length}');

      // Filter locally-completed IDs from accepted (backend may lag behind).
      // Evict an ID once the backend itself stops returning it in acceptedTasks,
      // which confirms the backend has processed the completion. We check the
      // RAW list (before filtering) so the eviction is based on what the backend
      // actually returned, not our already-filtered view.
      if (_locallyCompletedTaskIds.isNotEmpty) {
        _locallyCompletedTaskIds.removeWhere(
            (id) => !rawAccepted.any((t) => t.id == id));
        _myAcceptedTasks = rawAccepted
            .where((t) =>
                !completedStatuses.contains(t.status) &&
                !_locallyCompletedTaskIds.contains(t.id))
            .toList();
      } else {
        // Always exclude completed-status tasks from the Accepted tab
        _myAcceptedTasks = rawAccepted
            .where((t) => !completedStatuses.contains(t.status))
            .toList();
      }
      // Auto-persist any phone numbers the backend included in list responses.
      for (final t in [..._myAcceptedTasks, ..._myPostedTasks]) {
        if (t.posterPhone != null && t.posterPhone!.trim().isNotEmpty) {
          _savePhone(t.id, t.posterPhone!);
        }
        if (t.posterName.isNotEmpty && t.posterName != 'Anonymous') {
          _saveName(t.id, t.posterName);
        }
      }
      // Keep _detailCache in sync with the latest status/isPaid from the
      // fresh list response. Without this, a cached entry from acceptTask()
      // (status: 'accepted') shadows every subsequent fetchMyTasks() update,
      // causing the in-progress screen to show stale data until app restart.
      for (final fresh in [..._myAcceptedTasks, ..._myCompletedTasks]) {
        final cached = _detailCache[fresh.id];
        if (cached != null &&
            (cached.status != fresh.status || cached.isPaid != fresh.isPaid)) {
          final merged = Map<String, dynamic>.from(cached.toJson());
          merged['status'] = fresh.status;
          merged['is_paid'] = fresh.isPaid;
          try {
            _detailCache[fresh.id] = Task.fromJson(merged);
          } catch (_) {}
        }
      }
    } catch (e) {
      _error = e.toString();
    }

    _loadingMy = false;
    _notify();
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
          // Normalize the /tasks/$id/details response: that endpoint returns
          // poster info under 'provider' but Task.fromJson expects 'posted_by'.
          // Map it so posterPhone, posterName etc. are extracted correctly.
          Map<String, dynamic> normalizedJson = taskJson;
          final providerObj = taskJson['provider'];
          if (providerObj is Map<String, dynamic> && !taskJson.containsKey('posted_by')) {
            normalizedJson = Map<String, dynamic>.from(taskJson);
            normalizedJson['posted_by'] = providerObj;
            // Also flatten poster_phone at top level for extra safety
            if (!normalizedJson.containsKey('poster_phone') &&
                providerObj['phone'] != null) {
              normalizedJson['poster_phone'] = providerObj['phone'];
            }
          }

          var task = Task.fromJson(normalizedJson);

          // If the API response omitted posterPhone or posterName, inject
          // them from our persisted sources (browse list snapshot saved at
          // accept time, or any remaining list cache entry that has it).
          final enriched = Map<String, dynamic>.from(normalizedJson);
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

          // If the detail endpoint omitted drop_location, inject from the
          // accepted task list (populated from /user/tasks with flat DB columns).
          if (task.dropLatitude == null && task.dropAddress == null) {
            Task? listTask;
            for (final t in _myAcceptedTasks) {
              if (t.id == id) { listTask = t; break; }
            }
            if (listTask != null) {
              if (listTask.dropLatitude != null) {
                enriched['drop_location_lat'] = listTask.dropLatitude;
                enriched['drop_location_lng'] = listTask.dropLongitude;
                needsReparse = true;
              }
              if (listTask.dropAddress != null) {
                enriched['drop_location_address'] = listTask.dropAddress;
                needsReparse = true;
              }
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

    // ── Fallback: inject saved phone/name into a task object ─────────────────
    Task _enrichWithSaved(Task t) {
      final phone = _loadPhone(id) ?? _findPhoneInAllLists(id);
      final name  = _loadName(id)  ?? _findNameInAllLists(id);
      if ((phone == null || (t.posterPhone?.trim().isNotEmpty ?? false)) &&
          (name  == null || (t.posterName.isNotEmpty && t.posterName != 'Anonymous'))) {
        return t;
      }
      final json = Map<String, dynamic>.from(t.toJson());
      if (phone != null && (t.posterPhone == null || t.posterPhone!.trim().isEmpty)) {
        json['poster_phone'] = phone;
      }
      if (name != null && (t.posterName.isEmpty || t.posterName == 'Anonymous')) {
        json['poster_name'] = name;
      }
      return Task.fromJson(json);
    }

    // Both direct API endpoints failed (404/405). Refresh /user/tasks so we
    // always get the latest status — the poster may have paid or verified
    // since the last fetch. Never return a stale cache without refreshing first.
    try {
      await fetchMyTasks();
    } catch (_) {}

    final freshCached = _findCached(id);
    if (freshCached != null) return _enrichWithSaved(freshCached);

    return null;
  }

  Future<bool> postTask(Map<String, dynamic> taskData) async {
    try {
      await ApiService.post('/tasks', body: taskData);
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
      return false;
    }
  }

  /// Update an existing task (poster only, before a helper accepts).
  Future<bool> updateTask(String taskId, Map<String, dynamic> data) async {
    try {
      _error = null;
      final response = await ApiService.put('/tasks/$taskId', body: data);
      // Refresh the detail cache with the updated task data.
      _cacheDetailFromResponse(response, taskId);
      // Invalidate cached detail so next load fetches fresh data.
      _detailCache.remove(taskId);
      await fetchMyTasks();
      _notify();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
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
      // inject it directly into the cached task object so getTaskDetail()
      // can return it immediately without another network round-trip.
      final phoneToInject = browsePhone ?? _loadPhone(taskId);
      if (phoneToInject != null) {
        _savePhone(taskId, phoneToInject);
        final cached = _detailCache[taskId];
        if (cached != null &&
            (cached.posterPhone == null || cached.posterPhone!.trim().isEmpty)) {
          try {
            final enriched = Map<String, dynamic>.from(cached.toJson());
            enriched['poster_phone'] = phoneToInject;
            _detailCache[taskId] = Task.fromJson(enriched);
          } catch (_) {}
        }
      }

      await fetchMyTasks();

      // After fetchMyTasks(), the accepted task may now have a posterPhone
      // in _myAcceptedTasks. Inject it into the detail cache if still missing.
      final cached2 = _detailCache[taskId];
      if (cached2 != null &&
          (cached2.posterPhone == null || cached2.posterPhone!.trim().isEmpty)) {
        final phone2 = _loadPhone(taskId) ?? _findPhoneInAllLists(taskId);
        if (phone2 != null) {
          try {
            final enriched = Map<String, dynamic>.from(cached2.toJson());
            enriched['poster_phone'] = phone2;
            _detailCache[taskId] = Task.fromJson(enriched);
          } catch (_) {}
        }
      }

      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
      // If the server says user already has an active task, refresh the list
      // so hasActiveAcceptedTask and activeAcceptedTask become correct and the
      // UI can show the active-task warning banner immediately.
      if (e.statusCode == 409) {
        try { await fetchMyTasks(); } catch (_) {}
      }
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
      _notify();
      return true;
    } catch (e) {
      _error = e.toString();
      _notify();
      return false;
    }
  }

  Future<bool> abandonTask(String taskId) async {
    try {
      await ApiService.post('/tasks/$taskId/abandon');
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      // If the task no longer exists on the server, treat it as already released:
      // remove from local list so hasActiveAcceptedTask becomes correct.
      if (e.statusCode == 404 || e.statusCode == 405) {
        _myAcceptedTasks.removeWhere((t) => t.id == taskId);
        _detailCache.remove(taskId);
        _notify();
        return true;
      }
      _error = e.message;
      _notify();
      return false;
    }
  }

  /// Helper submits proof for verification (Step 1 of completion flow).
  /// Uploads proof photo first (as base64 JSON), then marks task as completed.
  Future<bool> markCompleted(String taskId, {String? proofPath}) async {
    try {
      // Upload proof image to task_proofs table if provided
      if (proofPath != null && proofPath.isNotEmpty) {
        try {
          final bytes = await File(proofPath).readAsBytes();
          final b64 = base64Encode(bytes);
          final ext = proofPath.split('.').last.toLowerCase();
          final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
          await ApiService.post(
            '/task/$taskId/upload-proof',
            body: {'imageUrl': 'data:$mime;base64,$b64', 'type': 'photo'},
          );
        } catch (e) {
          // Non-fatal: log but continue with completion
          debugPrint('[TaskProvider] Proof upload failed: $e');
        }
      }
      await ApiService.post('/tasks/$taskId/verify');
      // Invalidate detail cache so next load gets fresh status.
      _detailCache.remove(taskId);
      await fetchMyTasks();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
      return false;
    } catch (e) {
      _error = 'Network error. Please check your connection and try again.';
      _notify();
      return false;
    }
  }

  /// Helper confirms completion after payment is released (Step 3 of flow).
  Future<bool> finalMarkComplete(String taskId) async {
    void _clearTask() {
      _locallyCompletedTaskIds.add(taskId);
      // Move the task from accepted → completed list immediately so the UI
      // reflects the change before the background fetchMyTasks() returns.
      // Stamp completedAt = now so the 48 h expiry countdown starts correctly.
      final now = DateTime.now();
      _saveCompletedAt(taskId, now); // persist so it survives restarts
      final idx = _myAcceptedTasks.indexWhere((t) => t.id == taskId);
      if (idx >= 0) {
        final task = _myAcceptedTasks.removeAt(idx);
        if (!_myCompletedTasks.any((t) => t.id == taskId)) {
          _myCompletedTasks.insert(0, task.copyWith(completedAt: now));
        }
      } else {
        _myAcceptedTasks.removeWhere((t) => t.id == taskId);
        // Fallback: if task was only in the detail cache, still add to completed
        final cached = _detailCache[taskId];
        if (cached != null && !_myCompletedTasks.any((t) => t.id == taskId)) {
          _myCompletedTasks.insert(0, cached.copyWith(completedAt: now));
        }
      }
      _detailCache.remove(taskId);
      _notify();
      fetchMyTasks(); // background sync — filter above keeps task excluded
    }

    try {
      await ApiService.post('/tasks/$taskId/mark-completed');
      _clearTask();
      return true;
    } on ApiException catch (e) {
      // 404 means the task no longer exists on the backend OR the backend
      // already advanced it to 'done'. Either way the helper is unblocked.
      if (e.statusCode == 404) {
        _clearTask();
        return true;
      }
      _error = e.message;
      _notify();
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
      _notify();
      return false;
    }
  }

  /// Fetch proof photos the helper uploaded for a task.
  /// Returns a list of image_url strings, newest first.
  Future<List<String>> fetchTaskProofs(String taskId) async {
    try {
      final data = await ApiService.get('/task/$taskId/proofs');
      final proofs = data['proofs'] as List? ?? [];
      return proofs
          .map((p) => (p as Map)['image_url']?.toString() ?? '')
          .where((url) => url.isNotEmpty)
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Poster pays the helper after task completion — calls /pay-helper (no OTP needed).
  Future<bool> payHelper(String taskId) async {
    try {
      await ApiService.post('/tasks/$taskId/pay-helper');
      // Refresh task list; ignore refresh errors — payment already succeeded.
      try { await fetchMyTasks(); } catch (_) {}
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
      return false;
    } catch (e) {
      _error = e.toString();
      _notify();
      return false;
    }
  }

  Future<bool> rateTask(String taskId, double rating, String? comment) async {
    try {
      await ApiService.post('/tasks/$taskId/rate', body: {
        'rating': rating,
        if (comment != null) 'review': comment,
      });
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
      return false;
    }
  }

  Future<bool> deleteTask(String taskId) async {
    try {
      await ApiService.delete('/tasks/$taskId');
      _myPostedTasks.removeWhere((t) => t.id == taskId);
      _notify();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _notify();
      return false;
    }
  }

  void clearError() {
    _error = null;
    _notify();
  }
}
