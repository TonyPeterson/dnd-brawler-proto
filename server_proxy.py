#!/usr/bin/env python3
import asyncio
import os

GODOT_HOST = "127.0.0.1"
GODOT_PORT = 7000
HEALTH_CHECK_RESPONSE = (
    b"HTTP/1.1 200 OK\r\n"
    b"Content-Type: text/plain\r\n"
    b"Content-Length: 2\r\n"
    b"Connection: close\r\n"
    b"\r\n"
    b"OK"
)


async def pipe_stream(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


def ensure_min_headers(header_block: bytes) -> bytes:
    lines = header_block.split(b"\r\n")
    # lines[0] is request line, lines[1:] are headers
    header_lines = [line for line in lines[1:] if line]
    while len(header_lines) < 4:
        header_lines.append(b"X-Proxy: Render")
    return lines[0] + b"\r\n" + b"\r\n".join(header_lines)


async def handle_client(
    client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter
) -> None:
    backend_writer = None
    try:
        buffer = b""
        while b"\r\n\r\n" not in buffer:
            chunk = await asyncio.wait_for(client_reader.read(4096), timeout=10.0)
            if not chunk:
                client_writer.close()
                await client_writer.wait_closed()
                return
            buffer += chunk
            if len(buffer) > 65536:
                client_writer.close()
                await client_writer.wait_closed()
                return

        header_end = buffer.index(b"\r\n\r\n")
        header_block = buffer[:header_end]
        remaining_bytes = buffer[header_end + 4 :]

        if b"upgrade: websocket" not in header_block.lower():
            client_writer.write(HEALTH_CHECK_RESPONSE)
            await client_writer.drain()
            client_writer.close()
            await client_writer.wait_closed()
            return

        patched_headers = ensure_min_headers(header_block)
        forward_payload = patched_headers + b"\r\n\r\n" + remaining_bytes

        backend_reader, backend_writer = await asyncio.open_connection(
            GODOT_HOST, GODOT_PORT
        )
        backend_writer.write(forward_payload)
        await backend_writer.drain()

        await asyncio.gather(
            pipe_stream(client_reader, backend_writer),
            pipe_stream(backend_reader, client_writer),
        )
    except Exception:
        try:
            client_writer.close()
            await client_writer.wait_closed()
        except Exception:
            pass
        if backend_writer is not None:
            try:
                backend_writer.close()
                await backend_writer.wait_closed()
            except Exception:
                pass


async def main() -> None:
    port = int(os.environ.get("PORT", 10000))
    server = await asyncio.start_server(handle_client, "0.0.0.0", port)
    print(f"Render proxy listening on 0.0.0.0:{port} -> {GODOT_HOST}:{GODOT_PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
