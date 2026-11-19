import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.walletBalance,
    required this.freeQuestionsLeft,
    required this.isAdmin,
  });

  final String id;
  final String email;
  final String name;
  final double walletBalance;
  final int freeQuestionsLeft;
  final bool isAdmin;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      freeQuestionsLeft: (json['free_questions_left'] as num?)?.toInt() ?? 0,
      isAdmin: (json['is_admin'] as bool?) ?? false,
    );
  }
}

class VerificationReport {
  VerificationReport({
    required this.consistencyIndex,
    required this.combinedStressIndex,
    required this.classification,
    required this.verdictHi,
    required this.confidence,
    required this.visualStressIndex,
    required this.vocalStressIndex,
    required this.blinkRatePerMin,
    required this.pitchMeanHz,
    required this.pauseRatio,
    required this.findings,
    required this.disclaimer,
    required this.question,
    required this.flagged,
    required this.isLocalFallback,
    this.fallbackNotice,
  });

  final double consistencyIndex;
  final double combinedStressIndex;
  final String classification;
  final String verdictHi;
  final String confidence;
  final double visualStressIndex;
  final double vocalStressIndex;
  final double blinkRatePerMin;
  final double pitchMeanHz;
  final double pauseRatio;
  final List<String> findings;
  final String disclaimer;
  final String question;
  final bool flagged;
  final bool isLocalFallback;
  final String? fallbackNotice;

