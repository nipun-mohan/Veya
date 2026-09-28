# Deploying the Veya gateway

The gateway is a stateless FastAPI container. It calls Sarvam directly, so it needs no GPU, database, disk volume, or model download. A small managed container service is appropriate.

## Required production configuration

Set these values in the host's secret manager or environment-variable UI:

```text
SARVAM_API_KEY=<Sarvam server key>
SARVAM_STT_MODEL=saaras:v4
SARVAM_CHAT_MODEL=sarvam-105b
PORT=8080
```

Never upload `server/.env`, package it into the image, or add its value to Flutter.

## Build locally

Run from `server/`:

```zsh
docker build -t veya-gateway .
docker run --rm -p 8080:8080 \
  -e SARVAM_API_KEY \
  -e SARVAM_STT_MODEL=saaras:v4 \
  -e SARVAM_CHAT_MODEL=sarvam-105b \
  veya-gateway
```

Then verify with:

```zsh
curl http://127.0.0.1:8080/health
```

## Production host requirements

- Deploy the supplied `Dockerfile` as a private image.
- Route HTTPS traffic to the container's `PORT`.
- Configure at least 1 CPU, 512 MB RAM, and a request timeout of 90 seconds.
- Set a maximum instance count and billing alerts before exposing the service.
- Put a gateway/auth layer in front of the public API before releasing Veya to users. A static mobile-app token is not sufficient protection because it can be extracted from an APK.

After deployment, set Veya's **Server translation** setting to the new HTTPS base URL, for example `https://api.example.com`.

## Internal operations dashboard

Veya includes a small password-protected dashboard at
`https://api.heyveya.app/internal/dashboard`. It shows traffic and health from
its current Cloud Run instance plus the configured service inventory.

Set `VEYA_ADMIN_TOKEN` as a Secret Manager value before deploying. The page
sends this token in an `X-Veya-Admin-Token` request header and keeps it only in
the browser session. Do not put this value in the Android app.

The dashboard deliberately does not estimate costs. For accurate costs, enable
Cloud Billing export to BigQuery and connect a Sarvam usage or invoice feed.
Cloud Run may run more than one instance, so aggregate traffic belongs in Cloud
Monitoring for a full production-wide view.
