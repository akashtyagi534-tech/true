import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api_service.dart';
import 'theme.dart';

class ReportScreen extends StatefulWidget {
  final AnalysisReport report;
  final bool autoSpeakOnOpen;

  const ReportScreen({
    super.key,
    required this.report,
    this.autoSpeakOnOpen = true,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _initTtsAndSpeak();
  }

  Future<void> _initTtsAndSpeak() async {
    try {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      final dynamic hiAvailable = await _flutterTts.isLanguageAvailable('hi-IN');
      if (hiAvailable == true || hiAvailable == 1) {
        await _flutterTts.setLanguage('hi-IN');
      } else {
        await _flutterTts.setLanguage('en-IN');
      }

      _flutterTts.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _flutterTts.setCancelHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _flutterTts.setErrorHandler((_) {
        if (mounted) setState(() => _isSpeaking = false);
      });

      if (widget.autoSpeakOnOpen &&
          !_muted &&
          ApiService.otaConfig.activeDetectors['hindi_voice_tts'] != false) {
        await _speakFullReport();
      }
    } catch (_) {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _speakFullReport() async {
    try {
      await _flutterTts.stop();
      if (mounted) {
        setState(() {
          _muted = false;
          _isSpeaking = true;
        });
      }
      final script = widget.report.buildSpokenVerdictScript();
      await _flutterTts.speak(script);
    } catch (_) {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _muted = true;
        });
      }
    } else {
      await _speakFullReport();
    }
  }

