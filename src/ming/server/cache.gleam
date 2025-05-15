/// A cache represented as an erlang ets table.
/// Reading is concurrent and can be called outside of the owner process.
/// Writing requires message passing to the owner process.
/// 
import carpenter/table
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/otp/actor.{Failed, Ready}
import gleam/result

/// A cache's owner process receives insertions as messages.
/// This restriction maintains one writer and many readers.
/// Reading does not require message passing. 
/// 
pub type Message(k, v) {
  Insert(objects: List(#(k, v)))
  Delete(key: k)
}

/// Starts a cache process for a given table name and with a given loop
/// function. 
/// For the simplest functionality, pass cache.insert as the loop.
/// 
pub fn start(
  table_name: String,
  loop: fn(msg, table.Set(k, v)) -> actor.Next(msg, table.Set(k, v)),
) -> Result(Subject(msg), actor.StartError) {
  let spec =
    actor.Spec(init: fn() { init(table_name) }, init_timeout: 10, loop: loop)

  actor.start_spec(spec)
}

/// Inializes the table owned by the process and then primes the process
/// to begin receiving messages.
/// 
fn init(table_name: String) -> actor.InitResult(table.Set(k, v), msg) {
  let table_result =
    table.build(table_name)
    |> table.privacy(table.Protected)
    |> table.write_concurrency(table.AutoWriteConcurrency)
    |> table.read_concurrency(True)
    |> table.decentralized_counters(True)
    |> table.compression(False)
    |> table.set

  let selector =
    process.new_selector()
    |> process.selecting(process.new_subject(), function.identity)

  case table_result {
    Ok(table) -> Ready(table, selector)
    Error(_) -> Failed("Failed to start ets table: " <> table_name)
  }
}

pub fn recv(
  msg: Message(k, v),
  table: table.Set(k, v),
) -> actor.Next(Message(k, v), table.Set(k, v)) {
  case msg {
    Insert(objects:) -> table.insert(table, objects)
    Delete(key:) -> table.delete(table, key)
  }
  actor.continue(table)
}

/// ...but look ups for a given key do NOT require message passing.
/// Only the table name is required to perform a lookup from any process.
/// 
pub fn lookup(table_name: String, key key: k) -> Result(v, Nil) {
  // Converting to a string to convert to an atom may not be the most efficient.
  use table <- result.try(table.ref(table_name))
  case table.lookup(table, key) {
    [#(_, val)] -> Ok(val)
    _ -> Error(Nil)
  }
}
