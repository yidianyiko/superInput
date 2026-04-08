#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import time
from dataclasses import dataclass


DEFAULT_APP_PATH = pathlib.Path("/Users/lixingting/Desktop/StartUp/superInput/SlashVibe.app")
DEFAULT_DEBUG_LOG = pathlib.Path("/tmp/speechbar_debug.log")
DEFAULT_EVENTS = (
    pathlib.Path.home()
    / "Library"
    / "Application Support"
    / "StartUpSpeechBar"
    / "board-input"
    / "events.jsonl"
)
DEFAULT_RAW_CAPTURE = (
    pathlib.Path.home()
    / "Library"
    / "Application Support"
    / "StartUpSpeechBar"
    / "board-input"
    / "raw-serial-rx.bin"
)

DEFAULT_EVENT_KINDS = {
    "pushToTalkPressed",
    "pushToTalkReleased",
    "pressPrimary",
    "pressSecondary",
    "dismissSelected",
    "rotaryClockwise",
    "rotaryCounterClockwise",
    "switchBoardNext",
    "switchBoardPrevious",
}


@dataclass
class VerificationResult:
    handshake_ok: bool = False
    raw_bytes_grew: bool = False
    detected_event: str | None = None
    event_record: dict | None = None
    debug_line: str | None = None


class IncrementalFileReader:
    def __init__(self, path: pathlib.Path) -> None:
        self.path = path
        self.offset = 0

    def prime_to_end(self) -> None:
        if self.path.exists():
            self.offset = self.path.stat().st_size

    def read_new_text(self) -> str:
        if not self.path.exists():
            return ""
        size = self.path.stat().st_size
        if size < self.offset:
            self.offset = 0
        if size == self.offset:
            return ""
        with self.path.open("rb") as handle:
            handle.seek(self.offset)
            data = handle.read()
        self.offset = size
        return data.decode("utf-8", errors="ignore")

    def current_size(self) -> int:
        if not self.path.exists():
            return 0
        return self.path.stat().st_size


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="验证 SlashVibe 板端按键事件是否成功通过 CDC -> bridge -> app 链路上报。"
    )
    parser.add_argument("--app", default=str(DEFAULT_APP_PATH), help="SlashVibe.app 路径")
    parser.add_argument("--debug-log", default=str(DEFAULT_DEBUG_LOG))
    parser.add_argument("--events", default=str(DEFAULT_EVENTS))
    parser.add_argument("--raw-capture", default=str(DEFAULT_RAW_CAPTURE))
    parser.add_argument("--handshake-timeout", type=float, default=8.0)
    parser.add_argument("--event-timeout", type=float, default=15.0)
    parser.add_argument(
        "--event-kind",
        action="append",
        default=[],
        help="仅接受指定 kind，可多次传入；默认接受任意受支持板端事件",
    )
    parser.add_argument(
        "--no-open-app",
        action="store_true",
        help="不自动尝试打开 SlashVibe.app",
    )
    return parser.parse_args()


