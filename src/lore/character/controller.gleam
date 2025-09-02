//// A controller is a simple state machine that takes a request and outputs
//// a response.
//// 

import gleam/erlang/process
import lore/world.{type Id}
import lore/world/event.{
  type CharacterEvent, type Event, type RoomMessage, type ZoneMessage,
}
import lore/world/room/presence

/// A request received by a controller for processing.
/// 
pub type Request {
  UserSentCommand(text: String)
  Chat(event.ChatData)
  RoomToCharacter(event: Event(CharacterEvent, RoomMessage))
  ZoneToCharacter(event: Event(CharacterEvent, ZoneMessage))
}

/// Tagged flash data. This determines the state.
/// 
pub type Controller {
  Login(flash: LoginFlash)
  Character(flash: CharacterFlash)
  Spawn(flash: SpawnFlash)
}

pub type LoginFlash {
  /// Score determines if a connection is terminated due to bad behavior
  LoginFlash(stage: LoginStage, score: Int, name: String, portal: process.Pid)
}

pub type CharacterFlash {
  CharacterFlash(name: String)
}

pub type SpawnFlash {
  SpawnFlash(at: Id(world.Room), presence: process.Name(presence.Message))
}

/// Stages of Login
pub type LoginStage {
  LoginName
}

pub fn is_same_kind(a: Controller, b: Controller) -> Bool {
  kind(a) == kind(b)
}

fn kind(controller: Controller) -> Int {
  case controller {
    Login(..) -> 1
    Character(..) -> 2
    Spawn(..) -> 3
  }
}
