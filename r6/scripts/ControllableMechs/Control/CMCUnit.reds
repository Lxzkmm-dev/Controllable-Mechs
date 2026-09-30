// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: THE UNIT CONTRACT
// A unit is anything the session can control (the Minotaur now, the emplacement
// next). The session owns the when: the frame loop, the camera, input, V's locks
// and every exit. A unit owns the what: its body, its guns, how it moves.
// A unit never starts its own loops; everything it does runs from these calls.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public abstract class CMCUnit extends IScriptable {
  // "" = ready; otherwise the reason it can't start ("!" marks a warning)
  public func Begin(s: ref<CMCSession>) -> String = "!NO UNIT"
  // undo everything Begin made; `hard` = the game session is ending, no blends
  public func End(s: ref<CMCSession>, hard: Bool) -> Void {}
  // false ends the session, with LostReason()
  public func IsAlive() -> Bool = false
  public func LostReason() -> String = "!UNIT LOST"

  // where the camera ring sits: the body's ground position and facing, and the
  // sensor's height and reach for the sight view
  public func Ground() -> Vector4 = new Vector4(0.0, 0.0, 0.0, 1.0)
  public func Facing() -> Float = 0.0
  public func SensorUp() -> Float = 2.0
  public func SensorFwd() -> Float = 0.0
  // how far ahead of the camera the dynamic aim ray starts, so the unit can't aim at itself
  public func AimSkip() -> Float = 1.0

  // every frame, after the camera and the aim point are updated
  public func Tick(s: ref<CMCSession>, dt: Float, now: Float) -> Void {}
  // ten times a second: "" to carry on, else the exit reason
  public func SlowTick(s: ref<CMCSession>, now: Float) -> String = ""
  // ten times a second: the unit's part of the HUD
  public func Hud(s: ref<CMCSession>, state: ref<CMPilotHudState>) -> Void {}

  // the secondary weapon key (G) was pressed
  public func Secondary(s: ref<CMCSession>) -> Void {}

  public func Name() -> String = "UNIT"
}
