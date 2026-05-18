#!/usr/bin/env python3
"""
Cartesia Ink 2 STT WebSocket tester.

Streams either a WAV file or live microphone audio to
wss://api.cartesia.ai/stt/turns/websocket and prints every event the server
sends. Use this to sanity-check your API key and the event schema that the
Swift client expects.

Usage:
  export CARTESIA_API_KEY=sk-...
  python3 cartesia_test.py path/to/audio.wav      # stream a file
  python3 cartesia_test.py --mic 5                 # stream 5 seconds of mic

WAV requirements: PCM 16-bit, mono, 16 kHz. Convert with:
  ffmpeg -i input.m4a -ac 1 -ar 16000 -sample_fmt s16 out.wav

Dependencies:
  pip install websockets         # required
  pip install pyaudio            # only for --mic mode
                                 # on macOS: brew install portaudio first
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import wave
from pathlib import Path
from urllib.parse import urlencode

try:
    import websockets
except ImportError:
    sys.exit("Missing dependency: pip install websockets")

# python.org Python on macOS ships without a populated SSL trust store. Point
# OpenSSL at certifi's CA bundle so wss:// handshakes succeed.
try:
    import certifi
    os.environ.setdefault("SSL_CERT_FILE", certifi.where())
    os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())
except ImportError:
    pass


def load_dotenv() -> None:
    """Tiny .env loader: KEY=VALUE per line, # comments ok. Walks up from script
    dir to repo root. Does not overwrite existing env vars."""
    here = Path(__file__).resolve()
    for d in [here.parent, *here.parents]:
        env_file = d / ".env"
        if env_file.is_file():
            for raw in env_file.read_text().splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip().strip('"').strip("'")
                os.environ.setdefault(key, val)
            return


load_dotenv()
API_KEY = os.environ.get("CARTESIA_API_KEY")
SAMPLE_RATE = 16_000
CHUNK_MS = 100
FRAMES_PER_CHUNK = SAMPLE_RATE * CHUNK_MS // 1000  # 1600 frames per 100ms

URL_BASE = "wss://api.cartesia.ai/stt/turns/websocket"
PARAMS = {
    "model": "ink-2",
    "encoding": "pcm_s16le",
    "sample_rate": str(SAMPLE_RATE),
    "cartesia_version": "2026-03-01",
}


def read_wav_chunks(path: str):
    with wave.open(path, "rb") as w:
        assert w.getnchannels() == 1, f"need mono, got {w.getnchannels()} channels"
        assert w.getsampwidth() == 2, f"need 16-bit, got {w.getsampwidth()*8}-bit"
        assert w.getframerate() == SAMPLE_RATE, (
            f"need {SAMPLE_RATE} Hz, got {w.getframerate()} Hz"
        )
        while True:
            data = w.readframes(FRAMES_PER_CHUNK)
            if not data:
                return
            yield data


async def mic_chunks(seconds: float):
    """Yield 100 ms int16 PCM chunks from the default input device."""
    try:
        import pyaudio
    except ImportError:
        sys.exit(
            "Missing dependency for --mic mode: pip install pyaudio\n"
            "On macOS you may need: brew install portaudio"
        )

    pa = pyaudio.PyAudio()
    stream = pa.open(
        format=pyaudio.paInt16,
        channels=1,
        rate=SAMPLE_RATE,
        input=True,
        frames_per_buffer=FRAMES_PER_CHUNK,
    )

    total_chunks = int(seconds * 1000 / CHUNK_MS)

    # 1-2-3 countdown so the user is ready before chunks start streaming.
    for n in (3, 2, 1):
        print(f"  starting in {n}…", flush=True)
        await asyncio.sleep(1.0)
    print(f"🎤 SPEAK NOW — recording {seconds}s ({total_chunks} chunks)", flush=True)

    import audioop
    peak_rms = 0
    try:
        for i in range(total_chunks):
            data = stream.read(FRAMES_PER_CHUNK, exception_on_overflow=False)
            rms = audioop.rms(data, 2)  # int16 RMS, 0-32767
            peak_rms = max(peak_rms, rms)
            yield data
            await asyncio.sleep(0)
            if i % 5 == 0:
                bars = "█" * min(40, rms // 200)
                print(f"   {(i+1)*CHUNK_MS/1000:4.1f}s  rms={rms:5d} {bars}", file=sys.stderr)
        print(f"🎤 peak rms over session: {peak_rms} "
              f"({'silent — mic may not be working' if peak_rms < 200 else 'audible'})")
    finally:
        stream.stop_stream()
        stream.close()
        pa.terminate()
        print("🎤 done recording")


async def stream(audio_iter) -> None:
    if not API_KEY:
        sys.exit("Set CARTESIA_API_KEY in your environment.")

    url = f"{URL_BASE}?{urlencode(PARAMS)}"
    headers = [("X-API-Key", API_KEY)]
    print(f"→ connecting: {url}")

    async with websockets.connect(url, additional_headers=headers) as ws:
        print("✓ connected")

        async def sender():
            try:
                if hasattr(audio_iter, "__aiter__"):
                    async for chunk in audio_iter:
                        await ws.send(chunk)
                        await asyncio.sleep(CHUNK_MS / 1000.0)
                else:
                    for chunk in audio_iter:
                        await ws.send(chunk)
                        await asyncio.sleep(CHUNK_MS / 1000.0)
                print('→ sent all audio; sending {"type":"close"}')
                await ws.send(json.dumps({"type": "close"}))
            except Exception as e:
                print(f"[sender] {e}", file=sys.stderr)

        async def receiver():
            try:
                async for msg in ws:
                    try:
                        evt = json.loads(msg)
                    except Exception:
                        print(f"← (non-JSON) {msg!r}")
                        continue
                    t = evt.get("type", "?")
                    if t in ("turn.update", "turn.eager_end", "turn.end"):
                        print(f"← {t}  transcript={evt.get('transcript')!r}")
                    else:
                        print(f"← {t}  {evt}")
                print("← receiver: server stopped sending (clean close)")
            except websockets.ConnectionClosed as e:
                print(f"✓ closed: code={e.code} reason={e.reason!r}")

        await asyncio.gather(sender(), receiver())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav", nargs="?", help="WAV file (mono / 16-bit / 16 kHz)")
    ap.add_argument("--mic", type=float, metavar="SECONDS",
                    help="Stream live mic audio for N seconds instead of a WAV.")
    args = ap.parse_args()

    if args.mic is None and not args.wav:
        ap.error("provide a WAV path or --mic SECONDS")

    source = mic_chunks(args.mic) if args.mic else read_wav_chunks(args.wav)
    asyncio.run(stream(source))


if __name__ == "__main__":
    main()
