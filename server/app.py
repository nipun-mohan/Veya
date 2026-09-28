"""Veya's Sarvam-only speech and writing gateway."""
import asyncio
import base64
import hmac
import json
import os
import subprocess
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
import websockets
import firebase_admin
from firebase_admin import auth as firebase_auth
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from server.dashboard import DASHBOARD_HTML, GatewayMetrics, SUBSCRIPTIONS

load_dotenv(Path(__file__).with_name('.env'))

last_process_duration_ms: int | None = None
last_process_breakdown_ms: dict[str, int] = {}
# Secret-manager values can include a terminal newline. Header values cannot.
SARVAM_API_KEY = os.environ.get('SARVAM_API_KEY', '').strip()
SARVAM_STT_MODEL = os.environ.get('SARVAM_STT_MODEL', 'saaras:v4')
SARVAM_STYLE_MODEL = os.environ.get(
    'SARVAM_STYLE_MODEL', 'sarvam-105b-conversations',
)
SARVAM_BASE_URL = 'https://api.sarvam.ai'
# Required for the internal dashboard. Leave unset to keep the dashboard
# completely unavailable until its value is supplied through Secret Manager.
VEYA_ADMIN_TOKEN = os.environ.get('VEYA_ADMIN_TOKEN', '').strip()

# Languages available in Veya's current selector.
LANGUAGE_NAMES = {
    'as-IN': 'Assamese', 'bn-IN': 'Bengali', 'en-IN': 'English',
    'gu-IN': 'Gujarati', 'hi-IN': 'Hindi', 'kn-IN': 'Kannada',
    'ml-IN': 'Malayalam', 'mr-IN': 'Marathi', 'ne-IN': 'Nepali',
    'pa-IN': 'Punjabi', 'ta-IN': 'Tamil', 'te-IN': 'Telugu',
    'ur-IN': 'Urdu',
}

# Mayura's colloquial mode is available for this subset. For the other
# selector languages, Veya returns the fast formal translation first and
# replaces Casual in the background when style generation completes.
MAYURA_COLLOQUIAL_LANGUAGES = {
    'bn-IN', 'gu-IN', 'hi-IN', 'kn-IN', 'ml-IN', 'mr-IN', 'pa-IN',
    'ta-IN', 'te-IN',
}

