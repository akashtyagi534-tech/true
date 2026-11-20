import 'package:flutter/material.dart';

import 'admin_screen.dart';
import 'api_service.dart';
import 'login_screen.dart';
import 'recording_screen.dart';
import 'report_screen.dart';
import 'theme.dart';
import 'widgets/truth_lens_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AuthProfile? _profile;
  OtaAppConfig _ota = const OtaAppConfig();
  bool _useCloudMode = true;
  List<AnalysisReport> _history = [];
  bool _syncing = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await ApiService.init();
    if (mounted) {
      setState(() {
        _profile = ApiService.currentProfile;
        _ota = ApiService.otaConfig;
        _useCloudMode = ApiService.useCloudMode;
        _history = ApiService.sessionHistory;
      });
    }
    final ota = await ApiService.fetchOtaConfig();
    final refreshed = await ApiService.refreshMe();
    if (mounted) {
      setState(() {
        _ota = ota;
        _profile = refreshed ?? ApiService.currentProfile;
        _history = ApiService.sessionHistory;
        _syncing = false;
      });
    }
  }

  Future<void> _toggleCloudMode(bool value) async {
    await ApiService.setCloudMode(value);
    if (mounted) {
      setState(() => _useCloudMode = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Switched to Railway Cloud AI Mode'
                : 'Switched to On-Device Local Mode (Instant Offline Analysis)',
          ),
        ),
      );
    }
  }

  void _openServerUrlDialog() {
    final ctrl = TextEditingController(text: ApiService.baseUrl);
    String? statusMsg;
    bool testing = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF0E1630),
          title: const Text('Railway Backend Server URL'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Railway → Backend Service → Settings → Networking se apna live https://....up.railway.app URL paste karein:',
                style: TextStyle(fontSize: 12, color: TruthLensColors.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'https://your-service.up.railway.app',
                ),
              ),
              if (statusMsg != null) ...[
                const SizedBox(height: 10),
                Text(
                  statusMsg!,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusMsg!.startsWith('OK')
                        ? TruthLensColors.neonEmerald
                        : TruthLensColors.neonRose,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: testing
                  ? null
                  : () async {
                      setDlg(() {
                        testing = true;
                        statusMsg = 'Checking /health...';
                      });
                      await ApiService.setBaseUrl(ctrl.text);
                      final res = await ApiService.checkServerHealth();
                      setDlg(() {
                        testing = false;
                        statusMsg = res;
                      });
                    },
              child: Text(testing ? 'Testing...' : 'Test'),
            ),
            FilledButton(
              onPressed: () async {
                await ApiService.setBaseUrl(ctrl.text);
                if (!mounted) return;
                Navigator.of(ctx).pop();
                _bootstrap();
              },
              child: const Text('Save & Sync'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProfileOrLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    _bootstrap();
  }

  Future<void> _openScanner({required bool twoStage}) async {
    if (_useCloudMode &&
        _profile != null &&
        _profile!.token.isNotEmpty &&
        _profile!.freeQuestionsLeft <= 0 &&
        _profile!.walletBalance < _ota.pricePerQuestion) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Balance kam hai! ₹${_ota.pricePerQuestion}/question ke liye Wallet recharge karein ya Local Mode use karein.',
          ),
        ),
      );
      await _openProfileOrLogin();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordingScreen(
          twoStageMode: twoStage,
          otaConfig: _ota,
        ),
      ),
    );
    _bootstrap();
  }

  Color _scoreColor(double score) {
    if (score >= 72) return TruthLensColors.neonEmerald;
    if (score >= 45) return TruthLensColors.neonAmber;
    return TruthLensColors.neonRose;
  }

  Widget _buildProfileIcon() {
    final p = _profile;
    if (p != null && p.picture.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 17,
        backgroundColor: const Color(0x33A855F7),
        backgroundImage: NetworkImage(p.picture),
      );
    }
    if (p != null && p.email.isNotEmpty) {
      final letter = (p.name.isNotEmpty ? p.name[0] : p.email[0]).toUpperCase();
      return CircleAvatar(
        radius: 17,
        backgroundColor: const Color(0x4422D3EE),
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: TruthLensColors.neonCyan,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0x33A855F7),
        shape: BoxShape.circle,
        border: Border.all(color: TruthLensColors.borderCyan),
      ),
      child: const Icon(Icons.person_rounded, size: 19, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = _profile?.isAdmin == true;
    final double walletBal = ApiService.effectiveWalletBalance;

    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: TruthLensColors.neonCyan,
            onRefresh: _bootstrap,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                // Top Bar with Logo, Server URL, Admin Shield, and Profile Icon
                Row(
                  children: [
                    const TruthLensLogo(size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRUTH LENS PRO',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _syncing
                                ? 'Syncing OTA Config...'
                                : 'v${_ota.appVersion} · 22-Point AI Forensic Suite',
                            style: const TextStyle(
                              fontSize: 11,
                              color: TruthLensColors.neonCyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isAdmin)
                      IconButton(
                        tooltip: 'Admin Control Center',
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminScreen()),
                          );
                          _bootstrap();
                        },
                        icon: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: TruthLensColors.neonAmber,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Railway Server URL',
                      onPressed: _openServerUrlDialog,
                      icon: const Icon(Icons.dns_rounded, color: TruthLensColors.textMuted),
                    ),
                    GestureDetector(
                      onTap: _openProfileOrLogin,
                      child: Tooltip(
                        message: _profile == null ? 'Sign In with Google' : 'Profile & Account',
                        child: _buildProfileIcon(),
                      ),
                    ),
                  ],
                ),

                if (_ota.maintenanceMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GlassCard(
                    padding: const EdgeInsets.all(12),
                    borderColor: TruthLensColors.neonAmber,
                    child: Row(
                      children: [
                        const Icon(Icons.campaign_rounded, color: TruthLensColors.neonAmber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _ota.maintenanceMessage,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // Feature 4: Dual Mode Switcher (On-Device Local Mode vs Railway Cloud AI Mode)
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  borderColor: _useCloudMode
                      ? TruthLensColors.borderCyan
                      : TruthLensColors.borderPurple,
                  child: Row(
                    children: [
                      Icon(
                        _useCloudMode ? Icons.cloud_done_rounded : Icons.memory_rounded,
                        color: _useCloudMode
                            ? TruthLensColors.neonCyan
                            : TruthLensColors.neonPurple,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _useCloudMode
                                  ? 'Railway Cloud AI Mode'
                                  : 'On-Device Local Mode',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            Text(
                              _useCloudMode
                                  ? 'Deep Python FFT + OpenCV server (auto-fallback enabled)'
                                  : '100% instant on-device signal analysis, no internet needed',
                              style: const TextStyle(
                                fontSize: 11,
                                color: TruthLensColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _useCloudMode,
                        activeColor: TruthLensColors.neonCyan,
                        onChanged: _toggleCloudMode,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Hero Scanner Card
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  borderColor: TruthLensColors.borderCyan,
                  child: Column(
                    children: [
                      const TruthLensLogo(size: 82),
                      const SizedBox(height: 12),
                      const Text(
                        'AI Behavioral & Voice Scanner',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Live Camera Guide · Audio dB Waveform · Automatic Hindi/Hinglish Voice Verdict · 22 Pro Diagnostics',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: TruthLensColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      NeonGradientButton(
                        label: '2-Stage Forensic Calibration Scan',
                        icon: Icons.radar_rounded,
                        onPressed: () => _openScanner(twoStage: true),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: TruthLensColors.neonCyan,
                          side: const BorderSide(color: TruthLensColors.borderCyan),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => _openScanner(twoStage: false),
                        icon: const Icon(Icons.flash_on_rounded, size: 19),
                        label: const Text(
                          'Quick Single-Shot AI Scan',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Feature 19 & 20: Google Account & Wallet Credits Strip
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderColor: TruthLensColors.borderPurple,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profile != null
                                  ? (_profile!.name.isNotEmpty ? _profile!.name : _profile!.email)
                                  : 'Guest / Demo Wallet',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _profile != null
                                  ? 'Wallet: ₹${walletBal.toStringAsFixed(0)} · ${_profile!.freeQuestionsLeft} free · ₹${_ota.pricePerQuestion}/Q'
                                  : 'Demo Credits: ₹${walletBal.toStringAsFixed(0)} · Sign in with Google to sync',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: TruthLensColors.neonEmerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: TruthLensColors.neonPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        onPressed: _openProfileOrLogin,
                        child: Text(
                          _profile == null ? 'Google Sign-In' : 'Profile / Wallet',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Feature 17: Local Session History List (persisted via SharedPreferences)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SESSION HISTORY (${_history.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: TruthLensColors.neonCyan,
                      ),
                    ),
                    if (_history.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          await ApiService.clearHistory();
                          if (mounted) setState(() => _history = []);
                        },
                        child: const Text(
                          'Clear All',
                          style: TextStyle(fontSize: 12, color: TruthLensColors.neonRose),
                        ),
                      ),
                  ],
                ),

                if (_history.isEmpty)
                  const GlassCard(
                    padding: EdgeInsets.all(16),
                    borderColor: Color(0x3394A3B8),
                    child: Text(
                      'No past scans yet. Record your first verification session to save reports here automatically.',
                      style: TextStyle(fontSize: 12, color: TruthLensColors.textMuted),
                    ),
                  )
                else
                  for (final item in _history.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportScreen(
                                report: item,
                                autoSpeakOnOpen: false,
                              ),
                            ),
                          );
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.all(13),
                          borderColor: Color.fromRGBO(
                            _scoreColor(item.consistencyIndex).red,
                            _scoreColor(item.consistencyIndex).green,
                            _scoreColor(item.consistencyIndex).blue,
                            0.45,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _scoreColor(item.consistencyIndex),
                                    width: 2.5,
                                  ),
                                ),
                                child: Text(
                                  '${item.consistencyIndex.round()}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: _scoreColor(item.consistencyIndex),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.question.isNotEmpty
                                          ? item.question
                                          : 'Forensic Scan (${item.analysisMode})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.cognitiveLoadClassification} · Stress ${item.stressPercentage.round()}% · ${item.formattedFileSize}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: TruthLensColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete Report',
                                onPressed: () async {
                                  await ApiService.deleteHistoryItem(item.id);
                                  if (mounted) {
                                    setState(() => _history = ApiService.sessionHistory);
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 19,
                                  color: TruthLensColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                const SizedBox(height: 10),

                // Feature 22: Clear Disclaimer Banner
                GlassCard(
                  padding: const EdgeInsets.all(13),
                  borderColor: const Color(0x4434D399),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          color: TruthLensColors.neonEmerald, size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _ota.consentBanner,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: TruthLensColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
