import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class VerificationReport {
  VerificationReport({
    required this.consistencyIndex,
    required this.combinedStressIndex,
    required this.classification,
    required this.confidence,
    required this.visualStressIndex,
    required this.vocalStressIndex,
    required this.blinkRatePerMin,
    required this.pitchMeanHz,
    required this.pauseRatio,
    required this.findings,
    required this.disclaimer,
  });

  final double consistencyIndex;
  final double combinedStressIndex;
  final String classification;
  final String confidence;
  final double visualStressIndex;
  final double vocalStressIndex;
  final double blinkRatePerMin;
  final double pitchMeanHz;
  final double pauseRatio;
  final List<String> findings;
  final String disclaimer;

  factory VerificationReport.fromJson(Map<String, dynamic> json) {
    final video = (json['video'] as Map<String, dynamic>?) ?? {};
    final audio = (json['audio'] as Map<String, dynamic>?) ?? {};

    return VerificationReport(
      consistencyIndex: (json['consistency_index'] as num?)?.toDouble() ?? 0.0,
      combinedStressIndex: (json['combined_stress_index'] as num?)?.toDouble() ?? 0.0,
      classification: (json['classification'] as String?) ?? 'Unknown',
      confidence: (json['confidence'] as String?) ?? 'Moderate',
      visualStressIndex: (video['visual_stress_index'] as num?)?.toDouble() ?? 0.0,
      vocalStressIndex: (audio['vocal_stress_index'] as num?)?.toDouble() ?? 0.0,
      blinkRatePerMin: (video['blink_rate_per_min'] as num?)?.toDouble() ?? 0.0,
      pitchMeanHz: (audio['pitch_mean_hz'] as num?)?.toDouble() ?? 0.0,
      pauseRatio: (audio['pause_ratio'] as num?)?.toDouble() ?? 0.0,
      findings: (json['findings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      disclaimer: (json['disclaimer'] as String?) ?? '',
    );
  }
}

class ApiService {
  // Paste your live Railway URL here (do not include a trailing '/')
  ApiService({this.baseUrl = 'https://truth-verify-production.up.railway.app'});

  final String baseUrl;

  Future<bool> checkHealth() async {
    final uri = Uri.parse('$baseUrl/health');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    return response.statusCode == 200;
  }

  Future<VerificationReport> analyzeVideo(File videoFile) async {
    final uri = Uri.parse('$baseUrl/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', videoFile.path));

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Server error (${streamed.statusCode}): $body');
    }

    final Map<String, dynamic> decoded = jsonDecode(body) as Map<String, dynamic>;
    return VerificationReport.fromJson(decoded);
  }
}