# Unicode blocks used to verify that the selected Indic language is returned
# in its native writing system, rather than as a Latin transliteration.
NATIVE_SCRIPT_RANGES = {
    'as-IN': ((0x0980, 0x09FF),),
    'bn-IN': ((0x0980, 0x09FF),),
    'gu-IN': ((0x0A80, 0x0AFF),),
    'hi-IN': ((0x0900, 0x097F),),
    'kn-IN': ((0x0C80, 0x0CFF),),
    'ml-IN': ((0x0D00, 0x0D7F),),
    'mr-IN': ((0x0900, 0x097F),),
    'ne-IN': ((0x0900, 0x097F),),
    'pa-IN': ((0x0A00, 0x0A7F),),
    'ta-IN': ((0x0B80, 0x0BFF),),
    'te-IN': ((0x0C00, 0x0C7F),),
    'ur-IN': ((0x0600, 0x06FF),),
}
TRANSLITERATION_LANGUAGES = {
    'bn-IN', 'gu-IN', 'hi-IN', 'kn-IN', 'ml-IN', 'mr-IN', 'pa-IN',
    'ta-IN', 'te-IN',
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.sarvam_client = httpx.AsyncClient(
        timeout=httpx.Timeout(70, connect=10),
        limits=httpx.Limits(max_connections=24, max_keepalive_connections=12),
    )
    app.state.metrics = GatewayMetrics()
    yield
    await app.state.sarvam_client.aclose()


app = FastAPI(title='Veya Translation Gateway', lifespan=lifespan)


def require_admin(request: Request) -> None:
    """Keep the operations dashboard separate from mobile Firebase users."""
    supplied = request.headers.get('x-veya-admin-token', '')
    if not VEYA_ADMIN_TOKEN or not hmac.compare_digest(supplied, VEYA_ADMIN_TOKEN):
        raise HTTPException(401, 'Administrator authentication is required.')


def verified_firebase_user(request: Request) -> dict[str, object]:
    header = request.headers.get('authorization', '')
    if not header.startswith('Bearer '):
        raise HTTPException(401, 'Authentication is required.')
    token = header.removeprefix('Bearer ').strip()
    if not token:
        raise HTTPException(401, 'Authentication is required.')
    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        return firebase_auth.verify_id_token(token, check_revoked=True)
    except Exception as error:
        print(f'Firebase token rejected: {error!r}', flush=True)
        raise HTTPException(401, 'Your session has expired. Please verify your number again.')


def verified_firebase_socket(websocket: WebSocket) -> dict[str, object]:
    """Authenticate the mobile relay without exposing the Sarvam key."""
    header = websocket.headers.get('authorization', '')
    if not header.startswith('Bearer '):
        raise HTTPException(401, 'Authentication is required.')
    token = header.removeprefix('Bearer ').strip()
    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        return firebase_auth.verify_id_token(token, check_revoked=True)
    except Exception as error:
        print(f'Firebase streaming token rejected: {error!r}', flush=True)
        raise HTTPException(401, 'Your session has expired. Please verify your number again.')


class TranslateRequest(BaseModel):
    """Compatibility payload used by the currently installed Android build."""

    text: str = Field(min_length=1, max_length=6000)
    source_language: str
    target_language: str = 'en-IN'
    styles: list[str] = ['casual', 'formal']


class DeferredStylesRequest(BaseModel):
    original_text: str = Field(min_length=1, max_length=6000)
    english_text: str = ''
    source_language: str


class AudioDurationLimitExceeded(Exception):
    """Saaras' synchronous endpoint accepts at most 30 seconds of audio."""


def ensure_sarvam() -> None:
    if not SARVAM_API_KEY:
        raise HTTPException(503, 'SARVAM_API_KEY is not configured on the gateway.')


def ensure_language(language: str) -> str:
    if language not in LANGUAGE_NAMES:
        raise HTTPException(400, 'This speaking language is not supported by Saaras.')
    return language


def sarvam_headers() -> dict[str, str]:
    return {'api-subscription-key': SARVAM_API_KEY}


def gateway_error(product: str, response: httpx.Response) -> HTTPException:
    print(f'{product} failed: {response.status_code} {response.text[:500]}', flush=True)
    if response.status_code == 429:
        return HTTPException(429, f'{product} is busy. Please try again shortly.')
    return HTTPException(502, f'{product} failed ({response.status_code}).')


async def saaras_transcribe(
    client: httpx.AsyncClient, audio: bytes, source_language: str,
    filename: str | None, content_type: str | None,
) -> tuple[str, str]:
    # The language chosen in Veya is the desired output language. A recording
    # can still be spoken in another language, so let Saaras identify it first.
    ensure_language(source_language)
    # When Veya is set to English, use Saaras' audio-to-English mode. It
    # translates the speech before any Roman Indic transcript can be emitted,
    # which is more reliable than trying to identify a Latin-script result.
    mode = 'translate' if source_language == 'en-IN' else 'transcribe'
    response = await client.post(
        f'{SARVAM_BASE_URL}/speech-to-text',
        headers=sarvam_headers(),
        data={'model': SARVAM_STT_MODEL, 'mode': mode, 'language_code': 'unknown'},
        files={'file': (Path(filename or 'recording.m4a').name, audio, content_type or 'audio/mp4')},
    )
    if response.status_code >= 300:
        if (
            response.status_code == 400
            and 'maximum limit of 30 seconds' in response.text
        ):
            raise AudioDurationLimitExceeded
        raise gateway_error('Saaras transcription', response)
    try:
        payload = response.json()
        return (
            str(payload['transcript']).strip(),
            str(payload.get('language_code') or 'auto').strip(),
        )
    except (KeyError, TypeError, ValueError):
        raise HTTPException(502, 'Saaras returned an invalid transcription response.')


def split_audio_into_saaras_segments(source: Path, output_dir: Path) -> list[Path]:
    """Transcode into 28-second M4A segments, below Saaras' 30s ceiling."""
    pattern = output_dir / 'segment-%03d.m4a'
    subprocess.run(
        [
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(source),
            '-f', 'segment', '-segment_time', '28', '-c:a', 'aac', '-b:a', '24k',
            str(pattern),
        ],
        check=True,
        timeout=45,
    )
    return sorted(output_dir.glob('segment-*.m4a'))


async def transcribe_recording(
    client: httpx.AsyncClient, audio: bytes, source_language: str,
    filename: str | None, content_type: str | None,
) -> tuple[str, str]:
    """Use the fast direct path, splitting only recordings over 30 seconds."""
    try:
        return await saaras_transcribe(
            client, audio, source_language, filename, content_type,
        )
    except AudioDurationLimitExceeded:
        print('Veya: splitting recording longer than Saaras synchronous limit', flush=True)
        with tempfile.TemporaryDirectory(prefix='veya-audio-') as directory:
            work = Path(directory)
            source = work / 'recording.m4a'
            source.write_bytes(audio)
            try:
                segments = await asyncio.to_thread(
                    split_audio_into_saaras_segments, source, work,
                )
            except (OSError, subprocess.SubprocessError) as error:
                print(f'Veya audio segmentation failed: {error!r}', flush=True)
                raise HTTPException(502, 'Could not prepare the long recording.')
            if not segments:
                raise HTTPException(502, 'Could not split the long recording.')
            transcripts = []
            detected_languages = []
            for segment in segments:
                text, detected_language = await saaras_transcribe(
                    client, segment.read_bytes(), source_language,
                    segment.name, 'audio/mp4',
                )
                if text:
                    transcripts.append(text)
                    detected_languages.append(detected_language)
            detected_language = (
                detected_languages[0]
                if detected_languages and len(set(detected_languages)) == 1
                else 'auto'
            )
            return ' '.join(transcripts).strip(), detected_language


def translation_source_language(language: str) -> str:
    """Allow the provider to detect mixed or unrecognised STT output."""
    if language == 'auto' or language in LANGUAGE_NAMES:
        return language
    if language.lower().startswith('en'):
        return 'en-IN'
    return 'auto'


async def sarvam_translate(
    client: httpx.AsyncClient, text: str, source_language: str,
    target_language: str = 'en-IN',
) -> str:
    language = translation_source_language(source_language)
    target = ensure_language(target_language)
    if language == target:
        return text.strip()
    response = await client.post(
        f'{SARVAM_BASE_URL}/translate',
        headers={**sarvam_headers(), 'Content-Type': 'application/json'},
        json={
            'input': text,
            'source_language_code': language,
            'target_language_code': target,
            'model': 'sarvam-translate:v1',
            'mode': 'formal',
        },
    )
    if response.status_code >= 300:
        raise gateway_error('Sarvam translation', response)
    try:
        return str(response.json()['translated_text']).strip()
    except (KeyError, TypeError, ValueError):
        raise HTTPException(502, 'Sarvam returned an invalid translation response.')


async def normalize_transcript(
    client: httpx.AsyncClient, transcript: str, detected_language: str,
    selected_language: str,
) -> str:
    """Convert speech into the selected language's normal native script."""
    source = translation_source_language(detected_language)
    normalized = transcript if source == selected_language else await sarvam_translate(
        client, transcript, source, selected_language,
    )
    if not needs_native_script(normalized, selected_language):
        return normalized
    if selected_language in TRANSLITERATION_LANGUAGES:
        return await sarvam_transliterate_to_native(client, normalized, selected_language)
    # The transliteration endpoint does not cover every Veya language. The
    # translation model supports them all and returns their native script.
    return await sarvam_translate(client, normalized, 'auto', selected_language)


def needs_native_script(text: str, language: str) -> bool:
    ranges = NATIVE_SCRIPT_RANGES.get(language)
    letters = [char for char in text if char.isalpha()]
    if not ranges or not letters:
        return False
    native_letters = sum(
        any(start <= ord(char) <= end for start, end in ranges)
        for char in letters
    )
    # Do not accept a romanized sentence merely because it contains one native
    # character. Code-mixed output still passes when the selected script is the
    # dominant script, while Latin-dominant output is converted.
    return native_letters / len(letters) < 0.60


async def sarvam_transliterate_to_native(
    client: httpx.AsyncClient, text: str, target_language: str,
) -> str:
    response = await client.post(
        f'{SARVAM_BASE_URL}/transliterate',
        headers={**sarvam_headers(), 'Content-Type': 'application/json'},
        json={
            'input': text,
            'source_language_code': 'en-IN',
            'target_language_code': target_language,
            'numerals_format': 'international',
        },
    )
    if response.status_code >= 300:
        raise gateway_error('Sarvam native-script conversion', response)
    try:
        return str(response.json()['transliterated_text']).strip()
    except (KeyError, TypeError, ValueError):
        raise HTTPException(502, 'Sarvam returned an invalid native-script conversion.')


async def mayura_casual_translate(
    client: httpx.AsyncClient, text: str, source_language: str,
) -> str:
    response = await client.post(
        f'{SARVAM_BASE_URL}/translate',
        headers={**sarvam_headers(), 'Content-Type': 'application/json'},
        json={
            'input': text,
            'source_language_code': source_language,
            'target_language_code': 'en-IN',
            'model': 'mayura:v1',
            'mode': 'modern-colloquial',
        },
    )
    if response.status_code >= 300:
        raise gateway_error('Mayura casual translation', response)
    try:
        return str(response.json()['translated_text']).strip()
    except (KeyError, TypeError, ValueError):
        raise HTTPException(502, 'Mayura returned an invalid casual translation response.')


def split_text_for_mayura(text: str, limit: int = 900) -> list[str]:
    """Keep each Mayura request below its 1,000-character input limit."""
    words = text.split()
    if not words:
        return []
    chunks: list[str] = []
    current: list[str] = []
    current_length = 0
    for word in words:
        proposed = current_length + len(word) + (1 if current else 0)
        if current and proposed > limit:
            chunks.append(' '.join(current))
            current = [word]
            current_length = len(word)
        else:
            current.append(word)
            current_length = proposed
    if current:
        chunks.append(' '.join(current))
    return chunks


async def mayura_casual_translate_long(
    client: httpx.AsyncClient, text: str, source_language: str,
) -> str:
    chunks = split_text_for_mayura(text)
    if len(chunks) == 1:
        return await mayura_casual_translate(client, chunks[0], source_language)
    translated = await asyncio.gather(*[
        mayura_casual_translate(client, chunk, source_language) for chunk in chunks
    ])
    return ' '.join(part.strip() for part in translated if part.strip())


async def sarvam_deferred_styles(
    client: httpx.AsyncClient, original: str, english: str, source_language: str,
) -> dict[str, str]:
    # The initial result only needs Casual. Translate here so the foreground
    # response does not wait for a second provider call.
    if not english:
        english = await sarvam_translate(client, original, source_language)
    prompt = (
        'Return JSON only with exactly two non-empty string keys: casual and formal. '
        f'The English meaning of the user message is: {english!r}. '
        'Both values MUST preserve the exact meaning, names, numbers, and intent. '
        'Do not add facts, labels, explanations, or sign-offs. '
        'casual: rewrite as a warm, natural chat message. Use at most two small, context-appropriate emojis only when they improve a clearly friendly or informal message. Never add emojis to sensitive, urgent, financial, medical, legal, apologetic, or serious messages. '
        'formal: rewrite as polished, professional, respectful English with complete sentences. Do not use emojis, slang, contractions, or casual filler.'
    )
    response = await client.post(
        f'{SARVAM_BASE_URL}/v1/chat/completions',
        headers={**sarvam_headers(), 'Content-Type': 'application/json'},
        json={
            'model': SARVAM_STYLE_MODEL,
            'messages': [{'role': 'user', 'content': prompt}],
            'temperature': 0.2,
            'max_tokens': 350,
            'response_format': {'type': 'json_object'},
        },
    )
    if response.status_code >= 300:
        raise gateway_error('Sarvam deferred style generation', response)
    try:
        values = json.loads(response.json()['choices'][0]['message']['content'])
        styles = {
            'casual': str(values['casual']).strip(),
            'formal': str(values['formal']).strip(),
        }
        if not all(styles.values()):
            raise ValueError('empty style output')
        return styles
    except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f'Veya deferred styles parsing failed: {error!r}', flush=True)
        raise HTTPException(502, 'Sarvam returned invalid deferred styles.')


