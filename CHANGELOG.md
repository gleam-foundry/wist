# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-16

Initial release of Wist, a small, typed, ergonomic WebSocket layer for Gleam applications built on top of Mist.

### Added
- Transport-neutral `wist.handler` API.
- HTTP WebSocket upgrade through the Mist adapter.
- Complete WebSocket protocol frames (`Text`, `Binary`, `Ping`, `Pong`, `Close`).
- Strong typing for events (`Opened`, `Closed`, `Failed`, `Message`) and errors (`DecodeError`, `EncodeError`, `SocketError`).
- FIFO effect execution guarantees.
- Runnable examples (echo, notification stream, heartbeat, collaborative counter).
