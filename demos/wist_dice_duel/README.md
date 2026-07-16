# Wist Dice Duel (Demo Application)

This is a self-contained, full-duplex interactive verification application demonstrating Wist's connection-local state machine, custom codecs, and event-driven architecture.

## Overview

The application implements a real-time **Dice Duel** game. A user connects via a WebSocket client, rolls a dice against the server, and the server calculates the score transitions and updates the client.

```text
       "roll" (Inbound Text Frame)
Client ───────────────────────────► Server (Custom Codec decodes to Roll)
                                       │
                                       ▼
Client ◄─────────────────────────── Server (Update transitions GameState
        JSON State (Outbound Frame)         and sends rolls & scores)
```

---

## Exercised Wist APIs

This demo exercises the complete core surface of the Wist library:

### 1. Connection-Local State (`GameState`)
We track immutable connection state over the socket lifecycle without external databases:
```gleam
pub type GameState {
  GameState(player_score: Int, server_score: Int, total_rolls: Int)
}
```

### 2. Custom Codec (`wist.Codec`)
Rather than dealing with raw strings, we build a custom codec that decodes raw frames to typed actions and encodes outcomes back to JSON strings:
```gleam
pub type InboundMessage {
  Roll
  Reset
}

fn custom_codec() -> wist.Codec(InboundMessage, OutboundMessage) {
  wist.Codec(
    decode: fn(frame) {
      case frame {
        wist.Text("roll") -> Ok(Roll)
        wist.Text("reset") -> Ok(Reset)
        _ -> Error(wist.DecodeError("Malformed frame"))
      }
    },
    encode: fn(msg) {
      // Serializes welcome or update records to JSON text frames...
    }
  )
}
```

### 3. Unified Event Reducer (`wist.handler`)
All connections run a single stateful event loop reacting to lifecycle and message triggers:
```gleam
wist.handler(
  init_state: fn(ctx) {
    GameState(player_score: 0, server_score: 0, total_rolls: 0)
  },
  update: fn(state, event) {
    case event {
      wist.Opened -> #(state, [wist.Send(WelcomeMessage)])
      wist.Message(Roll) -> {
        // Roll dice, update score, send GameUpdate effect...
      }
      wist.Message(Reset) -> {
        // Reset scores...
      }
      wist.Closed(_) -> #(state, [])
      wist.Failed(_) -> #(state, [])
    }
  }
)
```

---

## Running the Demo

1. Make sure you have the parent dependencies compiled:
   ```bash
   gleam build
   ```

2. Run the server using the launcher script:
   ```bash
   ./run.sh
   ```

3. Open **`http://0.0.0.0:9987/`** in your browser and click **Connect**.
