// =============================================================================
// CONTROLLABLE MECHS - VERSION
// Shown in the terminal's status line; keep in step with CHANGELOG.md.
// =============================================================================
module ControllableMechs

public abstract class CMVersion {
  public static func Text() -> String = "0.7.0 ALPHA"
  // which build the game is running, logged when a pilot session begins (a game started
  // before a push still runs the old scripts); bumped with each test build
  public static func Build() -> String = "0.7.0-a18"
}
