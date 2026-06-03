"""Smoke-test TURN allocation over UDP and TCP.

The script intentionally uses only the Python standard library so it can run on
fresh Windows or VPS environments without installing coturn client tools.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import os
import socket
import struct
import sys
from collections.abc import Callable


MAGIC_COOKIE = 0x2112A442

MSG_ALLOCATE = 0x0003
MSG_ALLOCATE_SUCCESS = 0x0103

ATTR_USERNAME = 0x0006
ATTR_MESSAGE_INTEGRITY = 0x0008
ATTR_ERROR_CODE = 0x0009
ATTR_REALM = 0x0014
ATTR_NONCE = 0x0015
ATTR_XOR_RELAYED_ADDRESS = 0x0016
ATTR_REQUESTED_TRANSPORT = 0x0019

DEFAULT_HOST = "31.129.97.211"
DEFAULT_PORT = 3478
DEFAULT_USERNAME = "family"
DEFAULT_CREDENTIAL = "dev-turn-credential"


def _pad4(value: bytes) -> bytes:
    return value + (b"\x00" * ((4 - len(value) % 4) % 4))


def stun_attr(attr_type: int, value: bytes) -> bytes:
    return struct.pack("!HH", attr_type, len(value)) + _pad4(value)


def build_stun_message(
    message_type: int,
    transaction_id: bytes,
    attrs: list[bytes],
) -> bytes:
    if len(transaction_id) != 12:
        raise ValueError("transaction_id must be exactly 12 bytes")
    body = b"".join(attrs)
    return struct.pack(
        "!HHI12s",
        message_type,
        len(body),
        MAGIC_COOKIE,
        transaction_id,
    ) + body


def _requested_udp_relay_transport_attr() -> bytes:
    return stun_attr(ATTR_REQUESTED_TRANSPORT, b"\x11\x00\x00\x00")


def build_authenticated_allocate_request(
    *,
    transaction_id: bytes,
    username: str,
    password: str,
    realm: bytes,
    nonce: bytes,
) -> bytes:
    body_before_integrity = b"".join(
        [
            _requested_udp_relay_transport_attr(),
            stun_attr(ATTR_USERNAME, username.encode("utf-8")),
            stun_attr(ATTR_REALM, realm),
            stun_attr(ATTR_NONCE, nonce),
        ]
    )
    header = struct.pack(
        "!HHI12s",
        MSG_ALLOCATE,
        len(body_before_integrity) + 24,
        MAGIC_COOKIE,
        transaction_id,
    )
    key = hashlib.md5(
        f"{username}:{realm.decode('utf-8')}:{password}".encode("utf-8")
    ).digest()
    digest = hmac.new(key, header + body_before_integrity, hashlib.sha1).digest()
    return header + body_before_integrity + struct.pack(
        "!HH",
        ATTR_MESSAGE_INTEGRITY,
        20,
    ) + digest


def _iter_attrs(message: bytes):
    if len(message) < 20:
        raise ValueError("short STUN message")
    _, length, _, _ = struct.unpack("!HHI12s", message[:20])
    pos = 20
    end = 20 + length
    while pos + 4 <= end:
        attr_type, attr_len = struct.unpack("!HH", message[pos : pos + 4])
        yield attr_type, message[pos + 4 : pos + 4 + attr_len]
        pos += 4 + ((attr_len + 3) // 4) * 4


def _get_attr(message: bytes, attr_type: int) -> bytes | None:
    for current_type, value in _iter_attrs(message):
        if current_type == attr_type:
            return value
    return None


def _parse_error(message: bytes) -> str:
    value = _get_attr(message, ATTR_ERROR_CODE)
    if value is None or len(value) < 4:
        return "unknown error"
    code = (value[2] * 100) + value[3]
    reason = value[4:].rstrip(b"\x00").decode("utf-8", errors="replace")
    return f"{code} {reason}".strip()


def parse_xor_relayed_address(message: bytes) -> str | None:
    value = _get_attr(message, ATTR_XOR_RELAYED_ADDRESS)
    if value is None or len(value) < 8:
        return None
    family = value[1]
    port = struct.unpack("!H", value[2:4])[0] ^ (MAGIC_COOKIE >> 16)
    if family != 1:
        return None
    raw_ip = struct.unpack("!I", value[4:8])[0] ^ MAGIC_COOKIE
    return f"{socket.inet_ntoa(struct.pack('!I', raw_ip))}:{port}"


def encode_xor_ipv4_address_for_test(ip_address: str, port: int) -> bytes:
    encoded_port = port ^ (MAGIC_COOKIE >> 16)
    encoded_ip = struct.unpack("!I", socket.inet_aton(ip_address))[0] ^ MAGIC_COOKIE
    return b"\x00\x01" + struct.pack("!H", encoded_port) + struct.pack("!I", encoded_ip)


def _recv_tcp_message(sock: socket.socket) -> bytes:
    header = sock.recv(20)
    if len(header) < 20:
        raise RuntimeError("short TCP response header")
    length = struct.unpack("!H", header[2:4])[0]
    body = b""
    while len(body) < length:
        chunk = sock.recv(length - len(body))
        if not chunk:
            raise RuntimeError("short TCP response body")
        body += chunk
    return header + body


def _allocate(
    *,
    label: str,
    send_recv: Callable[[bytes], bytes],
    username: str,
    password: str,
) -> str:
    challenge_request = build_stun_message(
        MSG_ALLOCATE,
        os.urandom(12),
        [_requested_udp_relay_transport_attr()],
    )
    challenge_response = send_recv(challenge_request)
    realm = _get_attr(challenge_response, ATTR_REALM)
    nonce = _get_attr(challenge_response, ATTR_NONCE)
    if realm is None or nonce is None:
        raise RuntimeError(f"{label}: challenge failed: {_parse_error(challenge_response)}")

    allocate_request = build_authenticated_allocate_request(
        transaction_id=os.urandom(12),
        username=username,
        password=password,
        realm=realm,
        nonce=nonce,
    )
    allocate_response = send_recv(allocate_request)
    message_type = struct.unpack("!H", allocate_response[:2])[0]
    relay = parse_xor_relayed_address(allocate_response)
    if message_type != MSG_ALLOCATE_SUCCESS or relay is None:
        raise RuntimeError(f"{label}: allocation failed: {_parse_error(allocate_response)}")
    return relay


def allocate_udp(
    *,
    host: str,
    port: int,
    username: str,
    password: str,
    timeout: float,
) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)

        def send_recv(message: bytes) -> bytes:
            sock.sendto(message, (host, port))
            response, _ = sock.recvfrom(4096)
            return response

        return _allocate(
            label="udp",
            send_recv=send_recv,
            username=username,
            password=password,
        )


def allocate_tcp(
    *,
    host: str,
    port: int,
    username: str,
    password: str,
    timeout: float,
) -> str:
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)

        def send_recv(message: bytes) -> bytes:
            sock.sendall(message)
            return _recv_tcp_message(sock)

        return _allocate(
            label="tcp",
            send_recv=send_recv,
            username=username,
            password=password,
        )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Smoke-test TURN allocation.")
    parser.add_argument("--host", default=os.getenv("TURN_HOST", DEFAULT_HOST))
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.getenv("TURN_PORT", str(DEFAULT_PORT))),
    )
    parser.add_argument(
        "--username",
        default=os.getenv("TURN_USERNAME", DEFAULT_USERNAME),
    )
    parser.add_argument(
        "--credential",
        default=os.getenv("TURN_CREDENTIAL", DEFAULT_CREDENTIAL),
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.getenv("TURN_TIMEOUT", "5")),
    )
    parser.add_argument("--skip-udp", action="store_true")
    parser.add_argument("--skip-tcp", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    checks = []
    if not args.skip_udp:
        checks.append(("udp", allocate_udp))
    if not args.skip_tcp:
        checks.append(("tcp", allocate_tcp))
    if not checks:
        print("No checks selected")
        return 2

    failures = 0
    for label, check in checks:
        try:
            relay = check(
                host=args.host,
                port=args.port,
                username=args.username,
                password=args.credential,
                timeout=args.timeout,
            )
            print(f"{label}: allocation success, relay={relay}")
        except Exception as exc:
            failures += 1
            print(f"{label}: {exc}", file=sys.stderr)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
