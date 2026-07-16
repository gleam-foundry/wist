<p align="center">
  <img src="https://raw.githubusercontent.com/gleam-foundry/wist/main/assets/images/wist-logo.png" alt="Wist Logo" width="320" />
</p>

<p align="center">
  <a href="https://hex.pm/packages/wist">
    <img src="https://img.shields.io/hexpm/v/wist" alt="Package Version" />
  </a>
  <a href="https://hexdocs.pm/wist/">
    <img src="https://img.shields.io/badge/hex-docs-ffaff3" alt="Hex Docs" />
  </a>
</p>

<p align="center">
  Wist is a small, typed, transport-oriented realtime programming model for Gleam.
</p> 

It isolates connection lifecycle and state transitions behind a transport-neutral, testable state machine. In its initial release, Wist uses WebSockets through the Mist web server as its transport layer, treating the underlying server as an interchangeable infrastructure adapter.

---

## Mission

Wist exists to provide a clean, typed interface for persistent, bidirectional connections in Gleam. 

Realtime applications often suffer from tight coupling between business logic and the network protocols carrying the data. Wist decouples these concerns by introducing a unified, transport-neutral programming model. Whether the underlying connection runs over WebSockets, WebTransport, or Server-Sent Events, your application code remains unchanged.

---

## Vision

The vision for Wist is to serve as the minimal, elegant foundation upon which the Gleam ecosystem can build richer realtime abstractions.

Wist does not attempt to solve higher-level application architecture. Instead, it provides the low-level transport-oriented guarantees necessary to confidently build libraries such as:

* **LiveView & Livewire clones**: Server-driven UI rendering and DOM diffing.
* **Collaborative editors**: Operational transformation and conflict-free replicated data types (CRDTs).
* **Multiplayer game servers**: High-frequency physics synchronization and state replication.
* **Realtime dashboards & Notifications**: Live telemetry streaming and system alerts.
* **Custom Application Protocols**: RPC over persistent connections and IoT communication.

---

## Philosophy

Wist is guided by the following principles:

* **Small Public API**: Expose the minimal set of primitives required to model connection logic.
* **Strong Typing**: Use compiler-enforced types for states, events, close reasons, codecs, and effects.
* **Explicit Lifecycle**: Define clear transitions from connection initialization to termination.
* **Transport Neutrality**: Keep the core state machine decoupled from web server implementations.
* **Determinism**: Ensure connection logic behaves identically in production runtimes and test runners.
* **Ports-and-Adapters**: Treat the underlying network stack as an interchangeable adapter.

### Out of Scope by Design
Wist intentionally does **not** include:
* Rooms, channels, or connection registries.
* Presence tracking.
* PubSub messaging.
* Authentication and session management.
* Browser synchronization or DOM-patching runtimes.

These concerns belong strictly in higher-level libraries built on top of Wist.

---

## Mental Model

At its core, Wist models every connection as a **connection-local state machine**.

```text
Connection (established)
  │
  ▼
State (constructed once via Context)
  │
  ▼
Event (inbound message or lifecycle transition)
  │
  ▼
Update (pure reducer execution)
  │
  ▼
State + Effects (new state and sequential list of output actions)
```

Each connection manages its own private, immutable state. When an **Event** occurs (such as the connection opening, a new message arriving, or the connection closing), the state machine executes an **Update** function. The update function transitions the state and returns a list of declarative **Effects** (such as sending messages or closing the connection) to be executed sequentially by the runtime.

---

## API Walkthrough

Wist organizes its interface into eight main concepts, explained below in top-to-bottom order:

### 1. Context
`Context` carries the transport metadata captured during the initial handshake (e.g. headers, path, query parameters). It does not contain application-level domains.

### 2. State
`State` is any user-defined immutable Gleam type representing the private data held by a single connection (such as database IDs, connection metrics, or sequence counters).

### 3. Events
`Event(message)` represents inbound lifecycle or data triggers dispatched to the reducer:
* `Opened`: The connection is established.
* `Message(message)`: A decoded application message has arrived.
* `Closed(CloseReason)`: The connection terminated cleanly or abnormally.
* `Failed(SocketError)`: A transport error occurred.

### 4. Effects
`Effect(message)` represents outbound actions returned by the reducer:
* `Send(message)`: Serializes and sends an application message.
* `SendFrame(Frame)`: Sends a raw network data frame.
* `CloseConnection(Option(CloseFrame))`: Initiates the closing handshake.

### 5. Frames
`Frame` represents standard wire-level protocol frames (`Text`, `Binary`, `Ping`, `Pong`, `Close`).

### 6. Codecs
`Codec(inbound, outbound)` specifies how to decode a raw wire `Frame` into a typed application `inbound` message, and how to encode an `outbound` message back to a `Frame`.

### 7. Handler
`Handler` is an opaque type packaging the connection's `init_state` constructor and `update` reducer. It is instantiated using `wist.handler`.

### 8. Mist Adapter
The transport adapter (such as `wist/adapters/mist`) runs the opaque `Handler` inside the target web server's connection actor loop, executing effects and translating incoming data.

---

## Minimal Example

Below is a complete, runnable WebSocket echo server.

