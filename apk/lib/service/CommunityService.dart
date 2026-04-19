import 'dart:convert';
import 'package:http/http.dart' as http;

class UserReligionService {
  final String baseUrl;

  UserReligionService({required this.baseUrl});

  /// Insert or update religion and community details
  Future<Map<String, dynamic>> updateUserReligion({
    required int userId,
    int? religionId,
    int? communityId,
    int? subCommunityId,
    String? castlanguage,
  }) async {
    final url = Uri.parse(baseUrl);

    // Prepare POST body
    final body = <String, String>{
      'user_id': userId.toString(),
      if (religionId != null) 'religionId': religionId.toString(),
      if (communityId != null) 'communityId': communityId.toString(),
      if (subCommunityId != null) 'subCommunityId': subCommunityId.toString(),
      if (castlanguage != null) 'castlanguage': castlanguage,
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        return {
          'status': 'error',
          'message': 'Server returned status code ${response.statusCode}'
        };
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
