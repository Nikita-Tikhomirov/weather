import asyncio
import base64
import json
import unittest

from tunnel_server import MAX_RELAY_LINE_BYTES, TunnelServer


async def _read_json(reader: asyncio.StreamReader) -> dict:
    line = await asyncio.wait_for(reader.readline(), timeout=2)
    return json.loads(line.decode("utf-8"))


class TunnelServerLauncherTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.server = TunnelServer(host="127.0.0.1", port=0)
        await self.server.start()
        assert self.server._server is not None
        self.port = self.server._server.sockets[0].getsockname()[1]

    async def asyncTearDown(self) -> None:
        await self.server.stop()

    async def test_mobile_start_bridge_is_forwarded_to_launcher(self) -> None:
        launcher_reader, launcher_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        launcher_writer.write(
            json.dumps({"type": "launcher", "project_id": "launcher"}).encode("utf-8")
            + b"\n"
        )
        await launcher_writer.drain()
        self.assertEqual((await _read_json(launcher_reader))["type"], "status")

        mobile_reader, mobile_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        mobile_writer.write(
            json.dumps({"type": "start_bridge", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await mobile_writer.drain()

        command = await _read_json(launcher_reader)
        self.assertEqual(command["type"], "start_bridge")
        self.assertEqual(command["project_id"], "cifra")
        self.assertEqual((await _read_json(mobile_reader))["type"], "status")

        mobile_writer.close()
        launcher_writer.close()
        await mobile_writer.wait_closed()
        await launcher_writer.wait_closed()

    async def test_launcher_ping_reports_missing_launcher(self) -> None:
        probe_reader, probe_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        probe_writer.write(
            json.dumps({"type": "launcher_ping", "project_id": "launcher"}).encode(
                "utf-8"
            )
            + b"\n"
        )
        await probe_writer.drain()

        reply = await _read_json(probe_reader)
        self.assertEqual(reply["type"], "error")

        probe_writer.close()
        await probe_writer.wait_closed()

    async def test_launcher_ping_checks_registered_launcher_without_starting_bridge(
        self,
    ) -> None:
        launcher_reader, launcher_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        launcher_writer.write(
            json.dumps({"type": "launcher", "project_id": "launcher"}).encode("utf-8")
            + b"\n"
        )
        await launcher_writer.drain()
        self.assertEqual((await _read_json(launcher_reader))["type"], "status")

        probe_reader, probe_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        probe_writer.write(
            json.dumps({"type": "launcher_ping", "project_id": "launcher"}).encode(
                "utf-8"
            )
            + b"\n"
        )
        await probe_writer.drain()

        ping = await _read_json(launcher_reader)
        self.assertEqual(ping["type"], "ping")
        reply = await _read_json(probe_reader)
        self.assertEqual(reply["type"], "status")

        probe_writer.close()
        launcher_writer.close()
        await probe_writer.wait_closed()
        await launcher_writer.wait_closed()

    async def test_mobile_attach_notifies_bridge(self) -> None:
        bridge_reader, bridge_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
            limit=MAX_RELAY_LINE_BYTES,
        )
        bridge_writer.write(
            json.dumps({"type": "register", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await bridge_writer.drain()

        mobile_reader, mobile_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        mobile_writer.write(
            json.dumps({"type": "connect", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await mobile_writer.drain()

        self.assertEqual((await _read_json(mobile_reader))["type"], "status")
        attached = await _read_json(bridge_reader)
        self.assertEqual(attached["type"], "mobile_attached")
        self.assertEqual(attached["project_id"], "cifra")

        mobile_writer.close()
        bridge_writer.close()
        await mobile_writer.wait_closed()
        await bridge_writer.wait_closed()

    async def test_new_bridge_registration_replaces_stale_bridge(self) -> None:
        first_reader, first_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
            limit=MAX_RELAY_LINE_BYTES,
        )
        first_writer.write(
            json.dumps({"type": "register", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await first_writer.drain()

        second_reader, second_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
            limit=MAX_RELAY_LINE_BYTES,
        )
        second_writer.write(
            json.dumps({"type": "register", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await second_writer.drain()

        mobile_reader, mobile_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
        )
        mobile_writer.write(
            json.dumps({"type": "connect", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await mobile_writer.drain()

        self.assertEqual((await _read_json(mobile_reader))["type"], "status")
        attached = await _read_json(second_reader)
        self.assertEqual(attached["type"], "mobile_attached")

        mobile_writer.close()
        second_writer.close()
        first_writer.close()
        await mobile_writer.wait_closed()
        await second_writer.wait_closed()
        await first_writer.wait_closed()

    async def test_large_upload_message_is_relayed_to_bridge(self) -> None:
        bridge_reader, bridge_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
            limit=MAX_RELAY_LINE_BYTES,
        )
        bridge_writer.write(
            json.dumps({"type": "register", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await bridge_writer.drain()

        mobile_reader, mobile_writer = await asyncio.open_connection(
            "127.0.0.1",
            self.port,
            limit=MAX_RELAY_LINE_BYTES,
        )
        mobile_writer.write(
            json.dumps({"type": "connect", "project_id": "cifra"}).encode("utf-8")
            + b"\n"
        )
        await mobile_writer.drain()
        self.assertEqual((await _read_json(mobile_reader))["type"], "status")
        self.assertEqual((await _read_json(bridge_reader))["type"], "mobile_attached")

        payload = {
            "type": "upload_file",
            "filename": "large.jpg",
            "mime_type": "image/jpeg",
            "data_base64": base64.b64encode(b"x" * (96 * 1024)).decode("ascii"),
        }
        mobile_writer.write(json.dumps(payload).encode("utf-8") + b"\n")
        await mobile_writer.drain()

        relayed = await _read_json(bridge_reader)
        self.assertEqual(relayed["type"], "upload_file")
        self.assertEqual(relayed["filename"], "large.jpg")
        self.assertEqual(relayed["data_base64"], payload["data_base64"])

        mobile_writer.close()
        bridge_writer.close()
        await mobile_writer.wait_closed()
        await bridge_writer.wait_closed()


if __name__ == "__main__":
    unittest.main()
