"""Razorpay subscription state and AutoPay helpers for Veya."""
from __future__ import annotations

from datetime import UTC, datetime, timedelta
import hashlib
import hmac
import os
from typing import Any

import httpx
from google.cloud import firestore

TRIAL_DAYS = 5
MONTHLY_PRICE_INR = '129'
COLLECTION = os.environ.get('VEYA_SUBSCRIPTIONS_COLLECTION', 'veya_subscriptions')


def _timestamp(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace('+00:00', 'Z')


def _from_timestamp(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value.astimezone(UTC)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(UTC)
        except ValueError:
            return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, UTC)
    return None


class SubscriptionStore:
    """Firestore-backed entitlement records keyed by the Firebase UID."""

    def __init__(self) -> None:
        self._client: firestore.Client | None = None

    @property
    def client(self) -> firestore.Client:
        if self._client is None:
            self._client = firestore.Client()
        return self._client

    def entitlement_for(self, uid: str, phone_number: str | None) -> dict[str, Any]:
        reference = self.client.collection(COLLECTION).document(uid)
        snapshot, now = reference.get(), datetime.now(UTC)
        if not snapshot.exists:
            record = {
                'uid': uid, 'phone_number': phone_number or '', 'status': 'pending_payment',
                'provider': None, 'plan': 'monthly', 'trial_started_at': None,
                'trial_ends_at': None, 'created_at': _timestamp(now), 'updated_at': _timestamp(now),
            }
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
        if status == 'trialing' and trial_ends and now >= trial_ends:
            status = 'active'
        return {
            'status': status, 'provider': record.get('provider'), 'plan': record.get('plan', 'monthly'),
            'trial_started_at': record.get('trial_started_at'), 'trial_ends_at': record.get('trial_ends_at'),
            'current_period_ends_at': record.get('current_period_ends_at'),
            'subscription_id': record.get('subscription_id'), 'enforcement_enabled': False,
            'trial_price_inr': '0', 'monthly_price_inr': MONTHLY_PRICE_INR,
        }

    def record_checkout(self, uid: str, subscription_id: str) -> None:
        self.client.collection(COLLECTION).document(uid).set({
            'status': 'payment_pending', 'provider': 'razorpay', 'subscription_id': subscription_id,
            'updated_at': _timestamp(datetime.now(UTC)),
        }, merge=True)

    def owns_subscription(self, uid: str, subscription_id: str) -> bool:
        snapshot = self.client.collection(COLLECTION).document(uid).get()
        record = snapshot.to_dict() if snapshot.exists else None
        return bool(record and record.get('provider') == 'razorpay' and record.get('subscription_id') == subscription_id)

    def record_razorpay_status(self, uid: str, payload: dict[str, Any], event_id: str | None = None) -> None:
        now = datetime.now(UTC)
        provider_status = str(payload.get('status') or '').lower()
        existing_snapshot = self.client.collection(COLLECTION).document(uid).get()
        existing_record = (existing_snapshot.to_dict() or {}) if existing_snapshot.exists else {}
        if event_id and hmac.compare_digest(str(existing_record.get('last_razorpay_event_id') or ''), event_id):
            return
        # Webhooks can arrive out of order. Do not let an older pending event
        # overwrite a subscription that was already authenticated or active.
        existing_provider_status = str(existing_record.get('razorpay_subscription_status') or '').lower()
        if existing_provider_status in {'authenticated', 'active'} and provider_status == 'pending':
            return
        start_at = _from_timestamp(payload.get('start_at'))
        current_end = _from_timestamp(payload.get('current_end'))
        update: dict[str, Any] = {
            'provider': 'razorpay', 'subscription_id': payload.get('id'),
            'razorpay_subscription_status': provider_status, 'updated_at': _timestamp(now),
        }
        if event_id:
            update['last_razorpay_event_id'] = event_id
        if provider_status in {'authenticated', 'active'}:
            trial_ends = start_at or existing_record.get('trial_ends_at') or now + timedelta(days=TRIAL_DAYS)
            status = 'trialing' if isinstance(trial_ends, datetime) and now < trial_ends else 'active'
            update.update({
                'status': status,
                'trial_started_at': existing_record.get('trial_started_at') or _timestamp(now),
                'trial_ends_at': _timestamp(trial_ends) if isinstance(trial_ends, datetime) else trial_ends,
                'current_period_ends_at': _timestamp(current_end) if current_end else existing_record.get('current_period_ends_at'),
            })
        elif provider_status in {'pending', 'halted', 'cancelled', 'completed', 'expired'}:
            update['status'] = 'payment_failed' if provider_status in {'pending', 'halted'} else provider_status
        self.client.collection(COLLECTION).document(uid).set(update, merge=True)

    def uid_for_subscription(self, subscription_id: str) -> str | None:
        matches = self.client.collection(COLLECTION).where('subscription_id', '==', subscription_id).limit(1).stream()
        document = next(matches, None)
        return document.id if document else None


def _razorpay_credentials() -> tuple[str, str]:
    key_id = os.environ.get('RAZORPAY_KEY_ID', '').strip()
    key_secret = os.environ.get('RAZORPAY_KEY_SECRET', '').strip()
    if not key_id or not key_secret:
        raise RuntimeError('Razorpay credentials are not configured.')
    return key_id, key_secret


async def _razorpay_request(method: str, path: str, **kwargs: Any) -> dict[str, Any]:
    key_id, key_secret = _razorpay_credentials()
    async with httpx.AsyncClient(timeout=30) as client:
        response = await client.request(
            method, f'https://api.razorpay.com/v1{path}', auth=(key_id, key_secret), **kwargs,
        )
    if response.status_code not in {200, 201, 202}:
        print(f'Razorpay {method} {path} failed: {response.status_code} {response.text[:500]}', flush=True)
        raise RuntimeError('Razorpay could not complete the subscription request.')
    return response.json()


async def create_razorpay_subscription(uid: str, phone_number: str | None, email: str | None) -> dict[str, Any]:
    """Create a monthly Razorpay subscription with a five-day free trial."""
    key_id, _ = _razorpay_credentials()
    plan_id = os.environ.get('RAZORPAY_PLAN_ID', '').strip()
    if not plan_id:
        raise RuntimeError('RAZORPAY_PLAN_ID is not configured.')
    now = datetime.now(UTC)
    start_at = now + timedelta(days=TRIAL_DAYS)
    payload = {
        'plan_id': plan_id, 'total_count': 120, 'quantity': 1, 'customer_notify': False,
        'start_at': int(start_at.timestamp()),
        'expire_by': int((now + timedelta(days=1)).timestamp()),
        'notes': {'uid': uid, 'product': 'veya_premium'},
    }
    response = await _razorpay_request('POST', '/subscriptions', json=payload)
    subscription_id = str(response.get('id') or '')
    if not subscription_id.startswith('sub_'):
        raise RuntimeError('Razorpay did not return a subscription ID.')
    return {
        'subscription_id': subscription_id, 'key_id': key_id, 'name': 'Veya',
        'description': 'Veya Premium — ₹129/month after a 5-day free trial',
        'prefill': {'contact': phone_number or '', 'email': email or ''},
    }


async def fetch_razorpay_subscription(subscription_id: str) -> dict[str, Any]:
    return await _razorpay_request('GET', f'/subscriptions/{subscription_id}')


def verify_razorpay_checkout(subscription_id: str, payment_id: str, signature: str) -> bool:
    _, secret = _razorpay_credentials()
    message = f'{payment_id}|{subscription_id}'.encode()
    expected = hmac.new(secret.encode(), message, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


def verify_razorpay_webhook(raw_body: bytes, signature: str) -> bool:
    secret = os.environ.get('RAZORPAY_WEBHOOK_SECRET', '').strip()
    if not secret or not signature:
        return False
    expected = hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature)


def razorpay_configuration() -> dict[str, Any]:
    key_id = os.environ.get('RAZORPAY_KEY_ID', '').strip()
    plan_id = os.environ.get('RAZORPAY_PLAN_ID', '').strip()
    return {
        'provider': 'razorpay', 'ready': bool(key_id and os.environ.get('RAZORPAY_KEY_SECRET', '').strip() and plan_id),
        'monthly_price_inr': os.environ.get('RAZORPAY_MONTHLY_PRICE_INR', MONTHLY_PRICE_INR).strip(),
        'trial_days': TRIAL_DAYS, 'trial_price_inr': '0',
    }
