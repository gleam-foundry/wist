import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import mist
import wist
import wist/adapters/mist as wist_mist

pub fn main() {
  io.println("Starting echo server on http://localhost:8080...")

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}

fn handler(req: Request(mist.Connection)) -> Response(mist.ResponseData) {
  case req.path {
    "/ws" -> {
      let echo_handler =
        wist.handler(init_state: fn(_ctx) { Nil }, update: fn(state, event) {
          case event {
            wist.Opened -> {
              io.println("WebSocket connection opened")
              #(state, [])
            }
            wist.Message(frame) -> {
              #(state, [wist.SendFrame(frame)])
            }
            wist.Closed(reason) -> {
              io.println("WebSocket connection closed")
              case reason {
                wist.Normal -> io.println("Reason: Normal")
                wist.Abnormal(msg) ->
                  io.println("Reason: Abnormal (" <> msg <> ")")
                wist.Unknown -> io.println("Reason: Unknown")
              }
              #(state, [])
            }
            wist.Failed(err) -> {
              let wist.SocketError(msg) = err
              io.println("WebSocket connection failed: " <> msg)
              #(state, [])
            }
          }
        })
      wist_mist.upgrade(req, echo_handler, wist.raw_codec())
    }
    _ -> {
      response.new(200)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string(
          "Hello, this is wist! Connect a WebSocket client to /ws",
        )),
      )
    }
  }
}
