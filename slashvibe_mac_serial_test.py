#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import sys
import time
from dataclasses import dataclass
from typing import Iterable, Optional


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import slashvibe_host_proto as proto


DEFAULT_BAUDRATE = 115200
DEFAULT_PROTOCOL_BAUDRATE = 230400
DEFAULT_OPEN_DELAY_S = 1.0
DEFAULT_READ_TIMEOUT_S = 0.35
DEFAULT_TEXT_WAIT_S = 0.6
DEFAULT_PROTOCOL_WAIT_S = 0.8
DEFAULT_MONITOR_WINDOW_S = 20.0

INPUT_EVENT_NAMES = {
    proto.INPUT_EVENT_ROTATE_NEXT: "rotateNext",
    proto.INPUT_EVENT_ROTATE_PREVIOUS: "rotatePrevious",
    proto.INPUT_EVENT_PRESS_PRIMARY: "pressPrimary",
    proto.INPUT_EVENT_PRESS_SECONDARY: "pressSecondary",
    proto.INPUT_EVENT_DISMISS_SELECTED: "dismissSelected",
    proto.INPUT_EVENT_PUSH_TO_TALK_PRESSED: "pushToTalkPressed",
    proto.INPUT_EVENT_PUSH_TO_TALK_RELEASED: "pushToTalkReleased",
    proto.INPUT_EVENT_SWITCH_BOARD_NEXT: "switchBoardNext",
    proto.INPUT_EVENT_SWITCH_BOARD_PREVIOUS: "switchBoardPrevious",
}


@dataclass
class PortChoice:
    port: str
    baudrate: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "macOS-side SlashVibe serial validation helper. "
            "It can probe text CDC commands, @SVHEX protocol replies, INPUT STATUS polling, "
            "and live input events."
        )
    )
    parser.add_argument("--port", help="Explicit serial path, for example /dev/cu.usbmodem123401")
    parser.add_argument("--baudrate", type=int, default=DEFAULT_BAUDRATE,
                        help="Baud rate for text command tests. Default: 115200")
    parser.add_argument("--protocol-baudrate", type=int, default=DEFAULT_PROTOCOL_BAUDRATE,
                        help="Baud rate for @SVHEX protocol and event tests. Default: 230400")
    parser.add_argument("--open-delay", type=float, default=DEFAULT_OPEN_DELAY_S)
    parser.add_argument("--read-timeout", type=float, default=DEFAULT_READ_TIMEOUT_S)
    parser.add_argument("--text-wait", type=float, default=DEFAULT_TEXT_WAIT_S)
    parser.add_argument("--protocol-wait", type=float, default=DEFAULT_PROTOCOL_WAIT_S)
    parser.add_argument("--monitor-window", type=float, default=DEFAULT_MONITOR_WINDOW_S)
    parser.add_argument("--poll-count", type=int, default=12,
                        help="Number of INPUT STATUS polls during the poll phase.")
    parser.add_argument("--list", action="store_true", help="Only list candidate serial ports and exit")
    parser.add_argument("--skip-text", action="store_true", help="Skip text CDC command validation")
    parser.add_argument("--skip-protocol", action="store_true", help="Skip @SVHEX protocol validation")
    parser.add_argument("--skip-poll", action="store_true", help="Skip INPUT STATUS polling")
    parser.add_argument("--skip-events", action="store_true", help="Skip live input-event monitoring")
    parser.add_argument("--set-dtr", dest="set_dtr", action="store_true", default=True)
    parser.add_argument("--no-dtr", dest="set_dtr", action="store_false")
    parser.add_argument("--set-rts", dest="set_rts", action="store_true", default=True)
    parser.add_argument("--no-rts", dest="set_rts", action="store_false")
    return parser.parse_args()


def load_pyserial():
    try:
        import serial  # type: ignore
        from serial.tools import list_ports  # type: ignore
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(f"pyserial unavailable: {exc}") from exc
    return serial, list_ports


def iter_candidate_ports(list_ports_module) -> Iterable[object]:
    preferred = []
    fallback = []
    for port in list_ports_module.comports():
        device = getattr(port, "device", "") or ""
        if "usbmodem" in device or "usbserial" in device:
            preferred.append(port)
        elif device.startswith("/dev/cu.") or device.startswith("/dev/tty."):
            fallback.append(port)
    yield from preferred
    yield from fallback


def list_ports(list_ports_module) -> int:
    found = False
    for port in iter_candidate_ports(list_ports_module):
        found = True
        print(f"{port.device} hwid={getattr(port, 'hwid', '')} desc={getattr(port, 'description', '')}")
    if not found:
        print("no candidate serial ports found")
        return 1
    return 0


def choose_port(list_ports_module, explicit_port: Optional[str]) -> str:
    if explicit_port:
        return explicit_port
    for port in iter_candidate_ports(list_ports_module):
        return port.device
    raise RuntimeError("no candidate SlashVibe serial port found")


