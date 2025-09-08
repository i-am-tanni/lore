import gleam/result
import lore/world/event.{type CharacterMessage, type Event}
import lore/world/room/response

pub fn broadcast(
  builder: response.Builder(CharacterMessage),
  event: Event(event.CharacterToRoomEvent, CharacterMessage),
  data: event.RoomCommunicationData,
) -> response.Builder(CharacterMessage) {
  let result = case data {
    event.SayData(text:, adverb:) -> Ok(event.Say(text:, adverb:))

    event.SayAtData(at:, text:, adverb:) -> {
      response.find_local_character(builder, at)
      |> result.map(fn(victim) { event.SayAt(text:, adverb:, at: victim) })
    }

    event.WhisperData(at:, text:, ..) -> {
      response.find_local_character(builder, at)
      |> result.map(fn(victim) { event.Whisper(text:, at: victim) })
    }

    event.EmoteData(text:) -> Ok(event.Emote(text:))

    event.SocialData(report:) -> Ok(event.Social(report:))

    event.SocialAtData(report:, at:) -> {
      response.find_local_character(builder, at)
      |> result.map(fn(victim) { event.SocialAt(report:, at: victim) })
    }
  }

  case result {
    Ok(data) -> {
      let event =
        event.new(
          from: response.self(builder),
          acting_character: event.acting_character,
          data: event.Communication(data),
        )

      response.broadcast(builder, event)
    }

    Error(reason) -> {
      response.reply_character(builder, event, event.ActFailed(reason))
    }
  }
}
