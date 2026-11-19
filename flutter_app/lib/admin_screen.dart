import 'package:flutter/material.dart';
import 'api_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _priceCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _freeCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _minCtrl.dispose();
    _freeCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.apiService.fetchAdminOverview();
      final cfg = (res['settings'] as Map<String, dynamic>?) ?? {};
      _priceCtrl.text = '${cfg['price_per_question'] ?? 10}';
      _minCtrl.text = '${cfg['min_recharge'] ?? 50}';
      _freeCtrl.text = '${cfg['free_questions'] ?? 3}';
      _upiCtrl.text = '${cfg['upi_id'] ?? ''}';
      if (!mounted) return;
      setState(() {
        _data = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await widget.apiService.updateAdminSettings(
        pricePerQuestion: int.tryParse(_priceCtrl.text) ?? 10,
        minRecharge: int.tryParse(_minCtrl.text) ?? 50,
        freeQuestions: int.tryParse(_freeCtrl.text) ?? 3,
        upiId: _upiCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing aur UPI settings live save ho gayi!')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runAction(Future<void> Function() fn, String okMessage) async {
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMessage)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _statCard(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: accent),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = (_data?['stats'] as Map<String, dynamic>?) ?? {};
    final recharges = (_data?['recharges'] as List<dynamic>?) ?? [];
    final users = (_data?['users'] as List<dynamic>?) ?? [];
    final alerts = (_data?['alerts'] as List<dynamic>?) ?? [];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Control Center'),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'Pricing'),
              Tab(text: 'Recharges (${stats['pending_recharges'] ?? 0})'),
              Tab(text: 'Users (${users.length})'),
              Tab(text: 'Flagged (${alerts.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      // Tab 1: Overview & Live Pricing
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 2.0,
                            children: [
                              _statCard('Total Revenue', '₹${stats['total_revenue'] ?? 0}', Colors.greenAccent),
                              _statCard('Total Users', '${stats['total_users'] ?? 0}', Colors.lightBlueAccent),
                              _statCard('Questions', '${stats['total_questions'] ?? 0}', Colors.white),
                              _statCard('Flagged Alerts', '${stats['flagged_alerts'] ?? 0}', Colors.redAccent),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Live Pricing & UPI Control',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _priceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Price Per Question (₹)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _minCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Minimum Recharge (₹)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _freeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Free Questions Per User',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _upiCtrl,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Your UPI ID',
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _saving ? null : _saveSettings,
                              child: Text(_saving ? 'Saving...' : 'Save Live Settings'),
                            ),
                          ),
                        ],
                      ),

                      // Tab 2: UPI Recharges
                      recharges.isEmpty
                          ? const Center(child: Text('Abhi koi recharge request nahi hai.'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: recharges.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final r = recharges[i] as Map<String, dynamic>;
                                final isPending = r['status'] == 'pending';
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${r['user_email']}',
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                            Text(
                                              '₹${r['amount']}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.greenAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'UTR: ${r['utr']} · Status: ${r['status']}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                                        ),
                                        if (isPending) ...[
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              FilledButton(
                                                onPressed: () => _runAction(
                                                  () => widget.apiService.handleRechargeAction('${r['id']}', 'approve'),
                                                  'Recharge Approved!',
                                                ),
                                                child: const Text('Approve'),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton(
                                                onPressed: () => _runAction(
                                                  () => widget.apiService.handleRechargeAction('${r['id']}', 'reject'),
                                                  'Recharge Rejected',
                                                ),
                                                child: const Text('Reject'),
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

                      // Tab 3: Users
                      ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: users.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final u = users[i] as Map<String, dynamic>;
                          final isBanned = (u['is_banned'] as bool?) ?? false;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${u['email']}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Wallet: ₹${u['wallet_balance']} · Questions: ${u['total_questions_asked']}${isBanned ? ' · BANNED' : ''}',
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: () => _runAction(
                                          () => widget.apiService.adjustUserWallet('${u['id']}', 50),
                                          '+₹50 added to wallet',
                                        ),
                                        child: const Text('+₹50'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: () => _runAction(
                                          () => widget.apiService.toggleUserBan('${u['id']}'),
                                          isBanned ? 'User Unbanned' : 'User Banned',
                                        ),
                                        child: Text(isBanned ? 'Unban' : 'Ban'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      // Tab 4: Flagged Alerts
                      alerts.isEmpty
                          ? const Center(child: Text('Koi flagged unsafe alert nahi hai.'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: alerts.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final a = alerts[i] as Map<String, dynamic>;
                                final keywords = (a['matched_keywords'] as List<dynamic>?)?.join(', ') ?? '';
                                return Card(
                                  color: const Color(0xFF2B1218),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '🚨 ${a['user_email']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text('${a['question_text']}'),
                                        if (keywords.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Matched: $keywords',
                                            style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Video playback ke liye web Admin Panel (/admin) kholein.',
                                          style: TextStyle(fontSize: 11, color: Colors.white60),
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
    );
  }
}
