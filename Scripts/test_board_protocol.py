#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import select
import sys
import termios
import time
import tty
from dataclasses import asdict, dataclass, field


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
PROTO_DIR = (
    SCRIPT_DIR.parent
    / "Sources"
    / "SpeechBarApp"
    / "Resources"
    / "HardwareBridge"
)
if str(PROTO_DIR) not in sys.path:
    sys.path.insert(0, str(PROTO_DIR))

import slashvibe_host_proto as proto


DEFAULT_PORT = "/dev/cu.usbmodem3175334B31331"
DEFAULT_BAUDRATE = 230400
DEFAULT_REPORT_PATH = SCRIPT_DIR.parent / "board_protocol_test_report.json"

EVENT_KIND_MAP = {
    proto.INPUT_EVENT_ROTATE_NEXT: "rotaryClockwise",
    proto.INPUT_EVENT_ROTATE_PREVIOUS: "rotaryCounterClockwise",
    proto.INPUT_EVENT_PRESS_PRIMARY: "pressPrimary",
    proto.INPUT_EVENT_PRESS_SECONDARY: "pressSecondary",
    proto.INPUT_EVENT_DISMISS_SELECTED: "dismissSelected",
    proto.INPUT_EVENT_PUSH_TO_TALK_PRESSED: "pushToTalkPressed",
    proto.INPUT_EVENT_PUSH_TO_TALK_RELEASED: "pushToTalkReleased",
    proto.INPUT_EVENT_SWITCH_BOARD_NEXT: "switchBoardNext",
    proto.INPUT_EVENT_SWITCH_BOARD_PREVIOUS: "switchBoardPrevious",
}


@dataclass
class CheckResult:
    name: str
    passed: bool
    details: str
    observed: dict[str, object] = field(default_factory=dict)


@dataclass
class TestReport:
    port: str
    baudrate: int
    started_at: str
    checks: list[CheckResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(check.passed for check in self.checks)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="SlashVibe 板端串口协议联调测试。先自动测握手，再在人工按键配合下监听输入事件。"
    )
    parser.add_argument("--port", default=DEFAULT_PORT)
    parser.add_argument("--baudrate", type=int, default=DEFAULT_BAUDRATE)
    parser.add_argument("--hello-count", type=int, default=4)
    parser.add_argument("--hello-timeout", type=float, default=4.0)
    parser.add_argument("--event-timeout", type=float, default=12.0)
    parser.add_argument("--report", default=str(DEFAULT_REPORT_PATH))
    parser.add_argument(
        "--event-code",
        type=int,
        action="append",
        default=[],
        help="期望的人工作按键事件码，可多次传入；默认接受任意 1..9",
    )
    parser.add_argument(
        "--skip-manual",
        action="store_true",
        help="只做自动握手测试，不做人工作按键事件监听",
    )
    return parser.parse_args()


def open_serial(port: str, baudrate: int):
    try:
        import serial  # type: ignore
    except Exception as exc:
        raise RuntimeError(f"pyserial unavailable: {exc}") from exc
    device = serial.Serial(port=port, baudrate=baudrate, timeout=0.2, write_timeout=1.0)
    device.dtr = True
    device.rts = True
    try:
        device.reset_input_buffer()
        device.reset_output_buffer()
    except Exception:
        pass
    return device


def write_line(serial_port, line: str) -> None:
    serial_port.write(line.encode("ascii", errors="ignore") + b"\r\n")


def send_hello(serial_port, seq: int) -> None:
    report = proto.encode_report(proto.ProtocolMessage(opcode=proto.OP_HELLO, seq=seq))
    write_line(serial_port, proto.format_hex_line(report))


def read_messages(serial_port, timeout: float) -> list[proto.ProtocolMessage]:
    deadline = time.monotonic() + timeout
    buffer = bytearray()
    messages: list[proto.ProtocolMessage] = []
    while time.monotonic() < deadline:
        chunk = serial_port.read(max(1, getattr(serial_port, "in_waiting", 0) or 1))
        if chunk:
            buffer.extend(chunk)
            while True:
                newline_index = buffer.find(b"\n")
                if newline_index < 0:
                    break
                line = bytes(buffer[:newline_index]).rstrip(b"\r")
                del buffer[:newline_index + 1]
                text = line.decode("utf-8", errors="ignore").strip()
                if not text:
                    continue
                if not text.startswith("@SVHEX:") and not text.startswith("SVHEX "):
                    continue
                try:
                    report = proto.parse_hex_line(text)
                    messages.append(proto.decode_report(report))
                except Exception:
                    continue
        else:
            time.sleep(0.02)
    return messages


