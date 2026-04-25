import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../service/socket_service.dart';
import 'OutgoingCall.dart';
import 'videocall.dart';

/// Screen to display online users for initiating calls
class OnlineUsersListScreen extends StatefulWidget {
  const OnlineUsersListScreen({super.key});

  @override
  State<OnlineUsersListScreen> createState() => _OnlineUsersListScreenState();
}

class _OnlineUsersListScreenState extends State<OnlineUsersListScreen> {
  List<Map<String, dynamic>> _onlineUsers = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserImage;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndFetchOnlineUsers();
  }

  Future<void> _loadCurrentUserAndFetchOnlineUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        setState(() {
          _errorMessage = 'User not logged in';
          _isLoading = false;
        });
        return;
      }

      final userData = jsonDecode(userDataString);
      _currentUserId = userData["id"]?.toString() ?? '';
      _currentUserName = userData["name"]?.toString() ?? '';
      _currentUserImage = userData["image"]?.toString() ?? '';

      if (_currentUserId == null || _currentUserId!.isEmpty) {
        setState(() {
          _errorMessage = 'Invalid user data';
          _isLoading = false;
        });
        return;
      }

      await _fetchOnlineUsers();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading user data: $e';
        _isLoading = false;
      });
      debugPrint('Error loading current user: $e');
    }
  }

  Future<void> _fetchOnlineUsers() async {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final socketService = SocketService();
      final users = await socketService.getOnlineUsers(_currentUserId!);

      if (mounted) {
        setState(() {
          _onlineUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load online users';
          _isLoading = false;
        });
      }
      debugPrint('Error fetching online users: $e');
    }
  }

  void _initiateAudioCall(Map<String, dynamic> user) {
    if (_currentUserId == null || _currentUserName == null || _currentUserImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start call. Please try again.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CallScreen(
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName!,
          currentUserImage: _currentUserImage!,
          otherUserId: user['userId']?.toString() ?? '',
          otherUserName: user['userName']?.toString() ?? 'User',
          otherUserImage: user['userImage']?.toString() ?? '',
          isOutgoingCall: true,
        ),
      ),
    );
  }

  void _initiateVideoCall(Map<String, dynamic> user) {
    if (_currentUserId == null || _currentUserName == null || _currentUserImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start call. Please try again.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoCallScreen(
          currentUserId: _currentUserId!,
          currentUserName: _currentUserName!,
          currentUserImage: _currentUserImage!,
          otherUserId: user['userId']?.toString() ?? '',
          otherUserName: user['userName']?.toString() ?? 'User',
          otherUserImage: user['userImage']?.toString() ?? '',
          isOutgoingCall: true,
        ),
      ),
    );
  }

  void _showCallOptions(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Audio Call'),
              onTap: () {
                Navigator.pop(context);
                _initiateAudioCall(user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.blue),
              title: const Text('Video Call'),
              onTap: () {
                Navigator.pop(context);
                _initiateVideoCall(user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: const Text('Cancel'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchOnlineUsers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading online users...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCurrentUserAndFetchOnlineUsers,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_onlineUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No users are online',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Pull down to refresh',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchOnlineUsers,
      child: ListView.builder(
        itemCount: _onlineUsers.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final user = _onlineUsers[index];
          return _buildUserTile(user);
        },
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userName = user['userName']?.toString() ?? 'Unknown User';
    final userImage = user['userImage']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      child: ListTile(
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: userImage.isNotEmpty
                  ? NetworkImage(userImage) as ImageProvider
                  : null,
              backgroundColor: Colors.blue.shade100,
              child: userImage.isEmpty
                  ? Icon(Icons.person, size: 24, color: Colors.blue.shade700)
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          userName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Online',
          style: TextStyle(color: Colors.green, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              onPressed: () => _initiateAudioCall(user),
              tooltip: 'Audio Call',
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: Colors.blue),
              onPressed: () => _initiateVideoCall(user),
              tooltip: 'Video Call',
            ),
          ],
        ),
        onTap: () => _showCallOptions(user),
      ),
    );
  }
}
