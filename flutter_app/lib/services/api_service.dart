import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/download_item.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  /// Android emulator -> host machine's localhost is 10.0.2.2
  /// iOS simulator / desktop / web -> localhost works directly.
  /// Change this if your backend runs on a different host.
  // static const String baseUrl = 'http://10.0.2.2:8000';
  static const String baseUrl = 'http://localhost:8000'; // iOS sim / desktop

  Future<String> startDownload(String url) async {
    final response = await http.post(
      Uri.parse('$baseUrl/download'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url}),
    );

    if (response.statusCode != 200) {
      final body = _tryDecode(response.body);
      throw ApiException(body?['detail']?.toString() ?? 'Failed to start download');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['job_id'] as String;
  }

  Future<JobStatus> getStatus(String jobId) async {
    final response = await http.get(Uri.parse('$baseUrl/status/$jobId'));
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch job status');
    }
    return JobStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<DownloadItem>> getHistory() async {
    final response = await http.get(Uri.parse('$baseUrl/history'));
    if (response.statusCode != 200) {
      throw ApiException('Could not fetch history');
    }
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => DownloadItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
