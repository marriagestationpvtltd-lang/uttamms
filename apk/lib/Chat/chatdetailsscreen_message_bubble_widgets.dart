// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of chatdetails_screen;

extension _ChatDetailsMessageBubbleWidgets on _ChatDetailScreenState {
  // SWIPEABLE MESSAGE WIDGET
  Widget _swipeableMessage({
    required Widget child,
    required Map<String, dynamic> messageData,
    required bool isMine,
  }) {
    return _SwipeToReplyWrapper(
      isMine: isMine,
      onReply: () => _setReplyMessage(messageData),
      onDragStart: () {
        if (mounted) setState(() => _isHorizontalDragging = true);
      },
      onDragEnd: () {
        if (mounted) setState(() => _isHorizontalDragging = false);
      },
      child: child,
    );
  }

  // Message bubble with swipe reply
  Widget _messageBubble({
    required bool isMine,
    required String text,
    required DateTime timestamp,
    required String messageType,
    required bool isRead,
    required bool isDelivered,
    required int? duration,
    required Map<String, dynamic> messageData,
    required Map<String, dynamic>? repliedTo,
    required bool isEdited,
    bool isDeleted = false,
  }) {
    // Show a WhatsApp-style "This message was deleted" placeholder
    if (isDeleted) {
      return Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  'This message was deleted',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final msgId = messageData['messageId'] as String? ?? '';
    final bool isPendingSend = messageData['isPendingSend'] == true;
    // Assign a stable GlobalKey so we can scroll to this message
    final key = _messageKeys.putIfAbsent(msgId, () => GlobalKey());

    final time = _formatTime(timestamp);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isHighlighted = _highlightedMessageId == msgId;

    // Build the reply snippet widget (tappable to scroll to source)
    Widget? replyWidget;
    if (repliedTo != null) {
      final replyType = repliedTo['messageType']?.toString() ?? 'text';
      final replyImgUrl = (replyType == 'image' || replyType == 'image_gallery')
          ? (repliedTo['message']?.toString() ?? '')
          : null;
      final replySnippet = _replySnippetText(repliedTo);
      final senderName = repliedTo['senderName']?.toString() ?? 'User';

      // Sent-bubble overlay: white semi-transparent. Received: brand gradient.
      final replyBg = isMine ? Colors.white.withValues(alpha: 0.15) : null;
      final replyGradient = isMine ? null : _secondaryGradient;
      final replyBorderColor =
          isMine ? Colors.white.withValues(alpha: 0.55) : _accentColor;
      final replyNameColor = isMine ? Colors.white : _accentColor;
      final replyTextColor =
          isMine ? Colors.white.withValues(alpha: 0.75) : _lightTextColor;
      final replyIconColor =
          isMine ? Colors.white.withValues(alpha: 0.65) : _accentColor;

      IconData? typeIcon;
      if (replyType == 'voice') typeIcon = Icons.mic;
      if (replyType == 'image' || replyType == 'image_gallery') {
        typeIcon = Icons.image;
      }

      replyWidget = GestureDetector(
        onTap: () {
          final replyId = repliedTo['messageId'] as String?;
          if (replyId != null) _scrollToMessage(replyId);
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: replyBg,
            gradient: replyGradient,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: replyBorderColor, width: 3.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: replyNameColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (typeIcon != null) ...[
                          Icon(typeIcon, size: 12, color: replyIconColor),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            replySnippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: replyTextColor,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Thumbnail for image replies
              if (replyImgUrl != null && replyImgUrl.isNotEmpty) ...[
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: replyImgUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey.shade300,
                      child: Icon(Icons.image,
                          size: 18, color: Colors.grey.shade500),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Choose tick icon based on delivery/read state
    Widget buildTick() {
      if (isPendingSend) {
        return Icon(Icons.schedule, size: 16, color: Colors.orange.shade700);
      } else if (isRead) {
        return Icon(Icons.done_all, size: 16, color: const Color(0xFF34B7F1));
      } else if (isDelivered) {
        return Icon(Icons.done_all, size: 16, color: Colors.grey.shade500);
      } else {
        return Icon(Icons.done, size: 16, color: Colors.grey.shade500);
      }
    }

    Widget messageContent = GestureDetector(
      onLongPressStart: (details) {
        if (mounted) {
          setState(() {
            selectedMessage = messageData;
            selectedMine = isMine;
            showActionOverlay = true;
            _selectedMessageOffset = details.globalPosition;
          });
        }
      },
      child: Container(
        key: key,
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        decoration: BoxDecoration(
          color: isHighlighted
              ? _accentColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (replyWidget != null) replyWidget,
                Container(
                  padding: (messageType == 'image' ||
                          messageType == 'image_gallery' ||
                          messageType == 'profile_card' ||
                          messageType == 'report')
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: screenWidth * 0.75,
                  ),
                  clipBehavior: (messageType == 'image' ||
                          messageType == 'image_gallery' ||
                          messageType == 'profile_card' ||
                          messageType == 'report')
                      ? Clip.antiAlias
                      : Clip.none,
                  decoration: messageType == 'report'
                      ? const BoxDecoration(color: Colors.transparent)
                      : messageType == 'profile_card'
                          ? BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: _accentColor.withValues(alpha: 0.18),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            )
                          : BoxDecoration(
                              gradient: isMine ? _primaryGradient : null,
                              color: isMine ? null : _receivedBubbleColor,
                              border: isMine
                                  ? null
                                  : Border.all(
                                      color: _receivedBubbleBorder,
                                      width: 1,
                                    ),
                              borderRadius: isMine
                                  ? const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                      bottomLeft: Radius.circular(20),
                                      bottomRight: Radius.circular(4),
                                    )
                                  : const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                      bottomLeft: Radius.circular(4),
                                      bottomRight: Radius.circular(20),
                                    ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMessageContent(
                        text: text,
                        messageType: messageType,
                        isMine: isMine,
                        duration: duration,
                        messageId: messageData['messageId'] ?? '',
                        messageData: messageData,
                      ),
                      if (isEdited)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Edited',
                            style: TextStyle(
                              fontSize: 10,
                              color: isMine ? Colors.white70 : _lightTextColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(
                        color: _lightTextColor,
                        fontSize: 12,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: isPendingSend
                            ? () => _retrySinglePendingOutgoingMessage(msgId)
                            : null,
                        child: buildTick(),
                      ),
                      if (isPendingSend) ...[
                        const SizedBox(width: 4),
                        Text(
                          'Retry',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ]
                  ],
                ),
                // Reaction badge below the bubble
                Builder(builder: (_) {
                  final raw = messageData['reactions'];
                  if (raw == null) return const SizedBox.shrink();
                  final Map<String, dynamic> rxns =
                      (raw is Map) ? Map<String, dynamic>.from(raw) : {};
                  if (rxns.isEmpty) return const SizedBox.shrink();
                  return _buildReactionBadge(rxns, isMine);
                }),
              ],
            ),
            if (isMine) ...[
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );

    // Wrap with MouseRegion on web for hover quick-actions
    if (kIsWeb) {
      messageContent = MouseRegion(
        onEnter: (_) => setState(() => _hoveredMessageId = msgId),
        onExit: (_) => setState(() {
          if (_hoveredMessageId == msgId) _hoveredMessageId = null;
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            messageContent,
            if (_hoveredMessageId == msgId)
              Positioned(
                top: 0,
                right: isMine ? null : -80,
                left: isMine ? -80 : null,
                child: _buildHoverActions(messageData, isMine),
              ),
          ],
        ),
      );
    }

    return _swipeableMessage(
      child: messageContent,
      messageData: messageData,
      isMine: isMine,
    );
  }

  /// Small row of quick-action buttons shown on hover (web only).
  Widget _buildHoverActions(Map<String, dynamic> msg, bool isMine) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          const BoxShadow(
              color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _hoverActionBtn(Icons.reply, () => _setReplyMessage(msg)),
          if (isMine && msg['messageType'] == 'text')
            _hoverActionBtn(Icons.edit, () => _setEditMessage(msg)),
          _hoverActionBtn(Icons.delete, () {
            setState(() {
              selectedMessage = msg;
              selectedMine = isMine;
              showDeletePopup = true;
            });
          }, color: Colors.red),
        ],
      ),
    );
  }

  Widget _hoverActionBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: color ?? Colors.grey[700]),
      ),
    );
  }

  Widget _buildReactionBadge(Map<String, dynamic> reactions, bool isMine) {
    final Map<String, int> emojiCounts = {};
    for (final emoji in reactions.values) {
      final e = emoji.toString();
      emojiCounts[e] = (emojiCounts[e] ?? 0) + 1;
    }
    if (emojiCounts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        left: isMine ? 0 : 4,
        right: isMine ? 4 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: emojiCounts.entries.map((entry) {
          final count = entry.value;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _accentColor.withValues(alpha: 0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 13)),
                if (count > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      color: _lightTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessageContent({
    required String text,
    required String messageType,
    required bool isMine,
    required int? duration,
    required String messageId,
    Map<String, dynamic>? messageData,
  }) {
    // Resolve the effective image URL: prefer text (data['message']), then fall
    // back to the decoded `images` array returned by the server API.
    String resolveText() {
      if (text.isNotEmpty) return text;
      final imgs = messageData?['images'];
      if (imgs is List && imgs.isNotEmpty) {
        return imgs.first?.toString() ?? '';
      }
      return '';
    }

    switch (messageType) {
      case 'image':
        final String imageUrl = resolveText();
        final double imgWidth =
            MediaQuery.of(context).size.width * _kImageWidthFraction;
        final bool isUploading = messageData?['isUploading'] == true;

        // Only blur if not mine AND photo request is not accepted - ignore privacy
        final bool shouldBlur =
            !isMine && _photoRequestStatus.toLowerCase() != 'accepted';

        // Check if this is a base64 data URL (local preview)
        final bool isBase64 = imageUrl.startsWith('data:image/');

        if (shouldBlur) {
          return SizedBox(
            width: imgWidth,
            height: imgWidth * _kImageAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: isBase64
                      ? Image.memory(
                          base64Decode(imageUrl.split(',')[1]),
                          width: imgWidth,
                          height: imgWidth * _kImageAspectRatio,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Colors.grey[300],
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: imgWidth,
                          height: imgWidth * _kImageAspectRatio,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                          ),
                        ),
                ),
                Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade800.withValues(alpha: 0.9),
                          ),
                          child: const Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Photo Protected',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return GestureDetector(
          onTap: isBase64
              ? null
              : () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: Colors.black,
                      insetPadding: const EdgeInsets.all(8),
                      child: Stack(
                        children: [
                          InteractiveViewer(
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.contain,
                              errorWidget: (context, url, error) =>
                                  const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.white54, size: 64),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 16,
                            right: 16,
                            child: IconButton(
                              icon:
                                  const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: imgWidth,
                  minWidth: _kImageMinWidth,
                  maxHeight: _kImageMaxHeight,
                ),
                child: isBase64
                    ? Image.memory(
                        base64Decode(imageUrl.split(',')[1]),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => SizedBox(
                          width: imgWidth,
                          height: imgWidth * _kImageAspectRatio,
                          child: Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.grey.shade400)),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => SizedBox(
                          width: imgWidth,
                          height: imgWidth * _kImageAspectRatio,
                          child:
                              const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => SizedBox(
                          width: imgWidth,
                          height: imgWidth * _kImageAspectRatio,
                          child: Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.grey.shade400)),
                        ),
                      ),
              ),
              if (isUploading)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Uploading...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'image_gallery':
        return _buildImageGallery(text: text);
      case 'voice':
        final totalSecs = duration ?? 0;
        final bool isVoiceUploading = messageData?['isUploading'] == true;
        // While uploading show a compact sending indicator instead of play controls.
        if (isVoiceUploading) {
          return SizedBox(
            width: 210,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.20)
                        : _accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMine ? Colors.white : _accentColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: null,
                          minHeight: 4.5,
                          backgroundColor: isMine
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isMine ? Colors.white : _accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _formatDuration(totalSecs),
                        style: TextStyle(
                          color: isMine ? Colors.white70 : _lightTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        // A single ValueListenableBuilder on the combined audio state notifier
        // rebuilds only this bubble on each position/state tick; the message
        // list cache remains valid throughout playback.
        return RepaintBoundary(
          child: ValueListenableBuilder<_AudioPlaybackState>(
            valueListenable: _audioStateNotifier,
            builder: (context, audioState, _) {
              final isCurrentMessage = audioState.playingId == messageId;
              final isCurrentlyPlaying =
                  isCurrentMessage && audioState.isPlaying;
              final progressValue =
                  isCurrentMessage && audioState.duration.inSeconds > 0
                      ? (audioState.position.inMilliseconds /
                              audioState.duration.inMilliseconds)
                          .clamp(0.0, 1.0)
                      : 0.0;
              final displayTime =
                  isCurrentMessage && audioState.duration.inSeconds > 0
                      ? _formatDuration(audioState.position.inSeconds)
                      : _formatDuration(totalSecs);
              return GestureDetector(
                onTap: () => _toggleVoicePlayback(messageId, text),
                child: SizedBox(
                  width: 210,
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.20)
                              : _accentColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                          color: isMine ? Colors.white : _accentColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progressValue,
                                minHeight: 4.5,
                                backgroundColor: isMine
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : Colors.black.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isMine ? Colors.white : _accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              displayTime,
                              style: TextStyle(
                                color:
                                    isMine ? Colors.white70 : _lightTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      case 'report':
        return _buildReportCardWidget(text, isMine);
      case 'profile_card':
        return _buildProfileCardWidget(text, isMine);
      default:
        return Text(
          text,
          style: TextStyle(
            color: isMine ? Colors.white : _textColor,
            fontSize: 16,
            height: 1.4,
          ),
        );
    }
  }

  /// Builds a report card widget from a JSON-encoded report payload string.
  Widget _buildReportCardWidget(String jsonText, bool isMine) {
    Map<String, dynamic>? reportData;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) reportData = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    final reportReason = reportData?['reportReason']?.toString() ?? '';
    final reportedUserName = reportData?['reportedUserName']?.toString() ?? '';
    final reportedUserId = reportData?['reportedUserId']?.toString() ?? '';
    final initials = reportedUserName.isNotEmpty
        ? reportedUserName
            .trim()
            .split(' ')
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
            .take(2)
            .join()
        : '?';

    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDE7),
        border: Border.all(color: const Color(0xFFF9A825), width: 1.2),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft:
              isMine ? const Radius.circular(16) : const Radius.circular(4),
          bottomRight:
              isMine ? const Radius.circular(4) : const Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF9A825), Color(0xFFF57F17)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.flag_rounded, color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text(
                  'PROFILE REPORTED',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          // Reported user section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFF9A825),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reportedUserName.isNotEmpty)
                        Text(
                          reportedUserName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4A3000),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (reportedUserId.isNotEmpty)
                        Text(
                          'User ID: $reportedUserId',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(
              color: const Color(0xFFF9A825).withValues(alpha: 0.4),
              height: 1,
            ),
          ),
          // Reason section
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REPORT REASON',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF57F17),
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reportReason.isNotEmpty ? reportReason : 'No reason provided',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3000),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
