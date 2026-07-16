import gleam/int
import gleam/option.{None}
import gleeunit
import wist

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn echo_handler_test() {
  let ctx = wist.Context(path: "/ws", headers: [], query: None)
  let handler =
    wist.handler(init_state: fn(c) { c.path }, update: fn(state, event) {
      case event {
        wist.Message(frame) -> #(state, [wist.SendFrame(frame)])
        _ -> #(state, [])
      }
    })

  let init_state = wist.get_init_state(handler)
  let update = wist.get_update(handler)

  // Initialize
  let state = init_state(ctx)
  let assert "/ws" = state

  // Update
  let incoming_frame = wist.Text("hello")
  let #(state, update_effects) = update(state, wist.Message(incoming_frame))
  let assert "/ws" = state
  let assert [wist.SendFrame(wist.Text("hello"))] = update_effects
}

pub fn int_codec_test() {
  let codec =
    wist.Codec(
      decode: fn(frame) {
        case frame {
          wist.Text(s) -> {
            case int.parse(s) {
              Ok(i) -> Ok(i)
              Error(_) -> Error(wist.DecodeError("Failed to parse int"))
            }
          }
          _ -> Error(wist.DecodeError("Expected text frame"))
        }
      },
      encode: fn(i) { Ok(wist.Text(int.to_string(i))) },
    )

  let frame = wist.Text("123")
  let assert Ok(123) = codec.decode(frame)
  let assert Ok(wist.Text("123")) = codec.encode(123)
}

pub fn effect_ordering_test() {
  let ctx = wist.Context(path: "/ws", headers: [], query: None)
  let handler =
    wist.handler(init_state: fn(c) { c.path }, update: fn(state, event) {
      case event {
        wist.Message(frame) -> #(state, [
          wist.SendFrame(frame),
          wist.SendFrame(wist.Text("goodbye")),
          wist.CloseConnection(None),
        ])
        _ -> #(state, [])
      }
    })

  let init_state = wist.get_init_state(handler)
  let update = wist.get_update(handler)

  let state = init_state(ctx)
  let #(_, effects) = update(state, wist.Message(wist.Text("hello")))

  let assert [
    wist.SendFrame(wist.Text("hello")),
    wist.SendFrame(wist.Text("goodbye")),
    wist.CloseConnection(None),
  ] = effects
}
