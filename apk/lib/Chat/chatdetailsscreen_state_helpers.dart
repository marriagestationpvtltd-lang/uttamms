// ignore_for_file: invalid_use_of_protected_member, use_string_in_part_of_directives
part of chatdetails_screen;

extension _ChatDetailsStateHelpers on _ChatDetailScreenState {
  void _setHasTextState(bool hasText) {
    if (!mounted) return;
    setState(() => _hasText = hasText);
  }

  /// Saves the most recent messages via the singleton cache.
  void _saveMessagesToLocalCache() {
    ChatMessageCache.instance.saveMessages(widget.chatRoomId, _cachedMessages);
  }

  void _mergePendingIncomingMessagesState() {
    if (!mounted) return;
    setState(() {
      for (final newMsg in _pendingIncomingMessages) {
        final existingIdx = _cachedMessages.indexWhere(
          (m) => m['messageId']?.toString() == newMsg['messageId']?.toString(),
        );
        if (existingIdx >= 0) {
          _cachedMessages[existingIdx] = newMsg;
        } else {
          _cachedMessages.add(newMsg);
        }
      }
      _pendingIncomingMessages.clear();
      _messagesCacheVersion++;
      if (_forceScrollToBottom) _forceScrollToBottom = false;
    });
  }

  void _setCallHistoryState(List<CallHistory> callHistory) {
    if (!mounted) return;
    setState(() {
      _callHistory = callHistory;
    });
  }

  void _setBlockStatusState({
    required bool isBlocked,
    required bool isBlockedByReceiver,
  }) {
    if (!mounted) return;
    setState(() {
      _isBlocked = isBlocked;
      _isBlockedByReceiver = isBlockedByReceiver;
    });
  }

  void _setPhotoAndChatRequestStatusState({
    required String photoRequestStatus,
    required String chatRequestStatus,
  }) {
    if (!mounted) return;
    setState(() {
      _photoRequestStatus = photoRequestStatus;
      _chatRequestStatus = chatRequestStatus;
    });
  }

  void _setReceiverStatusState(bool online, DateTime? lastSeen) {
    if (!mounted) return;
    setState(() {
      _isOtherUserOnline = online;
      _otherUserLastSeen = lastSeen;
    });
  }

  void _setReceiverTypingState(bool isTyping) {
    if (!mounted) return;
    setState(() => _isReceiverTyping = isTyping);
  }

  void _setReceiverVoiceRecordingState(bool isRecording) {
    if (!mounted) return;
    setState(() => _isReceiverVoiceRecording = isRecording);
  }

  void _setHighlightedMessageIdState(String? messageId) {
    if (!mounted) return;
    setState(() => _highlightedMessageId = messageId);
  }

  void _setRefreshedMessagesState({
    required List<Map<String, dynamic>> messages,
    required bool hasMore,
  }) {
    if (!mounted) return;
    final pendingLocal = _collectLocallyPendingMessages(_cachedMessages);
    final merged = _mergeServerAndPendingMessages(
      serverMessages: messages,
      pendingLocalMessages: pendingLocal,
    );
    setState(() {
      _cachedMessages = merged;
      _hasMoreMessages = hasMore;
      _currentMessagePage = 1;
      _messagesCacheVersion++;
    });
  }

  List<Map<String, dynamic>> _collectLocallyPendingMessages(
      List<Map<String, dynamic>> source) {
    return source
        .where((m) {
          final isMine = m['senderId']?.toString() == widget.currentUserId;
          if (!isMine) return false;

          final isPending = m['isPendingSend'] == true;
          final isUploading = m['isUploading'] == true;
          final hasRetryKind =
              (m['retryKind']?.toString().trim().isNotEmpty ?? false);
          return isPending || isUploading || hasRetryKind;
        })
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  List<Map<String, dynamic>> _mergeServerAndPendingMessages({
    required List<Map<String, dynamic>> serverMessages,
    required List<Map<String, dynamic>> pendingLocalMessages,
  }) {
    final merged = serverMessages
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: true);

    for (final pending in pendingLocalMessages) {
      final pendingId = pending['messageId']?.toString() ?? '';
      if (pendingId.isEmpty) continue;

      final existsOnServer = merged.any(
        (m) => (m['messageId']?.toString() ?? '') == pendingId,
      );
      if (!existsOnServer) {
        merged.add(pending);
      }
    }

    merged.sort((a, b) {
      final aTs = SocketService.parseTimestamp(a['timestamp']) ?? DateTime(1970);
      final bTs = SocketService.parseTimestamp(b['timestamp']) ?? DateTime(1970);
      return aTs.compareTo(bTs);
    });

    return merged;
  }

