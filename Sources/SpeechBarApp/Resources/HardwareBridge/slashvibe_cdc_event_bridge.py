#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time

import slashvibe_host_proto as proto


DEFAULT_OUTPUT_PATH = (
    pathlib.Path.home()
    / "Library"
    / "Application Support"
    / "StartUpSpeechBar"
    / "board-input"
    / "events.jsonl"
)
DEFAULT_RAW_DUMP_PATH = (
    pathlib.Path.home()
    / "Library"
    / "Application Support"
    / "StartUpSpeechBar"
    / "board-input"
    / "raw-serial-rx.bin"
)

EVENT_KIND_MAP = {
    proto.INPUT_EVENT_PUSH_TO_TALK_PRESSED: "pushToTalkPressed",
    proto.INPUT_EVENT_PUSH_TO_TALK_RELEASED: "pushToTalkReleased",
    proto.INPUT_EVENT_ROTATE_NEXT: "rotaryClockwise",
    proto.INPUT_EVENT_ROTATE_PREVIOUS: "rotaryCounterClockwise",
    proto.INPUT_EVENT_PRESS_PRIMARY: "pressPrimary",
    proto.INPUT_EVENT_PRESS_SECONDARY: "pressSecondary",
    proto.INPUT_EVENT_DISMISS_SELECTED: "dismissSelected",
    proto.INPUT_EVENT_SWITCH_BOARD_NEXT: "switchBoardNext",
    proto.INPUT_EVENT_SWITCH_BOARD_PREVIOUS: "switchBoardPrevious",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bridge SlashVibe CDC @SVHEX input events into a JSONL hardware-event feed."
    )
    parser.add_argument("--port", required=True, help="Serial device path, for example /dev/tty.usbmodemXXXX")
    parser.add_argument("--baudrate", type=int, default=230400)
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH))
    parser.add_argument("--raw-dump", default=str(DEFAULT_RAW_DUMP_PATH))
    parser.add_argument("--source", default="usbHID")
    parser.add_argument("--hello-interval", type=float, default=0.8)
    return parser.parse_args()


def open_serial(port: str, baudrate: int):
    try:
        import serial  # type: ignore
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(f"pyserial unavailable: {exc}") from exc
    device = serial.Serial(port=port, baudrate=baudrate, timeout=1.0, write_timeout=1.0)
    device.dtr = True
    device.rts = True
    try:
        device.reset_input_buffer()
    except Exception:
        pass
    return device


def append_event(output_path: pathlib.Path, kind: str, source: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "kind": kind,
        "source": source,
        "occurredAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    with output_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=True) + "\n")


def append_raw_bytes(raw_dump_path: pathlib.Path, payload: bytes) -> None:
    if not payload:
        return
    raw_dump_path.parent.mkdir(parents=True, exist_ok=True)
    with raw_dump_path.open("ab") as handle:
        handle.write(payload)


def write_line(serial_port, line: str) -> None:
    serial_port.write(line.encode("ascii", errors="ignore") + b"\r\n")


def send_hello(serial_port, sequence: int) -> None:
    report = proto.encode_report(proto.ProtocolMessage(opcode=proto.OP_HELLO, seq=sequence))
    write_line(serial_port, proto.format_hex_line(report))


def extract_lines(buffer: bytearray) -> list[bytes]:
    lines: list[bytes] = []
    while True:
        newline_index = buffer.find(b"\n")
        if newline_index < 0:
            break
        line = bytes(buffer[:newline_index])
        del buffer[:newline_index + 1]
        lines.append(line.rstrip(b"\r"))
    return lines


def main() -> int:
    args = parse_args()
    output_path = pathlib.Path(args.output).expanduser().resolve()
    raw_dump_path = pathlib.Path(args.raw_dump).expanduser().resolve()

    try:
        serial_port = open_serial(args.port, args.baudrate)
    except Exception as exc:
        print(f"failed to open serial port: {exc}", file=sys.stderr)
        return 1

    print(f"bridge_ready port={args.port} output={output_path} raw_dump={raw_dump_path}")

    sequence = 1
    next_hello_at = 0.0
    read_buffer = bytearray()

    with serial_port:
        while True:
            now = time.monotonic()
            if now >= next_hello_at:
                try:
                    send_hello(serial_port, sequence)
                    sequence = 1 if sequence >= 0xFFFF else sequence + 1
                except Exception as exc:
                    print(f"hello_send_failed: {exc}", file=sys.stderr)
                next_hello_at = now + max(args.hello_interval, 0.2)

            chunk = serial_port.read(max(1, getattr(serial_port, "in_waiting", 0) or 0))
            if not chunk:
                continue
            append_raw_bytes(raw_dump_path, chunk)
            read_buffer.extend(chunk)

            for raw_line in extract_lines(read_buffer):
                text = raw_line.decode("utf-8", errors="ignore").strip()
                if not text or (not text.startswith("@SVHEX:") and not text.startswith("SVHEX ")):
                    continue

                try:
                    report = proto.parse_hex_line(text)
                    message = proto.decode_report(report)
                except Exception:
                    continue

                if message.opcode != proto.OP_INPUT_EVENT_PUSH or len(message.payload) != 1:
                    if message.opcode == proto.OP_DEVICE_INFO:
                        print(f"device_info seq={message.seq}")
                    elif message.opcode == proto.OP_ACK:
                        print(f"ack seq={message.seq}")
                    continue

                event_code = message.payload[0]
                kind = EVENT_KIND_MAP.get(event_code)
                if kind is None:
                    continue

                append_event(output_path, kind, args.source)
                print(f"event kind={kind} seq={message.seq}")


if __name__ == "__main__":
    raise SystemExit(main())
