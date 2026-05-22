// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of chatdetails_screen;

extension _ChatDetailsComposerOverlayWidgets on _ChatDetailScreenState {
  // ── SCREEN BODY ──────────────────────────────────────────────────────────

  Widget _buildScreenBody() {
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(context),
            if (_showSocketReconnectBanner) _buildSocketBanner(),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _backgroundColor,
                      _backgroundColor.withValues(alpha: 0.92),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: _buildMessagesList(),
              ),
            ),
            _buildPeerStatusBubble(),
            _bottomSection(),
          ],
        ),
        if (showActionOverlay) _fullScreenActionOverlay(),
        if (showDeletePopup) _deletePopupOverlay(),
      ],
    );
  }

  Widget _buildSocketBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _isSocketRealtimeHealthy
          ? Colors.green.withValues(alpha: 0.12)
          : Colors.orange.withValues(alpha: 0.14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isSocketRealtimeHealthy
                ? Icons.cloud_done_outlined
                : Icons.sync_problem_outlined,
            size: 14,
            color: _isSocketRealtimeHealthy
                ? Colors.green.shade700
                : Colors.orange.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            _isSocketRealtimeHealthy
                ? 'Realtime connected'
                : 'Realtime reconnecting...',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _isSocketRealtimeHealthy
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerStatusBubble() {
    if (_isReceiverVoiceRecording) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 12, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: _peerStatusDecoration(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic, size: 15, color: _accentColor),
              const SizedBox(width: 6),
              Text(
                'Recording voice...',
                style: TextStyle(
                  color: _textColor.withValues(alpha: 0.82),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_isReceiverTyping) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 12, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: _peerStatusDecoration(),
          child: const TypingIndicatorWidget(
            dotColor: Color(0xFF6B7280),
            dotSize: 7.0,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  BoxDecoration _peerStatusDecoration() {
    return BoxDecoration(
      gradient: _secondaryGradient,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(4),
        bottomRight: Radius.circular(20),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  // ── ACTION OVERLAY ───────────────────────────────────────────────────────

  Widget _fullScreenActionOverlay() {
    const emojis = ['❤️', '😂', '😮', '😢', '👍', '😡'];
    final msgId = selectedMessage?['messageId']?.toString() ??
        selectedMessage?['id']?.toString() ??
        '';
    final existingReactions = selectedMessage?['reactions'];
    final Map<String, dynamic> reactions = (existingReactions is Map)
        ? Map<String, dynamic>.from(existingReactions)
        : {};
    final myReaction = reactions[widget.currentUserId]?.toString() ?? '';

    final screenHeight = MediaQuery.of(context).size.height;
    final tapY = _selectedMessageOffset.dy;
    const double emojiBarHeight = 64.0;
    const double gap = 12.0;
    double emojiTop = tapY - emojiBarHeight - gap;
    if (emojiTop < 80) emojiTop = tapY + gap;
    emojiTop = emojiTop.clamp(60.0, screenHeight - emojiBarHeight - 280.0);

    return GestureDetector(
      onTap: () {
        if (mounted) setState(() => showActionOverlay = false);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.50),
          child: Stack(
            children: [
              // ── Emoji reaction pill ────────────────────────────────────
              Positioned(
                top: emojiTop,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 24,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: emojis.map((e) {
                          final isSelected = myReaction == e;
                          return GestureDetector(
                            onTap: () {
                              if (mounted) {
                                setState(() => showActionOverlay = false);
                              }
                              if (msgId.isNotEmpty) {
                                _socketService.addReaction(
                                    widget.chatRoomId, msgId, e);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              padding: EdgeInsets.all(isSelected ? 9 : 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _accentColor.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                e,
                                style:
                                    TextStyle(fontSize: isSelected ? 30 : 26),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Action menu bottom sheet ───────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181F),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.only(
                      top: 4,
                      bottom: MediaQuery.of(context).padding.bottom + 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Drag handle
                        Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        if (selectedMessage != null)
                          _menuItem(Icons.reply_rounded, 'Reply', () {
                            if (mounted) {
                              setState(() => showActionOverlay = false);
                            }
                            if (selectedMessage != null) {
                              _setReplyMessage(selectedMessage!);
                            }
                          }),
                        if (selectedMessage != null &&
                            selectedMessage!['messageType'] == 'text')
                          _menuItem(Icons.copy_outlined, 'Copy', _copyMessage),
                        if (selectedMessage != null &&
                            selectedMine &&
                            selectedMessage!['messageType'] == 'text')
                          _menuItem(Icons.edit_outlined, 'Edit', () {
                            _setEditMessage(selectedMessage!);
                          }),
                        _menuItem(
                          Icons.delete_outline_rounded,
                          'Delete',
                          () {
                            if (mounted) {
                              setState(() {
                                showActionOverlay = false;
                                showDeletePopup = true;
                              });
                            }
                          },
                          isDelete: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deletePopupOverlay() {
    return GestureDetector(
      onTap: () {
        if (mounted) setState(() => showDeletePopup = false);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black.withValues(alpha: 0.60),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 320,
              decoration: BoxDecoration(
                color: const Color(0xFF18181F),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 32,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Text(
                      'Delete Message',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                  _menuItem(Icons.delete_outline, 'Delete for me', () {
                    _deleteMessage(false);
                  }, isDelete: true),
                  if (selectedMine)
                    _menuItem(Icons.delete_sweep_outlined, 'Delete for everyone',
                        () {
                      _deleteMessage(true);
                    }, isDelete: true),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                  _menuItem(Icons.close_rounded, 'Cancel', () {
                    if (mounted) setState(() => showDeletePopup = false);
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String text, VoidCallback onTap,
      {bool isDelete = false}) {
    final color = isDelete ? Colors.red.shade400 : Colors.white;
    final bgColor = isDelete
        ? Colors.red.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.07);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.06),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 16),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── INPUT BAR ────────────────────────────────────────────────────────────

  Widget _bottomSection() => _bottomInputBar();

  Widget _bottomInputBar() {
    if (_isEitherBlocked) return _buildBlockedBar();

    final chatRequestNotAccepted =
        _chatRequestStatus != 'unknown' && _chatRequestStatus != 'accepted';
    if (chatRequestNotAccepted) return _buildChatRequestBar();

    final hasText =
        isEditing ? _editController.text.trim().isNotEmpty : _hasText;
    final isHoldMode = _isHoldRecording && !_isRecordingLocked;

    return Listener(
      onPointerUp: (_) {
        if (isHoldMode && _isRecording) {
          _isHoldRecording = false;
          if (mounted) setState(() => _recordSwipeDx = 0.0);
          _stopAndSendRecording();
        }
      },
      onPointerCancel: (_) {
        if (isHoldMode && _isRecording) {
          _isHoldRecording = false;
          if (mounted) {
            setState(() {
              _recordSwipeDx = 0.0;
              _isRecordingLocked = false;
            });
          }
          _cancelRecording();
        }
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 10,
          right: 10,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          border:
              Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReplying) _buildReplyPreview(),
            if (isEditing) _buildEditPreview(),
            if (_isRecording)
              _buildRecordingBar()
            else
              _buildNormalInputRow(hasText),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.block_rounded, color: Colors.red.shade400, size: 18),
          const SizedBox(width: 8),
          Text(
            _isBlocked
                ? 'You have blocked this user'
                : 'This user has blocked you',
            style: TextStyle(
              color: Colors.red.shade400,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatRequestBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              color: Colors.orange.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Send a chat request to start messaging',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: widget.receiverId)),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: _primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'Send Request',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalInputRow(bool hasText) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Attach button (hidden in edit mode)
        if (!isEditing)
          _isSendingImage
              ? SizedBox(
                  width: 40,
                  height: 46,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_accentColor),
                      ),
                    ),
                  ),
                )
              : IconButton(
                  onPressed: _pickAndSendImages,
                  icon: Icon(Icons.attach_file_rounded,
                      size: 22, color: Colors.grey.shade500),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 46),
                ),
        const SizedBox(width: 4),

        // Text field pill
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F3F5),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller:
                        isEditing ? _editController : _messageController,
                    focusNode: _messageFocusNode,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                        fontSize: 15, color: _textColor, height: 1.4),
                    decoration: InputDecoration(
                      hintText: isEditing
                          ? 'Edit your message...'
                          : 'Type a message...',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade500, fontSize: 15),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 12),
                    ),
                    onChanged: (value) {
                      if (!isEditing && value.isNotEmpty) {
                        _onTypingChanged();
                      } else if (!isEditing && value.isEmpty) {
                        _clearTyping();
                      }
                    },
                    onSubmitted: (_) =>
                        isEditing ? _editMessage() : _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Mic or Send button
        if (!isEditing && !hasText)
          _buildMicButton()
        else
          _buildSendButton(hasText),
      ],
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTap: () {
        if (mounted) setState(() => _isRecordingLocked = true);
        _startRecording();
      },
      onLongPressStart: (_) async {
        HapticFeedback.heavyImpact();
        if (mounted) {
          setState(() {
            _isHoldRecording = true;
            _isRecordingLocked = false;
            _recordSwipeDx = 0.0;
          });
        }
        await _startRecording();
      },
      onLongPressMoveUpdate: (details) {
        if (_isRecordingLocked) return;
        final dx = details.offsetFromOrigin.dx;
        final dy = details.offsetFromOrigin.dy;

        // Slide UP → lock recording (hands-free)
        if (dy < -64) {
          HapticFeedback.selectionClick();
          if (mounted) {
            setState(() {
              _isRecordingLocked = true;
              _recordSwipeDx = 0.0;
            });
          }
          return;
        }

        // Slide LEFT → drag feedback + auto-cancel at threshold
        final clampedDx = dx.clamp(-220.0, 0.0);
        if (mounted) setState(() => _recordSwipeDx = clampedDx);
        if (dx < -130) {
          HapticFeedback.mediumImpact();
          if (mounted) {
            setState(() {
              _isHoldRecording = false;
              _isRecordingLocked = false;
              _recordSwipeDx = 0.0;
            });
          }
          _cancelRecording();
        }
      },
      onLongPressEnd: (_) {
        if (_isRecordingLocked) return;
        if (_isHoldRecording && _isRecording) {
          if (mounted) {
            setState(() {
              _isHoldRecording = false;
              _recordSwipeDx = 0.0;
            });
          }
          _stopAndSendRecording();
        }
      },
      onLongPressCancel: () {
        if (_isRecordingLocked) return;
        if (_isHoldRecording && _isRecording) {
          if (mounted) {
            setState(() {
              _isHoldRecording = false;
              _recordSwipeDx = 0.0;
            });
          }
          _cancelRecording();
        }
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: _primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.38),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildSendButton(bool hasText) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: hasText ? _primaryGradient : null,
        color: hasText ? null : const Color(0xFFD0D0D0),
        shape: BoxShape.circle,
        boxShadow: hasText
            ? [
                BoxShadow(
                  color: _accentColor.withValues(alpha: 0.38),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: IconButton(
        onPressed: hasText ? (isEditing ? _editMessage : _sendMessage) : null,
        icon: Icon(
          isEditing ? Icons.check_rounded : Icons.send_rounded,
          color: Colors.white,
          size: 20,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  // ── RECORDING BAR ────────────────────────────────────────────────────────

  Widget _buildRecordingBar() {
    if (_recordingAnimController == null) return const SizedBox.shrink();
    final isHoldMode = _isHoldRecording && !_isRecordingLocked;
    return isHoldMode
        ? _buildHoldModeRecordingRow()
        : _buildLockedModeRecordingRow();
  }

  /// WhatsApp-style hold mode: "← Slide to cancel" with drag-to-cancel gesture.
  Widget _buildHoldModeRecordingRow() {
    final cancelProgress = (-_recordSwipeDx / 130.0).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lock icon floats above (right-aligned). Tapping locks recording.
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              if (mounted) setState(() => _isRecordingLocked = true);
            },
            child: Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(right: 4, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.lock_open_outlined,
                  size: 17, color: Colors.grey.shade500),
            ),
          ),
        ),

        // Main recording row — wrap in GestureDetector for horizontal swipe.
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            if (!mounted) return;
            setState(() {
              _recordSwipeDx =
                  (_recordSwipeDx + details.delta.dx).clamp(-220.0, 0.0);
            });
          },
          onHorizontalDragEnd: (details) {
            if (_recordSwipeDx < -90) {
              HapticFeedback.mediumImpact();
              if (mounted) {
                setState(() {
                  _isHoldRecording = false;
                  _isRecordingLocked = false;
                  _recordSwipeDx = 0.0;
                });
              }
              _cancelRecording();
            } else {
              if (mounted) setState(() => _recordSwipeDx = 0.0);
            }
          },
          child: Row(
            children: [
              const SizedBox(width: 10),

              // Pulsing red dot
              AnimatedBuilder(
                animation: _recordingAnimController!,
                builder: (_, __) {
                  final pulse = 0.35 +
                      0.65 *
                          (0.5 +
                              0.5 *
                                  sin(2 *
                                      pi *
                                      _recordingAnimController!.value));
                  return Opacity(
                    opacity: pulse,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),

              // Timer
              ValueListenableBuilder<int>(
                valueListenable: _recordDurationNotifier,
                builder: (_, secs, __) => Text(
                  _formatRecordDuration(secs),
                  style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Waveform
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: AnimatedBuilder(
                    animation: _recordingAnimController!,
                    builder: (_, __) => ValueListenableBuilder<double>(
                      valueListenable: _audioAmplitudeNotifier,
                      builder: (_, amp, __) => _buildWaveformBars(amp),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // "← Slide to cancel" — shifts left with drag, fades at threshold
              Transform.translate(
                offset: Offset(_recordSwipeDx * 0.45, 0),
                child: Opacity(
                  opacity: (1.0 - cancelProgress * 1.5).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left_rounded,
                          size: 18, color: Colors.grey.shade500),
                      Text(
                        'Slide to cancel',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }

  /// Locked / tap-to-record mode: shows cancel + timer/waveform + send.
  Widget _buildLockedModeRecordingRow() {
    return Row(
      children: [
        // Cancel (trash) button
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: () {
              if (mounted) {
                setState(() {
                  _isRecordingLocked = false;
                  _recordSwipeDx = 0.0;
                });
              }
              _cancelRecording();
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Recording indicator pill
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                  color: _accentColor.withValues(alpha: 0.18), width: 1),
            ),
            child: Row(
              children: [
                // Pulsing red dot
                AnimatedBuilder(
                  animation: _recordingAnimController!,
                  builder: (_, __) {
                    final pulse = 0.35 +
                        0.65 *
                            (0.5 +
                                0.5 *
                                    sin(2 *
                                        pi *
                                        _recordingAnimController!.value));
                    return Opacity(
                      opacity: pulse,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Timer
                ValueListenableBuilder<int>(
                  valueListenable: _recordDurationNotifier,
                  builder: (_, secs, __) => Text(
                    _formatRecordDuration(secs),
                    style: TextStyle(
                      color: _accentColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Waveform
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: AnimatedBuilder(
                      animation: _recordingAnimController!,
                      builder: (_, __) => ValueListenableBuilder<double>(
                        valueListenable: _audioAmplitudeNotifier,
                        builder: (_, amp, __) => _buildWaveformBars(amp),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Send / uploading
        _isSendingVoice
            ? SizedBox(
                width: 46,
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_accentColor),
                  ),
                ),
              )
            : GestureDetector(
                onTap: () {
                  if (mounted) {
                    setState(() {
                      _isRecordingLocked = false;
                      _recordSwipeDx = 0.0;
                    });
                  }
                  _stopAndSendRecording();
                },
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: _primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.38),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
      ],
    );
  }

  Widget _buildWaveformBars(double amplitude) {
    const barCount = 24;
    const maxH = 22.0;
    const minH = 3.0;
    final hasAudio = amplitude > -40.0;
    final t = _recordingAnimController?.value ?? 0.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(barCount, (i) {
        final phase = (i / barCount) * 2 * pi;
        final h = hasAudio
            ? minH + (maxH - minH) * (0.5 + 0.5 * sin(2 * pi * t + phase))
            : minH;
        return Container(
          width: 3,
          height: h,
          decoration: BoxDecoration(
            gradient: hasAudio
                ? LinearGradient(
                    colors: [
                      _accentColor.withValues(alpha: 0.85),
                      _accentColor.withValues(alpha: 0.45),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
            color: hasAudio ? null : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  // ── INLINE CALL BUBBLE ───────────────────────────────────────────────────

  Widget _buildInlineCallBubble({
    required String callType,
    required String callStatus,
    required int duration,
    required String callerId,
    required DateTime timestamp,
    required Map<String, dynamic> messageData,
  }) {
    final isVideo = callType == 'video';
    final isOutgoing = callerId == widget.currentUserId;
    final callLabel = isVideo ? 'Video' : 'Voice';

    Color iconColor;
    IconData directionIcon;
    String label;
    String subtitle = '';
    Color bubbleColor;
    Color borderColor;

    switch (callStatus) {
      case 'completed':
        iconColor = const Color(0xFF25D366);
        directionIcon = isOutgoing
            ? (isVideo ? Icons.videocam : Icons.call_made)
            : (isVideo ? Icons.videocam : Icons.call_received);
        label = isOutgoing
            ? 'Outgoing $callLabel Call'
            : 'Incoming $callLabel Call';
        if (duration > 0) {
          final m = duration ~/ 60;
          final s = duration % 60;
          subtitle = m > 0 ? '${m}m ${s}s' : '${s}s';
        }
        bubbleColor = Colors.white;
        borderColor = Colors.grey.withValues(alpha: 0.25);
        break;

      case 'missed':
        if (isOutgoing) {
          iconColor = Colors.amber[700]!;
          directionIcon =
              isVideo ? Icons.videocam_off : Icons.call_missed_outgoing;
          label = 'No Answer';
          subtitle = isVideo
              ? 'They didn\'t pick up the video call'
              : 'They didn\'t pick up';
          bubbleColor = Colors.amber.withValues(alpha: 0.06);
          borderColor = Colors.amber.withValues(alpha: 0.35);
        } else {
          iconColor = Colors.red;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          label = 'Missed $callLabel Call';
          bubbleColor = Colors.red.withValues(alpha: 0.06);
          borderColor = Colors.red.withValues(alpha: 0.3);
        }
        break;

      case 'declined':
        if (isOutgoing) {
          iconColor = Colors.red[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = '$callLabel Call Declined';
          subtitle = 'Declined by recipient';
          bubbleColor = Colors.red.withValues(alpha: 0.06);
          borderColor = Colors.red.withValues(alpha: 0.3);
        } else {
          iconColor = Colors.indigo[400]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = 'You Declined';
          subtitle = isVideo
              ? 'You declined the video call'
              : 'You declined the call';
          bubbleColor = Colors.indigo.withValues(alpha: 0.05);
          borderColor = Colors.indigo.withValues(alpha: 0.22);
        }
        break;

      case 'cancelled':
        if (isOutgoing) {
          iconColor = Colors.grey[600]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_end;
          label = 'Call Cancelled';
          subtitle = 'You cancelled before connecting';
          bubbleColor = Colors.grey.withValues(alpha: 0.06);
          borderColor = Colors.grey.withValues(alpha: 0.25);
        } else {
          iconColor = Colors.orange[700]!;
          directionIcon = isVideo ? Icons.videocam_off : Icons.call_missed;
          label = 'Missed $callLabel Call';
          subtitle = 'Caller cancelled';
          bubbleColor = Colors.orange.withValues(alpha: 0.06);
          borderColor = Colors.orange.withValues(alpha: 0.3);
        }
        break;

      case 'busy':
        iconColor = Colors.orange[700]!;
        directionIcon = isVideo ? Icons.videocam_off : Icons.phone_locked;
        label = isOutgoing ? 'User Was Busy' : 'You Were Busy';
        subtitle = isOutgoing
            ? 'Recipient was on another call'
            : 'You were on another call';
        bubbleColor = Colors.orange.withValues(alpha: 0.06);
        borderColor = Colors.orange.withValues(alpha: 0.3);
        break;

      default:
        iconColor = Colors.grey[500]!;
        directionIcon = isVideo ? Icons.videocam_off : Icons.phone_missed;
        label = '$callLabel Call';
        bubbleColor = Colors.grey.withValues(alpha: 0.05);
        borderColor = Colors.grey.withValues(alpha: 0.2);
    }

    final timeStr = _formatTime(timestamp);

    final bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(directionIcon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: iconColor,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(timeStr,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );

    final overlayData = {
      ...messageData,
      'messageType': messageData['messageType'] ?? 'call',
      'callerId': callerId,
      'callType': callType,
      'callStatus': callStatus,
      'duration': duration,
    };

    return _swipeableMessage(
      messageData: overlayData,
      isMine: isOutgoing,
      child: GestureDetector(
        onLongPressStart: (details) {
          if (mounted) {
            setState(() {
              selectedMessage = overlayData;
              selectedMine = isOutgoing;
              showActionOverlay = true;
              _selectedMessageOffset = details.globalPosition;
            });
          }
        },
        child: bubble,
      ),
    );
  }

  // ── DATE GROUPING ────────────────────────────────────────────────────────

  List<String> _sortDateKeysChronologically(List<String> dateKeys) {
    final uniqueKeys = dateKeys.toSet().toList();
    uniqueKeys.sort((a, b) {
      DateTime dateA, dateB;
      if (a == 'Today') {
        dateA = DateTime.now();
      } else if (a == 'Yesterday') {
        dateA = DateTime.now().subtract(const Duration(days: 1));
      } else {
        try {
          dateA = DateFormat('MMM dd, yyyy').parse(a);
        } catch (_) {
          dateA = DateTime.now();
        }
      }
      if (b == 'Today') {
        dateB = DateTime.now();
      } else if (b == 'Yesterday') {
        dateB = DateTime.now().subtract(const Duration(days: 1));
      } else {
        try {
          dateB = DateFormat('MMM dd, yyyy').parse(b);
        } catch (_) {
          dateB = DateTime.now();
        }
      }
      return dateA.compareTo(dateB);
    });
    return uniqueKeys;
  }

  String _formatDateForGrouping(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate =
        DateTime(localDate.year, localDate.month, localDate.day);
    if (messageDate == today) return 'Today';
    if (messageDate == yesterday) return 'Yesterday';
    return DateFormat('MMM dd, yyyy').format(localDate);
  }

  Widget _dateSeparator(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            date,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
