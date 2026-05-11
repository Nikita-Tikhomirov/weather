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
import os
import sys
from typing import Optional

class TunnelServer:
    def __init__(self, host: str = '0.0.0.0', port: int = 9877):
        self.host = host
        self.port = port
        self._server = None
        # project_id -> waiting bridge connection (writer, reader)
        self._bridges: dict[str, tuple] = {}
        # project_id -> queue of waiting mobile clients
        self._waiting_clients: dict[str, list[tuple]] = {}

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
            # Read first message to determine role
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
                self._send_json(writer, {'type': 'error', 'text': 'project_id required'})
                writer.close()
                return

            if msg_type == 'register':
                # PC bridge registering
                await self._handle_bridge(project_id, reader, writer)
            elif msg_type == 'connect':
                # Mobile client connecting
                await self._handle_mobile(project_id, reader, writer)
            else:
                self._send_json(writer, {'type': 'error', 'text': f'unknown type: {msg_type}'})
                writer.close()

        except asyncio.TimeoutError:
            pass
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            if not writer.is_closing():
                writer.close()

    async def _handle_bridge(self, project_id: str, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """PC bridge registers and waits for mobile clients."""
        self._bridges[project_id] = (reader, writer)
        print(f"[tunnel] Bridge registered: {project_id}", flush=True)

        # Notify any waiting mobile clients
        waiting = self._waiting_clients.pop(project_id, [])
        for m_reader, m_writer in waiting:
            self._send_json(m_writer, {
                'type': 'status',
                'text': f'Bridge available for {project_id}',
                'project_id': project_id,
            })
            # Start relay
            asyncio.create_task(self._relay(m_reader, m_writer, reader, writer, project_id))

        # Keep connection alive with ping/pong
        try:
            while True:
                line = await asyncio.wait_for(reader.readline(), timeout=60)
                if not line:
                    break
                try:
                    msg = json.loads(line.decode('utf-8', errors='replace').strip())
                    if msg.get('type') == 'ping':
                        self._send_json(writer, {'type': 'pong'})
                except json.JSONDecodeError:
                    pass
        except asyncio.TimeoutError:
            pass
        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            self._bridges.pop(project_id, None)
            print(f"[tunnel] Bridge unregistered: {project_id}", flush=True)
            if not writer.is_closing():
                writer.close()

    async def _handle_mobile(self, project_id: str, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Mobile client wants to talk to a PC bridge."""
        bridge = self._bridges.get(project_id)
        if bridge:
            b_reader, b_writer = bridge
            print(f"[tunnel] Paired mobile -> {project_id}", flush=True)
            self._send_json(writer, {
                'type': 'status',
                'text': f'Connected to {project_id}',
                'project_id': project_id,
            })
            await self._relay(reader, writer, b_reader, b_writer, project_id)
        else:
            # Bridge not yet connected — queue mobile client
            print(f"[tunnel] Mobile waiting for bridge: {project_id}", flush=True)
            self._send_json(writer, {
                'type': 'status',
                'text': f'Waiting for PC bridge ({project_id})...',
                'project_id': project_id,
            })
            self._waiting_clients.setdefault(project_id, []).append((reader, writer))
            # Wait until bridge appears or timeout
            try:
                while project_id in self._waiting_clients:
                    await asyncio.sleep(1)
            except Exception:
                pass

    async def _relay(self, a_reader, a_writer, b_reader, b_writer, project_id: str):
        """Bidirectional relay between two connections."""
        async def forward(src_reader, dst_writer, label: str):
            try:
                while True:
                    line = await src_reader.readline()
                    if not line:
                        break
                    dst_writer.write(line)
                    await dst_writer.drain()
            except (ConnectionResetError, asyncio.IncompleteReadError):
                pass
            except Exception as e:
                print(f"[tunnel] Relay {label} error: {e}", flush=True)

        task_a = asyncio.create_task(forward(a_reader, b_writer, f'{project_id}:A->B'))
        task_b = asyncio.create_task(forward(b_reader, a_writer, f'{project_id}:B->A'))

        _, pending = await asyncio.wait(
            [task_a, task_b],
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()

        print(f"[tunnel] Relay ended for {project_id}", flush=True)

    @staticmethod
    def _send_json(writer: asyncio.StreamWriter, obj: dict):
        data = json.dumps(obj, ensure_ascii=False) + '\n'
        writer.write(data.encode('utf-8'))

    async def stop(self):
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