def run_handshake_test(serial_port, hello_count: int, timeout: float) -> CheckResult:
    seen_device_info: list[int] = []
    for seq in range(1, hello_count + 1):
        send_hello(serial_port, seq)
        messages = read_messages(serial_port, timeout=max(timeout / hello_count, 0.4))
        for message in messages:
            if message.opcode == proto.OP_DEVICE_INFO:
                seen_device_info.append(message.seq)
    passed = len(seen_device_info) > 0
    detail = (
        f"收到 DEVICE_INFO seq={seen_device_info}"
        if passed else
        "未在超时时间内收到 DEVICE_INFO"
    )
    return CheckResult(
        name="handshake",
        passed=passed,
        details=detail,
        observed={"device_info_seq": seen_device_info},
    )


def prompt_manual_step(accepted_codes: set[int], event_timeout: float) -> None:
    accepted = ", ".join(f"{code}:{EVENT_KIND_MAP.get(code, 'unknown')}" for code in sorted(accepted_codes))
    print("")
    print("进入人工辅助步骤。")
    print(f"请在 {event_timeout:.0f} 秒内按一次板子上的目标按键。")
    print(f"当前接受的事件码: {accepted}")
    print("如果要取消，按 Ctrl+C。")


def run_event_test(serial_port, accepted_codes: set[int], event_timeout: float) -> CheckResult:
    prompt_manual_step(accepted_codes, event_timeout)
    messages = read_messages(serial_port, timeout=event_timeout)
    observed_events: list[dict[str, object]] = []
    for message in messages:
        if message.opcode != proto.OP_INPUT_EVENT_PUSH or len(message.payload) != 1:
            continue
        code = message.payload[0]
        observed_events.append({
            "seq": message.seq,
            "code": code,
            "kind": EVENT_KIND_MAP.get(code, "unknown"),
        })
        if code in accepted_codes:
            return CheckResult(
                name="input_event_push",
                passed=True,
                details=f"收到输入事件 code={code} kind={EVENT_KIND_MAP.get(code, 'unknown')} seq={message.seq}",
                observed={"events": observed_events},
            )

    return CheckResult(
        name="input_event_push",
        passed=False,
        details="未在等待窗口内收到期望的 INPUT_EVENT_PUSH",
        observed={"events": observed_events},
    )


def save_report(report_path: pathlib.Path, report: TestReport) -> None:
    report_path.write_text(
        json.dumps(
            {
                "port": report.port,
                "baudrate": report.baudrate,
                "started_at": report.started_at,
                "passed": report.passed,
                "checks": [asdict(check) for check in report.checks],
            },
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    report = TestReport(
        port=args.port,
        baudrate=args.baudrate,
        started_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    )
    accepted_codes = set(args.event_code) if args.event_code else set(EVENT_KIND_MAP.keys())

    print("== SlashVibe 板端协议测试 ==")
    print(f"port={args.port}")
    print(f"baudrate={args.baudrate}")
    print("")

    try:
        serial_port = open_serial(args.port, args.baudrate)
    except Exception as exc:
        print(f"打开串口失败: {exc}")
        return 2

    with serial_port:
        handshake = run_handshake_test(
            serial_port=serial_port,
            hello_count=args.hello_count,
            timeout=args.hello_timeout,
        )
        report.checks.append(handshake)
        print(f"[{'PASS' if handshake.passed else 'FAIL'}] {handshake.name}: {handshake.details}")

        if handshake.passed and not args.skip_manual:
            event_check = run_event_test(
                serial_port=serial_port,
                accepted_codes=accepted_codes,
                event_timeout=args.event_timeout,
            )
            report.checks.append(event_check)
            print(f"[{'PASS' if event_check.passed else 'FAIL'}] {event_check.name}: {event_check.details}")

    report_path = pathlib.Path(args.report).expanduser().resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    save_report(report_path, report)
    print("")
    print(f"测试报告已写入: {report_path}")

    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
