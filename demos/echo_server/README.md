# Wist Echo Server

A minimal runnable WebSocket echo server using Wist and Mist.

## Run

```bash
./run.sh
```

Open `http://localhost:8080/` for connection instructions, then connect a
WebSocket client to `ws://localhost:8080/ws`. Every received text or binary
frame is sent back unchanged.
