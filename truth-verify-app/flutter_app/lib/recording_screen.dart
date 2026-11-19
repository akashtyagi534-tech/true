import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'admin_screen.dart';
import 'api_service.dart';
import 'report_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _questionController = TextEditingController();

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
    _boot();
  }

  Future<void> _boot() async {
    await _apiService.init();
    if (mounted) setState(() {});
    await _initCamera();
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
      ResolutionPreset.low,
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

  Future<void> _openServerSettings() async {
    final textController = TextEditingController(text: _apiService.baseUrl);
    String? statusText;
    bool checking = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Railway Server URL'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Railway → Networking → Generate Domain se mila apna live URL paste karein (khali chhodne par On-Device Mode chalega):',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'https://your-app.up.railway.app',
                    ),
                  ),
                  if (statusText != null) ...[
                    const SizedBox(height: 10),
                    Text(statusText!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: checking
                      ? null
                      : () async {
                          setModalState(() {
                            checking = true;
                            statusText = 'Checking /health...';
                          });
                          await _apiService.saveUrl(textController.text);
                          if (_apiService.baseUrl.isEmpty) {
                            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                            if (mounted) setState(() {});
                            return;
                          }
                          try {
                            final ok = await _apiService.checkHealth();
                            if (ok) {
                              await _apiService.fetchPublicConfig();
                              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Railway Connected: ${_apiService.baseUrl}')),
                                );
                              }
                            } else {
                              setModalState(() {
                                checking = false;
                                statusText = 'Saved, lekin /health 200 OK nahi mila. Railway Root Directory (/backend) check karein.';
                              });
                            }
                          } catch (e) {
                            setModalState(() {
                              checking = false;
                              statusText = 'Saved, server unreachable: $e';
                            });
                          }
                        },
                  child: Text(checking ? 'Checking...' : 'Test & Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openAccountDialog() async {
    final emailCtrl = TextEditingController(text: _apiService.currentUser?.email ?? '');
    final nameCtrl = TextEditingController(text: _apiService.currentUser?.name ?? '');
    final passCtrl = TextEditingController();
    String? err;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final user = _apiService.currentUser;
            if (user != null) {
              return AlertDialog(
                title: Text(user.name),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.email, style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    Text('Free Questions Left: ${user.freeQuestionsLeft}'),
                    Text('Wallet Balance: ₹${user.walletBalance.toStringAsFixed(0)}'),
                    if (user.isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(dialogCtx).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AdminScreen(apiService: _apiService),
                              ),
                            );
                          },
                          icon: const Icon(Icons.admin_panel_settings, color: Colors.amber),
                          label: const Text('Open Admin Panel'),
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await _apiService.logout();
                      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                      if (mounted) setState(() {});
                    },
                    child: const Text('Logout'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogCtx).pop();
                      _openRechargeDialog();
                    },
                    child: const Text('+ Recharge'),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: const Text('Truth Lens Login'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pehle ${_apiService.freeQuestionsDefault} sawaal FREE, phir ₹${_apiService.pricePerQuestion}/sawaal.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Email'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Admin Password (optional)',
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setModalState(() {
                            busy = true;
                            err = null;
                          });
                          try {
                            await _apiService.devLogin(
                              email: emailCtrl.text,
                              name: nameCtrl.text,
                              password: passCtrl.text,
                            );
                            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                            if (mounted) setState(() {});
                          } catch (e) {
                            setModalState(() {
                              busy = false;
                              err = '$e';
                            });
                          }
                        },
                  child: Text(busy ? 'Signing in...' : 'Login'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openRechargeDialog() async {
    final amtCtrl = TextEditingController(text: '${_apiService.minRecharge}');
    final utrCtrl = TextEditingController();
    String? msg;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Wallet Recharge'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Min ₹${_apiService.minRecharge} · UPI ID: ${_apiService.upiId}',
                    style: const TextStyle(fontSize: 13, color: Colors.lightBlueAccent),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Amount (₹)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: utrCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'UPI Reference / UTR Number',
                    ),
                  ),
                  if (msg != null) ...[
                    const SizedBox(height: 8),
                    Text(msg!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setModalState(() => busy = true);
                          try {
                            final res = await _apiService.requestRecharge(
                              amount: double.tryParse(amtCtrl.text) ?? 0,
                              utr: utrCtrl.text,
                            );
                            setModalState(() {
                              busy = false;
                              msg = res;
                            });
                          } catch (e) {
                            setModalState(() {
                              busy = false;
                              msg = '$e';
                            });
                          }
                        },
                  child: Text(busy ? 'Sending...' : 'Submit UTR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isUploading) {
      return;
    }

    if (_isRecording) {
      _timer?.cancel();
      final recordedDuration = _elapsedSeconds;
      final XFile recorded = await controller.stopVideoRecording();
      setState(() {
        _isRecording = false;
        _isUploading = true;
      });

      try {
        final report = await _apiService.analyzeVideo(
          File(recorded.path),
          question: _questionController.text.trim(),
          durationSeconds: recordedDuration,
        );
        if (!mounted) return;
        setState(() {}); // refresh wallet pill if updated
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReportScreen(report: report),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 7),
            content: Text('$e'),
            action: SnackBarAction(
              label: 'Recharge',
              onPressed: _openRechargeDialog,
            ),
          ),
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
    _questionController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _apiService.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Truth Lens Pro'),
        actions: [
          if (user != null && user.isAdmin)
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminScreen(apiService: _apiService),
                  ),
                );
              },
              icon: const Icon(Icons.admin_panel_settings, color: Colors.amber),
              tooltip: 'Admin Panel',
            ),
          if (user != null)
            TextButton(
              onPressed: _openAccountDialog,
              child: Text(
                'F:${user.freeQuestionsLeft} · ₹${user.walletBalance.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else
            IconButton(
              onPressed: _openAccountDialog,
              icon: const Icon(Icons.person_outline),
              tooltip: 'Login / Wallet',
            ),
          IconButton(
            onPressed: _openServerSettings,
            icon: Icon(
              Icons.dns_outlined,
              color: _apiService.baseUrl.isNotEmpty ? Colors.lightGreenAccent : null,
            ),
            tooltip: 'Railway Server URL',
          ),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _questionController,
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          hintText: 'Sawaal likhein (e.g. Kal shaam 6 baje kahan the?)',
                          suffixIcon: _apiService.baseUrl.isEmpty
                              ? TextButton(
                                  onPressed: _openServerSettings,
                                  child: const Text('Local'),
                                )
                              : null,
                        ),
                      ),
                    ),
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
                        padding: const EdgeInsets.all(16),
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
