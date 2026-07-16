import wist

pub type State {
  State(count: Int)
}

pub type Action {
  Increment
  Decrement
}

pub fn counter_handler() {
  wist.handler(init_state: fn(_ctx) { State(0) }, update: fn(state, event) {
    case event {
      wist.Opened -> #(state, [])
      wist.Message(Increment) -> {
        let next_state = State(state.count + 1)
        #(next_state, [wist.Send(next_state.count)])
      }
      wist.Message(Decrement) -> {
        let next_state = State(state.count - 1)
        #(next_state, [wist.Send(next_state.count)])
      }
      wist.Closed(_) -> #(state, [])
      wist.Failed(_) -> #(state, [])
    }
  })
}
