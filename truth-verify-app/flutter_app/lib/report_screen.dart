import 'package:flutter/material.dart';
import 'api_service.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.report});

  final VerificationReport report;

  Color _statusColor() {
    if (report.consistencyIndex >= 72) return const Color(0xFF22C55E);
    if (report.consistencyIndex >= 45) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor();
    return Scaffold(
      appBar: AppBar(title: const Text('Truth Lens Report')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (report.fallbackNotice != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.14),
                border: Border.all(color: Colors.amber.shade700),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                report.fallbackNotice!,
                style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
              ),
            ),
          if (report.flagged)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.16),
                border: Border.all(color: Colors.redAccent),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Safety Alert: Unsafe question keyword detected & logged for Admin review.',
                style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (report.question.isNotEmpty) ...[
                  Text(
                    'Q: ${report.question}',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  report.classification,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: accent),
                ),
                const SizedBox(height: 8),
                Text(
                  'Consistency: ${report.consistencyIndex.toStringAsFixed(1)} / 100',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (report.verdictHi.isNotEmpty)
                  Text(
                    report.verdictHi,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Stress: ${report.combinedStressIndex.toStringAsFixed(1)}% · Mode: ${report.confidence}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Signal Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _MetricRow(label: 'Visual Stress Index', value: '${report.visualStressIndex.toStringAsFixed(1)}%'),
          _MetricRow(label: 'Vocal Stress Index', value: '${report.vocalStressIndex.toStringAsFixed(1)}%'),
          _MetricRow(label: 'Blink Frequency', value: '${report.blinkRatePerMin.toStringAsFixed(1)} / min'),
          _MetricRow(label: 'Mean Vocal Pitch (F0)', value: '${report.pitchMeanHz.toStringAsFixed(1)} Hz'),
          _MetricRow(label: 'Pause / Silence Ratio', value: '${report.pauseRatio.toStringAsFixed(1)}%'),
          const SizedBox(height: 20),
          const Text('Observed Indicators', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...report.findings.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• $item'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            report.disclaimer,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
