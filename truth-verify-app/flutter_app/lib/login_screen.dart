import 'package:flutter/material.dart';

import 'admin_screen.dart';
import 'api_service.dart';
import 'theme.dart';
import 'widgets/truth_lens_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl =
      TextEditingController(text: 'akashtyagi534@gmail.com');
  final TextEditingController _passwordCtrl = TextEditingController();

  AuthProfile? _profile;
  bool _googleBusy = false;
  bool _emailBusy = false;
  String? _error;
  String? _healthStatus;

  @override
  void initState() {
    super.initState();
    _profile = ApiService.currentProfile;
    if (_profile != null) {
      _emailCtrl.text = _profile!.email;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      final profile = await ApiService.signInWithGoogle();
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Signed in as ${profile.name} (${profile.email})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _signInWithEmailOrAdmin() async {
    setState(() {
      _emailBusy = true;
      _error = null;
    });
    try {
      final profile = await ApiService.login(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profile.isAdmin
                ? 'Admin Panel unlocked for ${profile.email}!'
                : 'Signed in as ${profile.email}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _emailBusy = false);
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    setState(() {
      _profile = null;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged out cleanly.')),
    );
  }

  Future<void> _runDiagnostics() async {
    setState(() => _healthStatus = 'Checking Railway backend /health...');
    final res = await ApiService.checkServerHealth();
    if (mounted) {
      setState(() => _healthStatus = res);
    }
  }

  void _openRechargeSheet() {
    final ota = ApiService.otaConfig;
    final amtCtrl = TextEditingController(text: ota.minRecharge.toString());
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
              Text(
                'UPI ID: ${ota.upiId} · Rate: ₹${ota.pricePerQuestion}/question',
                style: const TextStyle(color: TruthLensColors.neonCyan, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount (Min ₹${ota.minRecharge})',
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: utrCtrl,
                decoration: const InputDecoration(
                  labelText: 'UPI UTR / Reference Number',
                  prefixIcon: Icon(Icons.receipt_long),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: TruthLensColors.neonRose, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              NeonGradientButton(
                label: 'Submit Recharge',
                icon: Icons.bolt_rounded,
                loading: busy,
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
                  if (amt < ota.minRecharge || utrCtrl.text.trim().length < 4) {
                    setSheet(() => err = 'Minimum ₹${ota.minRecharge} aur valid UTR ID dalein.');
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

  Widget _buildAvatar(AuthProfile p) {
    if (p.picture.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 36,
        backgroundColor: const Color(0x33A855F7),
        backgroundImage: NetworkImage(p.picture),
        onBackgroundImageError: (_, __) {},
      );
    }
    final String initial = (p.name.isNotEmpty ? p.name[0] : p.email[0]).toUpperCase();
    return CircleAvatar(
      radius: 36,
      backgroundColor: const Color(0x33A855F7),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: TruthLensColors.neonCyan,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final ota = ApiService.otaConfig;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          p == null ? 'SIGN IN' : 'ACCOUNT & PROFILE',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 1.0,
          ),
        ),
      ),
      body: CyberBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            if (p == null) ...[
              // Logged-out Google Sign-In + Email/Admin Flow
              GlassCard(
                padding: const EdgeInsets.all(22),
                borderColor: TruthLensColors.borderCyan,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: TruthLensLogo(size: 84)),
                    const SizedBox(height: 14),
                    const Text(
                      'Truth Lens Pro Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Google se sign-in karein — ${ota.freeQuestions} free trial scans, phir ₹${ota.pricePerQuestion}/question wallet sync.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5, color: TruthLensColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    NeonGradientButton(
                      label: 'Continue with Google',
                      icon: Icons.g_mobiledata_rounded,
                      loading: _googleBusy,
                      colors: const [Color(0xFFFFFFFF), Color(0xFFD6F3FF)],
                      onPressed: _signInWithGoogle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.all(18),
                borderColor: TruthLensColors.borderPurple,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Admin / Email Login',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Admin Control Panel kholne ke liye apna Admin Email aur Password dalein.',
                      style: TextStyle(fontSize: 12, color: TruthLensColors.textMuted),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Admin Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: TruthLensColors.neonRose, fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 14),
                    NeonGradientButton(
                      label: 'Sign In & Sync',
                      icon: Icons.login_rounded,
                      loading: _emailBusy,
                      onPressed: _signInWithEmailOrAdmin,
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Logged-in Profile Card showing Google Name, Email, and Profile Photo
              GlassCard(
                padding: const EdgeInsets.all(20),
                borderColor: TruthLensColors.borderCyan,
                child: Column(
                  children: [
                    _buildAvatar(p),
                    const SizedBox(height: 12),
                    Text(
                      p.name.isNotEmpty ? p.name : p.email,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.email,
                      style: const TextStyle(fontSize: 13, color: TruthLensColors.textMuted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (p.isGoogleUser)
                          const Chip(
                            label: Text('Google Verified', style: TextStyle(fontSize: 11)),
                            backgroundColor: Color(0x3322D3EE),
                          ),
                        if (p.isAdmin)
                          const Chip(
                            label: Text('ADMIN ACCESS', style: TextStyle(fontSize: 11, color: TruthLensColors.neonAmber)),
                            backgroundColor: Color(0x33FBBF24),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0x2234D399),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0x5534D399)),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'WALLET BALANCE',
                                  style: TextStyle(fontSize: 10, color: TruthLensColors.textMuted),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${p.walletBalance.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 24,
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
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0x22A855F7),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0x55A855F7)),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'FREE / TOTAL Qs',
                                  style: TextStyle(fontSize: 10, color: TruthLensColors.textMuted),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${p.freeQuestionsLeft} free · ${p.totalQuestionsAsked}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFE9D5FF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: TruthLensColors.neonPurple,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _openRechargeSheet,
                            icon: const Icon(Icons.add_card_rounded, size: 18),
                            label: const Text('Recharge Wallet'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TruthLensColors.neonRose,
                              side: const BorderSide(color: TruthLensColors.neonRose),
                            ),
                            onPressed: _logout,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Logout'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (p.isAdmin) ...[
                const SizedBox(height: 14),
                NeonGradientButton(
                  label: 'Open Admin Control Panel',
                  icon: Icons.admin_panel_settings_rounded,
                  colors: const [TruthLensColors.neonAmber, Color(0xFFF97316)],
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminScreen()),
                    );
                  },
                ),
              ],
            ],

            const SizedBox(height: 16),

            // Diagnostics Panel
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: TruthLensColors.borderPurple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System Diagnostics',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Server: ${ApiService.baseUrl}\nMode: ${ApiService.useCloudMode ? "Railway Cloud AI Mode" : "On-Device Local Mode"}\nSaved History: ${ApiService.sessionHistory.length} reports',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: TruthLensColors.textMuted,
                    ),
                  ),
                  if (_healthStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _healthStatus!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _healthStatus!.startsWith('OK')
                            ? TruthLensColors.neonEmerald
                            : TruthLensColors.neonAmber,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _runDiagnostics,
                    icon: const Icon(Icons.monitor_heart_rounded, size: 17),
                    label: const Text('Test Railway Server /health'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
