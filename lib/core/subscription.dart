import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class SubscriptionStatus {
  final String status;
  final String? provider;
  final String plan;
  final DateTime? trialEndsAt;
  final bool enforcementEnabled;
  final String trialPriceInr;
  final String monthlyPriceInr;
  const SubscriptionStatus({
    required this.status,
    required this.provider,
    required this.plan,
    required this.trialEndsAt,
    required this.enforcementEnabled,
    required this.trialPriceInr,
    required this.monthlyPriceInr,
  });

  bool get isTrialing => status == 'trialing';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> data) =>
      SubscriptionStatus(
        status: data['status'] as String? ?? 'pending_payment',
        provider: data['provider'] as String?,
        plan: data['plan'] as String? ?? 'monthly',
        trialEndsAt: DateTime.tryParse(data['trial_ends_at'] as String? ?? ''),
        enforcementEnabled: data['enforcement_enabled'] as bool? ?? false,
        trialPriceInr: data['trial_price_inr'] as String? ?? '9',
        monthlyPriceInr: data['monthly_price_inr'] as String? ?? '129',
      );
}

class CashfreeSubscriptionSession {
  final String subscriptionId;
  final String? paymentId;
  final Map<String, String> androidAuthAppLinks;

  const CashfreeSubscriptionSession({
    required this.subscriptionId,
    required this.paymentId,
    required this.androidAuthAppLinks,
  });

  factory CashfreeSubscriptionSession.fromJson(Map<String, dynamic> data) =>
      CashfreeSubscriptionSession(
        subscriptionId: data['subscription_id'] as String,
        paymentId: data['payment_id'] as String?,
        androidAuthAppLinks:
            (data['android_auth_app_links'] as Map? ?? const {}).map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ),
      );
}

class SubscriptionApi {
  final String baseUrl;
  const SubscriptionApi(this.baseUrl);

  Future<SubscriptionStatus> status() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in is required.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty)
      throw StateError('Your session expired.');
    final response = await http.get(
      Uri.parse('$baseUrl/v1/subscription'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw StateError('Could not load subscription details.');
    }
    return SubscriptionStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CashfreeSubscriptionSession> createCheckout() async {
    final token = await _token();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/subscription/checkout'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw StateError('Could not start the subscription checkout.');
    }
    return CashfreeSubscriptionSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SubscriptionStatus> verifyCheckout(String subscriptionId) async {
    final token = await _token();
    final response = await http.post(
      Uri.parse('$baseUrl/v1/subscription/verify'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'subscription_id': subscriptionId}),
    );
    if (response.statusCode != 200) {
      throw StateError('Could not verify the payment.');
    }
    return SubscriptionStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in is required.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Your session expired.');
    }
    return token;
  }
}
