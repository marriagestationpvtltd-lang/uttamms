import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'call_history_model.dart';
import 'call_history_service.dart';
import '../Chat/ChatdetailsScreen.dart';
import 'OutgoingCall.dart';
import 'videocall.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  String _currentUserId = '';
  String _currentUserName = '';
  String _currentUserImage = '';
  Future<List<CallHistory>>? _callsFuture;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      setState(() {
        _currentUserId = userData['id']?.toString() ?? '';
        _currentUserName = userData['name']?.toString() ?? '';
        _currentUserImage = userData['image']?.toString() ?? '';
        if (_currentUserId.isNotEmpty) {
          _callsFuture = CallHistoryService.getCallHistoryFuture(_currentUserId);
        }
      });
    }
  }

  void _refresh() {
    if (_currentUserId.isNotEmpty) {
      setState(() {
        _callsFuture = CallHistoryService.getCallHistoryFuture(_currentUserId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Call History',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFFF90E18),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 1,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<CallHistory>>(
        future: _callsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _currentUserId.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final calls = snapshot.data ?? [];

          if (calls.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.call_outlined,
                      size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No call history',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your call history will appear here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: calls.length,
            itemBuilder: (context, index) {
              final call = calls[index];
              return _buildCallHistoryItem(call);
            },
          );
        },
      ),
    );
  }

  Widget _buildCallHistoryItem(CallHistory call) {
    final isIncoming = call.isIncoming(_currentUserId);
    final otherPersonName = call.getOtherPersonName(_currentUserId);
    final otherPersonImage = call.getOtherPersonImage(_currentUserId);
    final otherPersonId = call.getOtherPersonId(_currentUserId);

    // Status icon based on call type and direction
    IconData statusIcon;
    Color statusColor;

    if (call.status == CallStatus.missed && isIncoming) {
      statusIcon = Icons.call_missed;
      statusColor = Colors.red;
    } else if (call.status == CallStatus.declined) {
      statusIcon = Icons.call_end;
      statusColor = Colors.red;
    } else if (call.status == CallStatus.cancelled) {
      statusIcon = Icons.call_missed_outgoing;
      statusColor = Colors.orange;
    } else if (isIncoming) {
      statusIcon = Icons.call_received;
      statusColor = Colors.green;
    } else {
      statusIcon = Icons.call_made;
      statusColor = Colors.green;
    }

    return InkWell(
      onTap: () => _openChat(otherPersonId, otherPersonName, otherPersonImage),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Profile Image
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.grey[300],
              backgroundImage: otherPersonImage.isNotEmpty
                  ? NetworkImage(otherPersonImage)
                  : null,
              child: otherPersonImage.isEmpty
                  ? Text(
                      otherPersonName.isNotEmpty
                          ? otherPersonName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Call Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    otherPersonName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: call.status == CallStatus.missed && isIncoming
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: call.status == CallStatus.missed && isIncoming
                          ? Colors.red
                          : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Status and Date
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _formatCallTime(call.startTime),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      if (call.status == CallStatus.completed)
                        Text(
                          call.getFormattedDuration(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Call Type Icon and Action Button
            IconButton(
              icon: Icon(
                call.callType == CallType.video
                    ? Icons.videocam
                    : Icons.call,
                color: const Color(0xFFF90E18),
                size: 24,
              ),
              onPressed: () => _makeCall(
                otherPersonId,
                otherPersonName,
                otherPersonImage,
                call.callType,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCallTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      // Today - show time
      return 'Today ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday ${DateFormat('HH:mm').format(dateTime)}';
    } else if (difference.inDays < 7) {
      // Within a week - show day name
      final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return dayNames[dateTime.weekday % 7];
    } else {
      // Older - show date
      return DateFormat('yyyy/MM/dd').format(dateTime);
    }
  }

  void _openChat(String userId, String userName, String userImage) {
    // Generate chat room ID (same logic as in chat system)
    final chatRoomId = _currentUserId.compareTo(userId) < 0
        ? '${_currentUserId}_$userId'
        : '${userId}_$_currentUserId';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          chatRoomId: chatRoomId,
          receiverId: userId,
          receiverName: userName,
          receiverImage: userImage,
          currentUserId: _currentUserId,
          currentUserName: _currentUserName,
          currentUserImage: _currentUserImage,
        ),
      ),
    );
  }

  void _makeCall(
    String userId,
    String userName,
    String userImage,
    CallType callType,
  ) {
    if (callType == CallType.video) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoCallScreen(
            currentUserId: _currentUserId,
            currentUserName: _currentUserName,
            currentUserImage: _currentUserImage,
            otherUserId: userId,
            otherUserName: userName,
            otherUserImage: userImage,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            currentUserId: _currentUserId,
            currentUserName: _currentUserName,
            currentUserImage: _currentUserImage,
            otherUserId: userId,
            otherUserName: userName,
            otherUserImage: userImage,
          ),
        ),
      );
    }
  }
}
