//// Wist adapter for the Mist web server.
////
//// This module implements the transport adapter bridging Mist's WebSocket upgrade
//// logic and connection actor loops to Wist's transport-neutral `Handler` API.
////
//// Use `upgrade` inside your Mist HTTP request handler to switch protocols and
//// run a stateful Wist handler.

import gleam/bit_array
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/option.{type Option, None, Some}
import gleam/result
import glisten/transport as glisten_transport
import gramps/websocket as gramps_websocket
import mist.{
  type Connection, type ResponseData, type WebsocketConnection,
  type WebsocketMessage,
}
import wist

/// Upgrades an incoming HTTP request to a WebSocket connection managed by Wist.
///
/// If the request is a valid WebSocket handshake request, it returns a 101 Switching
/// Protocols response body configured to spawn Mist's WebSocket handler process.
/// If the request is malformed or invalid, a 400 Bad Request response is returned.
///
/// ### Parameters
/// - `request`: The incoming HTTP request carrying the Mist transport `Connection`.
/// - `handler`: The stateful `wist.Handler` defining initial state and event transitions.
/// - `codec`: A `wist.Codec` specifying how to encode and decode wire frames.
///
/// ### Guarantees
/// - **Serialization**: Connection events are processed strictly sequentially. `update` is never run concurrently.
/// - **FIFO Effects**: Effects returned by `update` are executed in the exact order they are listed.
/// - **Safety**: If frame decoding fails, the connection is closed immediately, and a `Failed` event is dispatched.
///
/// ### Limitations
/// - Outbound pings are supported via the `wist.Ping` effect, but client `Pong` frames are swallowed by Mist's internal wrapper and will not be dispatched as events.
///
/// ### Example
/// ```gleam
/// import wist
/// import wist/adapters/mist as wist_mist
///
/// fn my_http_handler(req) {
///   case req.path {
///     "/ws" -> wist_mist.upgrade(req, my_ws_handler, wist.raw_codec())
///     _ -> response.new(200)
///   }
/// }
/// ```
pub fn upgrade(
  request: Request(Connection),
  handler: wist.Handler(state, inbound, outbound),
  codec: wist.Codec(inbound, outbound),
) -> Response(ResponseData) {
  let context =
    wist.Context(
      path: request.path,
      headers: request.headers,
      query: request.query,
    )

  // INVARIANT: Handler state is immutable and mutated purely via reducer transitions.
  // INVARIANT: Reducer execution (update) is never invoked concurrently for a single connection.
  // INVARIANT: Codec execution (decode/encode) precedes reducer execution.
  // INVARIANT: The adapter never mutates the state outside of updating it with the value returned by the reducer.

  // Candidate future runtime responsibility: Building context, initializing state, and executing initial Opened event.
  let on_init = fn(connection: WebsocketConnection) {
    let init_state_fn = wist.get_init_state(handler)
    let update_fn = wist.get_update(handler)

    let user_state = init_state_fn(context)
    let #(user_state, opened_effects) = update_fn(user_state, wist.Opened)

    let #(should_close, _remaining_effects) =
      run_effects(opened_effects, connection, codec)

    case should_close {
      True -> {
        let _ = glisten_transport.close(connection.transport, connection.socket)
        Nil
      }
      False -> Nil
    }

    #(user_state, None)
  }

  let mist_handler = fn(
    state,
    message: WebsocketMessage(Nil),
    connection: WebsocketConnection,
  ) {
    case message {
      mist.Text(text) -> {
        let frame = wist.Text(text)
        process_inbound(state, frame, handler, codec, connection)
      }
      mist.Binary(bin) -> {
        let frame = wist.Binary(bin)
        process_inbound(state, frame, handler, codec, connection)
      }
      _ -> {
        mist.continue(state)
      }
    }
  }

  // Candidate future runtime responsibility: Translating connection closure into Closed event.
  let on_close = fn(state) {
    let update_fn = wist.get_update(handler)
    let _ = update_fn(state, wist.Closed(wist.Unknown))
    Nil
  }

  mist.websocket(request, mist_handler, on_init, on_close)
}

// Candidate future runtime responsibility: Decoding inbound frames and routing to update reducer.
fn process_inbound(
  state: state,
  frame: wist.Frame,
  handler: wist.Handler(state, inbound, outbound),
  codec: wist.Codec(inbound, outbound),
  connection: WebsocketConnection,
) -> mist.Next(state, Nil) {
  let update_fn = wist.get_update(handler)
  case codec.decode(frame) {
    Ok(decoded) -> {
      let #(next_state, effects) = update_fn(state, wist.Message(decoded))
      let #(should_close, _remaining) = run_effects(effects, connection, codec)
      case should_close {
        True -> mist.stop()
        False -> mist.continue(next_state)
      }
    }
    Error(_) -> {
      // On decode error, notify handler of failure and stop connection
      let _ =
        update_fn(state, wist.Failed(wist.SocketError("Frame decode failed")))
      mist.stop()
    }
  }
}

// INVARIANT: Effects are never reordered and always execute in returned FIFO order.
// Candidate future runtime responsibility: Sequential FIFO execution of effects.
fn run_effects(
  effects: List(wist.Effect(outbound)),
  connection: WebsocketConnection,
  codec: wist.Codec(inbound, outbound),
) -> #(Bool, List(wist.Effect(outbound))) {
  case effects {
    [] -> #(False, [])
    [wist.CloseConnection(maybe_close), ..] -> {
      let _ = send_frame(connection, wist.Close(maybe_close))
      #(True, [])
    }
    [wist.Send(msg), ..rest] -> {
      case codec.encode(msg) {
        Ok(frame) -> {
          let _ = send_frame(connection, frame)
          run_effects(rest, connection, codec)
        }
        Error(_) -> {
          #(True, [])
        }
      }
    }
    [wist.SendFrame(frame), ..rest] -> {
      let _ = send_frame(connection, frame)
      run_effects(rest, connection, codec)
    }
  }
}

fn send_frame(
  connection: WebsocketConnection,
  frame: wist.Frame,
) -> Result(Nil, Nil) {
  case frame {
    wist.Text(text) -> {
      mist.send_text_frame(connection, text)
      |> result.replace_error(Nil)
    }
    wist.Binary(bin) -> {
      mist.send_binary_frame(connection, bin)
      |> result.replace_error(Nil)
    }
    wist.Ping(data) -> {
      let bytes = gramps_websocket.encode_ping_frame(data, None)
      glisten_transport.send(connection.transport, connection.socket, bytes)
      |> result.replace_error(Nil)
    }
    wist.Pong(data) -> {
      let bytes = gramps_websocket.encode_pong_frame(data, None)
      glisten_transport.send(connection.transport, connection.socket, bytes)
      |> result.replace_error(Nil)
    }
    wist.Close(maybe_close) -> {
      let reason = to_gramps_close_reason(maybe_close)
      let bytes = gramps_websocket.encode_close_frame(reason, None)
      glisten_transport.send(connection.transport, connection.socket, bytes)
      |> result.replace_error(Nil)
    }
  }
}

fn to_gramps_close_reason(
  maybe_frame: Option(wist.CloseFrame),
) -> gramps_websocket.CloseReason {
  case maybe_frame {
    None -> gramps_websocket.Normal(<<>>)
    Some(wist.CloseFrame(code, reason)) -> {
      gramps_websocket.CustomCloseReason(code, bit_array.from_string(reason))
    }
  }
}
