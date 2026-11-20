import 'package:flutter/material.dart';
import 'admin_screen.dart';
import 'api_service.dart';
import 'recording_screen.dart';
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
  bool _syncing = true;
  bool _googleBusy = false;

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
      });
    }
    final ota = await ApiService.fetchOtaConfig();
    final refreshed = await ApiService.refreshMe();
    if (mounted) {
      setState(() {
        _ota = ota;
        _profile = refreshed ?? ApiService.currentProfile;
        _syncing = false;
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleBusy = true);
    try {
      final profile = await ApiService.signInWithGoogle();
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Welcome ${profile.name}! Wallet: ₹${profile.walletBalance.toStringAsFixed(0)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Sign-In error: $e — Email/Admin Login use kar sakte hain.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _openEmailOrAdminLogin() {
    final emailCtrl = TextEditingController(text: _profile?.email ?? 'akashtyagi534@gmail.com');
    final passCtrl = TextEditingController();
    bool busy = false;
    String? err;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Email / Admin Sign-In',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Normal user sirf email daalein. Admin Panel unlock karne ke liye Admin Email + Password dalein.',
                style: TextStyle(fontSize: 12, color: TruthLensColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Admin Password (Admin ke liye zaroori)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 10),
                Text(err!, style: const TextStyle(color: TruthLensColors.neonRose, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              NeonGradientButton(
                label: 'Sign In & Sync Wallet',
                icon: Icons.login_rounded,
                loading: busy,
                onPressed: () async {
                  setSheet(() {
                    busy = true;
                    err = null;
                  });
                  try {
                    final profile = await ApiService.login(
                      email: emailCtrl.text,
                      password: passCtrl.text,
                    );
                    if (!mounted) return;
                    setState(() => _profile = profile);
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          profile.isAdmin
                              ? 'Admin unlocked! Upar Shield icon se Admin Panel kholein.'
                              : 'Logged in as ${profile.email}',
                        ),
                      ),
                    );
                  } catch (e) {
                    setSheet(() {
                      busy = false;
                      err = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRechargeSheet() {
    if (_profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recharge karne ke liye pehle Google ya Email se Login karein.')),
      );
      return;
    }
    final amtCtrl = TextEditingController(text: _ota.minRecharge.toString());
    final utrCtrl = TextEditingController();
    bool busy = false;
    String? err;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A1024),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Recharge Wallet (UPI)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.all(12),
                borderColor: TruthLensColors.borderCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UPI ID: ${_ota.upiId}',
                      style: const TextStyle(
                        color: TruthLensColors.neonCyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Price: ₹${_ota.pricePerQuestion}/question · Min Recharge: ₹${_ota.minRecharge}',
                      style: const TextStyle(fontSize: 12, color: TruthLensColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (Min ₹${_ota.minRecharge})',
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: utrCtrl,
                decoration: const InputDecoration(
                  labelText: 'UPI UTR / Transaction Reference ID',
                  prefixIcon: Icon(Icons.receipt_long),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: TruthLensColors.neonRose, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              NeonGradientButton(
                label: 'Submit Recharge Request',
                icon: Icons.bolt_rounded,
                loading: busy,
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
                  if (amt < _ota.minRecharge || utrCtrl.text.trim().length < 4) {
                    setSheet(() => err = 'Valid amount (min ₹${_ota.minRecharge}) aur UTR ID dalein.');
                    return;
                  }
                  setSheet(() {
                    busy = true;
                    err = null;
                  });
                  try {
                    final msg = await ApiService.submitRecharge(amount: amt, utr: utrCtrl.text);
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                  } catch (e) {
                    setSheet(() {
                      busy = false;
                      err = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openServerUrlDialog() {
    final ctrl = TextEditingController(text: ApiService.baseUrl);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1630),
        title: const Text('Railway Backend Server URL'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'https://your-service.up.railway.app',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
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
    );
  }

  Future<void> _openScanner({required bool twoStage}) async {
    if (_profile != null &&
        _profile!.freeQuestionsLeft <= 0 &&
        _profile!.walletBalance < _ota.pricePerQuestion) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Balance kam hai! Per question ₹${_ota.pricePerQuestion} chahiye. Wallet recharge karein.',
          ),
        ),
      );
      _openRechargeSheet();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordingScreen(twoStageMode: twoStage, otaConfig: _ota),
      ),
    );
    _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = _profile?.isAdmin == true;
    final int activeModules =
        _ota.activeDetectors.values.where((v) => v).length;

    return Scaffold(
      body: CyberBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: TruthLensColors.neonCyan,
            onRefresh: _bootstrap,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                // Top Bar
                Row(
                  children: [
                    const TruthLensLogo(size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRUTH LENS PRO',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _syncing
                                ? 'Syncing OTA Engine...'
                                : 'v${_ota.appVersion} · $activeModules AI Biometric Modules',
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
                        tooltip: 'Open Admin Panel',
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminScreen()),
                          );
                          _bootstrap();
                        },
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0x33FBBF24),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: TruthLensColors.neonAmber),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings,
                            color: TruthLensColors.neonAmber,
                            size: 20,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Server Settings',
                      onPressed: _openServerUrlDialog,
                      icon: const Icon(Icons.dns_rounded, color: TruthLensColors.textMuted),
                    ),
                  ],
                ),

                if (_ota.maintenanceMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
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
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Futuristic Hero Card
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  borderColor: TruthLensColors.borderCyan,
                  child: Column(
                    children: [
                      const TruthLensLogo(size: 92),
                      const SizedBox(height: 14),
                      const Text(
                        '21-Point Forensic AI Scanner',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ocular Micro-Expressions · rPPG Heart Rate · 8-12 Hz Voice Tremor · Deepfake Check · Hindi Voice Verdict',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: TruthLensColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 18),
                      NeonGradientButton(
                        label: '2-Stage Forensic Calibration Scan',
                        icon: Icons.radar_rounded,
                        onPressed: () => _openScanner(twoStage: true),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
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

                const SizedBox(height: 16),

                // Google Sign-In & ₹10/Question Wallet Card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  borderColor: TruthLensColors.borderPurple,
                  child: _profile == null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_balance_wallet_rounded,
                                    color: TruthLensColors.neonPurple),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Sign In · ₹${_ota.pricePerQuestion}/Question Wallet',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Google se login karein — ${_ota.freeQuestions} free trial questions, uske baad sirf ₹${_ota.pricePerQuestion}/question.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: TruthLensColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            NeonGradientButton(
                              label: 'Continue with Google',
                              icon: Icons.g_mobiledata_rounded,
                              loading: _googleBusy,
                              colors: const [Color(0xFFFFFFFF), Color(0xFFD8F3FF)],
                              onPressed: _handleGoogleSignIn,
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _openEmailOrAdminLogin,
                              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                              label: const Text('Email / Admin Password Login'),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0x33A855F7),
                                  child: Text(
                                    (_profile!.name.isNotEmpty
                                            ? _profile!.name[0]
                                            : _profile!.email[0])
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: TruthLensColors.neonCyan,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _profile!.name.isNotEmpty
                                            ? _profile!.name
                                            : _profile!.email,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        _profile!.email,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: TruthLensColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Logout',
                                  onPressed: () async {
                                    await ApiService.logout();
                                    if (mounted) setState(() => _profile = null);
                                  },
                                  icon: const Icon(Icons.logout_rounded,
                                      size: 20, color: TruthLensColors.neonRose),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0x2234D399),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0x5534D399)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'WALLET BALANCE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: TruthLensColors.textMuted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${_profile!.walletBalance.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            color: TruthLensColors.neonEmerald,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0x2222D3EE),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0x5522D3EE)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'FREE TRIAL / RATE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: TruthLensColors.textMuted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_profile!.freeQuestionsLeft} free · ₹${_ota.pricePerQuestion}/Q',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            color: TruthLensColors.neonCyan,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: TruthLensColors.neonPurple,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _openRechargeSheet,
                                    icon: const Icon(Icons.add_card_rounded, size: 18),
                                    label: const Text('Recharge Wallet'),
                                  ),
                                ),
                                if (isAdmin) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: TruthLensColors.neonAmber,
                                        side: const BorderSide(
                                            color: TruthLensColors.neonAmber),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => const AdminScreen()),
                                        );
                                        _bootstrap();
                                      },
                                      icon: const Icon(Icons.shield_rounded, size: 18),
                                      label: const Text('Admin Panel'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 14),

                // Consent Notice
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderColor: const Color(0x4434D399),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_rounded,
                          color: TruthLensColors.neonEmerald, size: 20),
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
