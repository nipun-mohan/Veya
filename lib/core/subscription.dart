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

  bool get isTrialing => status == 'trialing' || status == 'active';

  factory SubscriptionStatus.fromJson(Map<String, dynamic> data) =>
      SubscriptionStatus(
        status: data['status'] as String? ?? 'pending_payment',
        provider: data['provider'] as String?,
        plan: data['plan'] as String? ?? 'monthly',
        trialEndsAt: DateTime.tryParse(data['trial_ends_at'] as String? ?? ''),
        enforcementEnabled: data['enforcement_enabled'] as bool? ?? false,
        trialPriceInr: data['trial_price_inr'] as String? ?? '0',
        monthlyPriceInr: data['monthly_price_inr'] as String? ?? '129',
      );
}

class RazorpaySubscriptionSession {
  final String subscriptionId;
  final String keyId;
  final String name;
  final String description;
  final String contact;
  final String email;

  const RazorpaySubscriptionSession({
    required this.subscriptionId,
    required this.keyId,
    required this.name,
    required this.description,
    required this.contact,
    required this.email,
  });

  factory RazorpaySubscriptionSession.fromJson(Map<String, dynamic> data) {
    final prefill = data['prefill'] as Map? ?? const {};
    return RazorpaySubscriptionSession(
      subscriptionId: data['subscription_id'] as String,
      keyId: data['key_id'] as String,
      name: data['name'] as String? ?? 'Veya',
      description:
          data['description'] as String? ?? 'Veya Premium subscription',
      contact: prefill['contact'] as String? ?? '',
      email: prefill['email'] as String? ?? '',
    );
  }
}

class SubscriptionApi {
  final String baseUrl;
  const SubscriptionApi(this.baseUrl);

  Future<SubscriptionStatus> status() async {
    final response = await http.get(
      Uri.parse('$baseUrl/v1/subscription'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (response.statusCode != 200)
      throw StateError('Could not load subscription details.');
    return SubscriptionStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<RazorpaySubscriptionSession> createCheckout() async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/subscription/checkout'),
      headers: {'Authorization': 'Bearer ${await _token()}'},
    );
    if (response.statusCode != 200)
      throw StateError('Could not start the subscription checkout.');
    return RazorpaySubscriptionSession.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<SubscriptionStatus> verifyCheckout({
    required String subscriptionId,
    required String paymentId,
    required String signature,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/v1/subscription/verify'),
      headers: {
        'Authorization': 'Bearer ${await _token()}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'subscription_id': subscriptionId,
        'payment_id': paymentId,
        'signature': signature,
      }),
    );
    if (response.statusCode != 200)
      throw StateError('Could not verify the payment.');
    return SubscriptionStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in is required.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty)
      throw StateError('Your session expired.');
    return token;
  }
}
