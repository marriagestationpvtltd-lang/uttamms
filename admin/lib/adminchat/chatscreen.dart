import 'package:adminmrz/adminchat/right.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chathome.dart';
import 'chatprovider.dart';
import 'left.dart';

const _kChatMobileBreakpoint = 768.0;

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _mobileChatOpen = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        Provider.of<ChatProvider>(context, listen: false).fetchChatList());
  }

  int selectedTab = 0;

  void _openMobileChat() {
    if (!_mobileChatOpen) setState(() => _mobileChatOpen = true);
  }

  void _closeMobileChat() {
    if (_mobileChatOpen) setState(() => _mobileChatOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < _kChatMobileBreakpoint;

    if (isMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        body: _mobileChatOpen
            ? ChatWindow(
                name: 'Chat',
                isOnline: true,
                receiverIdd: 0,
                onBack: _closeMobileChat,
              )
            : ChatSidebar(onUserTap: _openMobileChat),
      );
    }

    // ── Desktop layout ─────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: Row(
        children: [
          ChatSidebar(),
          Container(width: 1, color: const Color(0xFFE2E8F0)),
          Expanded(
              child: ChatWindow(
                  name: 'select user to chat',
                  isOnline: true,
                  receiverIdd: 0)),
          Container(width: 1, color: const Color(0xFFE2E8F0)),
          ProfileSidebar(
            selectedTab: selectedTab,
            onTabChange: (index) {
              setState(() {
                selectedTab = index;
              });
            },
          ),
        ],
      ),
    );
  }
}