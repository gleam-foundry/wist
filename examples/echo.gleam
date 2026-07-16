import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import mist
import wist
import wist/adapters/mist as wist_mist

pub fn echo_handler() {
  wist.handler(init_state: fn(_ctx) { Nil }, update: fn(state, event) {
    case event {
      wist.Opened -> #(state, [wist.SendFrame(wist.Text("Welcome!"))])
      wist.Message(frame) -> #(state, [wist.SendFrame(frame)])
      wist.Closed(_) -> #(state, [])
      wist.Failed(_) -> #(state, [])
    }
  })
}

pub fn handle_request(
  req: Request(mist.Connection),
) -> Response(mist.ResponseData) {
  case req.path {
    "/ws" -> wist_mist.upgrade(req, echo_handler(), wist.raw_codec())
    _ -> response.new(404) |> response.set_body(mist.Bytes(<<>>))
  }
}
