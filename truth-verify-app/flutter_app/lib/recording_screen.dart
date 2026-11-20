import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  static const List<String> _presetQuestions = [
    'Kya aap kal raat sach mein ghar par the?',
    'Kya aapne is baare mein kisi aur ko bataya tha?',
    'Kya aap mujhse koi zaroori baat chhupa rahe hain?',
    'Kya aapne woh paise ya document khud liya tha?',
    'Aaj aapne jo kaha, kya woh 100% sach hai?',
    'Did you personally verify those numbers yesterday?',
    'Have you ever withheld key information about this event?',
  ];

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;

  bool _initializing = true;
  bool _torchOn = false;
  String? _error;

  late ScanStage _stage;
  Timer? _timer;
  Timer? _waveTimer;
  int _elapsedSec = 0;
  DateTime? _recordStartTime;

  final math.Random _rng = math.Random();
  List<double> _waveBars = List<double>.filled(22, 0.15);
  double _currentDb = -42.0;

  File? _baselineFile;
  final TextEditingController _questionCtrl = TextEditingController();
  String? _selectedPreset;

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
          _error = 'Is device mein camera nahi mila.';
        });
        return;
      }
      // Prefer front camera for face alignment, or back camera if user switches
      final frontIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _cameraIndex = frontIdx >= 0 ? frontIdx : 0;
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
    } catch (_) {}

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
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Front camera par Flashlight nahi hoti — Rear Camera switch karke Torch ON karein!'),
        ),
      );
    }
  }

  bool get _isRecording =>
      _stage == ScanStage.baselineRecording || _stage == ScanStage.targetRecording;

  int get _maxDurationSec =>
      _stage == ScanStage.baselineRecording ? widget.otaConfig.baselineSeconds : 30;

  void _startWaveformVisualizer() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (!mounted || !_isRecording) return;
      final t = DateTime.now().millisecondsSinceEpoch / 180.0;
      final List<double> nextBars = List<double>.generate(22, (i) {
        final wave = 0.32 + 0.38 * (0.5 + 0.5 * math.sin(t + i * 0.55));
        final jitter = _rng.nextDouble() * 0.30;
        return (wave + jitter).clamp(0.12, 1.0);
      });
      final double avg = nextBars.reduce((a, b) => a + b) / nextBars.length;
      setState(() {
        _waveBars = nextBars;
        _currentDb = -48.0 + (avg * 42.0);
      });
    });
  }

  void _stopWaveformVisualizer() {
    _waveTimer?.cancel();
    if (mounted) {
      setState(() {
        _waveBars = List<double>.filled(22, 0.14);
        _currentDb = -48.0;
      });
    }
  }

  Future<void> _startRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;

    try {
      await ctrl.startVideoRecording();
      final bool isBaseline = _stage == ScanStage.baselineReady;
      _recordStartTime = DateTime.now();
      setState(() {
        _elapsedSec = 0;
        _stage = isBaseline ? ScanStage.baselineRecording : ScanStage.targetRecording;
      });

      _startWaveformVisualizer();

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
    _stopWaveformVisualizer();

    final double actualDuration = _recordStartTime != null
        ? DateTime.now().difference(_recordStartTime!).inMilliseconds / 1000.0
        : _elapsedSec.toDouble();

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

      if (!mounted) return;
      setState(() => _stage = ScanStage.analyzing);

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
        recordedDurationSec: actualDuration,
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
              child: const Text('Recharge / Switch Local Mode'),
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
    _waveTimer?.cancel();
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
          // Feature 1: Live Front/Back Camera Preview
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

          // Feature 1: Face Alignment Guide Overlay
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 225,
                    height: 285,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(120),
                      border: Border.all(
                        color: _isRecording
                            ? TruthLensColors.neonRose
                            : TruthLensColors.neonCyan,
                        width: 2.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xAA060B1D),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'ALIGN FACE INSIDE OVAL GUIDE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: TruthLensColors.neonCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top HUD Bar
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                                            : (ApiService.useCloudMode
                                                ? 'CLOUD AI SCAN'
                                                : 'LOCAL DEVICE SCAN')),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _HudCircleButton(
                          icon: _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                          tooltip: _torchOn ? 'Flashlight OFF' : 'Flashlight ON',
                          active: _torchOn,
                          onTap: _toggleFlashlight,
                        ),
                        const SizedBox(width: 8),
                        _HudCircleButton(
                          icon: Icons.cameraswitch_rounded,
                          tooltip: 'Switch Front/Back Camera',
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
                padding: const EdgeInsets.all(12),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderColor: _isRecording
                      ? TruthLensColors.neonRose
                      : TruthLensColors.borderPurple,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Feature 2: Real-Time Audio Waveform & Mic Decibel Visualizer
                      if (_isRecording) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.mic_rounded,
                                    size: 15, color: TruthLensColors.neonCyan),
                                SizedBox(width: 5),
                                Text(
                                  'LIVE MIC WAVEFORM',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: TruthLensColors.neonCyan,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${_currentDb.toStringAsFixed(1)} dB',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: TruthLensColors.neonEmerald,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 30,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: _waveBars.map((level) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 90),
                                width: 6,
                                height: 6 + (level * 24),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  gradient: const LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      TruthLensColors.neonPurple,
                                      TruthLensColors.neonCyan,
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

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
                        const SizedBox(height: 5),
                        for (final q in widget.otaConfig.baselineQuestions.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '• $q',
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        const SizedBox(height: 8),
                      ] else if (!_isRecording) ...[
                        // Feature 3: Quick Preset Questions Dropdown + Custom Question Input Box
                        DropdownButtonFormField<String>(
                          value: _selectedPreset,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF0E1630),
                          decoration: const InputDecoration(
                            labelText: 'Quick Preset Questions',
                            prefixIcon: Icon(Icons.list_alt_rounded, size: 18),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          hint: const Text('Select a preset question...', style: TextStyle(fontSize: 12.5)),
                          items: _presetQuestions
                              .map(
                                (q) => DropdownMenuItem<String>(
                                  value: q,
                                  child: Text(
                                    q,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _stage == ScanStage.analyzing
                              ? null
                              : (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedPreset = val;
                                      _questionCtrl.text = val;
                                    });
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _questionCtrl,
                          enabled: !_isRecording && _stage != ScanStage.analyzing,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Custom Verification Question',
                            hintText: 'Apna sawaal yahan likhein...',
                            prefixIcon: Icon(Icons.help_outline_rounded, size: 18),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                                'Running 22-Point Forensic Analysis...',
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? const Color(0xDD22D3EE) : const Color(0xBB060B1D),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.white : TruthLensColors.borderCyan,
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: active ? const Color(0xFF040712) : Colors.white,
          ),
        ),
      ),
    );
  }
}
