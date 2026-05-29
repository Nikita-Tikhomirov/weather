"""
Tunnel Relay Server — runs on VPS (31.129.97.211).
Pairs PC bridge with mobile clients and relays messages.

Protocol:
  PC bridge:  {"type":"register","project_id":"xxx"}
  Mobile:     {"type":"connect","project_id":"xxx"}
  Then bidirectional relay of all JSON-line messages.

Usage: python tunnel_server.py --port 9877
"""
import argparse
import asyncio
import json
import uuid

MAX_RELAY_LINE_BYTES = 32 * 1024 * 1024
LAUNCHER_PONG_TIMEOUT_SECONDS = 2.0

class TunnelServer:
    def __init__(self, host: str = '0.0.0.0', port: int = 9877):
        self.host = host
        self.port = port
        self._server = None
        # project_id -> (bridge_reader, bridge_writer)
        self._bridges: dict[str, tuple] = {}
        # project_id -> list of mobile writers
        self._mobile_writers: dict[str, list] = {}
        # project_id -> relay task
        self._relay_tasks: dict[str, asyncio.Task] = {}
        # PC launcher sockets that can start project_bridge.py on demand.
        self._launcher_writers: list[asyncio.StreamWriter] = []
        self._launcher_pongs: dict[tuple[int, str], asyncio.Event] = {}

    async def start(self):
        self._server = await asyncio.start_server(
            self._handle_client,
            host=self.host,
            port=self.port,
            limit=MAX_RELAY_LINE_BYTES,
        )
        addr = self._server.sockets[0].getsockname()
        print(f"Tunnel server listening on {addr[0]}:{addr[1]}", flush=True)

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        addr = writer.get_extra_info('peername')
        print(f"[tunnel] Connection from {addr}", flush=True)

        try:
            first_line = await asyncio.wait_for(reader.readline(), timeout=10)
            if not first_line:
                writer.close()
                return

            try:
                msg = json.loads(first_line.decode('utf-8', errors='replace').strip())
            except json.JSONDecodeError:
                writer.close()
                return

            msg_type = msg.get('type', '')
            project_id = msg.get('project_id', '').strip()

            if msg_type == 'codewhale_register':
                bridge_id = project_id or 'codewhale'
                await self._handle_bridge(
                    f'codewhale:{bridge_id}',
                    reader,
                    writer,
                )
                return
            if msg_type == 'codewhale_connect':
                bridge_id = project_id or 'codewhale'
                session_id = msg.get('session_id', '').strip()
                await self._handle_mobile(
                    f'codewhale:{bridge_id}',
                    reader,
                    writer,
                    session_id=session_id,
                    public_project_id=bridge_id,
                    attached_type='codewhale_mobile_attached',
                    autostart=False,
                )
                return

            if not project_id:
                writer.close()
                return

            if msg_type == 'register':
                await self._handle_bridge(project_id, reader, writer)
            elif msg_type == 'connect':
                session_id = msg.get('session_id', '').strip()
                await self._handle_mobile(project_id, reader, writer, session_id=session_id)
            elif msg_type == 'launcher':
                await self._handle_launcher(reader, writer)
            elif msg_type == 'launcher_ping':
                await self._handle_launcher_ping(writer)
            elif msg_type == 'start_bridge':
                await self._handle_start_bridge(project_id, writer)
            else:
                print(f"[tunnel] Unknown first msg from {addr}: {msg_type}", flush=True)

        except asyncio.TimeoutError:
            pass
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            if not writer.is_closing():
                writer.close()

    async def _handle_bridge(self, project_id: str, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """PC bridge registers. All data from bridge is broadcast to mobile clients."""
        previous = self._bridges.get(project_id)
        if previous is not None:
            old_reader, old_writer = previous
            if old_reader is not reader and not old_writer.is_closing():
                old_writer.close()
            old_task = self._relay_tasks.get(project_id)
            if old_task is not None and not old_task.done():
                old_task.cancel()
        self._bridges[project_id] = (reader, writer)
        print(f"[tunnel] Bridge registered: {project_id}", flush=True)

        # Start relay: bridge -> all mobile clients
        async def forward_bridge_to_mobiles():
            try:
                while True:
                    line = await reader.readline()
                    if not line:
                        break
                    # Forward to all mobile clients
                    mobiles = self._mobile_writers.get(project_id, [])
                    dead = []
                    for mw in mobiles:
                        try:
                            mw.write(line)
                            await mw.drain()
                        except Exception:
                            dead.append(mw)
                    for mw in dead:
                        mobiles.remove(mw)
                        try:
                            mw.close()
                        except Exception:
                            pass
            except (ConnectionResetError, asyncio.IncompleteReadError):
                pass
            finally:
                # Only clean up if our bridge entry is still current.
                # A reconnect may have registered a new (reader, writer)
                # while this relay task was shutting down.
                current = self._bridges.get(project_id)
                if current is not None and current[0] is reader:
                    self._bridges.pop(project_id, None)
                    self._mobile_writers.pop(project_id, None)
                    self._relay_tasks.pop(project_id, None)
                    print(f"[tunnel] Bridge unregistered: {project_id}", flush=True)
                if not writer.is_closing():
                    writer.close()

        task = asyncio.create_task(forward_bridge_to_mobiles())
        self._relay_tasks[project_id] = task
        await task

    async def _handle_launcher(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """PC launcher stays connected and receives start_bridge commands."""
        self._launcher_writers.append(writer)
        print("[tunnel] Launcher registered", flush=True)
        self._send_json(writer, {'type': 'status', 'text': 'Launcher registered'})
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode('utf-8', errors='replace').strip())
                except json.JSONDecodeError:
                    continue
                text = str(msg.get('text', '')).strip()
                if msg.get('type') == 'pong':
                    ping_id = str(msg.get('ping_id', '')).strip()
                    if ping_id:
                        pong = self._launcher_pongs.get((id(writer), ping_id))
                        if pong is not None:
                            pong.set()
                    else:
                        # Backward compatibility for older PC launchers.
                        for (writer_id, _), pong in list(self._launcher_pongs.items()):
                            if writer_id == id(writer):
                                pong.set()
                    continue
                if text:
                    print(f"[tunnel] Launcher: {text}", flush=True)
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            if writer in self._launcher_writers:
                self._launcher_writers.remove(writer)
            for key in list(self._launcher_pongs):
                if key[0] == id(writer):
                    self._launcher_pongs.pop(key, None)
            print("[tunnel] Launcher unregistered", flush=True)
            if not writer.is_closing():
                writer.close()

    async def _handle_start_bridge(self, project_id: str, writer: asyncio.StreamWriter):
        """Mobile asks a PC launcher to start project_bridge.py."""
        started = await self._request_bridge_start(project_id)
        if started:
            self._send_json(writer, {
                'type': 'status',
                'text': f'Bridge start requested for {project_id}',
                'project_id': project_id,
            })
        else:
            self._send_json(writer, {
                'type': 'error',
                'text': 'Bridge launcher is not connected',
                'project_id': project_id,
            })

    async def _handle_launcher_ping(self, writer: asyncio.StreamWriter):
        """Health endpoint for the Windows watchdog; does not start a bridge."""
        alive = await self._ping_launchers()
        if alive:
            self._send_json(writer, {
                'type': 'status',
                'text': 'Bridge launcher is connected',
                'project_id': 'launcher',
            })
        else:
            self._send_json(writer, {
                'type': 'error',
                'text': 'Bridge launcher is not connected',
                'project_id': 'launcher',
            })

    async def _ping_launchers(self) -> bool:
        if not self._launcher_writers:
            return False

        delivered = False
        dead = []
        for launcher in self._launcher_writers:
            pong_key = None
            try:
                if launcher.is_closing():
                    dead.append(launcher)
                    continue
                ping_id = uuid.uuid4().hex
                pong = asyncio.Event()
                pong_key = (id(launcher), ping_id)
                self._launcher_pongs[pong_key] = pong
                payload = json.dumps(
                    {
                        'type': 'ping',
                        'project_id': 'launcher',
                        'ping_id': ping_id,
                    },
                    ensure_ascii=False,
                ).encode('utf-8') + b'\n'
                launcher.write(payload)
                await launcher.drain()
                try:
                    await asyncio.wait_for(
                        pong.wait(),
                        timeout=LAUNCHER_PONG_TIMEOUT_SECONDS,
                    )
                    delivered = True
                except asyncio.TimeoutError:
                    dead.append(launcher)
            except Exception:
                dead.append(launcher)
            finally:
                if pong_key is not None:
                    self._launcher_pongs.pop(pong_key, None)
        for launcher in dead:
            if launcher in self._launcher_writers:
                self._launcher_writers.remove(launcher)
            if not launcher.is_closing():
                launcher.close()
        return delivered

    async def _request_bridge_start(self, project_id: str) -> bool:
        if not await self._ping_launchers():
            return False

        payload = json.dumps(
            {'type': 'start_bridge', 'project_id': project_id},
            ensure_ascii=False,
        ).encode('utf-8') + b'\n'
        delivered = False
        dead = []
        for launcher in self._launcher_writers:
            try:
                launcher.write(payload)
                await launcher.drain()
                delivered = True
            except Exception:
                dead.append(launcher)
        for launcher in dead:
            if launcher in self._launcher_writers:
                self._launcher_writers.remove(launcher)
        return delivered

    async def _handle_mobile(
        self,
        project_id: str,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        session_id: str = '',
        public_project_id: str | None = None,
        attached_type: str = 'mobile_attached',
        autostart: bool = True,
    ):
        """Mobile client connects. Messages from mobile go to bridge."""
        visible_project_id = public_project_id or project_id
        bridge = self._bridges.get(project_id)
        if not bridge:
            self._send_json(writer, {'type': 'status', 'text': f'Waiting for PC bridge ({visible_project_id})...'})
            print(f"[tunnel] Mobile waiting for bridge: {project_id}", flush=True)
            if autostart:
                await self._request_bridge_start(project_id)
            # Wait a bit and check again
            for _ in range(30):  # 30 seconds timeout
                await asyncio.sleep(1)
                bridge = self._bridges.get(project_id)
                if bridge:
                    break
            if not bridge:
                self._send_json(writer, {'type': 'error', 'text': 'Bridge not available'})
                return

        b_reader, b_writer = bridge
        print(f"[tunnel] Paired mobile -> {project_id}", flush=True)
        self._send_json(writer, {
            'type': 'status',
            'text': f'Connected to {visible_project_id}',
            'project_id': visible_project_id,
        })

        # Register this mobile writer for broadcasts from bridge
        self._mobile_writers.setdefault(project_id, []).append(writer)
        try:
            b_writer.write(
                json.dumps(
                    {
                        'type': attached_type,
                        'project_id': visible_project_id,
                        'session_id': session_id,
                    },
                    ensure_ascii=False,
                ).encode('utf-8') + b'\n'
            )
            await b_writer.drain()
        except Exception:
            pass

        # Forward mobile messages to bridge
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    b_writer.write(line)
                    await b_writer.drain()
                except Exception:
                    break
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            # Remove this mobile from broadcast list
            mobiles = self._mobile_writers.get(project_id, [])
            if writer in mobiles:
                mobiles.remove(writer)
            print(f"[tunnel] Mobile disconnected: {project_id}", flush=True)
            if not writer.is_closing():
                writer.close()

    @staticmethod
    def _send_json(writer: asyncio.StreamWriter, obj: dict):
        data = json.dumps(obj, ensure_ascii=False) + '\n'
        writer.write(data.encode('utf-8'))

    async def stop(self):
        for task in self._relay_tasks.values():
            task.cancel()
        for writer in list(self._launcher_writers):
            if not writer.is_closing():
                writer.close()
        self._launcher_writers.clear()
        if self._server:
            self._server.close()
            await self._server.wait_closed()


async def main():
    parser = argparse.ArgumentParser(description='Tunnel Relay Server')
    parser.add_argument('--port', type=int, default=9877)
    parser.add_argument('--host', type=str, default='0.0.0.0')
    args = parser.parse_args()

    server = TunnelServer(host=args.host, port=args.port)
    await server.start()
    try:
        await asyncio.Event().wait()
    except KeyboardInterrupt:
        print("\nShutting down...", flush=True)
    finally:
        await server.stop()


if __name__ == '__main__':
    asyncio.run(main())
