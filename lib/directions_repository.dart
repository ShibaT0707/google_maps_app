import 'package:http/http.dart' as http;
import 'dart:convert';

import 'constants.dart';

class DirectionsRepository {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  Future<Map<String, dynamic>?> getDirections({
    required String origin,
    required String destination,
  }) async {
    if (googleApiKey == 'YOUR_API_KEY_HERE') {
      // In a real app, you'd want to handle this more gracefully.
      throw Exception('APIキーが設定されていません。lib/constants.dart を確認してください。');
    }

    final url =
        '$_baseUrl?origin=$origin&destination=$destination&departure_time=now&alternatives=true&key=$googleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      // Consider throwing a more specific exception.
      print('Failed to get directions: ${response.body}');
      return null;
    }
  }
}