async def create_response(client: httpx.AsyncClient, transcript: str, source_language: str) -> dict[str, object]:
    # Produce both visible styles inside the authenticated recording request.
    # A separate mobile /styles call is rejected by the edge WAF on some
    # networks, which left the two tabs showing the same initial translation.
    english = transcript if source_language == 'en-IN' else await sarvam_translate(
        client, transcript, source_language,
    )
    styles = await sarvam_deferred_styles(client, transcript, english, source_language)
    return {
        'original_text': transcript,
        'english_text': english,
        'styles': styles,
    }


@app.middleware('http')
async def measure_process_time(request, call_next):
    global last_process_duration_ms
    started = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        request.app.state.metrics.record_http(request.url.path, 500)
        raise
    if request.url.path not in {'/health', '/internal/dashboard', '/internal/api/overview'}:
        request.app.state.metrics.record_http(request.url.path, response.status_code)
    if request.url.path in {'/process', '/process-audio'}:
        last_process_duration_ms = round((time.perf_counter() - started) * 1000)
        response.headers['X-Veya-Process-Ms'] = str(last_process_duration_ms)
        print(f'Veya {request.url.path}: {last_process_duration_ms}ms', flush=True)
    return response


@app.get('/health')
def health():
    return {
        'ok': True,
        'speech_provider': 'sarvam',
        'saaras_transcription_available': True,
        'saaras_transcription_model': SARVAM_STT_MODEL,
        'translation_provider': 'sarvam', 'translation_model': 'sarvam-translate:v1',
        'style_provider': 'sarvam', 'style_model': SARVAM_STYLE_MODEL,
        'sarvam_key_configured': bool(SARVAM_API_KEY),
        'last_process_duration_ms': last_process_duration_ms,
        'last_process_breakdown_ms': last_process_breakdown_ms,
    }


