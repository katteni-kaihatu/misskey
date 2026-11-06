# Server-side language detection

Misskey calls `POST <translation base URL>/language-detection` with the existing
translation bearer key. On prox1 this is the PLaMo gateway's authenticated
`/v1/language-detection` route. It forwards only to the CPU detector on loopback
port 8768. The detector does not use the GPU or a PLaMo inference slot.

## Install (Debian 13 / Python 3.13, LXC 114)

Install `python3-venv libgl1 libglib2.0-0t64 libegl1 libgles2`. Create a dedicated
venv at `/opt/mediapipe-language-detector/venv`, then install `requirements.txt`.
Copy `app.py` into `/opt/mediapipe-language-detector` and download the model:

```sh
curl -fL https://storage.googleapis.com/mediapipe-models/language_detector/language_detector/float32/1/language_detector.tflite -o /opt/mediapipe-language-detector/language_detector.tflite
echo '7db4f23dfe1ad8966b050b419a865da451143fd43eb6b606a256aadeeb1e5417  /opt/mediapipe-language-detector/language_detector.tflite' | sha256sum -c -
```

Copy the service file to `/etc/systemd/system/`, then `systemctl daemon-reload`
and `systemctl enable --now language-detector`. Check `http://127.0.0.1:8768/health`.
The existing `plamo` user must be able to read these files. Model and runtime
files should remain owned by root, not writable by the service user.

Back up `/opt/plamo-translate/app.py`, copy `language_detection_proxy.py` beside
it, and add these lines immediately after creating its FastAPI `app`:

```py
from language_detection_proxy import register_language_detection
register_language_detection(app)
```

Restart only `plamo-web`; do not restart either model engine. Verify that an
unauthenticated request returns 401, and an authenticated request returns
predictions. Preserve the existing gateway authentication and network middleware.
Do not expose port 8768. There are no credentials in these deployment files.

## Decisions and failure behavior

- Strip URLs, code, mentions, custom emoji, and MFM before detection.
- Ask Google for up to five candidates. Normally require probability >= 0.8.
- Japanese-only letters with kana override the model, including one-kana short
  replies. The explicit Han-only replies `草`, `笑`, `乙`, `了解` are Japanese;
  arbitrary Han-only text stays ambiguous.
- For Japanese mixed with product names, accept Google's top Japanese result
  from 0.25 when kana is present and there is no three-word Latin phrase or
  foreign script. This is a heuristic, not a guarantee for multilingual posts.
- Keep simplified and traditional Chinese distinct. Generic `zh` cannot prove
  either script without distinguishing characters.
- Share language results (including unknown) in Redis for 24 hours, keyed by
  text, provider revision, and detection-rule revision. Share translations for
  one hour as before. Check role and note visibility before either cache.
- Timeout after 1.5 seconds and use the previous local detector plus Japanese
  reply rules during outages. Back off for 30 seconds; do not cache failures.
- Same-language results return before any PLaMo generation request. Low-confidence
  or unsupported results remain unknown and still get translated.

Validation uses synthetic tests in the repository. The 100 real LTL regression
samples and their authors' text remain outside the repository.

Official documentation:
- https://developers.google.com/edge/mediapipe/solutions/text/language_detector/python
- https://developers.google.com/edge/mediapipe/solutions/text/language_detector
