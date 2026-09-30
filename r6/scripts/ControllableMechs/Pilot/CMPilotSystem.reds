// =============================================================================
// CONTROLLABLE MECHS - PILOT SETTINGS
//
// What the CONFIG tab of the Robot Link changes. The pilot session
// (ControllableMechs.Control.CMCSession) and the Minotaur unit read these when
// they need them; nothing here runs on its own.
//
// The settings live in a file, r6/storages/ControllableMechs/settings.txt (one
// "key=value" line each, through RedFunctions' ModStorage), not in the save: a
// setting kept in the save goes back to its old value whenever an older save is
// loaded, which is how the pilot mode once flipped on its own. The file is read
// once per game session and written when a setting changes.
//
// Lengths are kept in centimetres; the terminal shows them in feet and inches.
// =============================================================================
module ControllableMechs

import TerminalKit.*
import RedFunctions.Storage.*

public class CMPilotSystem extends ScriptableSystem {
  // ---- the settings file, in memory ----
  private let m_keys: array<String>;
  private let m_vals: array<String>;
  private let m_loaded: Bool;
  // read every frame or on every log line, so kept as plain fields
  private let m_debugOn: Bool;
  private let m_chaseSide: Float;

  private let MOUNT_UP_CM: Int32 = 230;
  private let MOUNT_FWD_CM: Int32 = 260;
  private let CHASE_DIST_CM: Int32 = 600;
  private let CHASE_UP_CM: Int32 = 370;
  private let CHASE_SIDE_CM: Int32 = 180;

