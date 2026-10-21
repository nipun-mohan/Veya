import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../core/localization.dart';
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

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late final Razorpay _razorpay;
  bool loading = false;
  String? _pendingSubscriptionId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _refresh();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _startCheckout() async {
    setState(() => loading = true);
    try {
      final session = await SubscriptionApi(
        widget.store.endpoint,
      ).createCheckout();
      _pendingSubscriptionId = session.subscriptionId;
      // Styling and eligible payment methods come from Razorpay Dashboard.
      _razorpay.open({
        'key': session.keyId,
        'subscription_id': session.subscriptionId,
        'name': session.name,
        'description': session.description,
        'prefill': {'contact': session.contact, 'email': session.email},
        // Veya already verifies the phone number during sign-in. Do not ask
        // the customer to enter contact details again in Checkout.
        'hidden': {'contact': true, 'email': true},
        'readonly': {'contact': true, 'email': true},
      });
    } catch (error) {
      _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final subscriptionId = _pendingSubscriptionId;
    final paymentId = response.paymentId;
    final signature = response.signature;
    if (subscriptionId == null || paymentId == null || signature == null) {
      _showMessage(
        'Razorpay returned an incomplete payment result.',
        error: true,
      );
      return;
    }
    setState(() => loading = true);
    try {
      final verified = await SubscriptionApi(widget.store.endpoint)
          .verifyCheckout(
            subscriptionId: subscriptionId,
            paymentId: paymentId,
            signature: signature,
          );
      if (!mounted) return;
      widget.store.applySubscription(verified);
      _showMessage('Your AutoPay subscription is active.');
    } catch (_) {
      await _refresh();
      _showMessage('We are confirming your AutoPay mandate.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) => _showMessage(
    response.message ?? 'Payment could not be completed. Please try again.',
    error: true,
  );

  void _onExternalWallet(ExternalWalletResponse response) => _showMessage(
    '${response.walletName ?? 'This wallet'} is not available for this AutoPay subscription.',
    error: true,
  );

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      await widget.store.refreshSubscription();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subscription = widget.store.subscription;
    if (subscription?.isTrialing == true) return _activePlan(subscription!);
    return _planOverview();
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
            'Start today',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Text(
                '5 days free',
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
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
                    'Approve a Razorpay AutoPay mandate to keep Premium active each month.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: loading ? null : _startCheckout,
            child: loading
                ? const SizedBox(width: 20, height: 20, child: VeyaLoader())
                : const LText('Set up AutoPay'),
          ),
          const SizedBox(height: 14),
          const LText(
            'Payment methods and checkout appearance are managed securely in Razorpay.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VeyaColors.muted, fontSize: 12),
          ),
        ],
      ),
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
                      : '$days day${days == 1 ? '' : 's'} remaining in your free trial.',
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
