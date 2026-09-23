# Veya

Veya is a Flutter Android voice-writing assistant. The Assistant flavour provides a draggable accessibility overlay that records a message, generates English writing variants, and inserts the selected result into the focused text field.

## Active flow

1. Focus a text field in an enabled app and tap the Veya overlay.
2. Record with the Android `MediaRecorder` control and tap Done.
3. The app uploads a compact M4A recording to the local Veya gateway using OkHttp multipart HTTP.
4. The gateway transcribes with Sarvam Saaras v4, translates with Sarvam Translate v1, and returns the Casual variant first.
5. Formal and Professional variants load silently through the gateway's `/styles` route. The sheet also offers the original text in Romanized English and in its original script.

## Speaking languages

Assamese, Bengali, English, Gujarati, Hindi, Kannada, Malayalam, Marathi, Nepali, Punjabi, Tamil, Telugu, and Urdu.

## Run the gateway locally

See [server/README.md](server/README.md). Keep the Sarvam key in `server/.env`; it is never bundled into the Android app.

## Build Android

```zsh
../../tools/flutter/bin/flutter pub get
../../tools/flutter/bin/flutter build apk --flavor assistant --release
```

The Assistant flavour uses Android accessibility to show the overlay and insert text into the focused field. The Standard flavour builds the Flutter app without the accessibility assistant.
