import 'package:flutter/material.dart';
import 'api_service.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.report});

  final VerificationReport report;

  Color _statusColor() {
    if (report.consistencyIndex >= 72) return const Color(0xFF16A34A);
    if (report.consistencyIndex >= 45) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor();
    return Scaffold(
      appBar: AppBar(title: const Text('Signal Verification Report')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.classification,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: accent),
                ),
                const SizedBox(height: 8),
                Text(
                  'Consistency Index: ${report.consistencyIndex.toStringAsFixed(1)} / 100',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Combined Stress: ${report.combinedStressIndex.toStringAsFixed(1)}% · Confidence: ${report.confidence}',
                  style: TextStyle(color: Colors.grey.shade700),
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
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
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
