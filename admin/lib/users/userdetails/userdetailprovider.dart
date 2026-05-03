import 'package:adminmrz/users/userdetails/userdetailservice.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'detailmodel.dart';

class UserDetailsProvider with ChangeNotifier {
  final UserDetailsService _userDetailsService = UserDetailsService();

  UserDetailsData? _userDetails;
  bool _isLoading = false;
  String _error = '';
  int? _userId;
  int? _myId;
  bool _isUpdating = false;
  String _updateError = '';
  bool _isUploadingMedia = false;

  // Activity stats
  ActivityStats? _activityStats;
  bool _isLoadingActivity = false;

  // Photo action
  bool _isPhotoActioning = false;

  // Notification
  bool _isSendingNotification = false;
  List<UserGalleryPhoto> _galleryPhotos = [];
  final Set<int> _galleryActioning = {};
  PartnerMatch? _partnerMatch;
  final Map<String, List<ProfileFieldOption>> _fieldOptions = {};
  final Set<String> _fieldOptionsLoading = {};

  UserDetailsData? get userDetails => _userDetails;
  bool get isLoading => _isLoading;
  String get error => _error;
  int? get userId => _userId;
  bool get isUpdating => _isUpdating;
  String get updateError => _updateError;
  bool get isUploadingMedia => _isUploadingMedia;
  ActivityStats? get activityStats => _activityStats;
  bool get isLoadingActivity => _isLoadingActivity;
  bool get isPhotoActioning => _isPhotoActioning;
  bool get isSendingNotification => _isSendingNotification;
  List<UserGalleryPhoto> get galleryPhotos => _galleryPhotos;
  PartnerMatch? get partnerMatch => _partnerMatch;
  bool isGalleryActioning(int galleryId) =>
      _galleryActioning.contains(galleryId);
  List<ProfileFieldOption> fieldOptionsFor(String field) =>
      _fieldOptions[field] ?? const [];
  bool isFieldOptionsLoading(String field) =>
      _fieldOptionsLoading.contains(field);

