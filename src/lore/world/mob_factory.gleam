import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/otp/factory_supervisor
import lore/world
import lore/world/event

pub type Message =
  factory_supervisor.Message(
    event.SpawnMobile,
    process.Subject(event.CharacterMessage),
  )

pub fn start_child(name: process.Name(Message), mobile: world.MobileInternal) {
  name
  |> factory_supervisor.get_by_name
  |> factory_supervisor.start_child(event.SpawnMobile(endpoint: None, mobile:))
}

pub fn start_child_puppeted(
  name: process.Name(Message),
  mobile: world.MobileInternal,
  puppeted_by endpoint: process.Subject(event.Outgoing),
) {
  name
  |> factory_supervisor.get_by_name
  |> factory_supervisor.start_child(event.SpawnMobile(
    endpoint: Some(endpoint),
    mobile:,
  ))
}
