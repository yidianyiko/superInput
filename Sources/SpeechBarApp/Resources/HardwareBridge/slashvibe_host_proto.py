#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
import struct


PROTOCOL_VERSION = 1
REPORT_SIZE = 64
PAYLOAD_MAX_BYTES = 56
OP_HELLO = 0x01
OP_DEVICE_INFO = 0x02
OP_INPUT_EVENT_PUSH = 0x19
OP_ACK = 0x7E

INPUT_EVENT_ROTATE_NEXT = 1
INPUT_EVENT_ROTATE_PREVIOUS = 2
INPUT_EVENT_PRESS_PRIMARY = 3
INPUT_EVENT_PRESS_SECONDARY = 4
INPUT_EVENT_DISMISS_SELECTED = 5
INPUT_EVENT_PUSH_TO_TALK_PRESSED = 6
INPUT_EVENT_PUSH_TO_TALK_RELEASED = 7
INPUT_EVENT_SWITCH_BOARD_NEXT = 8
INPUT_EVENT_SWITCH_BOARD_PREVIOUS = 9


@dataclass
class ProtocolMessage:
    opcode: int
    seq: int = 0
    payload: bytes = b""


def crc16_ccitt(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def encode_report(message: ProtocolMessage) -> bytes:
    payload = bytes(message.payload)
    if len(payload) > PAYLOAD_MAX_BYTES:
        raise ValueError("payload too large")
    report = bytearray(REPORT_SIZE)
    report[0] = PROTOCOL_VERSION
    report[1] = message.opcode & 0xFF
    struct.pack_into("<H", report, 2, message.seq & 0xFFFF)
    struct.pack_into("<H", report, 4, len(payload))
    report[6:6 + len(payload)] = payload
    struct.pack_into("<H", report, REPORT_SIZE - 2, crc16_ccitt(report[:-2]))
    return bytes(report)


def decode_report(report: bytes) -> ProtocolMessage:
    if len(report) != REPORT_SIZE:
        raise ValueError("report size mismatch")
    if report[0] != PROTOCOL_VERSION:
        raise ValueError("protocol version mismatch")
    expected_crc = crc16_ccitt(report[:-2])
    actual_crc = struct.unpack_from("<H", report, REPORT_SIZE - 2)[0]
    if expected_crc != actual_crc:
        raise ValueError("crc mismatch")
    payload_len = struct.unpack_from("<H", report, 4)[0]
    if payload_len > PAYLOAD_MAX_BYTES:
        raise ValueError("payload length invalid")
    return ProtocolMessage(
        opcode=report[1],
        seq=struct.unpack_from("<H", report, 2)[0],
        payload=bytes(report[6:6 + payload_len]),
    )


def format_hex_line(report: bytes) -> str:
    if len(report) != REPORT_SIZE:
        raise ValueError("report size mismatch")
    return "@SVHEX:" + report.hex().upper()


def parse_hex_line(line: str) -> bytes:
    if line.startswith("@SVHEX:"):
        hex_part = line[7:]
    elif line.startswith("SVHEX "):
        hex_part = line[6:]
    else:
        raise ValueError("not a SlashVibe frame")
    if len(hex_part) != REPORT_SIZE * 2:
        raise ValueError("hex line length mismatch")
    return bytes.fromhex(hex_part)
