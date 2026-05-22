// ignore_for_file: use_string_in_part_of_directives, invalid_use_of_protected_member
part of chatdetails_screen;

extension _ChatDetailsComposePreviewWidgets on _ChatDetailScreenState {
  Widget _buildReplyPreview() {
    if (!isReplying || repliedMessage == null) return const SizedBox.shrink();

    final isMyMessage = repliedMessage!['senderId'] == widget.currentUserId;
    final senderName = isMyMessage ? 'You' : widget.receiverName;
    final messageType = repliedMessage!['messageType'] ?? 'text';
    final message = repliedMessage!['message'];

    // Reply snippet type icon + label helper
    Widget typeRow(IconData icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _accentColor),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF444444),
                    fontWeight: FontWeight.w500)),
          ],
        );

    Widget snippetWidget;
    switch (messageType) {
      case 'image':
        snippetWidget = typeRow(Icons.image_outlined, 'Photo');
        break;
      case 'image_gallery':
        snippetWidget = typeRow(Icons.photo_library_outlined, 'Photos');
        break;
      case 'voice':
        snippetWidget = typeRow(Icons.mic_outlined, 'Voice message');
        break;
      case 'call':
        snippetWidget = typeRow(Icons.call_outlined, 'Voice call');
        break;
      case 'video_call':
        snippetWidget = typeRow(Icons.videocam_outlined, 'Video call');
        break;
      case 'profile_card':
        snippetWidget = typeRow(Icons.person_outline, 'Profile card');
        break;
      default:
        snippetWidget = Text(
          message?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
        );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F3),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _accentColor, width: 4),
          top: BorderSide(color: _accentColor.withValues(alpha: 0.15), width: 1),
          right: BorderSide(color: _accentColor.withValues(alpha: 0.15), width: 1),
          bottom: BorderSide(color: _accentColor.withValues(alpha: 0.15), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.08),
            blurRadius: 8,
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
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 3),
                snippetWidget,
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cancelReply,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded, size: 14, color: _accentColor),
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
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F3),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: _accentColor, width: 4),
          top: BorderSide(color: _accentColor.withValues(alpha: 0.15), width: 1),
          right: BorderSide(color: _accentColor.withValues(alpha: 0.15), width: 1),
          bottom: BorderSide(color: _accentColor.withValues(alpha: 0.15), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, size: 15, color: _accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing message',
                  style: TextStyle(
                    fontSize: 12,
                    color: _accentColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  editingMessage!['message']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF444444),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _cancelEdit,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close_rounded, size: 14, color: _accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
