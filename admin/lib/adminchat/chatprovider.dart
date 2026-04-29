import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constant.dart';
import 'package:adminmrz/config/app_endpoints.dart';

class ChatProvider extends ChangeNotifier {
  List<Map<String, String>> _chatList = [];
  List<Map<String, String>> _userList = [];

  int? id; // Store index 0 ID
  String? namee; // Store index 0 Name
  bool online = true;
  int? userid;
  String? memberid;
  String? first_name;
  String? last_name;
  String? matching_percentage;
  bool ispaid = true;
  bool isonline = true;

  // Add profile picture field
  String? profilePicture;

  // New match-related fields
  int? _matchesCount;
  List<Map<String, dynamic>> _matchedProfiles = [];
  bool _isLoadingMatches = false;
  String? _matchError;

  // Getters for match data
  int? get matchesCount => _matchesCount;
  List<Map<String, dynamic>> get matchedProfiles => _matchedProfiles;
  bool get isLoadingMatches => _isLoadingMatches;
  String? get matchError => _matchError;

  List<Map<String, String>> get chatList => _chatList;

  // Fetch chat list from API
  Future<void> fetchChatList() async {
    final url = Uri.parse('${kAdminApiBaseUrl}/get.php');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['status'] == true && responseData['data'] is List) {
          List<Map<String, String>> tempList = (responseData['data'] as List)
              .map((item) =>
          {
            'id': item['id'].toString(),
            'namee': item['name'].toString(),
            'online': item['is_online'].toString(),
            'matches': item['matches']?.toString() ?? '0',
            'is_paid': item['is_paid']?.toString() ?? 'false',
            'profile_picture': item['profile_picture']?.toString() ?? '',
            'last_seen_text': item['last_seen_text']?.toString() ?? '',
            'chat_message': item['chat_message']?.toString() ?? '',
            'unread_count': item['unread_count']?.toString() ?? '0',
            'last_message_time': item['last_message_time']?.toString() ?? '',
          })
              .toList();

          if (tempList.isNotEmpty) {
            id = int.parse(tempList[0]['id'].toString());
            namee = tempList[0]['namee'];
            online = tempList[0]['online'] == 'true';
            profilePicture = tempList[0]['profile_picture']; // Store profile picture

            // Set matches count for first user
            _matchesCount = int.tryParse(tempList[0]['matches'] ?? '0');

            myid ??= id;
          }

          _chatList = tempList;
          notifyListeners();
        }
      }
    } catch (error) {
      debugPrint('Error fetching chat list: $error');
    }
  }

  // Fetch matches for a specific user
  Future<void> fetchUserMatches(int userId) async {
    _isLoadingMatches = true;
    _matchError = null;
    notifyListeners();

    try {
      final url = Uri.parse('${kAdminApiBaseUrl}/matched.php');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        if (responseData['status'] == 'success' && responseData['data'] is List) {
          _matchedProfiles = List<Map<String, dynamic>>.from(responseData['data']);

          // Update matches count
          if (_matchedProfiles.isNotEmpty) {
            _matchesCount = _matchedProfiles.length;
          }
        } else {
          _matchError = responseData['message'] ?? 'Failed to load matches';
          _matchedProfiles = [];
        }
      } else {
        _matchError = 'Server error: ${response.statusCode}';
        _matchedProfiles = [];
      }
    } catch (error) {
      _matchError = 'Network error: $error';
      _matchedProfiles = [];
      debugPrint('Error fetching matches: $error');
    } finally {
      _isLoadingMatches = false;
      notifyListeners();
    }
  }

  // Get user by ID
  Map<String, String>? getUserById(int userId) {
    try {
      return _chatList.firstWhere(
            (user) => user['id'] == userId.toString(),
      );
    } catch (e) {
      return null;
    }
  }

  // Get matches count for a specific user
  int getMatchesCountForUser(int userId) {
    final user = getUserById(userId);
    if (user != null && user.containsKey('matches')) {
      return int.tryParse(user['matches'] ?? '0') ?? 0;
    }
    return 0;
  }

  // Check if user is paid
  bool isUserPaid(int userId) {
    final user = getUserById(userId);
    if (user != null && user.containsKey('is_paid')) {
      return user['is_paid'] == 'true';
    }
    return false;
  }

  // Get users with matches
  List<Map<String, String>> getUsersWithMatches() {
    return _chatList.where((user) {
      int matches = int.tryParse(user['matches'] ?? '0') ?? 0;
      return matches > 0;
    }).toList();
  }

  // Get paid users
  List<Map<String, String>> getPaidUsers() {
    return _chatList.where((user) {
      return user['is_paid'] == 'true';
    }).toList();
  }

  // Get online users
  List<Map<String, String>> getOnlineUsers() {
    return _chatList.where((user) {
      return user['online'] == 'true';
    }).toList();
  }

  // Search users
  List<Map<String, String>> searchUsers(String query) {
    if (query.isEmpty) return _chatList;

    return _chatList.where((user) {
      return user['namee']?.toLowerCase().contains(query.toLowerCase()) ?? false;
    }).toList();
  }

  // Filter users with multiple criteria
  List<Map<String, String>> filterUsers({
    String? searchQuery,
    bool? paidOnly,
    bool? onlineOnly,
    bool? withMatchesOnly,
    String? sortBy, // 'name', 'matches', 'last_seen'
  }) {
    List<Map<String, String>> filtered = List.from(_chatList);

    // Apply search filter
    if (searchQuery != null && searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        return user['namee']?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false;
      }).toList();
    }

    // Apply paid filter
    if (paidOnly == true) {
      filtered = filtered.where((user) => user['is_paid'] == 'true').toList();
    }

    // Apply online filter
    if (onlineOnly == true) {
      filtered = filtered.where((user) => user['online'] == 'true').toList();
    }

    // Apply matches filter
    if (withMatchesOnly == true) {
      filtered = filtered.where((user) {
        int matches = int.tryParse(user['matches'] ?? '0') ?? 0;
        return matches > 0;
      }).toList();
    }

    // Apply sorting
    if (sortBy != null) {
      switch (sortBy) {
        case 'name':
          filtered.sort((a, b) => (a['namee'] ?? '').compareTo(b['namee'] ?? ''));
          break;
        case 'matches':
          filtered.sort((a, b) {
            int aMatches = int.tryParse(a['matches'] ?? '0') ?? 0;
            int bMatches = int.tryParse(b['matches'] ?? '0') ?? 0;
            return bMatches.compareTo(aMatches); // Descending
          });
          break;
        case 'last_seen':
          filtered.sort((a, b) {
            bool aOnline = a['online'] == 'true';
            bool bOnline = b['online'] == 'true';

            // Online users first
            if (aOnline && !bOnline) return -1;
            if (!aOnline && bOnline) return 1;

            // Then sort by last seen (simplified - you might want better logic)
            return (a['last_seen_text'] ?? '').compareTo(b['last_seen_text'] ?? '');
          });
          break;
      }
    }

    return filtered;
  }

  // Clear matches data
  void clearMatches() {
    _matchedProfiles = [];
    _matchesCount = null;
    _matchError = null;
    notifyListeners();
  }

  void setId(int newId) {
    myid = newId;
    notifyListeners();
  }

  // Method to update namee from another page
  void updateName(String newName) {
    namee = newName;
    notifyListeners();
  }

  void updateuserid(int newName) {
    userid = newName;
    notifyListeners();
  }

  void updateidd(int newId) {
    id = newId;

    // Update profile picture when changing selected user
    final user = getUserById(newId);
    if (user != null) {
      profilePicture = user['profile_picture'];
      _matchesCount = int.tryParse(user['matches'] ?? '0');
      ispaid = user['is_paid'] == 'true';
      online = user['online'] == 'true';
    }

    notifyListeners();
  }

  void updateonline(bool newName) {
    online = newName;
    notifyListeners();
  }

  // Update a single user's online status in chatList from socket presence events.
  void updateUserOnlineStatus(String userId, bool isOnline, String lastSeenText) {
    final idx = _chatList.indexWhere((u) => u['id'] == userId);
    if (idx == -1) {
      debugPrint('updateUserOnlineStatus: user $userId not found in chatList');
      return;
    }
    _chatList[idx] = {
      ..._chatList[idx],
      'online': isOnline.toString(),
      'last_seen_text': isOnline ? 'Online' : lastSeenText,
    };
    // Keep provider's own online field in sync if this is the selected user
    if (id?.toString() == userId) {
      online = isOnline;
    }
    notifyListeners();
  }

  // Update paid status
  void updatePaidStatus(bool newStatus) {
    ispaid = newStatus;
    notifyListeners();
  }

  // Update matches count
  void updateMatchesCount(int count) {
    _matchesCount = count;
    notifyListeners();
  }

  // Add method to update profile picture
  void updateProfilePicture(String picture) {
    profilePicture = picture;
    notifyListeners();
  }
}