  public static func Get(game: GameInstance) -> ref<CMPilotSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMPilotSystem") as CMPilotSystem;
  }

  // ---------------------------------------------------------------------------
  // The file
  // ---------------------------------------------------------------------------
  private func Load() -> Void {
    if this.m_loaded {
      return;
    }
    this.m_loaded = true;
    let store = ModStorage.Open("ControllableMechs");
    if IsDefined(store) && store.Has("settings.txt") {
      for line in store.ReadLines("settings.txt") {
        let key = StrBeforeFirst(line, "=");
        if StrLen(key) > 0 {
          ArrayPush(this.m_keys, key);
          ArrayPush(this.m_vals, StrAfterFirst(line, "="));
        }
      }
    }
    this.Cache();
  }

  private func Find(key: String) -> Int32 {
    let i = 0;
    while i < ArraySize(this.m_keys) {
      if Equals(this.m_keys[i], key) {
        return i;
      }
      i += 1;
    }
    return -1;
  }

  // a setting as text / as a whole number, or `def` when it has never been set
  public func Text(key: String, def: String) -> String {
    this.Load();
    let i = this.Find(key);
    return i >= 0 ? this.m_vals[i] : def;
  }

  public func Int(key: String, def: Int32) -> Int32 {
    this.Load();
    let i = this.Find(key);
    return i >= 0 ? StringToInt(this.m_vals[i], def) : def;
  }

  public func Flag(key: String, def: Bool) -> Bool = this.Int(key, def ? 1 : 0) == 1

  // set a setting and write the file
  public func Put(key: String, value: String) -> Void {
    this.Load();
    let i = this.Find(key);
    if i >= 0 {
      if Equals(this.m_vals[i], value) {
        return;
      }
      this.m_vals[i] = value;
    } else {
      ArrayPush(this.m_keys, key);
      ArrayPush(this.m_vals, value);
    }
    this.Cache();
    this.Save();
  }

  public func PutInt(key: String, value: Int32) -> Void {
    this.Put(key, IntToString(value));
  }

  public func PutFlag(key: String, on: Bool) -> Void {
    this.Put(key, on ? "1" : "0");
  }

  private func Save() -> Void {
    let store = ModStorage.Open("ControllableMechs");
    if !IsDefined(store) {
      return;
    }
    let lines: array<String>;
    let i = 0;
    while i < ArraySize(this.m_keys) {
      ArrayPush(lines, this.m_keys[i] + "=" + this.m_vals[i]);
      i += 1;
    }
    store.WriteLines("settings.txt", lines);
  }

  private func Cache() -> Void {
    let debug = this.Find("showDebug");
    this.m_debugOn = debug >= 0 && Equals(this.m_vals[debug], "1");
    let side = this.Find("chaseSideCm");
    let cm = side >= 0 ? StringToInt(this.m_vals[side], this.CHASE_SIDE_CM) : this.CHASE_SIDE_CM;
    let left = this.Find("shoulderLeft");
    this.m_chaseSide = Cast<Float>(cm) / 100.0 * (left >= 0 && Equals(this.m_vals[left], "1") ? -1.0 : 1.0);
  }

  // ---------------------------------------------------------------------------
  // The settings
  // ---------------------------------------------------------------------------
  // ---- the operator ----
  public func StayWhenHit() -> Bool = this.Flag("stayWhenHit", false)
  public func SetStayWhenHit(stay: Bool) -> Void { this.PutFlag("stayWhenHit", stay); }
  // V out of enemy senses while linked (off by default: it makes piloting nearly safe)
  public func HideOperator() -> Bool = this.Flag("hideOperator", false)
  public func SetHideOperator(on: Bool) -> Void { this.PutFlag("hideOperator", on); }
  public func SensPct() -> Int32 = this.Int("sensPct", 100)
  public func SetSensPct(v: Int32) -> Void { this.PutInt("sensPct", Clamp(v, 25, 300)); }

  // hold a gun's fire until its barrel is on the reticle (off: fire while the guns traverse)
  public func FireGate() -> Bool = this.Flag("fireGate", false)
  public func SetFireGate(on: Bool) -> Void { this.PutFlag("fireGate", on); }

  // parts of the mech damaged and shot off (docs/DAMAGE_DESIGN.md): on unless turned off
  public func PartDamage() -> Bool = this.Flag("partDamage", true)
  public func SetPartDamage(on: Bool) -> Void { this.PutFlag("partDamage", on); }

  public func RecoilPct() -> Int32 = this.Int("recoilPct", 100)
  public func SetRecoilPct(v: Int32) -> Void { this.PutInt("recoilPct", Clamp(v, 0, 200)); }

  // how fast the view traverses and the chassis turns, % of the heavy baseline
  // the drone test build: how a flown drone is moved each frame (0 facility teleport,
  // 1 AI teleport, 2 AI move carrot)
  // drones: acro mode (rate control, no self-levelling) instead of angle mode
  public func DroneAcro() -> Bool = this.Flag("droneAcro", false)
  public func SetDroneAcro(on: Bool) -> Void { this.PutFlag("droneAcro", on); }

  public func DroneMove() -> Int32 = this.Int("droneMove", 1)
  public func SetDroneMove(v: Int32) -> Void { this.PutInt("droneMove", Clamp(v, 0, 3)); }

  public func TurnPct() -> Int32 = this.Int("turnPct", 175)
  public func SetTurnPct(v: Int32) -> Void { this.PutInt("turnPct", Clamp(v, 50, 300)); }

  // ---- the sensor (sight view) mount ----
  public func CamUpCm() -> Int32 = this.Int("camUpCm", this.MOUNT_UP_CM)
  public func CamFwdCm() -> Int32 = this.Int("camFwdCm", this.MOUNT_FWD_CM)
  public func SetCamUpCm(v: Int32) -> Void { this.PutInt("camUpCm", Clamp(v, 100, 450)); }
  public func SetCamFwdCm(v: Int32) -> Void { this.PutInt("camFwdCm", Clamp(v, 0, 500)); }

  // ---- the chase camera: distance behind, height above, and off to one shoulder ----
  public func ChaseDistCm() -> Int32 = this.Int("chaseDistCm", this.CHASE_DIST_CM)
  public func ChaseUpCm() -> Int32 = this.Int("chaseUpCm", this.CHASE_UP_CM)
  public func ChaseSideCm() -> Int32 = this.Int("chaseSideCm", this.CHASE_SIDE_CM)
  public func ShoulderLeft() -> Bool = this.Flag("shoulderLeft", false)
  public func SetChaseDistCm(v: Int32) -> Void { this.PutInt("chaseDistCm", Clamp(v, 300, 1600)); }
  public func SetChaseUpCm(v: Int32) -> Void { this.PutInt("chaseUpCm", Clamp(v, 150, 900)); }
  public func SetChaseSideCm(v: Int32) -> Void { this.PutInt("chaseSideCm", Clamp(v, 0, 400)); }
  public func SetShoulderLeft(left: Bool) -> Void { this.PutFlag("shoulderLeft", left); }
  // metres to the right of the centre line (negative = left), for the camera every frame
  public func ChaseSide() -> Float {
    this.Load();
    return this.m_chaseSide;
  }

  public func ResetCamera() -> Void {
    this.PutInt("camUpCm", this.MOUNT_UP_CM);
    this.PutInt("camFwdCm", this.MOUNT_FWD_CM);
    this.PutInt("sensPct", 100);
  }

  public func ResetChase() -> Void {
    this.PutInt("chaseDistCm", this.CHASE_DIST_CM);
    this.PutInt("chaseUpCm", this.CHASE_UP_CM);
    this.PutInt("chaseSideCm", this.CHASE_SIDE_CM);
    this.PutFlag("shoulderLeft", false);
  }

  // ---- the terminal's palette (a TerminalKit theme id) ----
  public func Theme() -> String {
    let id = this.Text("theme", "cm_military");   // our own palette (CMMilitaryPalette)
    return ArrayContains(TKTheme.Ids(), id) ? id : "cm_military";
  }

  public func SetTheme(id: String) -> Void {
    if ArrayContains(TKTheme.Ids(), id) {
      this.Put("theme", id);
    }
  }

  // ---- diagnostics: off in normal play ----
  public func ShowDebug() -> Bool {
    this.Load();
    return this.m_debugOn;
  }
  public func SetShowDebug(on: Bool) -> Void { this.PutFlag("showDebug", on); }
}
