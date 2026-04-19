import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ms2026/Auth/Screen/signupscreen10.dart';
import 'package:ms2026/Chat/ChatdetailsScreen.dart';
import 'package:ms2026/Models/masterdata.dart';
import 'package:ms2026/Notification/notification_inbox_service.dart';
import 'package:ms2026/Package/PackageScreen.dart';
import 'package:ms2026/otherenew/othernew.dart';
import 'package:ms2026/pushnotification/pushservice.dart';
import 'package:ms2026/purposal/purposalservice.dart';
import 'package:ms2026/utils/image_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'Purposalmodel.dart';
import 'package:ms2026/config/app_endpoints.dart';

class RequestCardDynamic extends StatefulWidget {
  final ProposalModel data;
  final int tabIndex;
  final String userid;
  final VoidCallback? onActionComplete;

  RequestCardDynamic({
    super.key,
    required this.data,
    required this.tabIndex,
    required this.userid,
    this.onActionComplete,
  });

  @override
  State<RequestCardDynamic> createState() => _RequestCardDynamicState();
}

class _RequestCardDynamicState extends State<RequestCardDynamic> {
  String usertye = '';
  String userimage = '';
  var pageno;
  var docstatus = 'not_uploaded';
  bool _isLoading = false;
  bool _isCheckingStatus = false;

  @override
  void initState() {
    super.initState();
    loadMasterData();
    _checkDocumentStatus();
  }

  Future<UserMasterData> fetchUserMasterData(String userId) async {
    final url = Uri.parse(
      "${kApiBaseUrl}/Api2/masterdata.php?userid=$userId",
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception("Failed: ${response.statusCode}");
    }

    final res = json.decode(response.body);

    if (res['success'] != true) {
      throw Exception(res['message'] ?? "API error");
    }

    return UserMasterData.fromJson(res['data']);
  }

  void loadMasterData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    final userData = jsonDecode(userDataString!);
    final userId = int.tryParse(userData["id"].toString());

    try {
      UserMasterData user = await fetchUserMasterData(userId.toString());

      setState(() {
        usertye = user.usertype;
        userimage = user.profilePicture;
        pageno = user.pageno;
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> _checkDocumentStatus() async {
    if (_isCheckingStatus) return;

    setState(() {
      _isCheckingStatus = true;
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      final userData = jsonDecode(userDataString!);
      final userId = int.tryParse(userData["id"].toString());

      final response = await http.post(
        Uri.parse("${kApiBaseUrl}/Api2/check_document_status.php"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['success'] == true) {
          setState(() {
            docstatus = result['status'] ?? 'not_uploaded';
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking document status: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Unable to check document status right now. Please try again later.",
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
        _isCheckingStatus = false;
      });
    }
  }

  // Determine if current user is the receiver
  bool get _isReceiver => widget.data.receiverId == widget.userid;

  // Determine if request is pending
  bool get _isPending => widget.data.status?.toLowerCase() == 'pending';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Colored header strip: request type + status chip
          _buildCardHeader(),

          // Main content row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileImage(),
                const SizedBox(width: 14),
                Expanded(child: _buildUserDetails()),
                const SizedBox(width: 8),
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
    final type = widget.data.requestType ?? 'Request';
    final typeColor = _getTypeColor(type);
    final typeIcon = _getTypeIcon(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.07),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        border: Border(
          bottom: BorderSide(
            color: typeColor.withOpacity(0.12),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(typeIcon, color: typeColor, size: 16),
              const SizedBox(width: 7),
              Text(
                '$type Request',
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          _buildStatusChip(),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    final status = widget.data.status ?? 'pending';
    Color chipColor;
    String label;

    switch (status.toLowerCase()) {
      case 'accepted':
        chipColor = const Color(0xFF2E7D32);
        label = 'Accepted';
        break;
      case 'rejected':
        chipColor = const Color(0xFFC62828);
        label = 'Rejected';
        break;
      default:
        chipColor = const Color(0xFFF57C00);
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withOpacity(0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chipColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: chipColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'photo':
        return const Color(0xFF6A1B9A);
      case 'chat':
        return const Color(0xFF1565C0);
      case 'profile':
        return const Color(0xFF00695C);
      default:
        return const Color(0xFFD32F2F);
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'photo':
        return Icons.photo_library_outlined;
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
      case 'profile':
        return Icons.person_outline_rounded;
      default:
        return Icons.favorite_border_rounded;
    }
  }

  Widget _buildUserDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                "MS: ${widget.data.memberid ?? ''} ${widget.data.lastName ?? ''}".trim(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.data.verified ?? false)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF1976D2),
                  size: 15,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _buildDetailRow(
            Icons.location_on_outlined, widget.data.city ?? 'Kathmandu'),
        const SizedBox(height: 2),
        _buildDetailRow(
            Icons.work_outline, widget.data.occupation ?? 'N/A'),
        _buildDetailRow(
            Icons.favorite_border, widget.data.maritalstatus ?? 'Single'),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    // For received pending requests (current user is receiver)
    if (_isReceiver && _isPending) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionButton(
            label: 'Accept',
            icon: Icons.check_rounded,
            color: const Color(0xFF2E7D32),
            onTap: _handleAcceptRequest,
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Reject',
            icon: Icons.close_rounded,
            color: Colors.grey.shade400,
            onTap: _handleRejectRequest,
          ),
        ],
      );
    }

    // For accepted chat requests
    if (widget.data.status == 'accepted' && widget.data.requestType == 'Chat') {
      return _actionButton(
        label: 'Chat',
        icon: Icons.chat_bubble_outline_rounded,
        color: const Color(0xFF1565C0),
        onTap: _handleChatNavigation,
      );
    }

    // For accepted profile requests
    if (widget.data.status == 'accepted' && widget.data.requestType == 'Profile') {
      return _actionButton(
        label: 'Profile',
        icon: Icons.person_outline_rounded,
        color: const Color(0xFF00695C),
        onTap: () {},
      );
    }

    // For accepted photo requests
    if (widget.data.status == 'accepted' && widget.data.requestType == 'Photo') {
      return _actionButton(
        label: 'Photos',
        icon: Icons.photo_library_outlined,
        color: const Color(0xFF6A1B9A),
        onTap: () {
          if (docstatus == "approved" && usertye == "paid") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(
                  userId: widget.data.memberid.toString(),
                ),
              ),
            );
          }
          if (docstatus == "not_uploaded" ||
              docstatus == "rejected" ||
              docstatus == "pending") {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => IDVerificationScreen()));
          }
          if (usertye == "free" && docstatus == "approved") {
            Navigator.push(context,
                MaterialPageRoute(builder: (context) => SubscriptionPage()));
          }
        },
      );
    }

