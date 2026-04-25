import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chatprovider.dart';

class ChatList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final chats = chatProvider.chatList;

        return Container(
          color: Colors.grey[200],
          child: Column(
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: "Search or start a new chat",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: chats.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final bool isPaid = chat['is_paid'] == 'true';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (chat['profile_picture'] ?? '').isNotEmpty
                                  ? NetworkImage(chat['profile_picture']!)
                                  : null,
                              child: (chat['profile_picture'] ?? '').isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(
                              chat['namee'] ?? '',
                              style: TextStyle(
                                color: isPaid ? Colors.blue : null,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(chat['chat_message'] ?? ''),
                            trailing: Text(chat['last_seen_text'] ?? ''),
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
