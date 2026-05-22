// ignore_for_file: invalid_use_of_protected_member, use_string_in_part_of_directives
part of chatdetails_screen;

extension _ChatDetailsRecordingHelpers on _ChatDetailScreenState {
  Future<void> _startRecording() async {
    if (_isEitherBlocked || _isRecording) return;
    if (_chatRequestStatus != 'unknown' && _chatRequestStatus != 'accepted') {
      return;
    }
    if (_isTyping) _clearTyping();

    // ── OPTIMISTIC: show recording bar immediately so the UX feels instant ──
    _setRecordingStartedState();           // _isRecording = true
    _recordDurationNotifier.value = 0;
    _recordingAnimController?.repeat();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordDurationNotifier.value = _recordDurationNotifier.value + 1;
    });

    // ── Feature gate ──
    final canRecord = await AccessControl.canAccessFeature(
      context,
      FeatureType.voiceMessage,
      hasAcceptedRequest: true,
      showDialogs: true,
    );
    if (!canRecord) {
      _cancelRecording();
      return;
    }

    // ── Microphone permission (native only) ──
    if (!kIsWeb) {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        _cancelRecording();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Microphone permission is required to record voice messages.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    // ── Actually start the recorder ──
    try {
      String path;
      if (kIsWeb) {
        path = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
      } else {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      await _audioRecorder.start(
        kIsWeb
            ? const RecordConfig(
                encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 44100)
            : const RecordConfig(
                encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );

      // Amplitude feed for waveform visualisation
      _amplitudeSubscription?.cancel();
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        _audioAmplitudeNotifier.value = amp.current;
      });

      _socketService.startVoiceRecording(
        widget.chatRoomId,
        widget.currentUserId,
      );
    } catch (e) {
      _cancelRecording();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to start recording: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;

    _socketService.stopVoiceRecording(
      widget.chatRoomId,
      widget.currentUserId,
    );

    _recordTimer?.cancel();
    _recordTimer = null;
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _audioAmplitudeNotifier.value = -160.0;
    _recordingAnimController?.stop();
    _recordingAnimController?.reset();
    if (mounted) _setHoldRecordingState(false);

    String? pendingVoiceMsgId;
    try {
      final path = await _audioRecorder.stop();
      _setRecordingSendingState();

      if (path == null || path.isEmpty) return;

      final messageId = _uuid.v4();
      pendingVoiceMsgId = messageId;
      final bool receiverViewingThisChat = _isReceiverViewingThisChat;
      final int recordDuration = _recordDurationNotifier.value;

      // Step 1: Show optimistic UI immediately so the message appears sent at once.
      _appendOptimisticVoiceMessageState(
        messageId: messageId,
        localPath: path,
        receiverViewingThisChat: receiverViewingThisChat,
        recordDuration: recordDuration,
        retryLocalPath: path,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      // Step 2: Read file bytes and upload in background.
      late Uint8List voiceBytes;
      if (kIsWeb) {
        // On web path is a blob URL; use XFile to read bytes.
        final xfile = XFile(path);
        voiceBytes = await xfile.readAsBytes();
      } else {
        voiceBytes = await File(path).readAsBytes();
      }

      final voiceUrl = await _socketService.uploadVoiceMessage(
        bytes: voiceBytes,
        filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
        userId: widget.currentUserId,
        chatRoomId: widget.chatRoomId,
      );

      if (!mounted) return;

      // Step 3: Update the optimistic message with the real uploaded URL.
      _updateVoiceMessageUploadState(
        messageId: messageId,
        uploadedUrl: voiceUrl,
      );

      // Step 4: Persist via HTTP path so delivery can be retried safely.
      await _sendMessageViaHttp(
        chatRoomId: widget.chatRoomId,
        senderId: widget.currentUserId,
        receiverId: widget.receiverId,
        message: voiceUrl,
        messageType: 'voice',
        messageId: messageId,
      );

      _markMessagePendingState(messageId, isPending: false);

      if (!receiverViewingThisChat) {
        unawaited(
          NotificationService.sendChatNotificationFast(
            recipientUserId: widget.receiverId.toString(),
            senderName: widget.currentUserName,
            senderId: widget.currentUserId.toString(),
            message: 'Voice message',
            extraData: {
              'chatRoomId': widget.chatRoomId,
            },
          ),
        );
      }
    } catch (e) {
      if (pendingVoiceMsgId != null) {
        if (_isRetryableSendError(e)) {
          _markMessagePendingState(pendingVoiceMsgId, isPending: true);
          final idx = _cachedMessages.indexWhere(
            (m) => m['messageId']?.toString() == pendingVoiceMsgId,
          );
          if (idx >= 0 && mounted) {
            setState(() {
              _cachedMessages[idx] = {
                ..._cachedMessages[idx],
                'isUploading': false,
              };
              _messagesCacheVersion++;
            });
          }
          _saveMessagesToLocalCache();
          _retryPendingOutgoingMessages();
        } else {
          _removePendingVoiceMessageState(pendingVoiceMsgId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isRetryableSendError(e)
                  ? 'Voice message queued. It will send automatically.'
                  : 'Failed to send voice message: $e'),
              backgroundColor:
                  _isRetryableSendError(e) ? Colors.orange : Colors.red),
        );
      }
    } finally {
      if (mounted) _resetRecordingAndSendingState();
    }
  }

  void _cancelRecording() {
    if (!_isRecording) return;

    _recordTimer?.cancel();
    _recordTimer = null;
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _audioAmplitudeNotifier.value = -160.0;
    _recordDurationNotifier.value = 0;
    _recordingAnimController?.stop();
    _recordingAnimController?.reset();
    // Safely stop recorder and socket — these are no-ops if not yet started.
    _audioRecorder.stop().ignore();
    try {
      _socketService.stopVoiceRecording(
        widget.chatRoomId,
        widget.currentUserId,
      );
    } catch (_) {}
    _setRecordingCancelledState();
  }

  String _formatRecordDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
