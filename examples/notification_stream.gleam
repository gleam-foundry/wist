import wist

pub type Status {
  Status(service: String, active: Bool)
}

fn status_to_string(status: Status) -> String {
  let active_str = case status.active {
    True -> "ONLINE"
    False -> "OFFLINE"
  }
  status.service <> " is " <> active_str
}

pub fn notification_handler() {
  wist.handler(init_state: fn(_ctx) { Nil }, update: fn(state, event) {
    case event {
      wist.Opened -> {
        let notifications = [
          Status("Database", True),
          Status("Auth Server", True),
          Status("Cache Cluster", False),
        ]
        let effects =
          notifications
          |> list_map(fn(n) { wist.Send(status_to_string(n)) })

        #(state, effects)
      }
      wist.Message(_) -> #(state, [])
      wist.Closed(_) -> #(state, [])
      wist.Failed(_) -> #(state, [])
    }
  })
}

fn list_map(list: List(a), fun: fn(a) -> b) -> List(b) {
  case list {
    [] -> []
    [x, ..xs] -> [fun(x), ..list_map(xs, fun)]
  }
}
