"""Cashfree subscription state and seamless UPI AutoPay helpers for Veya."""
from __future__ import annotations

from datetime import UTC, datetime, timedelta
import os
import secrets
from typing import Any

import httpx
from google.cloud import firestore

TRIAL_DAYS = 5
TRIAL_PRICE_INR = '9'
MONTHLY_PRICE_INR = '129'
COLLECTION = os.environ.get('VEYA_SUBSCRIPTIONS_COLLECTION', 'veya_subscriptions')
CASHFREE_API_VERSION = '2025-01-01'


def _timestamp(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace('+00:00', 'Z')


def _from_timestamp(value: Any) -> datetime | None:
    if isinstance(value, datetime): return value.astimezone(UTC)
    if isinstance(value, str):
        try: return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(UTC)
        except ValueError: return None
    return None


class SubscriptionStore:
    """Firestore-backed entitlement records keyed by the Firebase UID."""
    def __init__(self) -> None: self._client: firestore.Client | None = None

    @property
    def client(self) -> firestore.Client:
        if self._client is None: self._client = firestore.Client()
        return self._client

    def entitlement_for(self, uid: str, phone_number: str | None) -> dict[str, Any]:
        reference = self.client.collection(COLLECTION).document(uid)
        snapshot, now = reference.get(), datetime.now(UTC)
        if not snapshot.exists:
            record = {'uid': uid, 'phone_number': phone_number or '', 'status': 'pending_payment',
                      'provider': None, 'plan': 'monthly', 'trial_started_at': None,
                      'trial_ends_at': None, 'created_at': _timestamp(now), 'updated_at': _timestamp(now)}
            reference.set(record)
            return self._public(record, now)
        record = snapshot.to_dict() or {}
        if phone_number and record.get('phone_number') != phone_number:
            reference.set({'phone_number': phone_number, 'updated_at': _timestamp(now)}, merge=True)
            record['phone_number'] = phone_number
        return self._public(record, now)

    def _public(self, record: dict[str, Any], now: datetime) -> dict[str, Any]:
        status = str(record.get('status') or 'pending_payment')
        trial_ends = _from_timestamp(record.get('trial_ends_at'))
        if status == 'trialing' and trial_ends and now >= trial_ends: status = 'trial_ended'
        return {'status': status, 'provider': record.get('provider'), 'plan': record.get('plan', 'monthly'),
                'trial_started_at': record.get('trial_started_at'), 'trial_ends_at': record.get('trial_ends_at'),
                'current_period_ends_at': record.get('current_period_ends_at'),
                'cashfree_subscription_id': record.get('cashfree_subscription_id'), 'enforcement_enabled': False,
                'trial_price_inr': TRIAL_PRICE_INR, 'monthly_price_inr': MONTHLY_PRICE_INR}

    def record_checkout(self, uid: str, subscription_id: str) -> None:
        self.client.collection(COLLECTION).document(uid).set({
            'status': 'payment_pending', 'provider': 'cashfree', 'cashfree_subscription_id': subscription_id,
            'updated_at': _timestamp(datetime.now(UTC))}, merge=True)

    def owns_subscription(self, uid: str, subscription_id: str) -> bool:
        snapshot = self.client.collection(COLLECTION).document(uid).get()
        record = snapshot.to_dict() if snapshot.exists else None
        return bool(record and record.get('cashfree_subscription_id') == subscription_id)

    def record_cashfree_status(self, uid: str, payload: dict[str, Any]) -> None:
        authorization = payload.get('authorization_details') or {}
        authorization_status = str(authorization.get('authorization_status') or '').upper()
        subscription_status = str(payload.get('subscription_status') or '').upper()
        now = datetime.now(UTC)
        update: dict[str, Any] = {'provider': 'cashfree', 'cashfree_subscription_id': payload.get('subscription_id'),
            'cashfree_subscription_status': subscription_status, 'cashfree_authorization_status': authorization_status,
            'updated_at': _timestamp(now)}
        if authorization_status == 'ACTIVE' or subscription_status == 'ACTIVE':
            existing = self.client.collection(COLLECTION).document(uid).get()
            existing_record = (existing.to_dict() or {}) if existing.exists else {}
            existing_trial_end = _from_timestamp(existing_record.get('trial_ends_at'))
            trial_ends = existing_trial_end or now + timedelta(days=TRIAL_DAYS)
            update.update({'status': 'trialing', 'trial_started_at': existing_record.get('trial_started_at') or _timestamp(now),
                'trial_ends_at': _timestamp(trial_ends), 'current_period_ends_at': _timestamp(trial_ends)})
        elif authorization_status in {'FAILED', 'FAILURE'}: update['status'] = 'payment_failed'
        self.client.collection(COLLECTION).document(uid).set(update, merge=True)


def _cashfree() -> tuple[str, dict[str, str]]:
    client_id = os.environ.get('CASHFREE_CLIENT_ID', '').strip()
    client_secret = os.environ.get('CASHFREE_CLIENT_SECRET', '').strip()
    environment = os.environ.get('CASHFREE_ENVIRONMENT', 'sandbox').strip().lower()
    if not client_id or not client_secret: raise RuntimeError('Cashfree credentials are not configured.')
    if environment not in {'sandbox', 'production'}: raise RuntimeError('CASHFREE_ENVIRONMENT must be sandbox or production.')
    base_url = 'https://sandbox.cashfree.com/pg' if environment == 'sandbox' else 'https://api.cashfree.com/pg'
    return base_url, {'x-client-id': client_id, 'x-client-secret': client_secret,
        'x-api-version': CASHFREE_API_VERSION, 'accept': 'application/json', 'content-type': 'application/json'}


async def _cashfree_request(method: str, path: str, **kwargs: Any) -> dict[str, Any]:
    base_url, headers = _cashfree()
    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.request(method, f'{base_url}{path}', headers=headers, **kwargs)
    if response.status_code not in {200, 201, 202}:
        print(f'Cashfree {method} {path} failed: {response.status_code} {response.text[:500]}', flush=True)
        raise RuntimeError('Cashfree could not complete the subscription request.')
    return response.json()


async def create_cashfree_subscription(uid: str, phone_number: str | None, email: str | None) -> dict[str, Any]:
    if not phone_number: raise ValueError('A verified phone number is required for UPI AutoPay.')
    subscription_id, now = f'veya_{uid[:12]}_{secrets.token_hex(6)}', datetime.now(UTC)
    monthly = float(os.environ.get('CASHFREE_MONTHLY_PRICE_INR', MONTHLY_PRICE_INR))
    first_charge_at = now + timedelta(days=TRIAL_DAYS)
    payload = {'subscription_id': subscription_id,
        'customer_details': {'customer_name': 'Veya customer', 'customer_email': email or 'support@heyveya.app',
                             'customer_phone': phone_number.lstrip('+')},
        # A periodic mandate lets Cashfree debit the fixed ₹129 renewal itself.
        # The first debit is delayed for the paid five-day trial.
        'plan_details': {'plan_name': 'Veya Premium Monthly', 'plan_type': 'PERIODIC',
            'plan_currency': 'INR', 'plan_amount': monthly, 'plan_max_amount': monthly,
            'plan_max_cycles': 120, 'plan_intervals': 1, 'plan_interval_type': 'MONTH',
            'plan_note': 'Veya Premium monthly subscription'},
        'authorization_details': {'authorization_amount': float(os.environ.get('CASHFREE_TRIAL_PRICE_INR', TRIAL_PRICE_INR)),
                                  'authorization_amount_refund': False},
        'subscription_meta': {'return_url': os.environ.get('CASHFREE_RETURN_URL',
            'https://heyveya.app/subscription/return?subscription_id={subscription_id}')},
        # The mandate must remain valid beyond its first scheduled debit. The
        # 120-cycle plan is ten years, so use the same validity window.
        'subscription_expiry_time': _timestamp(now + timedelta(days=3653)),
        'subscription_first_charge_time': _timestamp(first_charge_at)}
    response = await _cashfree_request('POST', '/subscriptions', json=payload)
    session_id = response.get('subscription_session_id')
    if not session_id: raise RuntimeError('Cashfree did not return a subscription session.')
    return {'subscription_id': subscription_id, 'subscription_session_id': str(session_id),
            'environment': os.environ.get('CASHFREE_ENVIRONMENT', 'sandbox').strip().lower()}


async def create_cashfree_upi_authorization(subscription_id: str, session_id: str) -> dict[str, Any]:
    """Request Cashfree-issued links; Veya never manufactures mandate URLs."""
    payload = {'subscription_id': subscription_id, 'subscription_session_id': session_id,
        'payment_id': f'auth_{secrets.token_hex(10)}', 'payment_type': 'AUTH',
        'payment_method': {'upi': {'channel': 'link'}}}
    response = await _cashfree_request('POST', '/subscriptions/pay', json=payload)
    links = (((response.get('data') or {}).get('payload') or {}).get('upiIntentData') or {}).get('androidAuthAppLinks') or {}
    if not isinstance(links, dict) or not links: raise RuntimeError('Cashfree did not return Android UPI mandate links.')
    return {'subscription_id': subscription_id, 'payment_id': response.get('payment_id'),
            'android_auth_app_links': {str(key): str(value) for key, value in links.items()},
            'environment': os.environ.get('CASHFREE_ENVIRONMENT', 'sandbox').strip().lower()}


async def fetch_cashfree_subscription(subscription_id: str) -> dict[str, Any]:
    return await _cashfree_request('GET', f'/subscriptions/{subscription_id}')


def cashfree_configuration() -> dict[str, Any]:
    _, headers = _cashfree()
    return {'provider': 'cashfree', 'ready': bool(headers['x-client-id'] and headers['x-client-secret']),
        'environment': os.environ.get('CASHFREE_ENVIRONMENT', 'sandbox').strip() or 'sandbox',
        'monthly_price_inr': os.environ.get('CASHFREE_MONTHLY_PRICE_INR', MONTHLY_PRICE_INR).strip(),
        'trial_days': TRIAL_DAYS,
        'trial_price_inr': os.environ.get('CASHFREE_TRIAL_PRICE_INR', TRIAL_PRICE_INR).strip()}
