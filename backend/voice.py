import logging
from pathlib import Path
from threading import Lock

from fastapi import APIRouter, HTTPException, Request
from starlette.concurrency import run_in_threadpool

router = APIRouter()
SAMPLE_RATE = 16000
MAX_BYTES = SAMPLE_RATE * 2 * 20
MODEL_PATH = Path(__file__).resolve().parent / "models" / "whisper-base.en"
_inference = Lock()
_model = None
_logger = logging.getLogger(__name__)


def transcribe(audio: bytearray) -> str:
    global _model
    # Acquire in the worker so cancellation cannot free the slot during inference.
    if not _inference.acquire(blocking=False):
        raise HTTPException(503, "Voice transcription is busy. Try again.")
    try:
        import numpy as np
        from faster_whisper import WhisperModel

        if _model is None:
            _model = WhisperModel(str(MODEL_PATH), device="cpu", compute_type="int8",
                                  cpu_threads=2, local_files_only=True)
        samples = np.frombuffer(audio, dtype="<i2").astype(np.float32) / 32768.0
        segments, _ = _model.transcribe(
            samples, language="en", beam_size=3, vad_filter=True,
            condition_on_previous_text=False,
        )
        return " ".join(segment.text.strip() for segment in segments).strip()
    except Exception as error:
        _logger.warning("Voice inference failed (%s)", type(error).__name__)
        raise HTTPException(503, "Voice transcription is unavailable. Try again.") from error
    finally:
        _inference.release()


@router.post("/api/voice/transcribe")
async def transcribe_voice(request: Request) -> dict[str, str]:
    media_type = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
    if media_type != "application/octet-stream":
        raise HTTPException(415, "Send raw PCM audio as application/octet-stream.")
    audio = bytearray()
    async for chunk in request.stream():
        if len(audio) + len(chunk) > MAX_BYTES:
            raise HTTPException(413, "Recording exceeds 20 seconds.")
        audio.extend(chunk)
    if not audio or len(audio) % 2:
        raise HTTPException(400, "Recording must contain complete 16-bit audio samples.")
    return {"transcript": await run_in_threadpool(transcribe, audio)}
