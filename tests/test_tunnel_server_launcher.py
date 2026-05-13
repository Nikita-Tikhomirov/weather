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
