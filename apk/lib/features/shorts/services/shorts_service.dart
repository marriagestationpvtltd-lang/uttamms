import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../config/app_endpoints.dart';
import '../models/reel_item.dart';

class ShortsService {
  static Future<Map<String, dynamic>> uploadReel({
    required int userId,
    required String filePath,
    String caption = '',
    String privacy = 'public',
    bool allowComments = true,
    bool allowDuet = false,
    bool allowDownload = false,
    String soundUrl = '',
    String soundTitle = '',
    bool asAdmin = false,
    int? adminId,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse(kEndpointUploadReel));
    req.fields['user_id'] = '$userId';
    req.fields['caption'] = caption;
    req.fields['privacy'] = privacy;
    req.fields['allow_comments'] = allowComments ? '1' : '0';
    req.fields['allow_duet'] = allowDuet ? '1' : '0';
    req.fields['allow_download'] = allowDownload ? '1' : '0';
    if (asAdmin && (adminId ?? 0) > 0) {
      req.fields['as_admin'] = '1';
      req.fields['admin_id'] = '${adminId!}';
    }
    if (soundUrl.isNotEmpty) req.fields['sound_url'] = soundUrl;
    if (soundTitle.isNotEmpty) req.fields['sound_title'] = soundTitle;
    req.files.add(await http.MultipartFile.fromPath(
      'reel',
      filePath,
      contentType: MediaType('video', 'mp4'),
    ));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    final jsonBody = jsonDecode(body) as Map<String, dynamic>;
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(jsonBody['message']?.toString() ?? 'Upload failed');
    }
    return jsonBody;
  }

  static Future<Map<String, dynamic>> uploadStory({
    required int userId,
    required String filePath,
    required bool isImage,
    String caption = '',
    String privacy = 'public',
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse(kEndpointUploadStory));
    req.fields['user_id'] = '$userId';
    req.fields['caption'] = caption;
    req.fields['privacy'] = privacy;
    req.files.add(await http.MultipartFile.fromPath(
      'story',
      filePath,
      contentType:
          isImage ? MediaType('image', 'jpeg') : MediaType('video', 'mp4'),
    ));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    final jsonBody = jsonDecode(body) as Map<String, dynamic>;
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(jsonBody['message']?.toString() ?? 'Story upload failed');
    }
    return jsonBody;
  }

  static Future<(List<ReelItem>, int?, int?)> fetchReelFeed({
    required int userId,
    int? cursorId,
    int? offset,
    String sort = 'recent', // 'recent' | 'trending'
    int limit = 15,
  }) async {
    final uri = Uri.parse(kEndpointReelFeed).replace(queryParameters: {
      'user_id': '$userId',
      'sort': sort,
      if (sort == 'recent' && cursorId != null && cursorId > 0)
        'cursor_id': '$cursorId',
      if (sort == 'trending' && offset != null && offset > 0)
        'offset': '$offset',
      'limit': '$limit',
    });

    final res = await http.get(uri);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Failed to load reels');
    }

    final rows = (body['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => ReelItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final nextCursor = int.tryParse(body['next_cursor']?.toString() ?? '');
    final nextOffset = int.tryParse(body['next_offset']?.toString() ?? '');
    return (rows, nextCursor, nextOffset);
  }

  static Future<(bool liked, int likeCount)> react({
    required int userId,
    required int reelId,
    String action = 'toggle',
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointReactReel),
      headers: {'Content-Type': 'application/json'},
      body:
          jsonEncode({'user_id': userId, 'reel_id': reelId, 'action': action}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Like failed');
    }
    return (
      body['liked'] == true,
      int.tryParse(body['like_count']?.toString() ?? '') ?? 0,
    );
  }

  static Future<int> share({
    required int userId,
    required int reelId,
    String shareType = 'copy_link',
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointShareReel),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'user_id': userId, 'reel_id': reelId, 'share_type': shareType}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Share failed');
    }
    return int.tryParse(body['share_count']?.toString() ?? '') ?? 0;
  }

  static Future<int> addComment({
    required int userId,
    required int reelId,
    required String comment,
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointCommentReel),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'user_id': userId, 'reel_id': reelId, 'comment': comment}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Comment failed');
    }
    return int.tryParse(body['comment_count']?.toString() ?? '') ?? 0;
  }

  static Future<void> report({
    required int userId,
    required int reelId,
    required String reason,
    String note = '',
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointReportReel),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'reel_id': reelId,
        'reason': reason,
        'note': note,
      }),
    );

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Report failed');
    }
  }

  static Future<int> trackView({
    required int userId,
    required int reelId,
    int watchedSeconds = 2,
  }) async {
    try {
      final res = await http.post(
        Uri.parse(kEndpointViewReel),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'reel_id': reelId,
          'watched_seconds': watchedSeconds,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        return int.tryParse(body['view_count']?.toString() ?? '') ?? 0;
      }
    } catch (_) {
      // Keep feed smooth: do not break UX on analytics failure.
    }
    return 0;
  }

  static Future<(List<Map<String, dynamic>>, int?)> fetchComments({
    required int reelId,
    int? cursorId,
    int limit = 30,
  }) async {
    final uri = Uri.parse(kEndpointCommentReel).replace(queryParameters: {
      'reel_id': '$reelId',
      if (cursorId != null && cursorId > 0) 'cursor_id': '$cursorId',
      'limit': '$limit',
    });

    final res = await http.get(uri);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Failed to load comments');
    }

    final rows = (body['data'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final nextCursor = int.tryParse(body['next_cursor']?.toString() ?? '');
    return (rows, nextCursor);
  }

  static Future<List<Map<String, dynamic>>> fetchUserStories({
    required int userId,
    required int targetUserId,
  }) async {
    final uri = Uri.parse(kEndpointUserStories).replace(queryParameters: {
      'user_id': '$userId',
      'target_user_id': '$targetUserId',
    });

    final res = await http.get(uri);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Failed to load stories');
    }

    final data = body['data'];
    if (data is! Map) return const [];
    final stories = (data['stories'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return stories;
  }

  static Future<void> updateReelPrivacy({
    required int userId,
    required int reelId,
    required String privacy,
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointUpdateReelPrivacy),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'user_id': userId, 'reel_id': reelId, 'privacy': privacy}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(
          body['message']?.toString() ?? 'Failed to update reel privacy');
    }
  }

  static Future<void> deleteReel({
    required int userId,
    required int reelId,
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointDeleteReel),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'reel_id': reelId}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Failed to delete reel');
    }
  }

  static Future<void> updateStoryPrivacy({
    required int userId,
    required int storyId,
    required String privacy,
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointUpdateStoryPrivacy),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'user_id': userId, 'story_id': storyId, 'privacy': privacy}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(
          body['message']?.toString() ?? 'Failed to update story privacy');
    }
  }

  static Future<void> deleteStory({
    required int userId,
    required int storyId,
  }) async {
    final res = await http.post(
      Uri.parse(kEndpointDeleteStory),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'story_id': storyId}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || body['success'] != true) {
      throw Exception(body['message']?.toString() ?? 'Failed to delete story');
    }
  }
}
