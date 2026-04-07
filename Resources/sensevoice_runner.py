#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path

import sherpa_onnx


def decode_pcm16_mono(path: Path):
    data = path.read_bytes()
    if len(data) % 2 != 0:
        raise ValueError("PCM byte length must be even")

    samples = []
    for index in range(0, len(data), 2):
        value = int.from_bytes(data[index:index + 2], byteorder="little", signed=True)
        samples.append(max(-1.0, min(1.0, value / 32768.0)))
    return samples


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--tokens", required=True)
    parser.add_argument("--language", default="auto")
    parser.add_argument("--provider", default="cpu")
    parser.add_argument("--sample-rate", type=int, default=16000)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--use-itn", default="false")
    args = parser.parse_args()

    use_itn = str(args.use_itn).lower() == "true"

    recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=args.model,
        tokens=args.tokens,
        language=args.language,
        use_itn=use_itn,
        provider=args.provider,
        num_threads=max(1, args.threads),
    )

    stream = recognizer.create_stream()
    stream.accept_waveform(args.sample_rate, decode_pcm16_mono(Path(args.input)))
    recognizer.decode_stream(stream)

    print(
        json.dumps(
            {
                "text": stream.result.text,
                "error": None,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"text": "", "error": str(exc)}, ensure_ascii=False))
        sys.exit(1)
