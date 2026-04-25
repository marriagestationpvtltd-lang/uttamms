import 'package:flutter/material.dart';

class ChatList extends StatelessWidget {
  final List<Map<String, dynamic>> chats = [
    {"name": "Sumit Sharma", "matches": 7, "time": "12:58", "isPaid": true},
    {"name": "Amit Sharma", "matches": 1, "time": "12:50", "isPaid": false},
    {"name": "Priya Patel", "matches": 7, "time": "09:14", "isPaid": true},
    {"name": "Aarav Sharma", "matches": 1, "time": "07:05", "isPaid": false},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[200],
      child: Column(
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: "Search or start a new chat",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container( child:
            ListView.builder(
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                return ListTile(
                  leading: CircleAvatar(child: Icon(Icons.person)),
                  title: Text(chat["name"]),
                  subtitle: Text("${chat["matches"]} matches"),
                  trailing: Text(chat["time"]),
                );
              },
            ),
          ),)
        ],
      ),
    );
  }
}
