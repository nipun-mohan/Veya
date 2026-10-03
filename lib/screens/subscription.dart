import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/localization.dart';
import '../core/platform.dart';
import '../core/store.dart';
import '../core/subscription.dart';
import '../core/theme.dart';
import '../widgets/shared.dart';

class SubscriptionScreen extends StatefulWidget {
  final VeyaStore store;
  const SubscriptionScreen({super.key, required this.store});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen>
    with WidgetsBindingObserver {
  bool loading = false;
  bool choosingPayment = false;
  List<Map<String, String>> upiApps = const [];
  Map<String, String>? selectedUpiApp;
  String? _pendingSubscriptionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadUpiApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _pendingSubscriptionId != null &&
        !loading) {
      _verifyPayment(_pendingSubscriptionId!);
    }
  }

  Future<void> _loadUpiApps() async {
    final apps = await AndroidBridge.installedUpiApps();
    if (!mounted) return;
    setState(() {
      upiApps = apps;
      selectedUpiApp = apps.isEmpty ? null : apps.first;
    });
  }

  static const _cashfreeAppKeys = {
    'com.phonepe.app': 'PHONEPE',
    'com.google.android.apps.nbu.paisa.user': 'GPAY',
    'net.one97.paytm': 'PAYTM',
    'in.amazon.mShop.android.shopping': 'AMAZONPAY',
    'in.org.npci.upiapp': 'BHIM',
  };

  Future<void> _startCheckout() async {
    final selected = selectedUpiApp;
    if (selected == null) return;
    setState(() => loading = true);
    try {
      final session = await SubscriptionApi(
        widget.store.endpoint,
      ).createCheckout();
      _pendingSubscriptionId = session.subscriptionId;
      final providerKey = _cashfreeAppKeys[selected['package']];
      final intentUrl = providerKey == null
          ? null
          : session.androidAuthAppLinks[providerKey];
      if (intentUrl == null || intentUrl.isEmpty) {
        throw StateError(
          '${selected['name']} does not support Cashfree UPI AutoPay on this device. Choose another app.',
        );
      }
      final opened = await AndroidBridge.launchUpiIntent(
        intentUrl,
        selected['package']!,
      );
      if (!opened) {
        throw StateError(
          'Could not open ${selected['name']}. Please choose another UPI app.',
        );
      }
      if (mounted) {
        _showMessage(
          'Approve the AutoPay mandate in ${selected['name']}, then return to Veya.',
        );
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _verifyPayment(String subscriptionId) async {
    final id = subscriptionId.isNotEmpty
        ? subscriptionId
        : _pendingSubscriptionId;
    if (id == null) return;
    try {
      final verified = await SubscriptionApi(
        widget.store.endpoint,
      ).verifyCheckout(id);
      if (!mounted) return;
      widget.store.applySubscription(verified);
      setState(() => choosingPayment = false);
      _showMessage('Your subscription is active.');
    } catch (_) {
      await _refresh();
      _showMessage('We are confirming your AutoPay mandate.');
    }
  }

  void _showError(String message) => _showMessage(message, error: true);

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    await widget.store.refreshSubscription();
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final subscription = widget.store.subscription;
    if (subscription?.isTrialing == true) return _activePlan(subscription!);
    return choosingPayment ? _paymentPicker() : _planOverview();
  }

  Widget _planOverview() => Scaffold(
    appBar: AppBar(title: const LText('Upgrade to Premium')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF55D322),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Text(
                  'VEYA PREMIUM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your voice. Beautifully expressed.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          const LText(
            'Pay today',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Text(
                '₹9',
                style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900),
              ),
              SizedBox(width: 12),
              Text(
                'for 5 days',
                style: TextStyle(fontSize: 17, color: VeyaColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const LText(
            'Then ₹129 / month. Cancel anytime.',
            style: TextStyle(color: VeyaColors.muted),
          ),
          const SizedBox(height: 28),
          SurfaceCard(
            child: const Row(
              children: [
                Icon(Icons.autorenew_rounded, color: VeyaColors.teal),
                SizedBox(width: 12),
                Expanded(
                  child: LText(
                    'AutoPay keeps your Premium plan active each month.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: loading
                ? null
                : () => setState(() => choosingPayment = true),
            child: const LText('Choose payment app'),
          ),
          const SizedBox(height: 14),
          const LText(
            'No Veya feature is restricted during this rollout.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VeyaColors.muted, fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _paymentPicker() => Scaffold(
    appBar: AppBar(
      title: const LText('Choose payment app'),
      leading: IconButton(
        onPressed: loading
            ? null
            : () => setState(() => choosingPayment = false),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
              children: [
                const LText(
                  'Set up AutoPay',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const LText(
                  'Choose a UPI app installed on this phone. You will securely confirm the mandate in that app.',
                  style: TextStyle(color: VeyaColors.muted),
                ),
                const SizedBox(height: 22),
                if (upiApps.isEmpty)
                  const SurfaceCard(
                    child: LText(
                      'No supported UPI app was found. Install PhonePe, Google Pay, Paytm, CRED, Amazon Pay, BHIM, or SuperMoney, then reopen this screen.',
                    ),
                  ),
                ...upiApps.map(_upiAppTile),
                if (upiApps.isNotEmpty) const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: loading ? null : _loadUpiApps,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const LText('Refresh installed apps'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: loading ? null : _startCheckout,
                child: loading
                    ? const SizedBox(width: 20, height: 20, child: VeyaLoader())
                    : LText(
                        selectedUpiApp == null
                            ? 'Continue securely'
                            : 'Continue with ${selectedUpiApp!['name']}',
                      ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _upiAppTile(Map<String, String> app) {
    final isSelected = selectedUpiApp?['package'] == app['package'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected
            ? VeyaColors.teal.withValues(alpha: .10)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : () => setState(() => selectedUpiApp = app),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? VeyaColors.teal : VeyaColors.line,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _upiAppIcon(app),
                const SizedBox(width: 14),
                Expanded(
                  child: LText(
                    app['name']!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isSelected ? VeyaColors.teal : VeyaColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _appColor(String packageName) {
    if (packageName.contains('phonepe')) return const Color(0xFF5F259F);
    if (packageName.contains('google')) return const Color(0xFF4285F4);
    if (packageName.contains('paytm')) return const Color(0xFF00B9F5);
    if (packageName.contains('dreamplug')) return const Color(0xFF111111);
    if (packageName.contains('amazon')) return const Color(0xFFFF9900);
    return VeyaColors.teal;
  }

  Widget _upiAppIcon(Map<String, String> app) {
    final encodedIcon = app['icon'];
    if (encodedIcon != null && encodedIcon.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            base64Decode(encodedIcon),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _upiAppInitial(app),
          ),
        );
      } on FormatException {
        // A launcher icon is cosmetic. Preserve a usable fallback if Android
        // returns an icon in an unexpected format.
      }
    }
    return _upiAppInitial(app);
  }

  Widget _upiAppInitial(Map<String, String> app) => CircleAvatar(
    radius: 24,
    backgroundColor: _appColor(app['package']!),
    child: Text(
      app['name']!.substring(0, 1),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
    ),
  );

  Widget _activePlan(SubscriptionStatus subscription) {
    final ending = subscription.trialEndsAt;
    final days = ending == null
        ? null
        : ending.difference(DateTime.now()).inDays.clamp(0, 5) + 1;
    return Scaffold(
      appBar: AppBar(title: const LText('Plan & billing')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText(
                  'Premium is active',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
                const SizedBox(height: 8),
                LText(
                  days == null
                      ? 'Your plan is active.'
                      : '$days day${days == 1 ? '' : 's'} remaining in your trial.',
                  style: const TextStyle(color: VeyaColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const LText('Refresh status'),
          ),
        ],
      ),
    );
  }
}