  Future<void> _openExportSummarySheet() async {
    final summaryText = widget.report.buildExportTextSummary();
    await Clipboard.setData(ClipboardData(text: summaryText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full Forensic Report copied to clipboard — ready to share!'),
      ),
    );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.ios_share_rounded, color: TruthLensColors.neonCyan),
                SizedBox(width: 8),
                Text(
                  'Export / Share Report Summary',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF050814),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TruthLensColors.borderCyan),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  summaryText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.45,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            NeonGradientButton(
              label: 'Copy Text Summary Again',
              icon: Icons.copy_all_rounded,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: summaryText));
                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied forensic summary to clipboard!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Color _scoreColor(double score) {
    if (score >= 65) return TruthLensColors.neonEmerald;
    if (score >= 42) return TruthLensColors.neonAmber;
    return TruthLensColors.neonRose;
  }

  Color _statusColor(String status) {
    if (status == 'high') return TruthLensColors.neonRose;
    if (status == 'elevated') return TruthLensColors.neonAmber;
    return TruthLensColors.neonEmerald;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final Color accent = _scoreColor(r.consistencyIndex);

    final Map<String, List<IndicatorItem>> grouped = {};
    for (final item in r.indicators21) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TRUTH LENS REPORT',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 15),
        ),
        actions: [
          IconButton(
            tooltip: _isSpeaking ? 'Stop Voice' : 'Replay Voice Report',
            onPressed: _toggleSpeaker,
            icon: Icon(
              _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
              color: _isSpeaking ? TruthLensColors.neonRose : TruthLensColors.neonCyan,
            ),
          ),
          IconButton(
            tooltip: 'Export / Share Summary',
            onPressed: _openExportSummarySheet,
            icon: const Icon(Icons.share_rounded, color: TruthLensColors.neonPurple),
          ),
        ],
      ),
      body: CyberBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Features 6, 7, 8 & 15: Color-Coded Consistency Gauge + Cognitive Load + Stress % + Voice Verdict
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderColor: accent,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x3322D3EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${r.analysisMode.toUpperCase()} · ${r.confidence.toUpperCase()} CONFIDENCE',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: TruthLensColors.neonCyan,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Custom Painted Consistency Score Gauge (0-100)
                  SizedBox(
                    width: 154,
                    height: 154,
                    child: CustomPaint(
                      painter: _ScoreGaugePainter(
                        score: r.consistencyIndex,
                        accent: accent,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${r.consistencyIndex.round()}',
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: accent,
                              ),
                            ),
                            const Text(
                              'OUT OF 100',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.0,
                                color: TruthLensColors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    r.cognitiveLoadClassification,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stress Index: ${r.stressPercentage.toStringAsFixed(1)}% (100 - Consistency)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: TruthLensColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Spoken Hindi/Hinglish Voice Verdict Box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0x99060B1E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: TruthLensColors.borderPurple),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isSpeaking
                                  ? Icons.graphic_eq_rounded
                                  : Icons.record_voice_over_rounded,
                              color: TruthLensColors.neonCyan,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isSpeaking ? 'SPEAKING VOICE REPORT...' : 'AUTO VOICE VERDICT (TTS)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: TruthLensColors.neonCyan,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          r.verdictHi,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: TruthLensColors.neonCyan,
                                foregroundColor: const Color(0xFF040712),
                              ),
                              onPressed: _speakFullReport,
                              icon: const Icon(Icons.replay_rounded, size: 18),
                              label: const Text(
                                'Replay Voice',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    _isSpeaking ? TruthLensColors.neonRose : Colors.white,
                              ),
                              onPressed: _toggleSpeaker,
                              icon: Icon(
                                _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                                size: 18,
                              ),
                              label: Text(_isSpeaking ? 'Stop' : 'Speak'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Features 9–14: 6 Core Signal Metric Cards
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _MetricCard(
                  icon: Icons.visibility_rounded,
                  label: 'Visual Stress Index',
                  value: '${r.visualStressIndex.toStringAsFixed(1)}%',
                  color: TruthLensColors.neonPurple,
                ),
                _MetricCard(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Vocal Stress Index',
                  value: '${r.vocalStressIndex.toStringAsFixed(1)}%',
                  color: TruthLensColors.neonCyan,
                ),
                _MetricCard(
                  icon: Icons.remove_red_eye_rounded,
                  label: 'Blink Frequency',
                  value: '${r.blinkFrequency.toStringAsFixed(1)} /min',
                  color: TruthLensColors.neonEmerald,
                ),
                _MetricCard(
                  icon: Icons.music_note_rounded,
                  label: 'Mean Vocal Pitch (F0)',
                  value: '${r.meanVocalPitchHz.toStringAsFixed(0)} Hz',
                  color: TruthLensColors.neonAmber,
                ),
                _MetricCard(
                  icon: Icons.pause_circle_outline_rounded,
                  label: 'Pause / Silence Ratio',
                  value: '${r.pauseSilenceRatio.toStringAsFixed(1)}%',
                  color: TruthLensColors.neonRose,
                ),
                _MetricCard(
                  icon: Icons.face_retouching_natural_rounded,
                  label: 'Micro-Expr / Motion Var',
                  value: '${r.microExpressionVariance.toStringAsFixed(1)}%',
                  color: const Color(0xFF38BDF8),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Media Authenticity Card
            GlassCard(
              borderColor: TruthLensColors.borderCyan,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fingerprint_rounded, color: TruthLensColors.neonCyan),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Media Authenticity & Anti-Spoof',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        r.authenticity.overallStatus,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: TruthLensColors.neonEmerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AuthBar(
                    label: 'Face Liveness (Real Human)',
                    pct: r.authenticity.realHumanPct,
                    sub: 'Deepfake Risk: ${r.authenticity.deepfakeRiskPct.toStringAsFixed(1)}%',
                  ),
                  const SizedBox(height: 10),
                  _AuthBar(
                    label: 'Human Voice Authenticity',
                    pct: r.authenticity.humanVoicePct,
                    sub: 'AI Clone Risk: ${r.authenticity.voiceCloneRiskPct.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Feature 16: Follow-Up Question Recommendation Engine
            GlassCard(
              borderColor: TruthLensColors.borderPurple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.psychology_rounded, color: TruthLensColors.neonPurple),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Follow-Up Question Engine',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        'LOAD: ${r.coach.cognitiveLoadLevel}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE9D5FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (r.coach.reverseChronologicalTest.isNotEmpty)
                    _CoachTile(
                      title: 'Reverse Chronological Order Test',
                      body: r.coach.reverseChronologicalTest,
                      color: TruthLensColors.neonCyan,
                    ),
                  if (r.coach.unexpectedDetailShift.isNotEmpty)
                    _CoachTile(
                      title: 'Unexpected Detail Shift',
                      body: r.coach.unexpectedDetailShift,
                      color: TruthLensColors.neonPurple,
                    ),
                  for (final prompt in r.coach.targetedPrompts)
                    _CoachTile(
                      title: 'Hesitation Follow-Up',
                      body: prompt,
                      color: TruthLensColors.neonAmber,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Full 21-Point Multi-Modal Matrix
            if (r.indicators21.isNotEmpty) ...[
              GlassCard(
                borderColor: TruthLensColors.borderCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '21-Point Biometric Signal Matrix (${r.indicators21.length})',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Text(
                          entry.key.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: TruthLensColors.neonCyan,
                          ),
                        ),
                      ),
                      for (final ind in entry.value)
                        Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0x88070C1F),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: Color.fromRGBO(
                                _statusColor(ind.status).red,
                                _statusColor(ind.status).green,
                                _statusColor(ind.status).blue,
                                0.35,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(
                                    _statusColor(ind.status).red,
                                    _statusColor(ind.status).green,
                                    _statusColor(ind.status).blue,
                                    0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  '${ind.id}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _statusColor(ind.status),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ind.name,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      ind.value,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: TruthLensColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Δ ${ind.delta}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: _statusColor(ind.status),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Feature 22: Clip Metadata & Clear Disclaimer Banner
            GlassCard(
              padding: const EdgeInsets.all(14),
              borderColor: const Color(0x4494A3B8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CLIP METADATA & DISCLAIMER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: TruthLensColors.neonCyan,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Duration: ${r.clipDurationSec.toStringAsFixed(1)}s  ·  File Size: ${r.formattedFileSize}  ·  Mode: ${r.analysisMode}\nReport ID: ${r.id}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    r.disclaimer,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TruthLensColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Feature 18: Export / Share Summary + New Scan Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: TruthLensColors.neonCyan,
                      side: const BorderSide(color: TruthLensColors.borderCyan),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _openExportSummarySheet,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Export Summary'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeonGradientButton(
                    label: 'New Scan',
                    icon: Icons.radar_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreGaugePainter extends CustomPainter {
  final double score;
  final Color accent;

  _ScoreGaugePainter({required this.score, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;

    final trackPaint = Paint()
      ..color = const Color(0x3394A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweepPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;

    final double sweep = (score.clamp(0.0, 100.0) / 100.0) * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreGaugePainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.accent != accent;
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderColor: Color.fromRGBO(color.red, color.green, color.blue, 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: TruthLensColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBar extends StatelessWidget {
  final String label;
  final double pct;
  final String sub;

  const _AuthBar({
    required this.label,
    required this.pct,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final Color barColor =
        pct >= 75 ? TruthLensColors.neonEmerald : TruthLensColors.neonAmber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (pct / 100.0).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: const Color(0x3394A3B8),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 3),
        Text(sub, style: const TextStyle(fontSize: 11, color: TruthLensColors.textMuted)),
      ],
    );
  }
}

class _CoachTile extends StatelessWidget {
  final String title;
  final String body;
  final Color color;

  const _CoachTile({
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0x88070C1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color.fromRGBO(color.red, color.green, color.blue, 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