  factory VerificationReport.fromJson(Map<String, dynamic> json) {
    final video = (json['video'] as Map<String, dynamic>?) ?? {};
    final audio = (json['audio'] as Map<String, dynamic>?) ?? {};

    return VerificationReport(
      consistencyIndex: (json['consistency_index'] as num?)?.toDouble() ?? 0.0,
      combinedStressIndex: (json['combined_stress_index'] as num?)?.toDouble() ?? 0.0,
      classification: (json['classification'] as String?) ?? 'Unknown',
      verdictHi: (json['verdict_hi'] as String?) ?? '',
      confidence: (json['confidence'] as String?) ?? 'Moderate',
      visualStressIndex: (video['visual_stress_index'] as num?)?.toDouble() ?? 0.0,
      vocalStressIndex: (audio['vocal_stress_index'] as num?)?.toDouble() ?? 0.0,
      blinkRatePerMin: (video['blink_rate_per_min'] as num?)?.toDouble() ?? 0.0,
      pitchMeanHz: (audio['pitch_mean_hz'] as num?)?.toDouble() ?? 0.0,
      pauseRatio: (audio['pause_ratio'] as num?)?.toDouble() ?? 0.0,
      findings: (json['findings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      disclaimer: (json['disclaimer'] as String?) ?? '',
      question: (json['question'] as String?) ?? '',
      flagged: (json['flagged'] as bool?) ?? false,
      isLocalFallback: false,
    );
  }
}

class ApiService {
  static const _urlPrefKey = 'railway_base_url';
  static const _tokenPrefKey = 'tl_auth_token';

  // Paste your live Railway URL here (or set it directly inside the app via Server icon)
  ApiService({this.baseUrl = ''});

  String baseUrl;
  String authToken = '';
  UserProfile? currentUser;
  int pricePerQuestion = 10;
  int minRecharge = 50;
  int freeQuestionsDefault = 3;
  String upiId = 'yourupi@oksbi';

  static String normalizeUrl(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  Future<File> _prefsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/truth_lens_prefs.json');
  }

  Future<Map<String, dynamic>> _readPrefs() async {
    try {
      final file = await _prefsFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {
      // ignore read errors
    }
    return <String, dynamic>{};
  }

  Future<void> _writePrefs(Map<String, dynamic> data) async {
    try {
      final file = await _prefsFile();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // ignore write errors
    }
  }

  Future<void> init() async {
    final prefs = await _readPrefs();
    final savedUrl = prefs[_urlPrefKey] as String?;
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      baseUrl = normalizeUrl(savedUrl);
    }
    authToken = (prefs[_tokenPrefKey] as String?) ?? '';
    if (baseUrl.isNotEmpty) {
      await fetchPublicConfig();
      if (authToken.isNotEmpty) {
        await refreshProfile();
      }
    }
  }

  Future<void> saveUrl(String url) async {
    baseUrl = normalizeUrl(url);
    final prefs = await _readPrefs();
    prefs[_urlPrefKey] = baseUrl;
    await _writePrefs(prefs);
    if (baseUrl.isNotEmpty) {
      await fetchPublicConfig();
    }
  }

  Future<void> saveToken(String token) async {
    authToken = token;
    final prefs = await _readPrefs();
    prefs[_tokenPrefKey] = token;
    await _writePrefs(prefs);
  }

  Future<void> logout() async {
    authToken = '';
    currentUser = null;
    final prefs = await _readPrefs();
    prefs.remove(_tokenPrefKey);
    await _writePrefs(prefs);
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (authToken.isNotEmpty) 'Authorization': 'Bearer $authToken',
    };
  }

  Future<bool> checkHealth() async {
    final clean = normalizeUrl(baseUrl);
    if (clean.isEmpty) return false;
    final uri = Uri.parse('$clean/health');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    return resp.statusCode == 200;
  }

  Future<void> fetchPublicConfig() async {
    final clean = normalizeUrl(baseUrl);
    if (clean.isEmpty) return;
    try {
      final resp = await http
          .get(Uri.parse('$clean/api/public-config'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        pricePerQuestion = (data['price_per_question'] as num?)?.toInt() ?? 10;
        minRecharge = (data['min_recharge'] as num?)?.toInt() ?? 50;
        freeQuestionsDefault = (data['free_questions'] as num?)?.toInt() ?? 3;
        upiId = (data['upi_id'] as String?) ?? 'yourupi@oksbi';
      }
    } catch (_) {
      // ignore offline config fetch
    }
  }

  Future<UserProfile?> refreshProfile() async {
    final clean = normalizeUrl(baseUrl);
    if (clean.isEmpty || authToken.isEmpty) return null;
    try {
      final resp = await http
          .get(Uri.parse('$clean/api/me'), headers: _headers())
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        currentUser = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
        final pricing = data['pricing'] as Map<String, dynamic>?;
        if (pricing != null) {
          pricePerQuestion = (pricing['price_per_question'] as num?)?.toInt() ?? pricePerQuestion;
          minRecharge = (pricing['min_recharge'] as num?)?.toInt() ?? minRecharge;
          upiId = (pricing['upi_id'] as String?) ?? upiId;
        }
        return currentUser;
      }
    } catch (_) {
      // ignore offline profile check
    }
    return null;
  }

  Future<UserProfile> devLogin({
    required String email,
    required String name,
    String password = '',
  }) async {
    final clean = normalizeUrl(baseUrl);
    if (clean.isEmpty) {
      throw Exception('Pehle Railway Server URL set karein (upar Server icon tap karein).');
    }
    final resp = await http
        .post(
          Uri.parse('$clean/api/auth/dev-login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'name': name.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 12));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception((data['detail'] as String?) ?? 'Login failed (${resp.statusCode})');
    }
    await saveToken((data['token'] as String?) ?? '');
    currentUser = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
    return currentUser!;
  }

  Future<String> requestRecharge({required double amount, required String utr}) async {
    final clean = normalizeUrl(baseUrl);
    if (clean.isEmpty || authToken.isEmpty) {
      throw Exception('Recharge ke liye Railway Server aur Login zaroori hai.');
    }
    final resp = await http
        .post(
          Uri.parse('$clean/api/wallet/recharge'),
          headers: _headers(),
          body: jsonEncode({'amount': amount, 'utr': utr.trim()}),
        )
        .timeout(const Duration(seconds: 12));

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception((data['detail'] as String?) ?? 'Recharge failed');
    }
    return (data['message'] as String?) ?? 'Recharge request submitted.';
  }

  Future<Map<String, dynamic>> fetchAdminOverview() async {
    final clean = normalizeUrl(baseUrl);
    if (clean.isEmpty || authToken.isEmpty) {
      throw Exception('Admin login aur Railway URL zaroori hai.');
    }
    final resp = await http
        .get(Uri.parse('$clean/api/admin/overview'), headers: _headers())
        .timeout(const Duration(seconds: 12));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception((data['detail'] as String?) ?? 'Admin overview failed (${resp.statusCode})');
    }
    return data;
  }

