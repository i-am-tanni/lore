/// Temporary data tied to a controller.
/// 
pub type Flash {
  /// Score determines if a connection is terminated due to bad behavior
  LoginFlash(stage: LoginStage, score: Int, name: String)
  CharacterFlash(name: String)
}

/// Stages of Login
pub type LoginStage {
  LoginName
}
