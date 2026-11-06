"""Register with the existing authenticated PLaMo FastAPI gateway."""

import json
import urllib.error
import urllib.request

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from starlette.concurrency import run_in_threadpool

MAX_BODY_BYTES = 1024 * 1024


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def call_detector(body):
    request = urllib.request.Request(
        'http://127.0.0.1:8768/detect', data=body,
        headers={'Content-Type': 'application/json'}, method='POST')
    with opener.open(request, timeout=1.2) as response:
        result = response.read(16385)
        if len(result) > 16384:
            raise ValueError('Response too large')
        json.loads(result)
        return result


def register_language_detection(app):
    @app.post('/v1/language-detection')
    async def language_detection(request: Request):
        # /v1 inherits the gateway's bearer authentication and LAN/VPN restrictions.
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > MAX_BODY_BYTES:
                return JSONResponse({'error': {'message': 'Request too large.'}}, status_code=413)
        try:
            data = json.loads(body)
            if (not isinstance(data, dict) or set(data) != {'text'} or
                    not isinstance(data['text'], str) or not 1 <= len(data['text']) <= 100000):
                raise ValueError('Invalid request')
        except (ValueError, UnicodeDecodeError):
            return JSONResponse({'error': {'message': 'Invalid detection request.'}}, status_code=400)
        try:
            result = await run_in_threadpool(call_detector, bytes(body))
            return Response(result, media_type='application/json')
        except (urllib.error.URLError, OSError, ValueError):
            return JSONResponse({'error': {'message': 'Language detector is unavailable.'}}, status_code=503)
