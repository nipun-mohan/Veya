"""Veya's Sarvam-only speech and writing gateway."""
import asyncio
import json
import os
import subprocess
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

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


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.sarvam_client = httpx.AsyncClient(
        timeout=httpx.Timeout(70, connect=10),
        limits=httpx.Limits(max_connections=24, max_keepalive_connections=12),
    )
    yield
    await app.state.sarvam_client.aclose()


app = FastAPI(title='Veya Translation Gateway', lifespan=lifespan)


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
) -> str:
    language = ensure_language(source_language)
    response = await client.post(
        f'{SARVAM_BASE_URL}/speech-to-text',
        headers=sarvam_headers(),
        data={'model': SARVAM_STT_MODEL, 'mode': 'transcribe', 'language_code': language},
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
        return str(response.json()['transcript']).strip()
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
) -> str:
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
            for segment in segments:
                text = await saaras_transcribe(
                    client, segment.read_bytes(), source_language,
                    segment.name, 'audio/mp4',
                )
                if text:
                    transcripts.append(text)
            return ' '.join(transcripts).strip()


async def sarvam_translate(client: httpx.AsyncClient, text: str, source_language: str) -> str:
    language = ensure_language(source_language)
    if language == 'en-IN':
        return text.strip()
    response = await client.post(
        f'{SARVAM_BASE_URL}/translate',
        headers={**sarvam_headers(), 'Content-Type': 'application/json'},
        json={
            'input': text,
            'source_language_code': language,
            'target_language_code': 'en-IN',
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
        'Return JSON only with exactly one non-empty string key: formal. '
        f'The English meaning of the user message is: {english!r}. '
        'formal MUST be natural English only. Preserve exact meaning and add no facts, names, greetings, sign-offs, labels, or explanations. '
        'Make it polite and respectful.'
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
        styles = {'formal': str(values['formal']).strip()}
        if not all(styles.values()):
            raise ValueError('empty style output')
        return styles
    except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f'Veya deferred styles parsing failed: {error!r}', flush=True)
        raise HTTPException(502, 'Sarvam returned invalid deferred styles.')


async def create_response(client: httpx.AsyncClient, transcript: str, source_language: str) -> dict[str, object]:
    if source_language == 'en-IN':
        return {
            'original_text': transcript,
            'english_text': transcript,
            'styles': {'casual': transcript},
        }
    if source_language in MAYURA_COLLOQUIAL_LANGUAGES:
        # The result sheet appears after one post-transcription provider call.
        # Formal and the standard English translation load independently.
        casual = await mayura_casual_translate_long(client, transcript, source_language)
        english = ''
    else:
        english = await sarvam_translate(client, transcript, source_language)
        casual = english
    return {
        'original_text': transcript,
        'english_text': english,
        'styles': {'casual': casual},
    }


@app.middleware('http')
async def measure_process_time(request, call_next):
    global last_process_duration_ms
    started = time.perf_counter()
    response = await call_next(request)
    if request.url.path == '/process':
        last_process_duration_ms = round((time.perf_counter() - started) * 1000)
        response.headers['X-Veya-Process-Ms'] = str(last_process_duration_ms)
        print(f'Veya /process: {last_process_duration_ms}ms', flush=True)
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


@app.post('/translate')
async def translate_compat(payload: TranslateRequest, request: Request):
    """Serve older app builds that translate an already-transcribed string."""
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
    ensure_sarvam()
    ensure_language(source_language)
    try:
        audio = await file.read(20 * 1024 * 1024 + 1)
        if not audio:
            raise HTTPException(400, 'No recording was uploaded.')
        if len(audio) > 20 * 1024 * 1024:
            raise HTTPException(413, 'Recording is too large.')
        transcript = await transcribe_recording(
            request.app.state.sarvam_client, audio, source_language,
            file.filename, file.content_type,
        )
        if not transcript:
            raise HTTPException(422, 'No speech was detected. Please try again.')
        return {'transcript': transcript, 'english': transcript}
    except httpx.TimeoutException:
        raise HTTPException(504, 'Saaras transcription timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Saaras transcription connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Saaras.')
    finally:
        await file.close()


@app.post('/styles')
async def deferred_styles(req: DeferredStylesRequest, request: Request):
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


@app.post('/process')
async def process(
    request: Request, file: UploadFile = File(...), source_language: str = Form(...),
):
    global last_process_breakdown_ms
    ensure_sarvam()
    ensure_language(source_language)
    try:
        audio = await file.read(20 * 1024 * 1024 + 1)
        if not audio:
            raise HTTPException(400, 'No recording was uploaded.')
        if len(audio) > 20 * 1024 * 1024:
            raise HTTPException(413, 'Recording is too large.')
        transcription_started = time.perf_counter()
        transcript = await transcribe_recording(
            request.app.state.sarvam_client, audio, source_language, file.filename, file.content_type,
        )
        transcription_ms = round((time.perf_counter() - transcription_started) * 1000)
        if not transcript:
            raise HTTPException(422, 'No speech was detected. Please try again.')
        response_started = time.perf_counter()
        result = await create_response(request.app.state.sarvam_client, transcript, source_language)
        response_ms = round((time.perf_counter() - response_started) * 1000)
        last_process_breakdown_ms = {
            'transcription': transcription_ms,
            'initial_translation': response_ms,
        }
        return result
    except httpx.TimeoutException:
        raise HTTPException(504, 'Sarvam processing timed out. Please retry.')
    except httpx.RequestError as error:
        print(f'Saaras processing connection error: {error!r}', flush=True)
        raise HTTPException(502, 'Cannot reach Sarvam.')
    finally:
        await file.close()
