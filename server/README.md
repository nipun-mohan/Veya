# Veya gateway

The local gateway receives an M4A recording from Veya, transcribes it with **Sarvam Saaras v4**, translates it to English with **Sarvam Translate v1**, and creates writing variants with **Sarvam 105B**.

`/process` returns the original script, English meaning, and Casual first. For Mayura-supported languages, Casual uses its `modern-colloquial` translation mode in parallel with the formal English translation. The app requests Romanized, Formal, and Professional separately through `/styles`, using Sarvam's conversational model, so the result sheet can appear sooner.

## Setup

From the project root:

```zsh
python3 -m venv server/.venv
server/.venv/bin/pip install -r server/requirements.txt
cp server/.env.example server/.env
# Set SARVAM_API_KEY in server/.env
server/.venv/bin/uvicorn server.app:app --host 0.0.0.0 --port 8080
```

The key stays on this gateway. Do not put it in the Flutter app or an APK.

## Routes

- `GET /health` — gateway configuration and the most recent `/process` duration.
- `POST /process` — multipart form with `file` and `source_language`.
- `POST /styles` — JSON with `original_text`, `english_text`, and `source_language`.

The current language selector supports Assamese, Bengali, English, Gujarati, Hindi, Kannada, Malayalam, Marathi, Nepali, Punjabi, Tamil, Telugu, and Urdu.
