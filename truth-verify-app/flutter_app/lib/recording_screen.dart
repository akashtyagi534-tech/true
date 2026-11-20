import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api_service.dart';
import 'report_screen.dart';
import 'theme.dart';

enum ScanStage {
  baselineReady,
  baselineRecording,
  targetReady,
  targetRecording,
  analyzing,
}

class RecordingScreen extends StatefulWidget {
  final bool twoStageMode;
  final OtaAppConfig otaConfig;

  const RecordingScreen({
    super.key,
    required this.twoStageMode,
    required this.otaConfig,
  });

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;

  bool _initializing = true;
  bool _torchOn = false;
  String? _error;

  late ScanStage _stage;
  Timer? _timer;
  int _elapsedSec = 0;

  File? _baselineFile;
  final TextEditingController _questionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stage = widget.twoStageMode ? ScanStage.baselineReady : ScanStage.targetReady;
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    final camStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (!camStatus.isGranted || !micStatus.isGranted) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera aur Microphone permission zaroori hai.';
        });
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'Is phone mein camera nahi mila.';
        });
        return;
      }
      // Prefer back camera if available (supports Flashlight Torch), fallback to index 0
      final backIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _cameraIndex = backIdx >= 0 ? backIdx : 0;
      await _startController(_cameras[_cameraIndex]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera start nahi ho paya: $e';
        });
      }
    }
  }

  Future<void> _startController(CameraDescription desc) async {
    final old = _controller;
    _controller = null;
    await old?.dispose();

    final ctrl = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await ctrl.initialize();
    _torchOn = false;
    try {
      await ctrl.setFlashMode(FlashMode.off);
    } catch (_) {
      // Some lenses do not support flash controls.
    }

    if (!mounted) {
      await ctrl.dispose();
      return;
    }
    setState(() {
      _controller = ctrl;
      _initializing = false;
    });
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording || _stage == ScanStage.analyzing) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startController(_cameras[_cameraIndex]);
  }

  Future<void> _toggleFlashlight() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final bool next = !_torchOn;
    try {
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) {
        setState(() => _torchOn = next);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Is camera lens par Flashlight supported nahi hai — Rear Camera par switch karein!'),
        ),
      );
    }
  }

  bool get _isRecording =>
      _stage == ScanStage.baselineRecording || _stage == ScanStage.targetRecording;

  int get _maxDurationSec =>
      _stage == ScanStage.baselineRecording ? widget.otaConfig.baselineSeconds : 30;

  Future<void> _startRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;

    try {
      await ctrl.startVideoRecording();
      final bool isBaseline = _stage == ScanStage.baselineReady;
      setState(() {
        _elapsedSec = 0;
        _stage = isBaseline ? ScanStage.baselineRecording : ScanStage.targetRecording;
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _elapsedSec += 1);
        if (_elapsedSec >= _maxDurationSec) {
          _stopRecording();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording start error: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !_isRecording) return;
    _timer?.cancel();

    try {
      final XFile recorded = await ctrl.stopVideoRecording();
      final File videoFile = File(recorded.path);

      if (_stage == ScanStage.baselineRecording) {
        if (!mounted) return;
        setState(() {
          _baselineFile = videoFile;
          _elapsedSec = 0;
          _stage = ScanStage.targetReady;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stage 1 Baseline Calibrated! Ab Stage 2 Target sawaal record karein.'),
          ),
        );
        return;
      }

      // Stage 2 Target recorded -> analyze!
      if (!mounted) return;
      setState(() => _stage = ScanStage.analyzing);

      // Turn off torch once recording completes
      if (_torchOn) {
        try {
          await ctrl.setFlashMode(FlashMode.off);
          _torchOn = false;
        } catch (_) {}
      }

      final report = await ApiService.analyzeSession(
        targetVideo: videoFile,
        baselineVideo: _baselineFile,
        question: _questionCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() => _stage = widget.twoStageMode ? ScanStage.baselineReady : ScanStage.targetReady);
      _baselineFile = null;

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReportScreen(report: report)),
      );
    } on LowBalanceException catch (e) {
      if (!mounted) return;
      setState(() => _stage = ScanStage.targetReady);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0E1630),
          title: const Text('Wallet Balance Kam Hai'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Recharge Wallet'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = ScanStage.targetReady);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _questionCtrl.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isBaselinePhase =
        _stage == ScanStage.baselineReady || _stage == ScanStage.baselineRecording;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live Camera Feed
          if (_initializing)
            const Center(
              child: CircularProgressIndicator(color: TruthLensColors.neonCyan),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TruthLensColors.neonRose, fontSize: 15),
                ),
              ),
            )
          else if (_controller != null && _controller!.value.isInitialized)
            Center(child: CameraPreview(_controller!)),

          // Subtle cyber targeting frame
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 290,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _isRecording
                        ? TruthLensColors.neonRose
                        : TruthLensColors.borderCyan,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          // Top HUD Bar (Back, Stage badge, Flashlight Torch, Camera Switch)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _HudCircleButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xBB060B1D),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _isRecording
                                    ? TruthLensColors.neonRose
                                    : TruthLensColors.borderCyan,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isRecording ? Icons.fiber_manual_record : Icons.visibility,
                                  color: _isRecording
                                      ? TruthLensColors.neonRose
                                      : TruthLensColors.neonCyan,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _isRecording
                                        ? 'REC · ${_elapsedSec}s / ${_maxDurationSec}s'
                                        : (isBaselinePhase
                                            ? 'STAGE 1 · BASELINE (${widget.otaConfig.baselineSeconds}s)'
                                            : 'STAGE 2 · TARGET SCAN'),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // FLASHLIGHT TORCH TOGGLE
                        _HudCircleButton(
                          icon: _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                          tooltip: _torchOn ? 'Turn Flashlight OFF' : 'Turn Flashlight ON',
                          active: _torchOn,
                          onTap: _toggleFlashlight,
                        ),
                        const SizedBox(width: 8),
                        _HudCircleButton(
                          icon: Icons.cameraswitch_rounded,
                          tooltip: 'Switch Camera',
                          onTap: _switchCamera,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Visible Consent Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xBB071126),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x5534D399)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user, size: 14, color: TruthLensColors.neonEmerald),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'CONSENT-BASED SCANNER ACTIVE · Visible Recording & Mic ON',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFFD1FAE5)),
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

          // Bottom Control Glass Deck
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderColor: _isRecording
                      ? TruthLensColors.neonRose
                      : TruthLensColors.borderPurple,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isBaselinePhase) ...[
                        const Text(
                          'STAGE 1 — NEUTRAL BASELINE CALIBRATION',
                          style: TextStyle(
                            color: TruthLensColors.neonCyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final q in widget.otaConfig.baselineQuestions.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• $q',
                              style: const TextStyle(fontSize: 12.5, color: Colors.white),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ] else ...[
                        TextField(
                          controller: _questionCtrl,
                          enabled: !_isRecording && _stage != ScanStage.analyzing,
                          style: const TextStyle(fontSize: 13.5),
                          decoration: const InputDecoration(
                            labelText: 'Target Verification Question (Optional)',
                            hintText: 'e.g., Kya aap kal raat office mein the?',
                            prefixIcon: Icon(Icons.help_outline_rounded, size: 19),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_stage == ScanStage.analyzing)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: TruthLensColors.neonCyan,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Running 21-Point AI Forensic Pipeline...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: TruthLensColors.neonCyan,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: NeonGradientButton(
                                label: _isRecording
                                    ? 'STOP & ${isBaselinePhase ? "SAVE BASELINE" : "ANALYZE"}'
                                    : (isBaselinePhase
                                        ? 'START 10s BASELINE'
                                        : 'START TARGET SCAN'),
                                icon: _isRecording
                                    ? Icons.stop_circle_rounded
                                    : Icons.fiber_manual_record_rounded,
                                colors: _isRecording
                                    ? const [TruthLensColors.neonRose, Color(0xFFEF4444)]
                                    : const [TruthLensColors.neonPurple, TruthLensColors.neonCyan],
                                onPressed: _isRecording ? _stopRecording : _startRecording,
                              ),
                            ),
                            if (isBaselinePhase && !_isRecording) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => setState(() => _stage = ScanStage.targetReady),
                                child: const Text(
                                  'Skip',
                                  style: TextStyle(color: TruthLensColors.textMuted),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _HudCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? const Color(0xDD22D3EE) : const Color(0xBB060B1D),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.white : TruthLensColors.borderCyan,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? const Color(0xFF040712) : Colors.white,
          ),
        ),
      ),
    );
  }
}