@app.get('/internal/dashboard', response_class=HTMLResponse, include_in_schema=False)
def internal_dashboard():
    """The page contains no data; API reads require the admin header."""
    return DASHBOARD_HTML


@app.get('/internal/api/overview', include_in_schema=False)
def internal_overview(request: Request):
    require_admin(request)
    metrics = request.app.state.metrics.snapshot()
    return {
        **metrics,
        'health': health(),
        'subscriptions': [
            {'name': name, 'purpose': purpose, 'cost_status': status}
            for name, purpose, status in SUBSCRIPTIONS
        ],
    }


@app.post('/translate')
async def translate_compat(payload: TranslateRequest, request: Request):
    """Serve older app builds that translate an already-transcribed string."""
    verified_firebase_user(request)
    ensure_sarvam()
    ensure_language(payload.source_language)
    try:
        return await create_response(
            request.app.state.sarvam_client,
            payload.text,
            payload.source_language,
        )
    except httpx.TimeoutException:
        raise HTTPException(504, 'Sarvam processing timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Sarvam translate connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Sarvam.')


@app.post('/transcribe')
async def transcribe_compat(
    request: Request, file: UploadFile = File(...), source_language: str = Form(...),
):
    """Serve older app builds that upload audio before calling /translate."""
    verified_firebase_user(request)
    ensure_sarvam()
    ensure_language(source_language)
    try:
        audio = await file.read(20 * 1024 * 1024 + 1)
        if not audio:
            raise HTTPException(400, 'No recording was uploaded.')
        if len(audio) > 20 * 1024 * 1024:
            raise HTTPException(413, 'Recording is too large.')
        transcript, detected_language = await transcribe_recording(
            request.app.state.sarvam_client, audio, source_language,
            file.filename, file.content_type,
        )
        if not transcript:
            raise HTTPException(422, 'No speech was detected. Please try again.')
        normalized = await normalize_transcript(
            request.app.state.sarvam_client, transcript,
            detected_language, source_language,
        )
        return {
            'transcript': normalized,
            'english': await sarvam_translate(
                request.app.state.sarvam_client, normalized, source_language,
            ),
            'detected_language': detected_language,
        }
    except httpx.TimeoutException:
        raise HTTPException(504, 'Saaras transcription timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Saaras transcription connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Saaras.')
    finally:
        await file.close()


