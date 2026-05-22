// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of chatdetails_screen;

extension _ChatDetailsComposePreviewWidgets on _ChatDetailScreenState {
  Widget _buildReplyPreview() {
    if (!isReplying || repliedMessage == null) return const SizedBox.shrink();

    final isMyMessage = repliedMessage!['senderId'] == widget.currentUserId;
    final senderName = isMyMessage ? 'You' : widget.receiverName;
    final messageType = repliedMessage!['messageType'] ?? 'text';
    final message = repliedMessage!['message'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: _secondaryGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: _accentColor,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $senderName',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                if (messageType == 'text')
                  Text(
                    message?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _lightTextColor),
                  )
                else if (messageType == 'image')
                  Row(
                    children: [
                      Icon(Icons.image, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Photo',
                          style:
                              TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'image_gallery')
                  Row(
                    children: [
                      Icon(Icons.photo_library, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Photos',
                          style:
                              TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'voice')
                  Row(
                    children: [
                      Icon(Icons.mic, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Voice message',
                          style:
                              TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'call')
                  Row(
                    children: [
                      Icon(Icons.call, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Voice call',
                          style:
                              TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'video_call')
                  Row(
                    children: [
                      Icon(Icons.videocam, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Video call',
                          style:
                              TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else if (messageType == 'profile_card')
                  Row(
                    children: [
                      Icon(Icons.person, size: 15, color: _accentColor),
                      const SizedBox(width: 4),
                      Text('Profile card',
                          style:
                              TextStyle(fontSize: 13, color: _lightTextColor)),
                    ],
                  )
                else
                  Text(
                    message ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: _lightTextColor),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // EDIT PREVIEW WIDGET
  Widget _buildEditPreview() {
    if (!isEditing || editingMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: _secondaryGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _accentColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  editingMessage!['message']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _lightTextColor),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelEdit,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
