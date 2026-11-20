import 'package:flutter/material.dart';
import 'api_service.dart';
import 'theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _overview;
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _minRecCtrl = TextEditingController();
  final _freeCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _otaVersionCtrl = TextEditingController();
  final _otaMaintCtrl = TextEditingController();
  final _otaQuestionsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _priceCtrl.dispose();
    _minRecCtrl.dispose();
    _freeCtrl.dispose();
    _upiCtrl.dispose();
    _otaVersionCtrl.dispose();
    _otaMaintCtrl.dispose();
    _otaQuestionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.fetchAdminOverview();
      final s = (data['settings'] as Map<String, dynamic>?) ?? const {};
      final ota = (data['ota_config'] as Map<String, dynamic>?) ?? const {};
      _priceCtrl.text = (s['price_per_question'] ?? 10).toString();
      _minRecCtrl.text = (s['min_recharge'] ?? 50).toString();
      _freeCtrl.text = (s['free_questions'] ?? 3).toString();
      _upiCtrl.text = (s['upi_id'] ?? '').toString();
      _otaVersionCtrl.text = (ota['app_version'] ?? '4.0.0').toString();
      _otaMaintCtrl.text = (ota['maintenance_message'] ?? '').toString();
      final qs = (ota['baseline_questions'] as List<dynamic>?) ?? const [];
      _otaQuestionsCtrl.text = qs.map((e) => e.toString()).join('\n');

      if (mounted) {
        setState(() {
          _overview = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _openWalletAdjustDialog(Map<String, dynamic> user) async {
    final amtCtrl = TextEditingController(text: '50');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1630),
        title: Text('Wallet: ${user['email']}'),
        content: TextField(
          controller: amtCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: TruthLensColors.neonRose),
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
              if (amt <= 0) return;
              Navigator.of(ctx).pop();
              await ApiService.adjustUserWallet(user['id'].toString(), -amt);
              _load();
            },
            child: const Text('- Deduct'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TruthLensColors.neonEmerald),
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text.trim()) ?? 0;
              if (amt <= 0) return;
              Navigator.of(ctx).pop();
              await ApiService.adjustUserWallet(user['id'].toString(), amt);
              _load();
            },
            child: const Text('+ Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = (_overview?['stats'] as Map<String, dynamic>?) ?? const {};
    final users = ((_overview?['users'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final recharges = ((_overview?['recharges'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final scans = ((_overview?['recent_scans'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final alerts = ((_overview?['alerts'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredUsers = users.where((u) {
      if (query.isEmpty) return true;
      return (u['email'] ?? '').toString().toLowerCase().contains(query) ||
          (u['name'] ?? '').toString().toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ADMIN CONTROL CENTER',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.0),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: TruthLensColors.neonCyan,
          labelColor: TruthLensColors.neonCyan,
          unselectedLabelColor: TruthLensColors.textMuted,
          tabs: [
            Tab(text: 'Users (${users.length})'),
            Tab(text: 'Recharges (${stats['pending_recharges'] ?? 0})'),
            const Tab(text: 'Pricing & OTA'),
            Tab(text: 'Scans (${scans.length})'),
            Tab(text: 'Flagged (${alerts.length})'),
          ],
        ),
      ),
      body: CyberBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: TruthLensColors.neonCyan))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: TruthLensColors.neonRose),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // 6 KPI Analytics Strip
                      SizedBox(
                        height: 86,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                          children: [
                            _KpiBox('Users', '${stats['total_users'] ?? 0}', TruthLensColors.neonCyan),
                            _KpiBox('Total Scans', '${stats['total_scans'] ?? stats['total_questions'] ?? 0}', TruthLensColors.neonPurple),
                            _KpiBox('Revenue', '₹${stats['total_revenue'] ?? 0}', TruthLensColors.neonEmerald),
                            _KpiBox('Wallets', '₹${stats['active_wallet_balances'] ?? 0}', const Color(0xFF67E8F9)),
                            _KpiBox('Pending ₹', '${stats['pending_recharges'] ?? 0}', TruthLensColors.neonAmber),
                            _KpiBox('Flagged', '${stats['flagged_alerts'] ?? 0}', TruthLensColors.neonRose),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            // TAB 1: USERS
                            Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                                  child: TextField(
                                    controller: _searchCtrl,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      hintText: 'Search Google user by email or name...',
                                      prefixIcon: Icon(Icons.search_rounded),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                                    itemCount: filteredUsers.length,
                                    itemBuilder: (ctx, idx) {
                                      final u = filteredUsers[idx];
                                      final banned = u['is_banned'] == true;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: GlassCard(
                                          padding: const EdgeInsets.all(14),
                                          borderColor: banned
                                              ? TruthLensColors.neonRose
                                              : TruthLensColors.borderPurple,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          (u['email'] ?? '').toString(),
                                                          style: const TextStyle(
                                                            fontWeight: FontWeight.w800,
                                                            fontSize: 13.5,
                                                          ),
                                                        ),
                                                        Text(
                                                          'Wallet: ₹${u['wallet_balance']} · Qs: ${u['total_questions_asked']} ${u['google_connected'] == true ? '· Google' : ''}',
                                                          style: const TextStyle(
                                                            fontSize: 11.5,
                                                            color: TruthLensColors.textMuted,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: banned
                                                          ? const Color(0x33FB7185)
                                                          : const Color(0x3334D399),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      banned ? 'BLOCKED' : 'ACTIVE',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w800,
                                                        color: banned
                                                            ? TruthLensColors.neonRose
                                                            : TruthLensColors.neonEmerald,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: OutlinedButton.icon(
                                                      onPressed: () => _openWalletAdjustDialog(u),
                                                      icon: const Icon(Icons.account_balance_wallet,
                                                          size: 16),
                                                      label: const Text('Add / Deduct ₹'),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  OutlinedButton.icon(
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: banned
                                                          ? TruthLensColors.neonEmerald
                                                          : TruthLensColors.neonRose,
                                                    ),
                                                    onPressed: () async {
                                                      await ApiService.toggleUserBan(
                                                          u['id'].toString());
                                                      _load();
                                                    },
                                                    icon: Icon(
                                                      banned ? Icons.lock_open : Icons.block,
                                                      size: 16,
                                                    ),
                                                    label: Text(banned ? 'Unblock' : 'Block'),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),

                            // TAB 2: RECHARGES
                            ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: recharges.length,
                              itemBuilder: (ctx, idx) {
                                final r = recharges[idx];
                                final pending = r['status'] == 'pending';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GlassCard(
                                    padding: const EdgeInsets.all(14),
                                    borderColor: pending
                                        ? TruthLensColors.neonAmber
                                        : TruthLensColors.borderCyan,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                (r['user_email'] ?? '').toString(),
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            Text(
                                              '₹${r['amount']}',
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w900,
                                                color: TruthLensColors.neonEmerald,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'UTR: ${r['utr']} · Status: ${r['status']}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: TruthLensColors.textMuted,
                                          ),
                                        ),
                                        if (pending) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: FilledButton.icon(
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: TruthLensColors.neonEmerald,
                                                    foregroundColor: const Color(0xFF040712),
                                                  ),
                                                  onPressed: () async {
                                                    await ApiService.handleRecharge(
                                                        r['id'].toString(), 'approve');
                                                    _load();
                                                  },
                                                  icon: const Icon(Icons.check, size: 18),
                                                  label: const Text('Approve'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: TruthLensColors.neonRose,
                                                  ),
                                                  onPressed: () async {
                                                    await ApiService.handleRecharge(
                                                        r['id'].toString(), 'reject');
                                                    _load();
                                                  },
                                                  icon: const Icon(Icons.close, size: 18),
                                                  label: const Text('Reject'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            // TAB 3: PRICING & OTA
                            ListView(
                              padding: const EdgeInsets.all(14),
                              children: [
                                GlassCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Live Pricing & UPI Settings',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _priceCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Price Per Question (₹)'),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _minRecCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Minimum Recharge (₹)'),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _freeCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Free Trial Questions'),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _upiCtrl,
                                        decoration: const InputDecoration(labelText: 'Your UPI ID'),
                                      ),
                                      const SizedBox(height: 14),
                                      NeonGradientButton(
                                        label: 'Save Pricing & UPI Live',
                                        icon: Icons.save_rounded,
                                        onPressed: () async {
                                          await ApiService.updateAdminSettings(
                                            pricePerQuestion: int.tryParse(_priceCtrl.text) ?? 10,
                                            minRecharge: int.tryParse(_minRecCtrl.text) ?? 50,
                                            freeQuestions: int.tryParse(_freeCtrl.text) ?? 3,
                                            upiId: _upiCtrl.text,
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                                content: Text('Pricing & UPI updated live!')),
                                          );
                                          _load();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                GlassCard(
                                  borderColor: TruthLensColors.borderCyan,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Over-The-Air (OTA) App Push',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'No APK rebuild needed — changes reflect immediately on all phones.',
                                        style: TextStyle(
                                            fontSize: 11.5, color: TruthLensColors.textMuted),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _otaVersionCtrl,
                                        decoration:
                                            const InputDecoration(labelText: 'Live App Version'),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _otaMaintCtrl,
                                        decoration: const InputDecoration(
                                            labelText: 'Notice / Maintenance Banner (optional)'),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: _otaQuestionsCtrl,
                                        maxLines: 3,
                                        decoration: const InputDecoration(
                                            labelText: 'Baseline Questions (1 per line)'),
                                      ),
                                      const SizedBox(height: 14),
                                      NeonGradientButton(
                                        label: 'Push OTA Config Live',
                                        icon: Icons.cloud_upload_rounded,
                                        onPressed: () async {
                                          final qs = _otaQuestionsCtrl.text
                                              .split('\n')
                                              .map((s) => s.trim())
                                              .where((s) => s.isNotEmpty)
                                              .toList();
                                          await ApiService.updateOtaConfig(
                                            appVersion: _otaVersionCtrl.text,
                                            maintenanceMessage: _otaMaintCtrl.text,
                                            baselineQuestions: qs,
                                          );
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                                content: Text('OTA update pushed to all apps!')),
                                          );
                                          _load();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // TAB 4: RECENT SCANS
                            ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: scans.length,
                              itemBuilder: (ctx, idx) {
                                final sc = scans[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GlassCard(
                                    padding: const EdgeInsets.all(14),
                                    borderColor: TruthLensColors.borderCyan,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                (sc['user_email'] ?? '').toString(),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: TruthLensColors.neonCyan,
                                                    fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            Text(
                                              '${sc['consistency_score']}%',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: TruthLensColors.neonEmerald),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (sc['question'] ?? sc['title'] ?? '').toString(),
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (sc['verdict'] ?? '').toString(),
                                          style: const TextStyle(
                                              fontSize: 12, color: TruthLensColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            // TAB 5: FLAGGED ALERTS
                            ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: alerts.length,
                              itemBuilder: (ctx, idx) {
                                final a = alerts[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GlassCard(
                                    padding: const EdgeInsets.all(14),
                                    borderColor: TruthLensColors.neonRose,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (a['user_email'] ?? '').toString(),
                                          style: const TextStyle(
                                            color: TruthLensColors.neonRose,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (a['question_text'] ?? '').toString(),
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Keywords: ${((a['matched_keywords'] as List?) ?? const []).join(", ")}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFFFDA4AF),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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

class _KpiBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiBox(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TruthLensColors.surfaceGlass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Color.fromRGBO(color.red, color.green, color.blue, 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: TruthLensColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
