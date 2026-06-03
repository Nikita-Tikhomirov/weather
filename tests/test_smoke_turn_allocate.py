import hashlib
import hmac
import importlib.util
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "smoke_turn_allocate.py"


def load_smoke_turn_module():
    assert SCRIPT.exists(), "scripts/smoke_turn_allocate.py should exist"
    spec = importlib.util.spec_from_file_location("smoke_turn_allocate", SCRIPT)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_authenticated_allocate_request_uses_turn_long_term_auth_hmac():
    module = load_smoke_turn_module()
    txid = b"\x01" * 12
    username = "family"
    realm = b"31.129.97.211"
    nonce = b"nonce-123"
    password = "turn-secret"

    request = module.build_authenticated_allocate_request(
        transaction_id=txid,
        username=username,
        password=password,
        realm=realm,
        nonce=nonce,
    )

    body_before_integrity = b"".join(
        [
            module.stun_attr(module.ATTR_REQUESTED_TRANSPORT, b"\x11\x00\x00\x00"),
            module.stun_attr(module.ATTR_USERNAME, username.encode("utf-8")),
            module.stun_attr(module.ATTR_REALM, realm),
            module.stun_attr(module.ATTR_NONCE, nonce),
        ]
    )
    header = struct.pack(
        "!HHI12s",
        module.MSG_ALLOCATE,
        len(body_before_integrity) + 24,
        module.MAGIC_COOKIE,
        txid,
    )
    key = hashlib.md5(
        f"{username}:{realm.decode('utf-8')}:{password}".encode("utf-8")
    ).digest()
    expected_digest = hmac.new(
        key,
        header + body_before_integrity,
        hashlib.sha1,
    ).digest()

    assert request[:20] == header
    assert request[-24:-20] == struct.pack("!HH", module.ATTR_MESSAGE_INTEGRITY, 20)
    assert request[-20:] == expected_digest


def test_parse_xor_relayed_address_decodes_ipv4_address():
    module = load_smoke_turn_module()
    relay_ip = "31.129.97.211"
    relay_port = 64362
    encoded = module.encode_xor_ipv4_address_for_test(relay_ip, relay_port)
    response = module.build_stun_message(
        module.MSG_ALLOCATE_SUCCESS,
        b"\x02" * 12,
        [module.stun_attr(module.ATTR_XOR_RELAYED_ADDRESS, encoded)],
    )

    assert module.parse_xor_relayed_address(response) == f"{relay_ip}:{relay_port}"