```gleam
import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist
import wist
import wist/adapters/mist as wist_mist

// 1. Define the connection-local handler
pub fn echo_handler() {
  wist.handler(
    init_state: fn(_ctx) { Nil },
    update: fn(state, event) {
      case event {
        wist.Opened -> #(state, [])
        wist.Message(frame) -> #(state, [wist.SendFrame(frame)])
        wist.Closed(_) -> #(state, [])
        wist.Failed(_) -> #(state, [])
      }
    },
  )
}

// 2. Set up the HTTP request router
pub fn handle_request(req: Request(mist.Connection)) -> Response(mist.ResponseData) {
  case req.path {
    "/ws" -> wist_mist.upgrade(req, echo_handler(), wist.raw_codec())
    _ -> response.new(200) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}
```

### Walkthrough
* **`wist.handler`**: Creates an opaque state machine. The connection state here is `Nil` (representing stateless connections).
* **`update`**: Evaluates incoming events. When a `Message` arrives, it returns the current `state` and a list containing a `SendFrame` effect.
* **`wist_mist.upgrade`**: Upgrades the HTTP request to a WebSocket connection, using the `raw_codec` (no-op serializer) and running the handler.

---

## Why Not Use Mist Directly?

Mist is an excellent, high-performance web server that provides low-level WebSocket support. Wist builds on top of Mist by introducing several core design advantages:

* **100% Testable in Isolation (No Sockets Needed)**: Testing raw Mist handlers requires starting a real HTTP/TCP server, binding to ports, and asserting over raw network sockets. In Wist, connection logic is a pure reducer function: `fn(state, Event) -> #(state, List(Effect))`. You can write standard unit tests that assert state progression and output effects in less than a millisecond without ever spinning up a server.
* **Complete Transport Decoupling**: If you write code directly in Mist, your project is locked into Mist. With Wist, your handlers are transport-neutral. If a new high-performance web server (like Bandit) or a new protocol (like WebTransport) is introduced in the Gleam ecosystem, your core application code remains unchanged.
* **Unified, Type-Safe Lifecycle Events**: Instead of managing state initialization, message frames, socket cleanups, and errors across separate callbacks and low-level Erlang actor supervisors, Wist routes the entire lifecycle sequentially to a single reducer as typed `Event`s (`Opened`, `Closed`, `Failed`, `Message`).
* **Explicit Effect Ordering (FIFO)**: Sending frames in Mist is done imperatively via side-effects (`mist.send_text_frame`). If multiple callbacks trigger writes, ordering can become hard to guarantee. In Wist, side-effects are returned declaratively as a `List(Effect)` from the update function, guaranteeing they are executed sequentially in the exact order they are listed.
* **Separation of Protocol from Logic (Codecs)**: The `Codec(inbound, outbound)` serves as a strict protocol boundary, isolating network frame parsing and serialization entirely from your core business state machine logic.

---

## Semantic Guarantees

Wist provides strong guarantees to simplify application design:

1. **Isolation**: Exactly one handler instance is created per connection. Connections never share state.
2. **Serialization**: Events for a single connection are processed strictly sequentially. `update` is never executed concurrently for a single connection.
3. **Ordered Effects**: Effects returned by `update` are guaranteed to execute in the exact order they are listed (FIFO).
4. **State Immutability**: The runtime never mutates the state outside of updating it with the value returned by the reducer.

---

## Non-Goals

Wist does **not** attempt to:
* Manage a registry of active connections or coordinate cluster communication.
* Provide built-in JSON or database models.
* Implement custom client-side browser frameworks.
* Handle application authorization or routing logic.

Maintaining a narrow, focused scope ensures Wist remains simple, fast, and easy to maintain.

---

## Roadmap

Future development areas include:
* **JSON Codecs**: High-level serializers mapping typed structures to frames.
* **Testing Harness**: Utility modules to mock and assertions-test state machine effects.
* **Runtime Extraction**: Extracting the state machine runner from the Mist adapter into a standalone runtime package.
* **Bandit Adapter**: Support for alternative web servers.

## v0.1.0 API reference

### Core Types and Variants

| Type | Purpose | Details / Key Fields |
|------|---------|----------------------|
| `Context` | Handshake HTTP metadata | `path`, `headers`, `query` |
| `CloseFrame` | Raw WebSocket close payload | `code`, `reason` |
| `CloseReason` | Connection closure reason | `Normal`, `Abnormal(String)`, `Unknown` |
| `Frame` | WebSocket wire frame representation | `Text`, `Binary`, `Ping`, `Pong`, `Close` |
| `Event(msg)` | Connection lifecycle event stream | `Opened`, `Message(msg)`, `Closed(CloseReason)`, `Failed(SocketError)` |
| `Effect(msg)` | Outbound reducer execution action | `Send`, `SendFrame`, `CloseConnection` |
| `Codec(in, out)` | Frame serializer and deserializer | `decode`, `encode` function fields |
| `Handler(state, in, out)` | Opaque state-machine container | Created via `wist.handler` constructor |

### Constructors and Adapters

| Function | Module | Purpose |
|----------|--------|---------|
| `handler(init_state, update)` | `wist` | Primary builder constructor to create a `Handler` |
| `raw_codec()` | `wist` | Convenience no-op codec mapping raw frames directly |
| `upgrade(req, handler, codec)` | `wist/adapters/mist` | Upgrades a Mist HTTP connection to Wist WebSocket |

## License

MIT License - Copyright (c) 2026 Antonio Ognio

Made with ❤️  from 🇵🇪. El Perú es clave 🔑.
