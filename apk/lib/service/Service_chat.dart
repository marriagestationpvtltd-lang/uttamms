import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../service/socket_service.dart';

class ServiceChatPage extends StatefulWidget {
  final String senderId;
  final String receiverId;
  final String name;
  final String exp;
  final String cat;

  const ServiceChatPage({
    super.key,
    required this.senderId,
    required this.receiverId,
    required this.name,
    required this.exp,
    required this.cat,
  });

  @override
  State<ServiceChatPage> createState() => _ServiceChatPageState();
}

class _ServiceChatPageState extends State<ServiceChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final SocketService _socketService = SocketService();
  final Uuid _uuid = Uuid();

  late String chatId;

  // Messages driven by Socket.IO
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  // Color scheme matching AdminChatScreen
  final LinearGradient _primaryGradient = const LinearGradient(
    colors: [Color(0xFF6B46C1), Color(0xFF9F7AEA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  final LinearGradient _secondaryGradient = const LinearGradient(
    colors: [Color(0xFFE9D5FF), Color(0xFFD6BCFA)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  final Color _accentColor = const Color(0xFFEC4899);
  final Color _backgroundColor = const Color(0xFFF8FAFC);
  final Color _textColor = const Color(0xFF1F2937);
  final Color _lightTextColor = const Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    chatId = _getChatId(widget.senderId, widget.receiverId);
    _loadMessages();
    _socketService.joinRoom(chatId);
    _socketService.onNewMessage.listen((data) {
      if (data['chatRoomId'] == chatId && mounted) {
        setState(() => _messages.add(data));
      }
    });
  }

  @override
  void dispose() {
    _socketService.leaveRoom(chatId);
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final result = await _socketService.getMessages(chatId, page: 1, limit: 50);
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(
            (result['messages'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)),
          );
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getChatId(String a, String b) {
    final ids = [a, b]..sort();
    return "chat_${ids[0]}_${ids[1]}";
  }

  // ---------------- SEND FUNCTIONS ----------------
  Future<void> _sendText() async {
    if (_controller.text.trim().isEmpty) return;
    final messageText = _controller.text.trim();
    _controller.clear();
    await _sendMessage(type: 'text', message: messageText);
  }

  Future<void> _sendThanks() async {
    await _sendMessage(type: 'thanks', message: 'Thank you for the service');
  }

  Future<void> _sendNotSatisfied() async {
    await _sendMessage(type: 'not_satisfied', message: 'Not satisfied with the service');
  }

  Future<void> _sendImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      final bytes = await image.readAsBytes();
      final url = await _socketService.uploadChatImage(
        bytes: bytes,
        filename: image.name,
        userId: widget.senderId,
        chatRoomId: chatId,
      );
      await _sendMessage(type: 'image', imageUrl: url, message: 'Photo');
    } catch (e) {
      debugPrint('Image upload error: $e');
    }
  }

  Future<void> _sendMessage({
    required String type,
    String? message,
    String? imageUrl,
  }) async {
    final msgText = type == 'image' ? (imageUrl ?? '') : (message ?? '');
    _socketService.sendMessage(
      chatRoomId: chatId,
      senderId: widget.senderId,
      receiverId: widget.receiverId,
      message: msgText,
      messageType: type,
      messageId: _uuid.v4(),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: _primaryGradient,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${widget.name} • ${widget.cat}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            Text(
              "Experience: ${widget.exp}",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_backgroundColor, _backgroundColor.withOpacity(0.9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _messageList(),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _messageList() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _accentColor));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet',
          style: TextStyle(color: _lightTextColor),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final doc = _messages[_messages.length - 1 - index];
        final isMe = doc['senderId']?.toString() == widget.senderId;
        return _buildMessage(doc, isMe);
      },
    );
  }

  Widget _buildMessage(Map<String, dynamic> data, bool isMe) {
    final type = data['messageType']?.toString() ?? data['type']?.toString() ?? 'text';
    switch (type) {
      case 'thanks':
        return _thanksBubble(isMe);
      case 'not_satisfied':
        return _notSatisfiedBubble(isMe);
      case 'image':
        return _imageBubble(data['message']?.toString() ?? '', isMe);
      default:
        return _textBubble(data['message']?.toString() ?? '', isMe);
    }
  }

  Widget _bubble(bool isMe, Widget child, {bool specialCard = false}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe)
              CircleAvatar(
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _secondaryGradient,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: specialCard ? null : (isMe ? _primaryGradient : _secondaryGradient),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                    bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: child,
              ),
            ),
            if (isMe) const SizedBox(width: 8),
            if (isMe)
              CircleAvatar(
                backgroundColor: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _primaryGradient,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _textBubble(String text, bool isMe) {
    return _bubble(
      isMe,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: isMe ? Colors.white : _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatTimestamp(),
            style: TextStyle(
              fontSize: 11,
              color: isMe ? Colors.white70 : _lightTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageBubble(String url, bool isMe) {
    return _bubble(
      isMe,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 220,
                height: 160,
                decoration: BoxDecoration(
                  gradient: _secondaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: CircularProgressIndicator(color: _accentColor),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 220,
                height: 160,
                decoration: BoxDecoration(
                  gradient: _secondaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.broken_image, color: _lightTextColor, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatTimestamp(),
            style: TextStyle(
              fontSize: 11,
              color: isMe ? Colors.white70 : _lightTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thanksBubble(bool isMe) {
    return _bubble(
      isMe,
      Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF56AB2F), Color(0xFFA8E063)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Icon(Icons.favorite, color: Colors.white, size: 36),
            const SizedBox(height: 8),
            const Text(
              "Thank You 🙏",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "For your help",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              _formatTimestamp(),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      specialCard: true,
    );
  }

  Widget _notSatisfiedBubble(bool isMe) {
    return _bubble(
      isMe,
      Container(
        width: 240,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFCB2D3E), Color(0xFFEF473A)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 36),
            const SizedBox(height: 8),
            const Text(
              "Not Satisfied",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Issue reported to support",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              _formatTimestamp(),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      specialCard: true,
    );
  }

  String _formatTimestamp() {
    return DateFormat('HH:mm').format(DateTime.now());
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, -3),
            )
          ],
        ),
        child: Row(
          children: [
            PopupMenuButton(
              icon: Icon(Icons.add_circle_outlined, color: _primaryGradient.colors[0]),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'thanks',
                  child: ListTile(
                    leading: Icon(Icons.thumb_up, color: Colors.green),
                    title: Text('Send Thanks',
                        style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
                  ),
                ),
                PopupMenuItem(
                  value: 'not_satisfied',
                  child: ListTile(
                    leading: Icon(Icons.thumb_down, color: Colors.red),
                    title: Text('Not Satisfied',
                        style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
                  ),
                ),
                PopupMenuItem(
                  value: 'image',
                  child: ListTile(
                    leading: Icon(Icons.image, color: _primaryGradient.colors[0]),
                    title: Text('Image',
                        style: TextStyle(color: _textColor, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'thanks') _sendThanks();
                if (value == 'not_satisfied') _sendNotSatisfied();
                if (value == 'image') _sendImage();
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: _secondaryGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    hintStyle: TextStyle(
                        color: _lightTextColor.withOpacity(0.7), fontSize: 15),
                  ),
                  style: TextStyle(color: _textColor, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 22),
                onPressed: _sendText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
