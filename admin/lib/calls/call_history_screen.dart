import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import 'call_history_service.dart';

// ─── Design tokens ────────────────────────────────────────────────────────────
const _kPrimary  = Color(0xFF6366F1);
const _kViolet   = Color(0xFF8B5CF6);
const _kEmerald  = Color(0xFF10B981);
const _kSky      = Color(0xFF0EA5E9);
const _kAmber    = Color(0xFFF59E0B);
const _kRose     = Color(0xFFEF4444);
const _kSlate400 = Color(0xFF94A3B8);
const _kSlate100 = Color(0xFFF1F5F9);

class AdminCallHistoryScreen extends StatefulWidget {
  const AdminCallHistoryScreen({super.key});

  @override
  State<AdminCallHistoryScreen> createState() => _AdminCallHistoryScreenState();
}

class _AdminCallHistoryScreenState extends State<AdminCallHistoryScreen> {
  final AdminCallHistoryService _service = AdminCallHistoryService();
  final ScrollController         _scrollCtrl  = ScrollController();
  final TextEditingController    _searchCtrl  = TextEditingController();

  List<AdminCallRecord> _calls        = [];
  bool   _isLoading      = true;
  bool   _isLoadingMore  = false;
  String _error          = '';
  int    _page           = 1;
  int    _totalPages     = 1;
  int    _total          = 0;
  Timer? _refreshTimer;

  // Filters
  String  _searchText = '';
  String? _callType;   // null | 'audio' | 'video'
  String? _status;     // null | 'completed' | 'missed' | 'declined' | 'cancelled'