def ensure_parent(path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def open_app_if_needed(app_path: pathlib.Path) -> None:
    if not app_path.exists():
        return
    if os.system("pgrep -x SlashVibe >/dev/null 2>&1") == 0:
        return
    os.system(f"open -a {shell_quote(str(app_path))} >/dev/null 2>&1")


def shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\\''") + "'"


def wait_for_handshake(debug_reader: IncrementalFileReader, timeout: float, result: VerificationResult) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        text = debug_reader.read_new_text()
        if text:
            for line in text.splitlines():
                if "device_info seq=" in line:
                    result.handshake_ok = True
                    result.debug_line = line
                    return True
        time.sleep(0.2)
    return False


def wait_for_event(
    debug_reader: IncrementalFileReader,
    events_reader: IncrementalFileReader,
    raw_reader: IncrementalFileReader,
    accepted_kinds: set[str],
    timeout: float,
    result: VerificationResult,
) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if raw_reader.current_size() > raw_reader.offset:
            result.raw_bytes_grew = True

        debug_text = debug_reader.read_new_text()
        if debug_text:
            for line in debug_text.splitlines():
                marker = "event kind="
                if marker not in line:
                    continue
                try:
                    suffix = line.split(marker, 1)[1]
                    kind = suffix.split()[0]
                except Exception:
                    continue
                if kind in accepted_kinds:
                    result.detected_event = kind
                    result.debug_line = line
                    return True

        events_text = events_reader.read_new_text()
        if events_text:
            for line in events_text.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except Exception:
                    continue
                kind = record.get("kind")
                if kind in accepted_kinds:
                    result.detected_event = kind
                    result.event_record = record
                    return True
        time.sleep(0.15)
    return False


def main() -> int:
    args = parse_args()
    app_path = pathlib.Path(args.app).expanduser()
    debug_log = pathlib.Path(args.debug_log).expanduser()
    events_file = pathlib.Path(args.events).expanduser()
    raw_capture = pathlib.Path(args.raw_capture).expanduser()

    accepted_kinds = set(args.event_kind) if args.event_kind else set(DEFAULT_EVENT_KINDS)

    ensure_parent(events_file)
    ensure_parent(raw_capture)

    if not args.no_open_app:
        open_app_if_needed(app_path)

    debug_reader = IncrementalFileReader(debug_log)
    events_reader = IncrementalFileReader(events_file)
    raw_reader = IncrementalFileReader(raw_capture)
    debug_reader.prime_to_end()
    events_reader.prime_to_end()
    raw_reader.prime_to_end()

    result = VerificationResult()

    print("== SlashVibe 板端按键验证 ==")
    print(f"app: {app_path}")
    print(f"debug log: {debug_log}")
    print(f"events: {events_file}")
    print(f"raw capture: {raw_capture}")
    print("")
    print("步骤 1/2: 等待握手日志 device_info ...")

    if not wait_for_handshake(debug_reader, args.handshake_timeout, result):
        print("失败: 在超时时间内没有观察到 device_info seq=... 日志。")
        print("结论: 当前无法确认 app 已经连上板子。")
        print("")
        print("建议先检查:")
        print("1. SlashVibe.app 是否已打开")
        print("2. /dev/cu.usbmodem... 端口是否存在")
        print("3. 板子是否仍在用当前 CDC 固件")
        return 2

    print(f"通过: 已观察到握手日志 -> {result.debug_line}")
    print("")
    print("步骤 2/2: 现在请在 15 秒内按一次板子的目标按键 ...")

    if wait_for_event(
        debug_reader=debug_reader,
        events_reader=events_reader,
        raw_reader=raw_reader,
        accepted_kinds=accepted_kinds,
        timeout=args.event_timeout,
        result=result,
    ):
        print(f"通过: 检测到按键事件 -> {result.detected_event}")
        if result.event_record is not None:
            print(f"events.jsonl: {json.dumps(result.event_record, ensure_ascii=False)}")
        if result.debug_line is not None:
            print(f"debug log: {result.debug_line}")
        print("")
        print("结论: 嵌入式端按键触发通信可用，事件已经进入 Mac 端消费链路。")
        return 0

    print("失败: 握手已通，但在等待时间内没有检测到目标按键事件。")
    if raw_reader.current_size() > raw_reader.offset or result.raw_bytes_grew:
        print("补充: 原始串口抓包在等待期间有新字节，说明板子可能有发数据，但不是当前 app 识别的按键事件。")
    else:
        print("补充: 原始串口抓包也没有明显增长，说明按键触发时板子大概率没有向 CDC 发出新数据。")
    print("")
    print("建议排查:")
    print("1. 板子按键是否真的发送了 OP_INPUT_EVENT_PUSH")
    print("2. payload 是否为当前 Mac 端支持的事件码 1..9")
    print("3. 是否误发成了别的 opcode，或只做了本地状态变化没有上报")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
