import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/option
import mist
import simplifile
import wist
import wist/adapters/mist as wist_mist

const html_file_path = "/home/gnrfan/code/floss/gleam/wist/demos/wist_dice_duel/index.html"

const log_file_path = "/home/gnrfan/code/floss/gleam/wist/demos/wist_dice_duel/debug.log"

@external(erlang, "rand", "uniform")
fn erlang_rand(max: Int) -> Int

pub type InboundMessage {
  Roll
  Reset
}

pub type OutboundMessage {
  WelcomeMessage
  GameUpdate(
    player_roll: Int,
    server_roll: Int,
    player_score: Int,
    server_score: Int,
    result_message: String,
  )
}

pub type GameState {
  GameState(player_score: Int, server_score: Int, total_rolls: Int)
}

fn log_debug(msg: String) {
  io.println(msg)
  let _ = simplifile.append(log_file_path, msg <> "\n")
  Nil
}

fn custom_codec() -> wist.Codec(InboundMessage, OutboundMessage) {
  wist.Codec(
    decode: fn(frame) {
      case frame {
        wist.Text("roll") -> Ok(Roll)
        wist.Text("reset") -> Ok(Reset)
        wist.Text(other) ->
          Error(wist.DecodeError("Unknown payload: " <> other))
        _ -> Error(wist.DecodeError("Expected text frame"))
      }
    },
    encode: fn(msg) {
      case msg {
        WelcomeMessage -> {
          Ok(wist.Text("{\"type\":\"welcome\"}"))
        }
        GameUpdate(p_roll, s_roll, p_score, s_score, result) -> {
          let json =
            "{\"type\":\"update\",\"player_roll\":"
            <> int.to_string(p_roll)
            <> ",\"server_roll\":"
            <> int.to_string(s_roll)
            <> ",\"player_score\":"
            <> int.to_string(p_score)
            <> ",\"server_score\":"
            <> int.to_string(s_score)
            <> ",\"result\":\""
            <> result
            <> "\"}"
          Ok(wist.Text(json))
        }
      }
    },
  )
}

pub fn main() {
  let _ = simplifile.write(log_file_path, "=== Game Session Started ===\n")
  log_debug("Starting Wist Dice Duel server on http://0.0.0.0:9987...")

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(9987)
    |> mist.bind("0.0.0.0")
    |> mist.start

  process.sleep_forever()
}

fn handler(req: Request(mist.Connection)) -> Response(mist.ResponseData) {
  case req.path {
    "/ws" -> {
      let ws_handler =
        wist.handler(
          init_state: fn(ctx) {
            log_debug(
              "WS Game Upgrade: path="
              <> ctx.path
              <> " query="
              <> option.unwrap(ctx.query, "None"),
            )
            GameState(player_score: 0, server_score: 0, total_rolls: 0)
          },
          update: fn(state, event) {
            case event {
              wist.Opened -> {
                log_debug("WS Game Event: Opened")
                #(state, [wist.Send(WelcomeMessage)])
              }
              wist.Message(Roll) -> {
                let p_roll = erlang_rand(6)
                let s_roll = erlang_rand(6)

                let #(p_inc, s_inc, result) = case p_roll, s_roll {
                  p, s if p > s -> #(1, 0, "You win!")
                  p, s if p < s -> #(0, 1, "Server wins!")
                  _, _ -> #(0, 0, "It's a tie!")
                }

                let new_state =
                  GameState(
                    player_score: state.player_score + p_inc,
                    server_score: state.server_score + s_inc,
                    total_rolls: state.total_rolls + 1,
                  )

                log_debug(
                  "Roll #"
                  <> int.to_string(new_state.total_rolls)
                  <> ": Player="
                  <> int.to_string(p_roll)
                  <> ", Server="
                  <> int.to_string(s_roll)
                  <> " ("
                  <> result
                  <> ")",
                )

                #(new_state, [
                  wist.Send(GameUpdate(
                    player_roll: p_roll,
                    server_roll: s_roll,
                    player_score: new_state.player_score,
                    server_score: new_state.server_score,
                    result_message: result,
                  )),
                ])
              }
              wist.Message(Reset) -> {
                log_debug("WS Game Event: Reset Scoreboard")
                #(GameState(player_score: 0, server_score: 0, total_rolls: 0), [
                  wist.Send(WelcomeMessage),
                ])
              }
              wist.Closed(reason) -> {
                log_debug("WS Game Event: Closed")
                case reason {
                  wist.Normal -> log_debug("Reason: Normal Close")
                  wist.Abnormal(msg) ->
                    log_debug("Reason: Abnormal (" <> msg <> ")")
                  wist.Unknown -> log_debug("Reason: Unknown Close")
                }
                #(state, [])
              }
              wist.Failed(err) -> {
                let wist.SocketError(msg) = err
                log_debug("WS Game Event: Failed - " <> msg)
                #(state, [])
              }
            }
          },
        )
      wist_mist.upgrade(req, ws_handler, custom_codec())
    }

    "/" -> {
      case simplifile.read(html_file_path) {
        Ok(html_content) -> {
          response.new(200)
          |> response.set_header("content-type", "text/html")
          |> response.set_body(mist.Bytes(bytes_tree.from_string(html_content)))
        }
        Error(err) -> {
          log_debug(
            "Error reading index.html: " <> simplifile.describe_error(err),
          )
          response.new(500)
          |> response.set_body(
            mist.Bytes(bytes_tree.from_string(
              "Error: index.html file not found",
            )),
          )
        }
      }
    }

    _ -> {
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
    }
  }
}
