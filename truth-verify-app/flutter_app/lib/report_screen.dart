import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'api_service.dart';
import 'theme.dart';

class ReportScreen extends StatefulWidget {
  final AnalysisReport report;

  const ReportScreen({super.key, required this.report});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _initAndSpeakVerdict();
  }

  Future<void> _initAndSpeakVerdict() async {
    try {
      await _tts.setSpeechRate(0.47);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // Try Hindi (hi-IN) first, fall back cleanly to Indian English (en-IN)
      final dynamic avail = await _tts.isLanguageAvailable('hi-IN');
      if (avail == true || avail == 1) {
        await _tts.setLanguage('hi-IN');
      } else {
        await _tts.setLanguage('en-IN');
      }

      _tts.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _tts.setCancelHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });

      if (!_muted && ApiService.otaConfig.activeDetectors['hindi_voice_tts'] != false) {
        await _speakNow();
      }
    } catch (_) {
      // Ignore TTS engine unavailability on emulators.
    }
  }

  Future<void> _speakNow() async {
    try {
      await _tts.stop();
      setState(() {
        _muted = false;
        _isSpeaking = true;
      });
      await _tts.speak(widget.report.verdictHi);
    } catch (_) {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  Future<void> _toggleMute() async {
    if (_muted) {
      await _speakNow();
    } else {
      await _tts.stop();
      if (mounted) {
        setState(() {
          _muted = true;
          _isSpeaking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Color _scoreColor(double score) {
    if (score >= 72) return TruthLensColors.neonEmerald;
    if (score >= 45) return TruthLensColors.neonAmber;
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

    // Group 21 indicators by category
    final Map<String, List<IndicatorItem>> grouped = {};
    for (final item in r.indicators21) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FORENSIC REPORT',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Replay Voice Verdict',
            onPressed: _speakNow,
            icon: const Icon(Icons.replay_circle_filled_rounded,
                color: TruthLensColors.neonCyan),
          ),
          IconButton(
            tooltip: _muted ? 'Unmute Voice' : 'Mute Voice',
            onPressed: _toggleMute,
            icon: Icon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _muted ? TruthLensColors.neonRose : TruthLensColors.neonEmerald,
            ),
          ),
        ],
      ),
      body: CyberBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Hero Verdict + Voice TTS Control Card
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderColor: accent,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0x3322D3EE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          r.calibrated
                              ? '2-STAGE CALIBRATED · ${r.confidence.toUpperCase()}'
                              : '${r.analysisMode.toUpperCase()} · ${r.confidence.toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: TruthLensColors.neonCyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Glowing Score Ring
                  Container(
                    width: 136,
                    height: 136,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent, width: 6),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(accent.red, accent.green, accent.blue, 0.35),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${r.consistencyIndex.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                        const Text(
                          'CONSISTENCY',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.1,
                            color: TruthLensColors.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    r.classification,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Spoken Hindi/Hinglish Verdict Box
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
                              _isSpeaking ? 'AI BOL RAHA HAI...' : 'HINDI VOICE VERDICT',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: TruthLensColors.neonCyan,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          r.verdictHi,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                            color: Colors.white,
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
                              onPressed: _speakNow,
                              icon: const Icon(Icons.volume_up_rounded, size: 18),
                              label: const Text(
                                'Replay Voice',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    _muted ? TruthLensColors.neonRose : Colors.white,
                                side: BorderSide(
                                  color: _muted
                                      ? TruthLensColors.neonRose
                                      : const Color(0x5594A3B8),
                                ),
                              ),
                              onPressed: _toggleMute,
                              icon: Icon(
                                _muted ? Icons.volume_off_rounded : Icons.stop_rounded,
                                size: 18,
                              ),
                              label: Text(_muted ? 'Muted' : 'Mute'),
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

            // Module 4: Media Authenticity (Deepfake + Voice Clone)
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
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x2234D399),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          r.authenticity.overallStatus,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: TruthLensColors.neonEmerald,
                          ),
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

            // Module 2: AI Interrogation Coach
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
                          'AI Interrogation Coach',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x33A855F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'LOAD: ${r.coach.cognitiveLoadLevel}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE9D5FF),
                          ),
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
                      title: 'Targeted Follow-Up',
                      body: prompt,
                      color: TruthLensColors.neonAmber,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Module 3: 21-Point Diagnostic Dashboard
            GlassCard(
              borderColor: TruthLensColors.borderCyan,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '21-Point Behavioral & Biometric Matrix (${r.indicators21.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Stage 1 Baseline vs Stage 2 Target deltas across Ocular, rPPG, Kinesic & Bio-Acoustic signals.',
                    style: TextStyle(fontSize: 11.5, color: TruthLensColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: TruthLensColors.neonCyan,
                          letterSpacing: 0.9,
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Δ ${ind.delta}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: _statusColor(ind.status),
                                  ),
                                ),
                                Text(
                                  ind.status.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: TruthLensColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Disclaimer
            Text(
              r.disclaimer,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: TruthLensColors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            NeonGradientButton(
              label: 'New Forensic Scan',
              icon: Icons.radar_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
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
