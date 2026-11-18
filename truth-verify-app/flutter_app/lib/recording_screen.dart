import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'report_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final ApiService _apiService = ApiService();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isUploading = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (!cameraStatus.isGranted || !micStatus.isGranted) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Camera and microphone permissions are required.';
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'No camera device found.';
        });
        return;
      }

      // Prefer front camera by default
      _selectedCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_selectedCameraIndex < 0) _selectedCameraIndex = 0;

      await _startCameraController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _startCameraController(CameraDescription camera) async {
    await _controller?.dispose();
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await controller.initialize();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _isInitializing = false;
    });
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isRecording || _isUploading) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _startCameraController(_cameras[_selectedCameraIndex]);
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isUploading) {
      return;
    }

    if (_isRecording) {
      _timer?.cancel();
      final XFile recorded = await controller.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _isUploading = true;
      });

      try {
        final report = await _apiService.analyzeVideo(File(recorded.path));
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportScreen(report: report),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isUploading = false;
            _elapsedSeconds = 0;
          });
        }
      }
    } else {
      await controller.startVideoRecording();
      setState(() {
        _isRecording = true;
        _elapsedSeconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsedSeconds++);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TruthVerify'),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              onPressed: _toggleCamera,
              icon: const Icon(Icons.cameraswitch_outlined),
              tooltip: 'Switch camera',
            ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _initCamera,
                          child: const Text('Retry Permissions'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_controller != null) CameraPreview(_controller!),
                          if (_isRecording)
                            Positioned(
                              top: 16,
                              left: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade700,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'REC ${_elapsedSeconds}s',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          if (_isUploading)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: Colors.white),
                                    SizedBox(height: 16),
                                    Text(
                                      'Analyzing video and audio signals...',
                                      style: TextStyle(color: Colors.white, fontSize: 15),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _isUploading ? null : _toggleRecording,
                            style: FilledButton.styleFrom(
                              backgroundColor: _isRecording ? Colors.red.shade700 : const Color(0xFF1D4ED8),
                            ),
                            icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                            label: Text(_isRecording ? 'Stop & Analyze' : 'Start Recording'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