    // For sent pending requests (current user is sender)
    if (widget.data.senderId == widget.userid && _isPending) {
      return _actionButton(
        label: 'Cancel',
        icon: Icons.cancel_outlined,
        color: const Color(0xFFC62828),
        onTap: _handleCancelRequest,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileImage() {
    final imageUrl =
        widget.data.profilePicture ?? "https://via.placeholder.com/150";
    final type = widget.data.requestType ?? 'Request';
    final typeColor = _getTypeColor(type);
    final privacy = widget.data.privacy?.toLowerCase() ?? '';
    final photoRequest = widget.data.photoRequest?.toLowerCase() ?? '';
    final shouldShowClear = privacy == 'free' || photoRequest == 'accepted';

    Widget profileImg = Image.network(
      imageUrl,
      width: 67,
      height: 67,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: Icon(Icons.person, color: Colors.grey.shade400, size: 32),
      ),
      loadingBuilder: (_, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey.shade200,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: typeColor,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );

    if (!shouldShowClear) {
      profileImg = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: profileImg,
      );
    }

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [typeColor.withOpacity(0.7), typeColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: typeColor.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: ClipOval(child: profileImg),
      ),
    );
  }

  // Action Handlers
  Future<void> _handleAcceptRequest() async {
    // Step 1: Check document verification
    if (docstatus != 'approved') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => IDVerificationScreen()),
      );
      return;
    }

    // Step 2: Check payment / subscription
    if (usertye != 'paid') {
      _showUpgradeDialog();
      return;
    }

    // Step 3: Confirm and accept
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Accept Request"),
        content: const Text(
          "Are you sure you want to accept this request?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Accept"),
          ),
        ],
      ),
    );

    if (confirm) {
      try {
        bool success = await ProposalService.acceptProposal(
          widget.data.proposalId.toString(),
          widget.userid,
        );

        if (success) {
          final senderName = await NotificationInboxService.getCurrentUserDisplayName();
          await NotificationService.sendRequestAccepted(
            recipientUserId: widget.data.senderId ?? '',
            senderName: senderName,
            senderId: widget.userid,
            requestType: widget.data.requestType ?? 'Request',
          );
          await NotificationInboxService.markRequestResolved(
            peerUserId: widget.data.senderId ?? '',
            requestType: widget.data.requestType ?? 'Request',
            status: 'accepted',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Request accepted successfully"),
              backgroundColor: Colors.green,
            ),
          );

          widget.onActionComplete?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to accept request"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print("Error accepting proposal: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFFff0000), Color(0xFF2575FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Upgrade to Accept",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Upgrade your plan to accept chat requests and start chatting.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Skip",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SubscriptionPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          "Upgrade",
                          style: TextStyle(
                            color: Color(0xFFff0000),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRejectRequest() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Request"),
        content: const Text(
          "Are you sure you want to reject this request?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Reject"),
          ),
        ],
      ),
    );

    if (confirm) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        bool success = await ProposalService.rejectProposal(
          widget.data.proposalId.toString(),
          widget.userid,
        );

        if (context.mounted) {
          Navigator.pop(context);
        }

        if (success) {
          final senderName = await NotificationInboxService.getCurrentUserDisplayName();
          await NotificationService.sendRequestRejected(
            recipientUserId: widget.data.senderId ?? '',
            senderName: senderName,
            senderId: widget.userid,
            requestType: widget.data.requestType ?? 'Request',
          );
          await NotificationInboxService.markRequestResolved(
            peerUserId: widget.data.senderId ?? '',
            requestType: widget.data.requestType ?? 'Request',
            status: 'rejected',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Request rejected"),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );

          widget.onActionComplete?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to reject request"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
        }
        print("Error rejecting proposal: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleCancelRequest() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Request"),
        content: const Text(
          "Are you sure you want to cancel this request?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (confirm) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        bool success = await ProposalService.rejectProposal(
          widget.data.proposalId.toString(),
          widget.userid,
        );

        if (context.mounted) {
          Navigator.pop(context);
        }

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Request cancelled successfully"),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );

          widget.onActionComplete?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to cancel request"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
        }
        print("Error cancelling proposal: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleChatNavigation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');

      if (userDataString == null) {
        throw Exception('User data not found');
      }

      final userData = jsonDecode(userDataString);
      final currentUserIdStr = widget.userid.toString();
      final currentUserName = "${userData['id'] ?? ''} ${userData['lastName'] ?? ''}".trim();
      final currentUserImage =
          resolveApiImageUrl(userData['profile_picture']?.toString() ?? '');

      final isCurrentUserSender = currentUserIdStr == widget.data.senderId;
      final otherUserId = isCurrentUserSender
          ? (widget.data.receiverId ?? '')
          : (widget.data.senderId ?? '');

      // Use the other user's name from widget.data (which already contains the other user's info)
      final otherUserName = "MS: ${widget.data.memberid.toString() ?? ''} ${widget.data.firstName ?? ''} ${widget.data.lastName ?? ''}".trim();
      final otherUserImage =
          resolveApiImageUrl(widget.data.profilePicture ?? '');

      List<String> userIds = [currentUserIdStr, otherUserId];
      userIds.sort();
      final chatRoomId = userIds.join('_');

      // Chat room is auto-created by the Socket.IO server on first message send.
      // No need to pre-create it in Firestore.

      if (docstatus == "approved" && usertye == "paid") {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              chatRoomId: chatRoomId,
              receiverId: otherUserId,
              receiverName: otherUserName.isNotEmpty
                  ? otherUserName
                  : "User $otherUserId",
              receiverImage: otherUserImage.isNotEmpty
                  ? otherUserImage
                  : 'https://via.placeholder.com/150',
              currentUserId: currentUserIdStr,
              currentUserName: currentUserName.isNotEmpty
                  ? currentUserName
                  : "User $currentUserIdStr",
              currentUserImage: currentUserImage.isNotEmpty
                  ? currentUserImage
                  : 'https://via.placeholder.com/150',
            ),
          ),
        );
      }

      if (docstatus == "not_uploaded" || docstatus == "rejected" || docstatus == "pending") {
        Navigator.push(context, MaterialPageRoute(builder: (context) => IDVerificationScreen()));
      }

      if (usertye == "free" && docstatus == "approved") {
        showUpgradeDialog(context);
      }
    } catch (e) {
      print("Error navigating to chat: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open chat. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

void showUpgradeDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [
                Color(0xFFff0000),
                Color(0xFF2575FC),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),

              const SizedBox(height: 20),

              // Title
              const Text(
                "Upgrade to Chat",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              // Description
              const Text(
                "Unlock unlimited messaging and premium chat features by upgrading your plan.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 28),

              // Buttons
              Row(
                children: [
                  // Skip Button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Skip",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Upgrade Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => SubscriptionPage(),));
                        // Navigate to upgrade screen
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Upgrade",
                        style: TextStyle(
                          color: Color(0xFFff0000),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