@app.post('/styles')
async def deferred_styles(req: DeferredStylesRequest, request: Request):
    verified_firebase_user(request)
    ensure_sarvam()
    ensure_language(req.source_language)
    try:
        styles = await sarvam_deferred_styles(
            request.app.state.sarvam_client,
            req.original_text,
            req.english_text,
            req.source_language,
        )
        return {'styles': styles}
    except httpx.TimeoutException:
        raise HTTPException(504, 'Style generation timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Sarvam styles connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Sarvam.')


@app.post('/styles-raw')
async def deferred_styles_raw(request: Request):
    """Accept opaque style payloads without asking the edge WAF to parse text."""
    if request.headers.get('content-type', '').split(';', 1)[0].strip() != 'application/octet-stream':
        raise HTTPException(415, 'Use the Veya style payload format.')
    verified_firebase_user(request)
    try:
        encoded = await request.body()
        decoded = base64.urlsafe_b64decode(encoded + b'=' * (-len(encoded) % 4))
        req = DeferredStylesRequest.model_validate_json(decoded)
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(400, 'Invalid style payload.')
    ensure_sarvam()
    ensure_language(req.source_language)
    try:
        styles = await sarvam_deferred_styles(
            request.app.state.sarvam_client,
            req.original_text,
            req.english_text,
            req.source_language,
        )
        return {'styles': styles}
    except httpx.TimeoutException:
        raise HTTPException(504, 'Style generation timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Sarvam styles connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Sarvam.')


