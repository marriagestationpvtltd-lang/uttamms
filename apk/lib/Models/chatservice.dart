import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io' if (dart.library.html) 'package:ms2026/utils/web_io_stub.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = Uuid();

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Send text message
// In FirebaseService class, update sendMessage:
  // In FirebaseService class, update sendMessage method:
  Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String message,
    required String messageType,
  }) async {
    try {
      print('=== DEBUG SEND MESSAGE ===');
      print('chatRoomId: $chatRoomId');
      print('senderId: $senderId (This should be YOUR ID)');
      print('receiverId: $receiverId (This should be OTHER PERSON ID)');
      print('message: $message');

      final timestamp = DateTime.now();
      final messageId = _uuid.v4();

      // Create message document
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .doc(messageId)
          .set({
        'messageId': messageId,
        'senderId': senderId,  // Should be YOUR ID
        'receiverId': receiverId,  // Should be OTHER PERSON ID
        'message': message,
        'messageType': messageType,
        'timestamp': timestamp,
        'isRead': false,
        'isDeletedForSender': false,
        'isDeletedForReceiver': false,
      });

      // CRITICAL FIX: Update chat room last message - use senderId NOT receiverId
      print('Updating chat room with lastMessageSenderId: $senderId');

      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': message,
        'lastMessageType': messageType,
        'lastMessageTime': timestamp,
        'lastMessageSenderId': senderId,  // FIX: Use senderId, not receiverId
        'unreadCount.$receiverId': FieldValue.increment(1),
      });

      print('=== MESSAGE SENT SUCCESSFULLY ===');

    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }
  // In FirebaseService class, update getOrCreateChatRoom:
  // In FirebaseService class, update getOrCreateChatRoom:
  // Make sure your getOrCreateChatRoom method stores correct participant names:
  // In FirebaseService class - CORRECTED VERSION:
  Future<String> getOrCreateChatRoom({
    required String user1Id,
    required String user2Id,
    required String user1Name,
    required String user2Name,
    required String user1Image,
    required String user2Image,
    String? user1Privacy,
    String? user2Privacy,
    String? user1PhotoRequest,
    String? user2PhotoRequest,
  }) async {
    try {
      // Create sorted IDs for consistent chat room ID
      final List<String> ids = [user1Id, user2Id]..sort();
      final chatRoomId = '${ids[0]}_${ids[1]}';

      final chatRoomDoc = await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .get();

      if (!chatRoomDoc.exists) {
        // CRITICAL FIX: Store names with correct ID mapping
        // user1Id should map to user1Name, user2Id should map to user2Name
        await _firestore.collection('chatRooms').doc(chatRoomId).set({
          'chatRoomId': chatRoomId,
          'participants': [user1Id, user2Id],
          'participantNames': {
            user1Id: user1Name,  // User ID 0 maps to their name
            user2Id: user2Name,  // User ID 194 maps to their name
          },
          'participantImages': {
            user1Id: user1Image,
            user2Id: user2Image,
          },
          'participantPrivacy': {
            user1Id: user1Privacy ?? 'free',
            user2Id: user2Privacy ?? 'free',
          },
          'participantPhotoRequests': {
            user1Id: user1PhotoRequest ?? '',
            user2Id: user2PhotoRequest ?? '',
          },
          'createdAt': DateTime.now(),
          'lastMessage': '',
          'lastMessageType': '',
          'lastMessageTime': DateTime.now(),
          'lastMessageSenderId': '',
          'unreadCount': {
            user1Id: 0,
            user2Id: 0,
          },
        });
      } else {
        // Update existing chat room if names/images/privacy changed
        await _firestore.collection('chatRooms').doc(chatRoomId).update({
          'participantNames': {
            user1Id: user1Name,
            user2Id: user2Name,
          },
          'participantImages': {
            user1Id: user1Image,
            user2Id: user2Image,
          },
          'participantPrivacy': {
            user1Id: user1Privacy ?? 'free',
            user2Id: user2Privacy ?? 'free',
          },
          'participantPhotoRequests': {
            user1Id: user1PhotoRequest ?? '',
            user2Id: user2PhotoRequest ?? '',
          },
        });
      }

      return chatRoomId;
    } catch (e) {
      print('Error creating chat room: $e');
      rethrow;
    }
  }
  // Send image message
  Future<void> sendImageMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required File imageFile,
  }) async {
    try {
      final timestamp = DateTime.now();
      final messageId = _uuid.v4();
      final fileName = 'chat_images/$chatRoomId/$messageId.jpg';

      // Upload image to Firebase Storage (cross-platform)
      final ref = _storage.ref().child(fileName);
      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        await ref.putData(bytes);
      } else {
        await ref.putFile(imageFile);
      }
      final imageUrl = await ref.getDownloadURL();

      // Create message document
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .doc(messageId)
          .set({
        'messageId': messageId,
        'senderId': senderId,
        'receiverId': receiverId,
        'message': imageUrl,
        'messageType': 'image',
        'timestamp': timestamp,
        'isRead': false,
        'isDeletedForSender': false,
        'isDeletedForReceiver': false,
      });

      // Update chat room
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': '📷 Image',
        'lastMessageType': 'image',
        'lastMessageTime': timestamp,
        'lastMessageSenderId': senderId,
        'unreadCount.$receiverId': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error sending image: $e');
      rethrow;
    }
  }

  // Send voice message
  Future<void> sendVoiceMessage({
    required String chatRoomId,
    required String senderId,
    required String receiverId,
    required String audioPath,
    required Duration duration,
  }) async {
    try {
      final timestamp = DateTime.now();
      final messageId = _uuid.v4();
      final fileName = 'voice_messages/$chatRoomId/$messageId.mp3';

      // Upload audio to Firebase Storage (cross-platform)
      final ref = _storage.ref().child(fileName);
      if (kIsWeb) {
        final xfile = XFile(audioPath);
        final bytes = await xfile.readAsBytes();
        await ref.putData(bytes);
      } else {
        await ref.putFile(File(audioPath));
      }
      final audioUrl = await ref.getDownloadURL();

      // Create message document
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .doc(messageId)
          .set({
        'messageId': messageId,
        'senderId': senderId,
        'receiverId': receiverId,
        'message': audioUrl,
        'messageType': 'voice',
        'duration': duration.inSeconds,
        'timestamp': timestamp,
        'isRead': false,
        'isDeletedForSender': false,
        'isDeletedForReceiver': false,
      });

      // Update chat room
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': '🎤 Voice message',
        'lastMessageType': 'voice',
        'lastMessageTime': timestamp,
        'lastMessageSenderId': senderId,
        'unreadCount.$receiverId': FieldValue.increment(1),
      });
    } catch (e) {
      print('Error sending voice message: $e');
      rethrow;
    }
  }

  // Get or create chat room


  // Get messages stream
  Stream<QuerySnapshot> getMessagesStream(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Get chat rooms for a user
// Get chat rooms for a user
  Stream<QuerySnapshot> getUserChatRooms(String userId) {
    print('FirebaseService.getUserChatRooms called with userId: $userId');
    print('userId type: ${userId.runtimeType}');

    return _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: userId)
        // orderBy omitted intentionally — avoids composite index requirement;
        // results are sorted client-side by lastMessageTime in ChatListScreen.
        .snapshots();
  }
  // Mark messages as read
  Future<void> markMessagesAsRead({
    required String chatRoomId,
    required String userId,
  }) async {
    try {
      // Update unread count
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'unreadCount.$userId': 0,
      });

      // Mark all unread messages as read
      final unreadMessages = await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .where('receiverId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  // Delete message
  Future<void> deleteMessage({
    required String chatRoomId,
    required String messageId,
    required String userId,
    required bool deleteForEveryone,
  }) async {
    try {
      if (deleteForEveryone) {
        // Delete for everyone
        await _firestore
            .collection('chatRooms')
            .doc(chatRoomId)
            .collection('messages')
            .doc(messageId)
            .delete();
      } else {
        // Delete only for me
        final messageDoc = await _firestore
            .collection('chatRooms')
            .doc(chatRoomId)
            .collection('messages')
            .doc(messageId)
            .get();

        if (messageDoc.exists) {
          final data = messageDoc.data() as Map<String, dynamic>;
          final senderId = data['senderId'];

          if (userId == senderId) {
            await messageDoc.reference.update({'isDeletedForSender': true});
          } else {
            await messageDoc.reference.update({'isDeletedForReceiver': true});
          }
        }
      }
    } catch (e) {
      print('Error deleting message: $e');
      rethrow;
    }
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String userId,
    required String name,
    required String email,
    required String? imageUrl,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'userId': userId,
        'name': name,
        'email': email,
        'imageUrl': imageUrl,
        'lastSeen': DateTime.now(),
        'isOnline': true,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  // Upload profile image
  Future<String> uploadProfileImage(String userId, File imageFile) async {
    try {
      final fileName = 'profile_images/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(fileName);
      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        await ref.putData(bytes);
      } else {
        await ref.putFile(imageFile);
      }
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading profile image: $e');
      rethrow;
    }
  }

  // Pick image from gallery
  Future<XFile?> pickImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      return pickedFile;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }
}