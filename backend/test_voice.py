import asyncio
import unittest
from unittest.mock import patch

import httpx

from backend import main, voice


class VoiceTests(unittest.TestCase):
    def post(self, audio, media_type="application/octet-stream"):
        async def send():
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=main.app), base_url="http://test"
            ) as client:
                return await client.post(
                    "/api/voice/transcribe", content=audio,
                    headers={"Content-Type": media_type},
                )
        return asyncio.run(send())

    def test_returns_transcript_or_silence(self):
        with patch.object(voice, "transcribe", side_effect=["200 rupees for lunch.", ""]) as infer:
            self.assertEqual(self.post(b"\x01\x00").json(), {"transcript": "200 rupees for lunch."})
            self.assertEqual(self.post(b"\x00\x00").json(), {"transcript": ""})
            self.assertEqual(infer.call_count, 2)

    def test_rejects_invalid_audio_before_inference(self):
        with patch.object(voice, "transcribe") as infer:
            self.assertEqual(self.post(b"", "audio/wav").status_code, 415)
            self.assertEqual(self.post(b"").status_code, 400)
            self.assertEqual(self.post(b"\x00").status_code, 400)
            self.assertEqual(self.post(bytes(voice.MAX_BYTES + 2)).status_code, 413)
            infer.assert_not_called()

    def test_returns_service_unavailable_when_busy(self):
        with voice._inference:
            response = self.post(b"\x01\x00")
        self.assertEqual(response.status_code, 503)
        self.assertIn("busy", response.json()["detail"])

    def test_model_load_failure_releases_inference_slot(self):
        with patch.dict("sys.modules", {"faster_whisper": None}), patch.object(voice, "_model", None):
            for _ in range(2):
                response = self.post(b"\x01\x00")
                self.assertEqual(response.status_code, 503)
                self.assertIn("unavailable", response.json()["detail"])
