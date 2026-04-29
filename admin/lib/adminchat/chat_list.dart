import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'chatprovider.dart';

class ChatList extends StatefulWidget {
  @override
  State<ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<ChatList> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ChatProvider>(context, listen: false);
      if (provider.chatList.isEmpty) {
        provider.fetchChatList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final allUsers = chatProvider.chatList;
        final users = _searchQuery.isEmpty
            ? allUsers
            : chatProvider.searchUsers(_searchQuery);

        // Sort: unread first, then online first, then by last_message_time DESC
        final sortedUsers = List<Map<String, String>>.from(users)
          ..sort((a, b) {
            final aUnread = int.tryParse(a['unread_count'] ?? '0') ?? 0;
            final bUnread = int.tryParse(b['unread_count'] ?? '0') ?? 0;
            if (aUnread != bUnread) return bUnread.compareTo(aUnread);
            final aOnline = a['online'] == 'true';
            final bOnline = b['online'] == 'true';
            if (aOnline != bOnline) return aOnline ? -1 : 1;
            final aTime = DateTime.tryParse(a['last_message_time'] ?? '');
            final bTime = DateTime.tryParse(b['last_message_time'] ?? '');
            if (aTime != null && bTime != null) return bTime.compareTo(aTime);
            if (aTime != null) return -1;
            if (bTime != null) return 1;
            return 0;
          });

        return Container(
          color: Colors.grey[200],
          child: Column(
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search conversations',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              Expanded(
                child: sortedUsers.isEmpty
                    ? Center(
                        child: chatProvider.chatList.isEmpty
                            ? const CircularProgressIndicator()
                            : const Text('No conversations found'),
                      )
                    : ListView.builder(
                        itemCount: sortedUsers.length,
                        itemBuilder: (context, index) {
                          final chat = sortedUsers[index];
                          final unreadCount =
                              int.tryParse(chat['unread_count'] ?? '0') ?? 0;
                          final isOnline = chat['online'] == 'true';
                          final isPaid = chat['is_paid'] == 'true';
                          final profileUrl = chat['profile_picture'] ?? '';
                          final lastMsg = chat['chat_message'] ?? '';
                          final lastSeen = chat['last_seen_text'] ?? '';

                          return ListTile(
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.grey[300],
                                  backgroundImage: profileUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(profileUrl)
                                      : null,
                                  child: profileUrl.isEmpty
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                if (isOnline)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chat['namee'] ?? '',
                                    style: TextStyle(
                                      fontWeight: unreadCount > 0
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isPaid)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.amber[700],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'PAID',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              lastMsg.isNotEmpty ? lastMsg : lastSeen,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: unreadCount > 0
                                    ? Colors.black87
                                    : Colors.grey[600],
                              ),
                            ),
                            trailing: unreadCount > 0
                                ? Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF25D366),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () {
                              final id = int.tryParse(chat['id'] ?? '');
                              if (id != null) {
                                chatProvider.updateidd(id);
                                chatProvider.updateName(chat['namee'] ?? '');
                                chatProvider.updateonline(isOnline);
                                chatProvider.updatePaidStatus(isPaid);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