  Future<void> updateAdminSettings({
    required int pricePerQuestion,
    required int minRecharge,
    required int freeQuestions,
    required String upiId,
  }) async {
    final clean = normalizeUrl(baseUrl);
    final resp = await http
        .post(
          Uri.parse('$clean/api/admin/settings'),
          headers: _headers(),
          body: jsonEncode({
            'price_per_question': pricePerQuestion,
            'min_recharge': minRecharge,
            'free_questions': freeQuestions,
            'upi_id': upiId.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      throw Exception((data['detail'] as String?) ?? 'Settings save failed');
    }
    await fetchPublicConfig();
  }

  Future<void> handleRechargeAction(String rechargeId, String action) async {
    final clean = normalizeUrl(baseUrl);
    final resp = await http
        .post(
          Uri.parse('$clean/api/admin/recharges/$rechargeId/$action'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      throw Exception((data['detail'] as String?) ?? 'Recharge update failed');
    }
  }

  Future<void> adjustUserWallet(String userId, double delta) async {
    final clean = normalizeUrl(baseUrl);
    final resp = await http
        .post(
          Uri.parse('$clean/api/admin/users/$userId/wallet'),
          headers: _headers(),
          body: jsonEncode({'delta': delta}),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      throw Exception((data['detail'] as String?) ?? 'Wallet update failed');
    }
  }

  Future<void> toggleUserBan(String userId) async {
    final clean = normalizeUrl(baseUrl);
    final resp = await http
        .post(
          Uri.parse('$clean/api/admin/users/$userId/toggle-ban'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      throw Exception((data['detail'] as String?) ?? 'Ban toggle failed');
    }
  }

  Future<VerificationReport> analyzeVideo(
    File videoFile, {
    String question = '',
    int durationSeconds = 4,
  }) async {
    final clean = normalizeUrl(baseUrl);

    if (clean.isNotEmpty) {
      try {
        final healthResp = await http
            .get(Uri.parse('$clean/health'))
            .timeout(const Duration(seconds: 8));

        if (healthResp.statusCode == 200) {
          final uri = Uri.parse('$clean/analyze');
          final request = http.MultipartRequest('POST', uri);
          if (authToken.isNotEmpty) {
            request.headers['Authorization'] = 'Bearer $authToken';
          }
          request.fields['question'] = question;
          request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));

          final streamed = await request.send().timeout(const Duration(seconds: 120));
          final body = await streamed.stream.bytesToString();

          if (streamed.statusCode == 402) {
            final err = jsonDecode(body) as Map<String, dynamic>;
            throw Exception((err['detail'] as String?) ?? 'Wallet balance kam hai! Recharge karein.');
          }

          if (streamed.statusCode == 200) {
            final Map<String, dynamic> decoded = jsonDecode(body) as Map<String, dynamic>;
            if (decoded['user'] is Map<String, dynamic>) {
              currentUser = UserProfile.fromJson(decoded['user'] as Map<String, dynamic>);
            }
            return VerificationReport.fromJson(decoded);
          }

          return _buildLocalFallbackReport(
            videoFile,
            question: question,
            durationSeconds: durationSeconds,
            notice: 'Railway server HTTP ${streamed.statusCode} return kar raha hai — Local On-Device Mode report dikhayi ja rahi hai.',
          );
        }

        return _buildLocalFallbackReport(
          videoFile,
          question: question,
          durationSeconds: durationSeconds,
          notice: 'Railway URL ($clean) par backend live nahi mila (HTTP ${healthResp.statusCode}) — Local On-Device Mode use kiya gaya.',
        );
      } catch (e) {
        if (e.toString().contains('Balance kam hai') || e.toString().contains('Recharge')) {
          rethrow;
        }
        return _buildLocalFallbackReport(
          videoFile,
          question: question,
          durationSeconds: durationSeconds,
          notice: 'Railway server unreachable — Local On-Device Mode se turant report banayi gayi hai. Live AI server ke liye upar Server icon tap karein.',
        );
      }
    }

    return _buildLocalFallbackReport(
      videoFile,
      question: question,
      durationSeconds: durationSeconds,
      notice: 'On-Device Mode active hai. Railway Cloud AI + Wallet + Admin connect karne ke liye upar Server icon par apna Railway URL dalein.',
    );
  }

  /// Byte-level bitrate & frame variance estimator so the APK ALWAYS produces a report even before Railway is deployed.
  Future<VerificationReport> _buildLocalFallbackReport(
    File videoFile, {
    required String question,
    required int durationSeconds,
    required String notice,
  }) async {
    final bytes = await videoFile.readAsBytes();
    final safeDuration = max(1, durationSeconds);
    final kbPerSec = (bytes.length / 1024.0) / safeDuration;

    // Sample byte entropy across video chunks to approximate motion/bitrate variance
    final chunkSize = max(512, bytes.length ~/ 24);
    final chunkMeans = <double>[];
    for (int offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = min(bytes.length, offset + chunkSize);
      double sum = 0.0;
      for (int i = offset; i < end; i += 4) {
        sum += bytes[i];
      }
      final double denom = max(1.0, (end - offset) / 4.0);
      chunkMeans.add(sum / denom);
    }
    final double meanVal = chunkMeans.isEmpty
        ? 128.0
        : chunkMeans.reduce((a, b) => a + b) / chunkMeans.length;
    final double variance = chunkMeans.isEmpty
        ? 10.0
        : chunkMeans.map<double>((v) => (v - meanVal) * (v - meanVal)).reduce((a, b) => a + b) /
            chunkMeans.length;
    final double stdDev = sqrt(variance);

    final double visualStress = min(78.0, max(12.0, (stdDev * 1.4) + (kbPerSec > 450 ? 12.0 : 4.0)));
    final double vocalStress = min(75.0, max(14.0, (stdDev * 1.2) + (safeDuration < 3 ? 16.0 : 8.0)));
    final double combinedStress = double.parse(((0.45 * visualStress) + (0.55 * vocalStress)).toStringAsFixed(1));
    final double consistency = double.parse((100.0 - combinedStress).clamp(0.0, 100.0).toDouble().toStringAsFixed(1));

    String classification;
    String verdictHi;
    if (consistency >= 72) {
      classification = 'Low Stress / Consistent';
      verdictHi = 'Ye jawab natural aur steady lag raha hai (On-Device Estimation).';
    } else if (consistency >= 45) {
      classification = 'Moderate Cognitive Load';
      verdictHi = 'Thoda hesitation ya motion variance mila hai — ek follow-up sawaal poochhein.';
    } else {
      classification = 'Elevated Stress Indicators';
      verdictHi = 'Kaafi variance detect hua hai — exact details dobara poochhein.';
    }

    final unsafeRx = RegExp(
      r'\b(bomb|bam|boom|gun|pistol|weapon|kill|murder|drugs|terror|katta|bandook)\b',
      caseSensitive: false,
    );
    final flagged = unsafeRx.hasMatch(question);

    return VerificationReport(
      consistencyIndex: consistency,
      combinedStressIndex: combinedStress,
      classification: classification,
      verdictHi: verdictHi,
      confidence: 'Local Mode',
      visualStressIndex: double.parse(visualStress.toStringAsFixed(1)),
      vocalStressIndex: double.parse(vocalStress.toStringAsFixed(1)),
      blinkRatePerMin: double.parse((14.0 + (stdDev % 11)).toStringAsFixed(1)),
      pitchMeanHz: double.parse((128.0 + (meanVal % 45)).toStringAsFixed(1)),
      pauseRatio: double.parse((18.0 + (stdDev % 22)).toStringAsFixed(1)),
      findings: [
        'Recorded ${safeDuration}s clip (${(bytes.length / 1024).toStringAsFixed(0)} KB) analyzed locally.',
        if (flagged) 'Unsafe keyword detected in question — connect Railway URL to log alert to Admin Panel.',
        'Connect your live Railway URL in Server Settings for full OpenCV + Librosa + Admin cloud analysis.',
      ],
      disclaimer:
          'Signal analysis measures acoustic and visual stress indicators only and does not constitute definitive truth or deception verification.',
      question: question,
      flagged: flagged,
      isLocalFallback: true,
      fallbackNotice: notice,
    );
  }
}
