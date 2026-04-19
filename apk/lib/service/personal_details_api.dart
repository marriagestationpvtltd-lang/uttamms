import 'dart:convert';
import 'package:http/http.dart' as http;

class UserPersonalDetailService {
  final String baseUrl;

  UserPersonalDetailService({required this.baseUrl});

  /// Fetch user personal details
  Future<Map<String, dynamic>> fetchUserPersonalDetail(int userId) async {
    try {
      final url = Uri.parse('$baseUrl?user_id=$userId');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
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

  /// Update or insert user personal detail
  Future<Map<String, dynamic>> saveUserPersonalDetail({
    required int userId,
    int? maritalStatusId,
    String? heightName,
    String? weightName,
    int? haveSpecs,
    int? anyDisability,
    String? disability,
    String? bloodGroup,
    String? complexion,
    String? bodyType,
    String? aboutMe,
    String? childStatus,
    String? childLiveWith,
  }) async {
    final url = Uri.parse(baseUrl);

    // Prepare request body
    final body = <String, String>{
      'user_id': userId.toString(),
      if (maritalStatusId != null) 'maritalStatusId': maritalStatusId.toString(),
      if (heightName != null) 'height_name': heightName,
      if (weightName != null) 'weight_name': weightName,
      if (haveSpecs != null) 'haveSpecs': haveSpecs.toString(),
      if (anyDisability != null) 'anyDisability': anyDisability.toString(),
      if (disability != null) 'Disability': disability,
      if (bloodGroup != null) 'bloodGroup': bloodGroup,
      if (complexion != null) 'complexion': complexion,
      if (bodyType != null) 'bodyType': bodyType,
      if (aboutMe != null) 'aboutMe': aboutMe,
      if (childStatus != null) 'childStatus': childStatus,
      if (childLiveWith != null) 'childLiveWith': childLiveWith,
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