async def process_audio_bytes(
    request: Request,
    audio: bytes,
    source_language: str,
    filename: str,
    content_type: str,
):
    global last_process_breakdown_ms
    verified_firebase_user(request)
    ensure_sarvam()
    ensure_language(source_language)
    try:
        if not audio:
            raise HTTPException(400, 'No recording was uploaded.')
        if len(audio) > 20 * 1024 * 1024:
            raise HTTPException(413, 'Recording is too large.')
        transcription_started = time.perf_counter()
        transcript, detected_language = await transcribe_recording(
            request.app.state.sarvam_client, audio, source_language, filename, content_type,
        )
        transcription_ms = round((time.perf_counter() - transcription_started) * 1000)
        if not transcript:
            raise HTTPException(422, 'No speech was detected. Please try again.')
        response_started = time.perf_counter()
        normalized_transcript = await normalize_transcript(
            request.app.state.sarvam_client, transcript,
            detected_language, source_language,
        )
        result = await create_response(
            request.app.state.sarvam_client, normalized_transcript, source_language,
        )
        response_ms = round((time.perf_counter() - response_started) * 1000)
        last_process_breakdown_ms = {
            'transcription': transcription_ms,
            'initial_translation': response_ms,
        }
        return {**result, 'detected_language': detected_language}
    except httpx.TimeoutException:
        raise HTTPException(504, 'Sarvam processing timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Saaras processing connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Sarvam.')


@app.post('/process')
async def process(
    request: Request, file: UploadFile = File(...), source_language: str = Form(...),
):
    """Compatibility endpoint for existing multipart clients."""
    audio = await file.read(20 * 1024 * 1024 + 1)
    try:
        return await process_audio_bytes(
            request, audio, source_language, file.filename or 'recording.m4a',
            file.content_type or 'audio/mp4',
        )
    finally:
        await file.close()


@app.post('/process-audio')
async def process_raw_audio(request: Request):
    """Accept a direct M4A body so Cloud Armor never parses binary as form data."""
    source_language = request.headers.get('x-veya-source-language', '')
    if request.headers.get('content-type', '').split(';', 1)[0].strip() != 'audio/mp4':
        raise HTTPException(415, 'Upload an M4A audio recording.')
    # Reject unauthenticated or unsupported requests before accepting their
    # body, keeping the raw-upload path as tightly bounded as the legacy one.
    verified_firebase_user(request)
    ensure_language(source_language)
    audio = await request.body()
    return await process_audio_bytes(
        request, audio, source_language, 'recording.m4a', 'audio/mp4',
    )