  // Audio playback state
  final AudioPlayer _player   = AudioPlayer();
  String?           _playingCallId;
  bool              _isPlaying = false;

  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (mounted) _fetch(reset: true, silent: true); },
    );
    _scrollCtrl.addListener(_onScroll);
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _playingCallId = null;
          _isPlaying     = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _page < _totalPages) {
        _fetch(reset: false);
      }
    }
  }

  Future<void> _fetch({bool reset = true, bool silent = false}) async {
    if (!mounted) return;
    if (reset) {
      if (!silent) setState(() { _isLoading = true; _error = ''; });
      _page = 1;
    } else {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }
    try {
      final resp = await _service.getCalls(
        page:     _page,
        limit:    _pageSize,
        search:   _searchText.isEmpty ? null : _searchText,
        callType: _callType,
        status:   _status,
      );
      if (!mounted) return;
      setState(() {
        _totalPages  = resp.totalPages;
        _total       = resp.total;
        _isLoading     = false;
        _isLoadingMore = false;
        _error         = '';
        if (reset) {
          _calls = resp.calls;
          _page  = 2;
        } else {
          _calls.addAll(resp.calls);
          _page++;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading     = false;
        _isLoadingMore = false;
        if (reset) _error = e.toString();
      });
    }
  }

  Future<void> _togglePlayback(AdminCallRecord call) async {
    final url = call.recordingUrl;
    if (url == null || url.isEmpty) return;

    if (_playingCallId == call.callId && _isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      if (_playingCallId != call.callId) {
        await _player.stop();
        await _player.setUrl(url);
        setState(() => _playingCallId = call.callId);
      }
      await _player.play();
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot play recording: $e')),
      );
    }
  }

  void _openRecordingInBrowser(String url) {
    html.window.open(url, '_blank');
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  static Color _statusColor(String s) {
    switch (s) {
      case 'completed': return _kEmerald;
      case 'missed':    return _kAmber;
      case 'declined':  return _kRose;
      case 'cancelled': return _kSlate400;
      default:          return _kPrimary;
    }
  }

  static IconData _callTypeIcon(String type, String status) {
    if (type == 'video') return Icons.videocam_rounded;
    if (status == 'missed' || status == 'declined') return Icons.call_missed_rounded;
    return Icons.call_rounded;
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '—';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(cs, isDark),
        const SizedBox(height: 12),
        _buildFilterBar(cs, isDark),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(cs, isDark)),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Row(
      children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kEmerald, _kSky],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Call History',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
              Text(
                _isLoading
                    ? 'Loading…'
                    : '$_total calls total',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.55)),
              ),
            ],
          ),
        ),
        // Search box
        SizedBox(
          width: 220, height: 38,
          child: TextField(
            controller: _searchCtrl,
            onSubmitted: (v) {
              setState(() => _searchText = v);
              _fetch(reset: true);
            },
            decoration: InputDecoration(
              hintText: 'Search name or ID…',
              hintStyle: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.4)),
              prefixIcon: Icon(Icons.search_rounded, size: 16, color: cs.onSurface.withOpacity(0.4)),
              suffixIcon: _searchText.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _searchText = '');
                        _fetch(reset: true);
                      },
                      child: Icon(Icons.close_rounded, size: 14, color: cs.onSurface.withOpacity(0.4)),
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outlineVariant)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kPrimary)),
            ),
            style: TextStyle(fontSize: 12, color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 38, height: 38,
          child: Tooltip(
            message: 'Refresh',
            child: ElevatedButton(
              onPressed: () => _fetch(reset: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(ColorScheme cs, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All Types', null == _callType && null == _status, _kPrimary, isDark, cs,
            onTap: () { setState(() { _callType = null; _status = null; }); _fetch(reset: true); }),
          const SizedBox(width: 8),
          _chip('Audio', _callType == 'audio', _kEmerald, isDark, cs,
            onTap: () { setState(() => _callType = _callType == 'audio' ? null : 'audio'); _fetch(reset: true); }),
          const SizedBox(width: 8),
          _chip('Video', _callType == 'video', _kViolet, isDark, cs,
            onTap: () { setState(() => _callType = _callType == 'video' ? null : 'video'); _fetch(reset: true); }),
          const SizedBox(width: 16),
          _chip('Completed', _status == 'completed', _kEmerald, isDark, cs,
            onTap: () { setState(() => _status = _status == 'completed' ? null : 'completed'); _fetch(reset: true); }),
          const SizedBox(width: 8),
          _chip('Missed',    _status == 'missed',    _kAmber,   isDark, cs,
            onTap: () { setState(() => _status = _status == 'missed' ? null : 'missed'); _fetch(reset: true); }),
          const SizedBox(width: 8),
          _chip('Declined',  _status == 'declined',  _kRose,    isDark, cs,
            onTap: () { setState(() => _status = _status == 'declined' ? null : 'declined'); _fetch(reset: true); }),
          const SizedBox(width: 8),
          _chip('Cancelled', _status == 'cancelled', _kSlate400, isDark, cs,
            onTap: () { setState(() => _status = _status == 'cancelled' ? null : 'cancelled'); _fetch(reset: true); }),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, Color color, bool isDark, ColorScheme cs, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color:  active ? color : (isDark ? const Color(0xFF1E293B) : _kSlate100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : cs.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : cs.onSurface.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: _kRose),
            const SizedBox(height: 12),
            Text('Failed to load call history', style: TextStyle(color: cs.onSurface)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _fetch(reset: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_calls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_rounded, size: 48, color: cs.onSurface.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text('No calls found', style: TextStyle(fontSize: 15, color: cs.onSurface.withOpacity(0.5))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetch(reset: true),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(top: 4),
        itemCount: _calls.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == _calls.length) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          return _buildCallTile(_calls[i], cs, isDark);
        },
      ),
    );
  }

  Widget _buildCallTile(AdminCallRecord call, ColorScheme cs, bool isDark) {
    final color    = _statusColor(call.status);
    final icon     = _callTypeIcon(call.callType, call.status);
    final timeStr  = call.startTime != null
        ? DateFormat('MMM d, HH:mm').format(call.startTime!.toLocal())
        : '—';
    final dur      = _formatDuration(call.duration);
    final hasRec   = call.recordingUrl != null && call.recordingUrl!.isNotEmpty;
    final isThisPlaying = _playingCallId == call.callId && _isPlaying;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Call icon badge
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          // Caller info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        call.callerName.isNotEmpty ? call.callerName : 'User ${call.callerId}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded, size: 14, color: cs.onSurface.withOpacity(0.4)),
                    ),
                    Flexible(
                      child: Text(
                        call.recipientName.isNotEmpty ? call.recipientName : 'User ${call.recipientId}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Call type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (call.callType == 'video' ? _kViolet : _kSky).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        call.callType == 'video' ? '📹 Video' : '📞 Audio',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: call.callType == 'video' ? _kViolet : _kSky,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        call.status[0].toUpperCase() + call.status.substring(1),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 12, color: cs.onSurface.withOpacity(0.45)),
                    const SizedBox(width: 4),
                    Text(timeStr, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.55))),
                    const SizedBox(width: 12),
                    Icon(Icons.timelapse_rounded, size: 12, color: cs.onSurface.withOpacity(0.45)),
                    const SizedBox(width: 4),
                    Text(dur, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.55))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Recording playback controls
          if (hasRec) ...[
            Tooltip(
              message: isThisPlaying ? 'Pause Recording' : 'Play Recording',
              child: SizedBox(
                width: 36, height: 36,
                child: ElevatedButton(
                  onPressed: () => _togglePlayback(call),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isThisPlaying ? _kRose : _kEmerald,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Icon(
                    isThisPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Open in Browser',
              child: SizedBox(
                width: 36, height: 36,
                child: ElevatedButton(
                  onPressed: () => _openRecordingInBrowser(call.recordingUrl!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kSky,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Icon(Icons.open_in_new_rounded, size: 16),
                ),
              ),
            ),
          ] else ...[
            // No recording available
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_off_rounded, size: 12, color: cs.onSurface.withOpacity(0.35)),
                  const SizedBox(width: 4),
                  Text(
                    'No recording',
                    style: TextStyle(fontSize: 10, color: cs.onSurface.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