  Future<void> fetchUserDetails(int userId, int myId) async {
    _isLoading = true;
    _error = '';
    _userId = userId;
    _myId = myId;
    notifyListeners();

    try {
      final response = await _userDetailsService.getUserDetails(userId, myId);
      if (response.status == 'success') {
        _userDetails = response.data;
        _galleryPhotos = response.gallery;
        _partnerMatch = response.partnerMatch;
      } else {
        _error = 'Failed to load user details';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Also fetch activity stats in parallel
    fetchActivityStats(userId);

    final p = _userDetails?.personalDetail;
    if (p != null) {
      ensureFieldOptions(field: 'religionId');
      ensureFieldOptions(field: 'communityId', religionId: p.religionId);
      ensureFieldOptions(
        field: 'subCommunityId',
        religionId: p.religionId,
        communityId: p.communityId,
      );

      for (final field in const [
        'annualincome',
        'educationtype',
        'degree',
        'faculty',
        'educationmedium',
        'occupationtype',
        'workingwith',
      ]) {
        ensureFieldOptions(field: field);
      }
    }
  }

  Future<void> ensureFieldOptions({
    required String field,
    int? religionId,
    int? communityId,
    bool force = false,
  }) async {
    if (!force &&
        _fieldOptions.containsKey(field) &&
        _fieldOptions[field]!.isNotEmpty) {
      return;
    }
    if (_fieldOptionsLoading.contains(field)) return;

    _fieldOptionsLoading.add(field);
    notifyListeners();
    try {
      final options = await _userDetailsService.getProfileFieldOptions(
        field: field,
        religionId: religionId,
        communityId: communityId,
      );
      _fieldOptions[field] = options;
    } finally {
      _fieldOptionsLoading.remove(field);
      notifyListeners();
    }
  }

  /// Fetch user activity stats (requests, chats, views, matches).
  Future<void> fetchActivityStats(int userId) async {
    _isLoadingActivity = true;
    notifyListeners();
    try {
      _activityStats = await _userDetailsService.getUserActivity(userId);
    } catch (_) {
      _activityStats = ActivityStats.empty();
    } finally {
      _isLoadingActivity = false;
      notifyListeners();
    }
  }

  /// Update a single profile field and refresh the local model on success.
  Future<bool> updateField({
    required String section,
    required String field,
    required String value,
  }) async {
    if (_userId == null) return false;
    _isUpdating = true;
    _updateError = '';
    notifyListeners();

    try {
      final success = await _userDetailsService.updateUserDetail(
        userId: _userId!,
        section: section,
        field: field,
        value: value,
      );
      if (!success) {
        _updateError = 'Update failed. Please try again.';
      }
      _isUpdating = false;
      notifyListeners();
      return success;
    } catch (e) {
      _updateError = e.toString();
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Update multiple fields in the same section atomically on the backend.
  Future<bool> updateSection({
    required String section,
    required Map<String, String> fields,
  }) async {
    if (_userId == null) return false;
    if (fields.isEmpty) return true;

    _isUpdating = true;
    _updateError = '';
    notifyListeners();

    try {
      final success = await _userDetailsService.updateUserDetailSection(
        userId: _userId!,
        section: section,
        fields: fields,
      );
      if (!success) {
        _updateError = 'Section update failed. Please try again.';
      }
      _isUpdating = false;
      notifyListeners();
      return success;
    } catch (e) {
      _updateError = e.toString();
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _refreshLocalDetails() async {
    if (_userId == null) return;
    final response = await _userDetailsService.getUserDetails(
      _userId!,
      _myId ?? _userId!,
    );
    if (response.status == 'success') {
      _userDetails = response.data;
      _galleryPhotos = response.gallery;
    }
  }

  /// Approve or reject the user's pending profile photo.
  Future<bool> handleProfilePhotoRequest({
    required String action,
    String? reason,
  }) async {
    if (_userId == null) return false;
    _isPhotoActioning = true;
    notifyListeners();
    try {
      final ok = await _userDetailsService.handleProfilePhotoRequest(
        userId: _userId!,
        action: action,
        reason: reason,
      );
      if (ok && _userDetails != null) {
        await _refreshLocalDetails();
      }
      _isPhotoActioning = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _isPhotoActioning = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> handleGalleryPhotoRequest({
    required int galleryId,
    required String action,
    String? reason,
  }) async {
    if (_userId == null || galleryId <= 0) return false;

    _galleryActioning.add(galleryId);
    notifyListeners();
    try {
      final ok = await _userDetailsService.handleGalleryPhotoRequest(
        userId: _userId!,
        galleryId: galleryId,
        action: action,
        reason: reason,
      );

      if (ok) {
        await _refreshLocalDetails();
      }

      _galleryActioning.remove(galleryId);
      notifyListeners();
      return ok;
    } catch (_) {
      _galleryActioning.remove(galleryId);
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadProfilePhoto(PlatformFile file) async {
    if (_userId == null) return false;
    _isUploadingMedia = true;
    notifyListeners();
    try {
      final ok = await _userDetailsService.uploadProfilePhoto(
        userId: _userId!,
        file: file,
      );
      if (ok) {
        await _refreshLocalDetails();
      }
      _isUploadingMedia = false;
      notifyListeners();
      return ok;
    } catch (_) {
      _isUploadingMedia = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadGalleryPhotos(List<PlatformFile> files) async {
    if (_userId == null || files.isEmpty) return false;
    _isUploadingMedia = true;
    notifyListeners();
    try {
      final ok = await _userDetailsService.uploadGalleryPhotos(
        userId: _userId!,
        files: files,
      );
      if (ok) {
        await _refreshLocalDetails();
      }
      _isUploadingMedia = false;
      notifyListeners();
      return ok;
    } catch (_) {
      _isUploadingMedia = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> replaceGalleryPhoto({
    required int galleryId,
    required PlatformFile file,
  }) async {
    if (_userId == null || galleryId <= 0) return false;

    _galleryActioning.add(galleryId);
    notifyListeners();
    try {
      final ok = await _userDetailsService.replaceGalleryPhoto(
        userId: _userId!,
        galleryId: galleryId,
        file: file,
      );

      if (ok) {
        await _refreshLocalDetails();
      }

      _galleryActioning.remove(galleryId);
      notifyListeners();
      return ok;
    } catch (_) {
      _galleryActioning.remove(galleryId);
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteGalleryPhoto({required int galleryId}) async {
    if (_userId == null || galleryId <= 0) return false;

    _galleryActioning.add(galleryId);
    notifyListeners();
    try {
      final ok = await _userDetailsService.deleteGalleryPhoto(
        userId: _userId!,
        galleryId: galleryId,
      );

      if (ok) {
        await _refreshLocalDetails();
      }

      _galleryActioning.remove(galleryId);
      notifyListeners();
      return ok;
    } catch (_) {
      _galleryActioning.remove(galleryId);
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadDocument({
    required String documentType,
    String? documentIdNumber,
    required PlatformFile file,
  }) async {
    if (_userId == null) return false;
    _isUploadingMedia = true;
    notifyListeners();
    try {
      final ok = await _userDetailsService.uploadDocument(
        userId: _userId!,
        documentType: documentType,
        documentIdNumber: documentIdNumber,
        file: file,
      );
      if (ok) {
        await _refreshLocalDetails();
      }
      _isUploadingMedia = false;
      notifyListeners();
      return ok;
    } catch (_) {
      _isUploadingMedia = false;
      notifyListeners();
      return false;
    }
  }

  /// Send an admin notification directly to the user.
  Future<bool> sendAdminNotification({
    required String title,
    required String message,
  }) async {
    if (_userId == null) return false;
    _isSendingNotification = true;
    notifyListeners();
    try {
      final ok = await _userDetailsService.sendAdminNotification(
        userId: _userId!,
        title: title,
        message: message,
      );
      _isSendingNotification = false;
      notifyListeners();
      return ok;
    } catch (e) {
      _isSendingNotification = false;
      notifyListeners();
      return false;
    }
  }

  void clearData() {
    _userDetails = null;
    _error = '';
    _userId = null;
    _myId = null;
    _updateError = '';
    _isUploadingMedia = false;
    _activityStats = null;
    _galleryPhotos = [];
    _galleryActioning.clear();
    _fieldOptions.clear();
    _fieldOptionsLoading.clear();
    _countries = [];
    _states = [];
    _cities = [];
    notifyListeners();
  }

  // ── Location ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  List<Map<String, dynamic>> _cities = [];
  bool _loadingCountries = false;
  bool _loadingStates = false;
  bool _loadingCities = false;

  List<Map<String, dynamic>> get countries => _countries;
  List<Map<String, dynamic>> get states => _states;
  List<Map<String, dynamic>> get cities => _cities;
  bool get loadingCountries => _loadingCountries;
  bool get loadingStates => _loadingStates;
  bool get loadingCities => _loadingCities;

  Future<void> loadCountries() async {
    if (_countries.isNotEmpty) return;
    _loadingCountries = true;
    notifyListeners();
    _countries = await _userDetailsService.fetchCountries();
    _loadingCountries = false;
    notifyListeners();
  }

  Future<void> loadStatesFor(int countryId) async {
    _states = [];
    _cities = [];
    _loadingStates = true;
    notifyListeners();
    _states = await _userDetailsService.fetchStates(countryId);
    _loadingStates = false;
    notifyListeners();
  }

  Future<void> loadCitiesFor(int stateId) async {
    _cities = [];
    _loadingCities = true;
    notifyListeners();
    _cities = await _userDetailsService.fetchCities(stateId);
    _loadingCities = false;
    notifyListeners();
  }
}