@app.websocket('/stream')
async def stream_audio(websocket: WebSocket):
    """Relay raw PCM from Veya to Sarvam's realtime STT WebSocket."""
    await websocket.accept()
    stream_started = False
    stream_outcome = 'failed'
    try:
        verified_firebase_socket(websocket)
        ensure_sarvam()
        source_language = websocket.query_params.get('source_language', '')
        ensure_language(source_language)
        websocket.app.state.metrics.stream_opened()
        stream_started = True
    except HTTPException as error:
        await websocket.send_json({'type': 'error', 'message': error.detail})
        await websocket.close(code=4401)
        return

    params = {
        'language_code': 'auto', 'model': SARVAM_STT_MODEL,
        'mode': 'transcribe', 'stream_type': 'balanced',
        'endpointing': 'manual', 'encoding': 'linear16', 'sample_rate': '16000',
    }
    query = '&'.join(f'{key}={value}' for key, value in params.items())
    sarvam_url = f'wss://api.sarvam.ai/speech-to-text-realtime/ws?{query}'
    client_finished = asyncio.Event()
    final_parts: list[str] = []

    try:
        async with websockets.connect(
            sarvam_url,
            additional_headers=sarvam_headers(),
            open_timeout=12, close_timeout=5, max_size=2 * 1024 * 1024,
        ) as sarvam:
            await websocket.send_json({'type': 'ready'})
            await sarvam.send(json.dumps({'event': 'speech_start'}))

            async def forward_audio() -> None:
                nonlocal stream_outcome
                while True:
                    message = json.loads(await websocket.receive_text())
                    event = message.get('event')
                    if event == 'audio':
                        audio = message.get('audio', '')
                        if not isinstance(audio, str) or len(audio) > 18000:
                            raise ValueError('Invalid audio frame.')
                        await sarvam.send(json.dumps({'event': 'audio_input', 'audio': audio}))
                    elif event == 'finish':
                        client_finished.set()
                        await sarvam.send(json.dumps({'event': 'speech_end'}))
                        await sarvam.send(json.dumps({'event': 'flush'}))
                        return
                    elif event == 'cancel':
                        stream_outcome = 'cancelled'
                        return

            async def receive_results() -> None:
                nonlocal stream_outcome
                async for raw in sarvam:
                    data = json.loads(raw)
                    event = data.get('event', '')
                    text = str(data.get('text') or data.get('transcript') or '').strip()
                    if event == 'transcript.partial' and text:
                        await websocket.send_json({'type': 'partial', 'text': text})
                    elif event == 'transcript.final' and text:
                        final_parts.append(text)
                        if client_finished.is_set():
                            transcript = ' '.join(final_parts).strip()
                            detected = str(data.get('language') or source_language)
                            normalized = await normalize_transcript(
                                websocket.app.state.sarvam_client, transcript,
                                detected, source_language,
                            )
                            result = await create_response(
                                websocket.app.state.sarvam_client,
                                normalized, source_language,
                            )
                            await websocket.send_json({
                                'type': 'result', **result,
                                'detected_language': detected,
                            })
                            stream_outcome = 'completed'
                            return
                    elif event == 'error':
                        await websocket.send_json({
                            'type': 'error',
                            'message': str(data.get('message') or 'Sarvam streaming failed.'),
                        })
                        return

            sender = asyncio.create_task(forward_audio())
            receiver = asyncio.create_task(receive_results())
            done, pending = await asyncio.wait(
                {sender, receiver}, return_when=asyncio.FIRST_COMPLETED,
            )
            # Always retrieve task exceptions. In particular, a normal mobile
            # disconnect raises WebSocketDisconnect in forward_audio; leaving
            # it unretrieved could leave the Sarvam relay in an inconsistent
            # state and produce a spurious error on the next recording.
            if sender in done:
                sender.result()
                if not receiver.done():
                    await receiver
            else:
                receiver.result()
            for task in pending:
                task.cancel()
            if pending:
                await asyncio.gather(*pending, return_exceptions=True)
    except (WebSocketDisconnect, asyncio.CancelledError):
        return
    except Exception as error:
        print(f'Sarvam stream failed: {error!r}', flush=True)
        # A mobile client may have already disconnected (for example after a
        # network hand-off), in which case ASGI forbids another send. Android
        # handles that close locally and shows the retry state.
    finally:
        if stream_started:
            websocket.app.state.metrics.stream_finished(stream_outcome)
        try:
            await websocket.close()
        except Exception:
            pass
