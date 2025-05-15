import ming/world.{type CharacterMessage, type Event, type RoomEvent}
import ming/world/room/context.{type Context}

fn look(
  context: Context(CharacterMessage),
  event: Event(RoomEvent, CharacterMessage),
) -> Context(CharacterMessage) {
  todo
}
