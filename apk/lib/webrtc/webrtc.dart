import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ms2026/config/app_endpoints.dart';

class Webrtc {
  final int ide;
  final String cert;

  Webrtc({required this.ide, required this.cert});

  factory Webrtc.fromJson(Map<String, dynamic> json) {
    return Webrtc(
      ide: int.parse(json['ide'].toString()), // ✅ FIX
      cert: json['cert'],
    );
  }
}


Future<Webrtc?> fetchWebrtc() async {
  final String apiUrl = "${kApiBaseUrl}/Api2/webrtc.php";

  final response = await http.get(Uri.parse(apiUrl));

  if (response.statusCode == 200) {
    final Map<String, dynamic> jsonResponse = json.decode(response.body);

    if (jsonResponse['status'] == 'success') {
      List dataList = jsonResponse['data'];

      if (dataList.isNotEmpty) {
        return Webrtc.fromJson(dataList[0]); // ✅ FIX
      } else {
        return null;
      }
    } else {
      print("API error: ${jsonResponse['message']}");
      return null;
    }
  } else {
    throw Exception("Failed to fetch data from API");
  }
}

