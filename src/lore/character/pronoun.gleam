pub type Pronoun {
  /// Note: These are only masculine because he/him/his/himself is clearer 
  /// than she/her/her/herself
  Pronoun(he: String, him: String, his: String, himself: String)
}

pub type PronounChoice {
  Feminine
  Masculine
  Neutral
}

pub fn lookup(choice: PronounChoice) -> Pronoun {
  case choice {
    Feminine -> feminine
    Masculine -> masculine
    Neutral -> neutral
  }
}

const feminine = Pronoun(he: "she", him: "her", his: "her", himself: "herself")

const masculine = Pronoun(he: "he", him: "him", his: "his", himself: "himself")

const neutral = Pronoun(
  he: "they",
  him: "them",
  his: "their",
  himself: "themself",
)
