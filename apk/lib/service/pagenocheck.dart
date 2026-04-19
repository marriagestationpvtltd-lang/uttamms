import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class PageService {
  static const String apiUrl = "${kApiBaseUrl}/Api2/get_page.php";

  static Future<int?> getPageNo(int userId) async {
    try {
      final url = Uri.parse("$apiUrl?user_id=$userId");
      final res = await http.get(url).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json["status"] == "success") {
          return int.tryParse(json["data"]["pageno"].toString());
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
