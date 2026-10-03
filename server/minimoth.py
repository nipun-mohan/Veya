"""MiniMoth OTP delivery, kept server-side so API keys never enter the APK."""
import os

import httpx


MINIMOTH_API_URL = 'https://api.minimoth.dev'


def _api_key() -> str:
    key = os.environ.get('MINIMOTH_API_KEY', '').strip()
    if not key:
        raise RuntimeError('MiniMoth OTP is not configured.')
    return key


async def _request(client: httpx.AsyncClient, method: str, path: str, **kwargs) -> dict:
    response = await client.request(
        method,
        f'{MINIMOTH_API_URL}{path}',
        headers={'X-Api-Key': _api_key()},
        **kwargs,
    )
    try:
        body = response.json()
    except ValueError:
        body = {}
    if response.is_error:
        code = body.get('code') if isinstance(body, dict) else None
        message = body.get('message') if isinstance(body, dict) else None
        raise ValueError(code or message or 'Could not send a verification code.')
    if not isinstance(body, dict):
        raise RuntimeError('MiniMoth returned an invalid response.')
    return body


async def send_otp(client: httpx.AsyncClient, phone: str) -> dict:
    """Send one WhatsApp-first OTP; MiniMoth handles SMS fallback."""
    return await _request(client, 'POST', '/v1/otp/send', json={'phone': phone})


async def verify_otp(client: httpx.AsyncClient, phone: str, code: str) -> dict:
    return await _request(
        client, 'POST', '/v1/otp/verify', json={'phone': phone, 'code': code},
    )
