import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ms2026/config/app_endpoints.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBlockedUsers();
  }

  Future<void> _fetchBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final myId = userData["id"].toString();

    try {
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/get_blocked_users.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'my_id': myId}),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          _blockedUsers = List<Map<String, dynamic>>.from(data['users'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockUser(int userId, String userName) async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString == null) return;

    final userData = jsonDecode(userDataString);
    final myId = userData["id"].toString();

    try {
      final response = await http.post(
        Uri.parse('${kApiBaseUrl}/Api2/unblock_user.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'my_id': myId,
          'user_id': userId.toString(),
        }),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        setState(() {
          _blockedUsers.removeWhere((user) => user['id'] == userId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName unblocked'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No blocked users',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Users you block will appear here',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _blockedUsers.length,
        itemBuilder: (context, index) {
          final user = _blockedUsers[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: user['photo'] != null && user['photo'].isNotEmpty
                  ? NetworkImage(user['photo'])
                  : null,
              child: user['photo'] == null || user['photo'].isEmpty
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            title: Text(
              '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim(),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Blocked on ${user['blocked_date'] ?? 'unknown date'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: TextButton(
              onPressed: () => _unblockUser(
                user['id'],
                user['first_name'] ?? 'this user',
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('UNBLOCK'),
            ),
          );
        },
      ),
    );
  }
}