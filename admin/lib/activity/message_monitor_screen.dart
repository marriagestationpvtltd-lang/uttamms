import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adminmrz/adminchat/services/admin_socket_service.dart';
import 'package:adminmrz/config/app_endpoints.dart';

// ─── Design tokens ─────────────────────────────────────────────────────────────
const _kPrimary  = Color(0xFF6366F1);
const _kEmerald  = Color(0xFF10B981);
const _kSky      = Color(0xFF0EA5E9);
const _kAmber    = Color(0xFFF59E0B);
const _kRose     = Color(0xFFEF4444);
const _kSlate100 = Color(0xFFF1F5F9);
const _kSlate200 = Color(0xFFE2E8F0);
const _kSlate400 = Color(0xFF94A3B8);
const _kSlate700 = Color(0xFF334155);
const _kSlate900 = Color(0xFF0F172A);

// ─── Models ────────────────────────────────────────────────────────────────────

class _MonitorMessage {
  final String messageId;
  final String chatRoomId;
  final String senderId;
  final String receiverId;
  final String senderName;
  final String receiverName;
  final String message;
  final String messageType;
  final DateTime timestamp;

  const _MonitorMessage({
    required this.messageId,
    required this.chatRoomId,
    required this.senderId,
    required this.receiverId,
    required this.senderName,
    required this.receiverName,
    required this.message,
    required this.messageType,
    required this.timestamp,
  });

  factory _MonitorMessage.fromSocketData(Map<String, dynamic> data) {
    final ts = data['timestamp']?.toString();
    return _MonitorMessage(
      messageId:    data['messageId']?.toString()   ?? '',
      chatRoomId:   data['chatRoomId']?.toString()  ?? '',
      senderId:     data['senderId']?.toString()    ?? '',
      receiverId:   data['receiverId']?.toString()  ?? '',
      senderName:   data['senderName']?.toString()  ?? data['sender_name']?.toString() ?? '',
      receiverName: data['receiverName']?.toString() ?? data['receiver_name']?.toString() ?? '',
      message:      data['message']?.toString()     ?? '',
      messageType:  data['messageType']?.toString() ?? 'text',
      timestamp:    ts != null ? (DateTime.tryParse(ts) ?? DateTime.now()) : DateTime.now(),
    );
  }