def open_serial(serial_module,
                port: str,
                baudrate: int,
                timeout: float,
                set_dtr: bool,
                set_rts: bool):
    device = serial_module.Serial(
        port=port,
        baudrate=baudrate,
        timeout=timeout,
        write_timeout=1.5,
    )
    device.dtr = set_dtr
    device.rts = set_rts
    try:
        device.reset_input_buffer()
        device.reset_output_buffer()
    except Exception:
        pass
    return device


def read_lines(serial_port, window_s: float) -> list[str]:
    deadline = time.monotonic() + max(window_s, 0.0)
    lines: list[str] = []
    while time.monotonic() < deadline:
        raw = serial_port.readline()
        if not raw:
            continue
        text = raw.decode("utf-8", errors="replace").strip()
        if text:
            lines.append(text)
    return lines


def send_text_command(serial_port, command: str, wait_s: float) -> list[str]:
    try:
        serial_port.reset_input_buffer()
    except Exception:
        pass
    serial_port.write(command.encode("ascii", errors="ignore") + b"\r\n")
    serial_port.flush()
    return read_lines(serial_port, wait_s)


def decode_protocol_line(line: str) -> str:
    if not line.startswith("@SVHEX:") and not line.startswith("SVHEX "):
        return "non-protocol"

    try:
        message = proto.decode_report(proto.parse_hex_line(line))
    except Exception as exc:
        return f"decode-failed: {exc}"

    if message.opcode == proto.OP_DEVICE_INFO:
        try:
            info = proto.decode_device_info(message.payload)
            return (
                "device-info "
                f"seq={message.seq} "
                f"usb_connected={info.usb_connected} "
                f"host_connected={info.host_connected} "
                f"recording={info.recording} "
                f"features=0x{info.feature_flags:08X} "
                f"name={info.device_name}"
            )
        except Exception as exc:
            return f"device-info-decode-failed: {exc}"

    if message.opcode == proto.OP_RUNTIME_STATS_GET:
        try:
            stats = proto.decode_runtime_stats(message.payload)
            return (
                "runtime-stats "
                f"seq={message.seq} "
                f"keys=0x{stats.key_bitmap:02X} "
                f"enc_press={stats.encoder_pressed} "
                f"usb_ready={stats.usb_ready} "
                f"host_live={stats.host_agents_live} "
                f"uptime_ms={stats.uptime_ms}"
            )
        except Exception as exc:
            return f"runtime-stats-decode-failed: {exc}"

    if message.opcode == proto.OP_INPUT_EVENT_PUSH and len(message.payload) == 1:
        event_name = INPUT_EVENT_NAMES.get(message.payload[0], f"unknown({message.payload[0]})")
        return f"input-event seq={message.seq} event={event_name}"

    if message.opcode == proto.OP_ACK:
        return f"ack seq={message.seq} payload={message.payload.hex().upper()}"
    if message.opcode == proto.OP_NACK:
        return f"nack seq={message.seq} payload={message.payload.hex().upper()}"

    return f"opcode=0x{message.opcode:02X} seq={message.seq} payload={message.payload.hex().upper()}"


def send_protocol_message(serial_port,
                          message: proto.ProtocolMessage,
                          wait_s: float) -> list[str]:
    line = proto.format_hex_line(proto.encode_report(message))
    try:
        serial_port.reset_input_buffer()
    except Exception:
        pass
    serial_port.write(line.encode("ascii") + b"\r\n")
    serial_port.flush()
    return read_lines(serial_port, wait_s)


def run_text_phase(serial_module, port_choice: PortChoice, args: argparse.Namespace) -> bool:
    print(f"text_phase open port={port_choice.port} baud={port_choice.baudrate}")
    success = True
    with open_serial(serial_module,
                     port_choice.port,
                     port_choice.baudrate,
                     args.read_timeout,
                     args.set_dtr,
                     args.set_rts) as serial_port:
        if args.open_delay > 0:
            time.sleep(args.open_delay)

        checks = [
            ("PING", lambda lines: any(line == "PONG" for line in lines)),
            ("HELP", lambda lines: any(line.startswith("OK HELP") for line in lines)),
            ("UI STATUS", lambda lines: any(line.startswith("OK UI ") for line in lines)),
            ("INPUT STATUS", lambda lines: any(line.startswith("OK INPUT ") for line in lines)),
        ]

        for command, predicate in checks:
            lines = send_text_command(serial_port, command, args.text_wait)
            print(f"text_cmd {command}")
            if not lines:
                print("  no-reply")
                success = False
                continue
            for line in lines:
                print(f"  {line}")
            if not predicate(lines):
                success = False
    print(f"text_phase result={'PASS' if success else 'FAIL'}")
    return success