  void _setLoadingMoreState(bool isLoading) {
    if (!mounted) return;
    setState(() => _isLoadingMore = isLoading);
  }

  void _setLoadMoreEmptyState() {
    if (!mounted) return;
    setState(() {
      _hasMoreMessages = false;
      _isLoadingMore = false;
    });
  }

  void _applyLoadedMoreMessagesState({
    required List<Map<String, dynamic>> newMessages,
    required bool hasMore,
    required int nextPage,
  }) {
    if (!mounted) return;
    setState(() {
      _cachedMessages.insertAll(0, newMessages);
      _hasMoreMessages = hasMore;
      _currentMessagePage = nextPage;
      _isLoadingMore = false;
      _messagesCacheVersion++;
    });
  }

  void _setRecordingCancelledState() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isHoldRecording = false;
      _isRecordingLocked = false;
      _recordSwipeDx = 0.0;
    });
  }

  void _setRecordingStartedState() {
    if (!mounted) return;
    setState(() {
      _isRecording = true;
    });
  }

  void _setRecordingSendingState() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isSendingVoice = true;
    });
  }

  void _setHoldRecordingState(bool value) {
    if (!mounted) return;
    setState(() {
      _isHoldRecording = value;
    });
  }

  void _appendOptimisticVoiceMessageState({
    required String messageId,
    required String localPath,
    required bool receiverViewingThisChat,
    required int recordDuration,
    String? retryLocalPath,
  }) {
    if (!mounted) return;
    setState(() {
      _cachedMessages.add({
        'messageId': messageId,
        'senderId': widget.currentUserId,
        'receiverId': widget.receiverId,
        'message': localPath,
        'messageType': 'voice',
        'timestamp': DateTime.now(),
        'isRead': receiverViewingThisChat,
        'isDelivered': receiverViewingThisChat,
        'isDeletedForSender': false,
        'isDeletedForReceiver': false,
        'duration': recordDuration,
        'isUploading': true,
        'isPendingSend': true,
        'retryKind': 'voice',
        'retryLocalPath': retryLocalPath ?? localPath,
      });
      _messagesCacheVersion++;
    });
    _saveMessagesToLocalCache();
  }

  void _updateVoiceMessageUploadState({
    required String messageId,
    required String uploadedUrl,
  }) {
    if (!mounted) return;
    setState(() {
      final msgIndex =
          _cachedMessages.indexWhere((m) => m['messageId'] == messageId);
      if (msgIndex != -1) {
        _cachedMessages[msgIndex] = {
          ..._cachedMessages[msgIndex],
          'message': uploadedUrl,
          'isUploading': false,
        };
        _messagesCacheVersion++;
      }
    });
  }

  void _removePendingVoiceMessageState(String messageId) {
    if (!mounted) return;
    setState(() {
      _cachedMessages.removeWhere((m) => m['messageId'] == messageId);
      _messagesCacheVersion++;
    });
  }

  void _resetRecordingAndSendingState() {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isSendingVoice = false;
      _isRecordingLocked = false;
      _recordSwipeDx = 0.0;
    });
  }

  void _clearDeletePopupAndSelectedOverlayState() {
    if (!mounted) return;
    setState(() {
      showDeletePopup = false;
      showActionOverlay = false;
      selectedMessage = null;
    });
  }

  void _clearSelectedMessageOverlayState() {
    if (!mounted) return;
    setState(() {
      showActionOverlay = false;
      selectedMessage = null;
    });
  }

  void _setReplyState(Map<String, dynamic> message) {
    if (!mounted) return;
    setState(() {
      repliedMessage = message;
      isReplying = true;
      showActionOverlay = false;
    });
  }

  void _clearReplyState() {
    if (!mounted) return;
    setState(() {
      repliedMessage = null;
      isReplying = false;
    });
  }

  void _setEditState(Map<String, dynamic> message) {
    if (!mounted) return;
    setState(() {
      editingMessage = message;
      isEditing = true;
      _editController.text = message['message'];
      showActionOverlay = false;
    });
  }

  void _clearEditState() {
    if (!mounted) return;
    setState(() {
      editingMessage = null;
      isEditing = false;
      _editController.clear();
    });
  }

  void _unlockScrollIfMounted() {
    if (!mounted) return;
    setState(() => _scrollLocked = false);
  }
}
