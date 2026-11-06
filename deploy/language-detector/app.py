"""CPU-only MediaPipe language detection; bind to loopback behind the PLaMo gateway."""

from contextlib import asynccontextmanager
import os
from threading import Lock

from fastapi import FastAPI, HTTPException
import mediapipe as mp
from pydantic import BaseModel, ConfigDict, Field

MODEL_PATH = os.environ.get(
    'LANGUAGE_DETECTOR_MODEL', '/opt/mediapipe-language-detector/language_detector.tflite')
DETECTOR_VERSION = 'mediapipe-1.2.2-model-float32-1'
lock = Lock()


@asynccontextmanager
async def lifespan(app):
    options = mp.tasks.text.LanguageDetectorOptions(
        base_options=mp.tasks.BaseOptions(
            model_asset_path=MODEL_PATH, delegate=mp.tasks.BaseOptions.Delegate.CPU),
        max_results=5, score_threshold=0.0)
    with mp.tasks.text.LanguageDetector.create_from_options(options) as detector:
        app.state.detector = detector
        yield


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


class DetectionRequest(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    text: str = Field(min_length=1, max_length=100000)


@app.get('/health')
def health():
    return {'status': 'ok', 'detector': DETECTOR_VERSION}


@app.post('/detect')
def detect(data: DetectionRequest):
    # One model instance, bounded worker pool, no input logging or external calls.
    try:
        with lock:
            result = app.state.detector.detect(data.text)
        return {'detector': DETECTOR_VERSION, 'predictions': [
            {'language': item.language_code, 'probability': item.probability}
            for item in result.detections]}
    except Exception:
        raise HTTPException(503, 'Language detector is unavailable.') from None
