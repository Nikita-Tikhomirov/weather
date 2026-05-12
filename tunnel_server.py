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
import sys
from typing import Optional

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

    async def start(self):
        self._server = await asyncio.start_server(
            self._handle_client,
            host=self.host,
            port=self.port,
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

            if not project_id:
                writer.close()
                return

            if msg_type == 'register':
                await self._handle_bridge(project_id, reader, writer)
            elif msg_type == 'connect':
                await self._handle_mobile(project_id, reader, writer)
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
                # Cleanup
                self._bridges.pop(project_id, None)
                self._mobile_writers.pop(project_id, None)
                self._relay_tasks.pop(project_id, None)
                print(f"[tunnel] Bridge unregistered: {project_id}", flush=True)
                if not writer.is_closing():
                    writer.close()

        task = asyncio.create_task(forward_bridge_to_mobiles())
        self._relay_tasks[project_id] = task
        await task

    async def _handle_mobile(self, project_id: str, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Mobile client connects. Messages from mobile go to bridge."""
        bridge = self._bridges.get(project_id)
        if not bridge:
            self._send_json(writer, {'type': 'status', 'text': f'Waiting for PC bridge ({project_id})...'})
            print(f"[tunnel] Mobile waiting for bridge: {project_id}", flush=True)
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
            'text': f'Connected to {project_id}',
            'project_id': project_id,
        })

        # Register this mobile writer for broadcasts from bridge
        self._mobile_writers.setdefault(project_id, []).append(writer)

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