def run_protocol_phase(serial_module, port: str, args: argparse.Namespace) -> bool:
    print(f"protocol_phase open port={port} baud={args.protocol_baudrate}")
    success = True
    with open_serial(serial_module,
                     port,
                     args.protocol_baudrate,
                     args.read_timeout,
                     args.set_dtr,
                     args.set_rts) as serial_port:
        if args.open_delay > 0:
            time.sleep(args.open_delay)

        checks = [
            (
                "HELLO",
                proto.ProtocolMessage(opcode=proto.OP_HELLO, seq=1),
                lambda lines: any("device-info " in decode_protocol_line(line) for line in lines),
            ),
            (
                "RUNTIME_STATS_GET",
                proto.ProtocolMessage(opcode=proto.OP_RUNTIME_STATS_GET, seq=2),
                lambda lines: any("runtime-stats " in decode_protocol_line(line) for line in lines),
            ),
        ]

        for label, message, predicate in checks:
            lines = send_protocol_message(serial_port, message, args.protocol_wait)
            print(f"protocol_cmd {label}")
            if not lines:
                print("  no-reply")
                success = False
                continue
            for line in lines:
                print(f"  raw {line}")
                print(f"  dec {decode_protocol_line(line)}")
            if not predicate(lines):
                success = False
    print(f"protocol_phase result={'PASS' if success else 'FAIL'}")
    return success


def run_input_poll_phase(serial_module, port_choice: PortChoice, args: argparse.Namespace) -> bool:
    print(f"poll_phase open port={port_choice.port} baud={port_choice.baudrate}")
    success = True
    seen_changes = 0
    last_line = ""
    with open_serial(serial_module,
                     port_choice.port,
                     port_choice.baudrate,
                     args.read_timeout,
                     args.set_dtr,
                     args.set_rts) as serial_port:
        if args.open_delay > 0:
            time.sleep(args.open_delay)

        for index in range(max(args.poll_count, 1)):
            lines = send_text_command(serial_port, "INPUT STATUS", args.text_wait)
            if not lines:
                print(f"  poll[{index}] no-reply")
                success = False
                continue
            matched = False
            for line in lines:
                print(f"  poll[{index}] {line}")
                if line.startswith("OK INPUT "):
                    matched = True
                    if line != last_line:
                        if last_line:
                            seen_changes += 1
                        last_line = line
            if not matched:
                success = False
    print(f"poll_phase transitions={seen_changes}")
    print(f"poll_phase result={'PASS' if success else 'FAIL'}")
    return success


def run_event_phase(serial_module, port: str, args: argparse.Namespace) -> bool:
    print(
        "event_phase listen "
        f"port={port} baud={args.protocol_baudrate} window={args.monitor_window:.1f}s "
        "rotate encoder / press keys during this window"
    )
    event_count = 0
    with open_serial(serial_module,
                     port,
                     args.protocol_baudrate,
                     args.read_timeout,
                     args.set_dtr,
                     args.set_rts) as serial_port:
        if args.open_delay > 0:
            time.sleep(args.open_delay)

        hello_seq = 10
        deadline = time.monotonic() + max(args.monitor_window, 1.0)
        next_hello_at = time.monotonic()
        while time.monotonic() < deadline:
            now = time.monotonic()
            if now >= next_hello_at:
                serial_port.write(
                    (proto.format_hex_line(proto.encode_report(
                        proto.ProtocolMessage(opcode=proto.OP_HELLO, seq=hello_seq)
                    )) + "\r\n").encode("ascii")
                )
                serial_port.flush()
                hello_seq = 1 if hello_seq >= 0xFFFF else hello_seq + 1
                next_hello_at = now + 0.8

            raw = serial_port.readline()
            if not raw:
                continue
            text = raw.decode("utf-8", errors="replace").strip()
            if not text:
                continue
            decoded = decode_protocol_line(text)
            if decoded.startswith("input-event "):
                event_count += 1
                print(f"  {decoded}")

    print(f"event_phase count={event_count}")
    print(f"event_phase result={'PASS' if event_count > 0 else 'WARN'}")
    return event_count > 0


def main() -> int:
    args = parse_args()
    try:
        serial_module, list_ports_module = load_pyserial()
    except Exception as exc:
        print(exc, file=sys.stderr)
        return 1

    if args.list:
        return list_ports(list_ports_module)

    try:
        port = choose_port(list_ports_module, args.port)
    except Exception as exc:
        print(f"port selection failed: {exc}", file=sys.stderr)
        return 1

    text_choice = PortChoice(port=port, baudrate=args.baudrate)

    print(f"selected_port {port}")
    print(
        "plan "
        f"text_baud={args.baudrate} protocol_baud={args.protocol_baudrate} "
        f"poll_count={args.poll_count} event_window={args.monitor_window:.1f}s"
    )

    results: list[bool] = []

    if not args.skip_text:
        results.append(run_text_phase(serial_module, text_choice, args))
    if not args.skip_protocol:
        results.append(run_protocol_phase(serial_module, port, args))
    if not args.skip_poll:
        results.append(run_input_poll_phase(serial_module, text_choice, args))
    if not args.skip_events:
        results.append(run_event_phase(serial_module, port, args))

    passed = all(results) if results else True
    print(f"overall_result {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
