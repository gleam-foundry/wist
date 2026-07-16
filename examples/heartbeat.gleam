import wist

pub type State {
  State(heartbeat_count: Int)
}

pub fn heartbeat_handler() {
  wist.handler(init_state: fn(_ctx) { State(0) }, update: fn(state, event) {
    case event {
      wist.Opened -> {
        // Send initial Ping on open
        #(state, [wist.SendFrame(wist.Ping(<<>>))])
      }
      wist.Message(wist.Pong(_)) -> {
        // Received Pong from client, increment heartbeat count and send next Ping
        let next_state = State(state.heartbeat_count + 1)
        #(next_state, [wist.SendFrame(wist.Ping(<<>>))])
      }
      wist.Message(_) -> #(state, [])
      wist.Closed(_) -> #(state, [])
      wist.Failed(_) -> #(state, [])
    }
  })
}