  factory _MonitorMessage.fromApiJson(Map<String, dynamic> json) {
    final ts = json['timestamp']?.toString();
    return _MonitorMessage(
      messageId:    json['messageId']?.toString()   ?? '',
      chatRoomId:   json['chatRoomId']?.toString()  ?? '',
      senderId:     json['senderId']?.toString()    ?? '',
      receiverId:   json['receiverId']?.toString()  ?? '',
      senderName:   json['senderName']?.toString()  ?? '',
      receiverName: json['receiverName']?.toString() ?? '',
      message:      json['message']?.toString()     ?? '',
      messageType:  json['messageType']?.toString() ?? 'text',
      timestamp:    ts != null ? (DateTime.tryParse(ts) ?? DateTime.now()) : DateTime.now(),
    );
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────

/// Admin message monitor — shows real-time messages across all chat rooms and
/// allows the admin to load full conversation history between any two users.
class MessageMonitorScreen extends StatefulWidget {
  const MessageMonitorScreen({super.key});

  @override
  State<MessageMonitorScreen> createState() => _MessageMonitorScreenState();
}

class _MessageMonitorScreenState extends State<MessageMonitorScreen> {
  final AdminSocketService _socket = AdminSocketService();
  StreamSubscription<Map<String, dynamic>>? _sub;

  // Live feed — newest first, capped at 500 entries to avoid unbounded growth.
  static const int _feedCap = 500;
  final List<_MonitorMessage> _feed = [];

  // Filter
  final TextEditingController _filterCtrl = TextEditingController();
  String _filterText = '';

  @override
  void initState() {
    super.initState();
    _sub = _socket.onMessageMonitor.listen(_onMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final msg = _MonitorMessage.fromSocketData(data);
    setState(() {
      _feed.insert(0, msg);
      if (_feed.length > _feedCap) _feed.removeRange(_feedCap, _feed.length);
    });
  }

  List<_MonitorMessage> get _filtered {
    if (_filterText.isEmpty) return _feed;
    final q = _filterText.toLowerCase();
    return _feed.where((m) =>
      m.senderName.toLowerCase().contains(q) ||
      m.receiverName.toLowerCase().contains(q) ||
      m.message.toLowerCase().contains(q) ||
      m.senderId.contains(q) ||
      m.receiverId.contains(q),
    ).toList();
  }

  // ─── History dialog ──────────────────────────────────────────────────────────

  Future<void> _showHistory(_MonitorMessage msg) async {
    await showDialog(
      context: context,
      builder: (_) => _ChatHistoryDialog(
        chatRoomId: msg.chatRoomId,
        label: '${msg.senderName} ↔ ${msg.receiverName}',
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header bar ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Message Monitor',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Real-time feed of all user messages',
                      style: TextStyle(fontSize: 13, color: _kSlate400),
                    ),
                  ],
                ),
              ),
              // Live indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kEmerald.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kEmerald.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: _kEmerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kEmerald,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Stats bar ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              _StatChip(
                label: 'In feed',
                value: '${_feed.length}',
                color: _kPrimary,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Showing',
                value: '${_filtered.length}',
                color: _kSky,
              ),
              const Spacer(),
              if (_feed.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() => _feed.clear()),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: _kSlate400,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
            ],
          ),
        ),

        // ── Search bar ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: TextField(
            controller: _filterCtrl,
            onChanged: (v) => setState(() => _filterText = v.trim()),
            decoration: InputDecoration(
              hintText: 'Filter by name, user ID or message…',
              hintStyle: TextStyle(fontSize: 13, color: _kSlate400),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _kSlate400),
              suffixIcon: _filterText.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: _kSlate400,
                      onPressed: () {
                        _filterCtrl.clear();
                        setState(() => _filterText = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : _kSlate100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _kSlate200, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kPrimary, width: 1.5),
              ),
            ),
          ),
        ),

        // ── Feed ────────────────────────────────────────────────────────────
        Expanded(
          child: _filtered.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _MessageTile(
                    msg: _filtered[i],
                    onHistory: () => _showHistory(_filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 56, color: _kSlate400.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            _filterText.isNotEmpty ? 'No messages match your filter' : 'Waiting for messages…',
            style: const TextStyle(fontSize: 15, color: _kSlate400),
          ),
          if (_filterText.isEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'Messages sent by users will appear here in real-time.',
              style: TextStyle(fontSize: 12, color: _kSlate400),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Message tile ──────────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  final _MonitorMessage msg;
  final VoidCallback onHistory;

  const _MessageTile({required this.msg, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final timeStr = DateFormat('HH:mm:ss').format(msg.timestamp.toLocal());
    final dateStr = DateFormat('MMM d').format(msg.timestamp.toLocal());

    final typeColor = _typeColor(msg.messageType);
    final typeIcon  = _typeIcon(msg.messageType);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF334155) : _kSlate200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Type icon ────────────────────────────────────────────────
            Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(right: 12, top: 2),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(typeIcon, size: 18, color: typeColor),
            ),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender → Receiver
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          msg.senderName.isEmpty ? 'User ${msg.senderId}' : msg.senderName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, size: 12, color: _kSlate400),
                      ),
                      Flexible(
                        child: Text(
                          msg.receiverName.isEmpty ? 'User ${msg.receiverId}' : msg.receiverName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Message text
                  Text(
                    _messagePreview(msg),
                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.75)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Footer row
                  Row(
                    children: [
                      // IDs
                      Text(
                        'ID ${msg.senderId} → ${msg.receiverId}',
                        style: const TextStyle(fontSize: 11, color: _kSlate400),
                      ),
                      const Spacer(),
                      // Timestamp
                      Text(
                        '$dateStr $timeStr',
                        style: const TextStyle(fontSize: 11, color: _kSlate400),
                      ),
                      const SizedBox(width: 8),
                      // History button
                      InkWell(
                        onTap: onHistory,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kPrimary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'History',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messagePreview(_MonitorMessage m) {
    switch (m.messageType) {
      case 'image':        return '📷 Photo';
      case 'voice':        return '🎤 Voice message';
      case 'video':        return '🎬 Video';
      case 'file':         return '📎 File';
      case 'doc':          return '📄 Document';
      case 'profile_card': return '👤 Match profile';
      case 'call':         return '📞 Call';
      default:             return m.message.isEmpty ? '(empty)' : m.message;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'image':        return _kSky;
      case 'voice':        return _kEmerald;
      case 'video':        return _kAmber;
      case 'file':
      case 'doc':          return _kAmber;
      case 'profile_card': return _kPrimary;
      case 'call':         return _kEmerald;
      default:             return _kSky;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'image':        return Icons.image_rounded;
      case 'voice':        return Icons.mic_rounded;
      case 'video':        return Icons.videocam_rounded;
      case 'file':
      case 'doc':          return Icons.attach_file_rounded;
      case 'profile_card': return Icons.person_rounded;
      case 'call':         return Icons.call_rounded;
      default:             return Icons.chat_bubble_rounded;
    }
  }
}

// ─── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$value ',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(fontSize: 12, color: _kSlate400),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chat history dialog ────────────────────────────────────────────────────────

class _ChatHistoryDialog extends StatefulWidget {
  final String chatRoomId;
  final String label;

  const _ChatHistoryDialog({required this.chatRoomId, required this.label});

  @override
  State<_ChatHistoryDialog> createState() => _ChatHistoryDialogState();
}

class _ChatHistoryDialogState extends State<_ChatHistoryDialog> {
  List<_MonitorMessage> _messages = [];
  bool _loading = true;
  String _error = '';
  int _page = 1;
  int _totalPages = 1;
  bool _loadingMore = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore && _page < _totalPages) {
      _load(more: true);
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      setState(() => _loadingMore = true);
    } else {
      setState(() { _loading = true; _error = ''; });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final uri = Uri.parse('$kAdminSocketBaseUrl/api/admin/chat-history')
          .replace(queryParameters: {
        'chatRoomId': widget.chatRoomId,
        'page': _page.toString(),
        'limit': '50',
      });

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final list = (body['messages'] as List<dynamic>? ?? [])
            .map((e) => _MonitorMessage.fromApiJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        setState(() {
          _totalPages = body['pages'] is int
              ? body['pages'] as int
              : int.tryParse(body['pages'].toString()) ?? 1;
          if (more) {
            _messages.addAll(list);
            _page++;
          } else {
            _messages = list;
            _page = 2;
          }
          _loading = false;
          _loadingMore = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _error = 'Unauthorized. Please log in again.';
          _loading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load history (${response.statusCode}).';
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Network error: $e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 640,
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            // ── Title bar ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _kSlate200)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 20, color: _kPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chat History',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.label,
                          style: const TextStyle(fontSize: 12, color: _kSlate400),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    color: _kSlate400,
                  ),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: _kRose, size: 40),
                                const SizedBox(height: 12),
                                Text(_error, textAlign: TextAlign.center,
                                    style: const TextStyle(color: _kRose)),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: () => _load(),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _messages.isEmpty
                          ? const Center(
                              child: Text('No messages found.',
                                  style: TextStyle(color: _kSlate400)),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _messages.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                return _HistoryMessageRow(msg: _messages[i]);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History message row ────────────────────────────────────────────────────────

class _HistoryMessageRow extends StatelessWidget {
  final _MonitorMessage msg;

  const _HistoryMessageRow({required this.msg});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = DateFormat('MMM d, HH:mm').format(msg.timestamp.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : _kSlate100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 16,
            backgroundColor: _kPrimary.withOpacity(0.15),
            child: Text(
              _initial(msg.senderName, msg.senderId),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender → Receiver
                Row(
                  children: [
                    Text(
                      msg.senderName.isEmpty ? 'User ${msg.senderId}' : msg.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(Icons.arrow_forward_rounded, size: 11, color: _kSlate400),
                    ),
                    Text(
                      msg.receiverName.isEmpty ? 'User ${msg.receiverId}' : msg.receiverName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeStr,
                      style: const TextStyle(fontSize: 11, color: _kSlate400),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Message
                Text(
                  _preview(msg),
                  style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initial(String name, String id) {
    if (name.isNotEmpty) return name[0].toUpperCase();
    if (id.isNotEmpty)   return id[0].toUpperCase();
    return '?';
  }

  String _preview(_MonitorMessage m) {
    switch (m.messageType) {
      case 'image':        return '📷 Photo';
      case 'voice':        return '🎤 Voice message';
      case 'video':        return '🎬 Video';
      case 'file':
      case 'doc':          return '📎 File';
      case 'profile_card': return '👤 Match profile';
      case 'call':         return '📞 Call';
      default:             return m.message.isEmpty ? '(empty)' : m.message;
    }
  }
}
