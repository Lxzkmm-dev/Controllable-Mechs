// =============================================================================
// CONTROLLABLE MECHS - PILOT SETTINGS
//
// What the CONFIG tab of the Robot Link changes, kept in the save. The pilot
// session (ControllableMechs.Control.CMCSession) and the Minotaur unit read these
// when they need them; nothing here runs on its own.
//
// The class keeps the name CMPilotSystem from the alpha's Pilot Mode (removed
// when the control framework replaced it) so the values already in saves carry
// over: the stored fields keep their names and meaning. Lengths are kept in
// centimetres; the terminal shows them in feet and inches.
// =============================================================================
module ControllableMechs

import TerminalKit.*

public class CMPilotSystem extends ScriptableSystem {
  private persistent let m_stayWhenHit: Bool;
  private persistent let m_themeIdx: Int32;      // 0 = our own palette (default), else 1 + index into TKTheme.Ids()
  // stored +1 so 0 means "default"
  private persistent let m_camUpCm: Int32;       // sensor view: above the mech's feet
  private persistent let m_camFwdCm: Int32;      // sensor view: ahead of its centre
  private persistent let m_sensPct: Int32;
  private persistent let m_chaseDistCm: Int32;   // chase view: behind the mech's centre
  private persistent let m_chaseUpCm: Int32;     // chase view: above its feet
  private persistent let m_chaseSideCm: Int32;   // chase view: off the centre line, toward the shoulder
  private persistent let m_shoulderLeft: Bool;   // chase view: over the left shoulder instead of the right
  private persistent let m_showDebug: Bool;      // diagnostics: the hit trace and the file log

  private let MOUNT_UP_CM: Int32 = 230;
  private let MOUNT_FWD_CM: Int32 = 260;
  private let CHASE_DIST_CM: Int32 = 600;
  private let CHASE_UP_CM: Int32 = 370;
  private let CHASE_SIDE_CM: Int32 = 180;

  public static func Get(game: GameInstance) -> ref<CMPilotSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMPilotSystem") as CMPilotSystem;
  }

  // ---- the operator ----
  public func StayWhenHit() -> Bool = this.m_stayWhenHit
  public func SetStayWhenHit(stay: Bool) -> Void { this.m_stayWhenHit = stay; }
  public func SensPct() -> Int32 = this.m_sensPct > 0 ? this.m_sensPct - 1 : 100
  public func SetSensPct(v: Int32) -> Void { this.m_sensPct = Clamp(v, 25, 300) + 1; }

  // ---- the sensor (sight view) mount ----
  public func CamUpCm() -> Int32 = this.m_camUpCm > 0 ? this.m_camUpCm - 1 : this.MOUNT_UP_CM
  public func CamFwdCm() -> Int32 = this.m_camFwdCm > 0 ? this.m_camFwdCm - 1 : this.MOUNT_FWD_CM
  public func SetCamUpCm(v: Int32) -> Void { this.m_camUpCm = Clamp(v, 100, 450) + 1; }
  public func SetCamFwdCm(v: Int32) -> Void { this.m_camFwdCm = Clamp(v, 0, 500) + 1; }

  // ---- the chase camera: distance behind, height above, and off to one shoulder ----
  public func ChaseDistCm() -> Int32 = this.m_chaseDistCm > 0 ? this.m_chaseDistCm - 1 : this.CHASE_DIST_CM
  public func ChaseUpCm() -> Int32 = this.m_chaseUpCm > 0 ? this.m_chaseUpCm - 1 : this.CHASE_UP_CM
  public func ChaseSideCm() -> Int32 = this.m_chaseSideCm > 0 ? this.m_chaseSideCm - 1 : this.CHASE_SIDE_CM
  public func ShoulderLeft() -> Bool = this.m_shoulderLeft
  public func SetChaseDistCm(v: Int32) -> Void { this.m_chaseDistCm = Clamp(v, 300, 1600) + 1; }
  public func SetChaseUpCm(v: Int32) -> Void { this.m_chaseUpCm = Clamp(v, 150, 900) + 1; }
  public func SetChaseSideCm(v: Int32) -> Void { this.m_chaseSideCm = Clamp(v, 0, 400) + 1; }
  public func SetShoulderLeft(left: Bool) -> Void { this.m_shoulderLeft = left; }
  // metres to the right of the centre line (negative = left), for the camera
  public func ChaseSide() -> Float = Cast<Float>(this.ChaseSideCm()) / 100.0 * (this.m_shoulderLeft ? -1.0 : 1.0)

  public func ResetCamera() -> Void {
    this.m_camUpCm = 0;
    this.m_camFwdCm = 0;
    this.m_sensPct = 0;
  }

  public func ResetChase() -> Void {
    this.m_chaseDistCm = 0;
    this.m_chaseUpCm = 0;
    this.m_chaseSideCm = 0;
    this.m_shoulderLeft = false;
  }

  // ---- the terminal's palette (a TerminalKit theme id) ----
  public func Theme() -> String {
    let ids = TKTheme.Ids();
    let i = this.m_themeIdx - 1;
    if i >= 0 && i < ArraySize(ids) {
      return ids[i];
    }
    return "cm_military";   // our own palette, registered with TerminalKit (CMMilitaryPalette)
  }

  public func SetTheme(id: String) -> Void {
    let ids = TKTheme.Ids();
    let i = 0;
    while i < ArraySize(ids) {
      if Equals(ids[i], id) {
        this.m_themeIdx = i + 1;
        return;
      }
      i += 1;
    }
  }

  // ---- diagnostics: off in normal play ----
  public func ShowDebug() -> Bool = this.m_showDebug
  public func SetShowDebug(on: Bool) -> Void { this.m_showDebug = on; }
}
