/// Example Provider - Template for State Management
///
/// Shows proper state management patterns with Provider,
/// loading states, error handling, and lifecycle management.

import 'package:flutter/foundation.dart';
import '../models/example_model.dart';
import '../services/example_service.dart';

class ExampleProvider extends ChangeNotifier {
  final ExampleService _service = ExampleService();

  // ==================== State Variables ====================

  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  List<ExampleModel>? _items;
  ExampleModel? _selectedItem;

  // ==================== Getters ====================

  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;
  List<ExampleModel> get items => _items ?? [];
  bool get hasItems => _items != null && _items!.isNotEmpty;
  ExampleModel? get selectedItem => _selectedItem;

  // ==================== Load Items ====================

  Future<void> loadItems(String userId) async {
    if (userId.isEmpty) {
      _setError('User ID is required');
      return;
    }

    try {
      _setLoading(true);
      _clearError();

      final response = await _service.fetchItems(userId: userId);

      if (response.isSuccess && response.data != null) {
        _items = response.data;
        notifyListeners();
      } else {
        _setError(response.error ?? 'Failed to load items');
      }
    } catch (e) {
      _setError('Error loading items: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // ==================== Refresh Items ====================

  Future<void> refreshItems(String userId) async {
    if (userId.isEmpty) return;

    try {
      _isRefreshing = true;
      _clearError();
      notifyListeners();

      final response = await _service.fetchItems(userId: userId);

      if (response.isSuccess && response.data != null) {
        _items = response.data;
      } else {
        _setError(response.error ?? 'Failed to refresh items');
      }
    } catch (e) {
      _setError('Error refreshing items: ${e.toString()}');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  // ==================== Load Single Item ====================

  Future<void> loadItem(String itemId) async {
    if (itemId.isEmpty) return;

    try {
      _setLoading(true);
      _clearError();

      final response = await _service.fetchItem(itemId: itemId);

      if (response.isSuccess && response.data != null) {
        _selectedItem = response.data;
        notifyListeners();
      } else {
        _setError(response.error ?? 'Failed to load item');
      }
    } catch (e) {
      _setError('Error loading item: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // ==================== Create Item ====================

  Future<bool> createItem({
    required String userId,
    required String title,
    String? description,
  }) async {
    try {
      _clearError();

      final response = await _service.createItem(
        userId: userId,
        title: title,
        description: description,
      );

      if (response.isSuccess && response.data != null) {
        // Add new item to list
        if (_items != null) {
          _items!.insert(0, response.data!);
          notifyListeners();
        }
        return true;
      } else {
        _setError(response.error ?? 'Failed to create item');
        return false;
      }
    } catch (e) {
      _setError('Error creating item: ${e.toString()}');
      return false;
    }
  }

  // ==================== Update Item ====================

  Future<bool> updateItem({
    required String itemId,
    String? title,
    String? description,
    bool? isActive,
  }) async {
    try {
      _clearError();

      final response = await _service.updateItem(
        itemId: itemId,
        title: title,
        description: description,
        isActive: isActive,
      );

      if (response.isSuccess && response.data != null) {
        // Update item in list
        if (_items != null) {
          final index = _items!.indexWhere((item) => item.id == itemId);
          if (index != -1) {
            _items![index] = response.data!;
            notifyListeners();
          }
        }
        // Update selected item if it matches
        if (_selectedItem?.id == itemId) {
          _selectedItem = response.data;
          notifyListeners();
        }
        return true;
      } else {
        _setError(response.error ?? 'Failed to update item');
        return false;
      }
    } catch (e) {
      _setError('Error updating item: ${e.toString()}');
      return false;
    }
  }

  // ==================== Delete Item ====================

  Future<bool> deleteItem(String itemId) async {
    try {
      _clearError();

      final response = await _service.deleteItem(itemId: itemId);

      if (response.isSuccess) {
        // Remove item from list
        if (_items != null) {
          _items!.removeWhere((item) => item.id == itemId);
          notifyListeners();
        }
        // Clear selected item if it matches
        if (_selectedItem?.id == itemId) {
          _selectedItem = null;
          notifyListeners();
        }
        return true;
      } else {
        _setError(response.error ?? 'Failed to delete item');
        return false;
      }
    } catch (e) {
      _setError('Error deleting item: ${e.toString()}');
      return false;
    }
  }

  // ==================== Helper Methods ====================

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  void clearSelectedItem() {
    _selectedItem = null;
    notifyListeners();
  }

  void clearAll() {
    _items = null;
    _selectedItem = null;
    _error = null;
    _isLoading = false;
    _isRefreshing = false;
    notifyListeners();
  }

  // ==================== Lifecycle ====================

  @override
  void dispose() {
    // Clean up resources
    _items?.clear();
    _items = null;
    _selectedItem = null;
    super.dispose();
  }
}
