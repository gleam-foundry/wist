//// Wist provides a transport-neutral, stateful WebSocket programming model for Gleam.
////
//// This module contains the core data structures, codecs, events, effects, and handler
//// constructors. It represents the "port" in Wist's ports-and-adapters architecture,
//// defining the API interface that developers use to write WebSocket connection logic.
////
//// Transports (like the Mist web server) consume the `Handler` defined here and run it
//// using a specific transport adapter (e.g. `wist/adapters/mist`).

import gleam/option.{type Option}

/// A transport-neutral representation of the HTTP WebSocket handshake request.
///
/// It contains connection-specific metadata that is available before the connection
/// is upgraded.
///
/// Use `Context` to extract authentication tokens from headers, route based on path,
/// or load initial configuration parameters.
pub type Context {
  Context(
    /// The HTTP path of the WebSocket request (e.g., `"/ws"`).
    path: String,
    /// A list of HTTP request headers sent by the client during upgrade.
    headers: List(#(String, String)),
    /// The raw query string, if present (e.g., `Some("token=xyz")`).
    query: Option(String),
  )
}

/// Represents the WebSocket close code and close reason payload sent on the wire.
///
/// Under the hood, close frames are encoded with a 16-bit status code and an
/// optional UTF-8 string payload.
pub type CloseFrame {
  CloseFrame(
    /// The 16-bit WebSocket status code (e.g. `1000` for normal closure).
    code: Int,
    /// The human-readable reason payload.
    reason: String,
  )
}

/// Represents the classification of why a WebSocket connection closed.
pub type CloseReason {
  /// The connection closed cleanly via a normal close handshake.
  Normal
  /// The connection closed due to a protocol violation, crash, or transport-level error.
  Abnormal(String)
  /// The connection closed without a clear code or details.
  Unknown
}

/// Represents an error encountered while decoding a raw WebSocket frame.
pub type DecodeError {
  DecodeError(String)
}

/// Represents an error encountered while encoding an application message.
pub type EncodeError {
  EncodeError(String)
}

/// Represents physical socket or TCP/SSL transport failures.
pub type SocketError {
  SocketError(String)
}

/// Represents all standard WebSocket frame types defined by RFC-6455.
pub type Frame {
  /// A UTF-8 text data frame.
  Text(String)
  /// A binary data frame.
  Binary(BitArray)
  /// A control Ping frame carrying a raw payload.
  Ping(BitArray)
  /// A control Pong frame carrying a raw payload.
  Pong(BitArray)
  /// A control Close frame indicating connection shutdown.
  Close(Option(CloseFrame))
}

/// Represents connection lifecycle and message events dispatched to `Handler.update`.
pub type Event(message) {
  /// Dispatched exactly once when the connection has been successfully established.
  /// Generate any initial welcome messages or startup pushes here.
  Opened
  /// Dispatched when a new application message is successfully received and decoded.
  Message(message)
  /// Dispatched when the connection closes. This is a terminal event; any returned
  /// effects will be ignored by the runtime.
  Closed(CloseReason)
  /// Dispatched when a socket or protocol failure occurs. This is a terminal event.
  Failed(SocketError)
}

/// Represents output actions or side-effects returned by the handler's reducer.
pub type Effect(message) {
  /// Encode and send a typed application message to the client.
  Send(message)
  /// Send a raw WebSocket data frame directly to the client.
  SendFrame(Frame)
  /// Initiate the WebSocket close handshake carrying optional close metadata.
  CloseConnection(Option(CloseFrame))
}

/// A Codec specifies how to serialize and deserialize messages.
///
/// It translates raw wire `Frame`s to typed `inbound` messages, and typed
/// `outbound` messages back to raw `Frame`s.
pub type Codec(inbound, outbound) {
  Codec(
    decode: fn(Frame) -> Result(inbound, DecodeError),
    encode: fn(outbound) -> Result(Frame, EncodeError),
  )
}

/// A no-op codec that maps raw `Frame`s directly to and from themselves.
///
/// Useful for handlers that process raw text or binary frames directly.
///
/// ### Example
/// ```gleam
/// import wist
///
/// let codec = wist.raw_codec()
/// ```
pub fn raw_codec() -> Codec(Frame, Frame) {
  Codec(decode: fn(frame) { Ok(frame) }, encode: fn(frame) { Ok(frame) })
}

/// A stateful WebSocket handler that manages its own state and responds to events.
///
/// Handlers are opaque to ensure binary compatibility and prevent external code
/// from directly reading or mutating the handler's transitions. Create them using `handler`.
pub opaque type Handler(state, inbound, outbound) {
  Handler(
    init_state: fn(Context) -> state,
    update: fn(state, Event(inbound)) -> #(state, List(Effect(outbound))),
  )
}

/// Constructor to create a stateful WebSocket handler.
///
/// The handler defines:
/// 1. `init_state`: How to construct the connection state from the `Context`.
/// 2. `update`: A pure reducer mapping state and events to state transitions and effects.
///
/// ### Example
/// ```gleam
/// import wist
///
/// let echo = wist.handler(
///   init_state: fn(_ctx) { Nil },
///   update: fn(state, event) {
///     case event {
///       wist.Message(frame) -> #(state, [wist.SendFrame(frame)])
///       _ -> #(state, [])
///     }
///   }
/// )
/// ```
pub fn handler(
  init_state init_state: fn(Context) -> state,
  update update: fn(state, Event(inbound)) -> #(state, List(Effect(outbound))),
) -> Handler(state, inbound, outbound) {
  Handler(init_state:, update:)
}

/// Internal accessor to retrieve the init_state function of a Handler.
/// Used by transport adapters to build the initial state.
@internal
pub fn get_init_state(
  handler: Handler(state, inbound, outbound),
) -> fn(Context) -> state {
  handler.init_state
}

/// Internal accessor to retrieve the update function of a Handler.
/// Used by transport adapters to run the connection event loop.
@internal
pub fn get_update(
  handler: Handler(state, inbound, outbound),
) -> fn(state, Event(inbound)) -> #(state, List(Effect(outbound))) {
  handler.update
}
