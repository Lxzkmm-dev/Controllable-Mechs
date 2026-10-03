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
import ControllableMechs.Control.*

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
  // the wind's strength on the drones (CMWind), 0 (none) to 200%. Off by default: parked
  // until Omar's wind design doc (2026-10-01)
  public func WindPct() -> Int32 = Clamp(this.Int("windPct2", 0), 0, 200)
  public func SetWindPct(v: Int32) -> Void { this.PutInt("windPct2", Clamp(v, 0, 200)); }
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
  // CONFIG's profile: whose settings the page shows (mech, bombus, griffin, wyvern, octant)
  public func CfgProfile() -> String {
    let v = this.Int("cfgProfile", 0);
    switch v {
      case 1: return "bombus";
      case 2: return "griffin";
      case 3: return "wyvern";
      case 4: return "octant";
    }
    return "mech";
  }
  public func CfgProfileIndex() -> Int32 = Clamp(this.Int("cfgProfile", 0), 0, 4)
  public func SetCfgProfile(i: Int32) -> Void { this.PutInt("cfgProfile", Clamp(i, 0, 4)); }

  // each drone type's flight settings: self-levelling (0-100%, 0 = acro), tilt limit (deg),
  // full-stick rate (deg/s)
  public func DroneLevel(kind: String) -> Int32 = Clamp(this.Int(kind + "Level", CMDroneProfiles.DefaultLevel(kind)), 0, 100)
  public func SetDroneLevel(kind: String, v: Int32) -> Void { this.PutInt(kind + "Level", Clamp(v, 0, 100)); }
  public func DroneTilt(kind: String, def: Int32) -> Int32 = Clamp(this.Int(kind + "Tilt", def), 10, 70)
  public func SetDroneTilt(kind: String, v: Int32) -> Void { this.PutInt(kind + "Tilt", Clamp(v, 10, 70)); }
  public func DroneRate(kind: String, def: Int32) -> Int32 = Clamp(this.Int(kind + "Rate", def), 45, 600)
  public func SetDroneRate(kind: String, v: Int32) -> Void { this.PutInt(kind + "Rate", Clamp(v, 45, 600)); }
  // how far the drone's model is drawn leaning (90 = as flown; the physics is never capped)
  public func DroneShowTilt(kind: String, def: Int32) -> Int32 = Clamp(this.Int(kind + "ShowTilt", def), 10, 90)
  public func SetDroneShowTilt(kind: String, v: Int32) -> Void { this.PutInt(kind + "ShowTilt", Clamp(v, 10, 90)); }
  // each drone type's sight-view sensor mount (cm): above and ahead of the body's origin,
  // defaulting to its nose at its centre height (scanned from its mesh, CMDroneHull)
  public func DroneCamUpCm(kind: String) -> Int32 = Clamp(this.Int(kind + "CamUpCm", CMDroneHull.SensorUpCm(kind)), 0, 300)
  public func SetDroneCamUpCm(kind: String, v: Int32) -> Void { this.PutInt(kind + "CamUpCm", Clamp(v, 0, 300)); }
  public func DroneCamFwdCm(kind: String) -> Int32 = Clamp(this.Int(kind + "CamFwdCm", CMDroneHull.SensorFwdCm(kind)), 0, 400)
  public func SetDroneCamFwdCm(kind: String, v: Int32) -> Void { this.PutInt(kind + "CamFwdCm", Clamp(v, 0, 400)); }
  // the drone's own model hidden in the sight view, so the view isn't inside it (the
  // Bombus: its sensor sits within its shell). On by default for the Bombus.
  public func DroneHideInSight(kind: String) -> Bool = this.Flag(kind + "HideInSight", Equals(kind, "bombus"))
  public func SetDroneHideInSight(kind: String, on: Bool) -> Void { this.PutFlag(kind + "HideInSight", on); }

  // STABILIZE: the sight view held level instead of swaying with the drone (a57): 0 off,
  // 1 while zoomed, 2 always
  public func DroneStabilize(kind: String) -> Int32 = Clamp(this.Int(kind + "Stabilize", 0), 0, 2)
  public func SetDroneStabilize(kind: String, v: Int32) -> Void { this.PutInt(kind + "Stabilize", Clamp(v, 0, 2)); }

  public func ResetDroneCam(kind: String) -> Void {
    this.Put(kind + "CamUpCm", "");
    this.Put(kind + "CamFwdCm", "");
  }

  public func ResetDrone(kind: String) -> Void {
    this.Put(kind + "ShowTilt", "");
    this.Put(kind + "Level", "");
    this.Put(kind + "Tilt", "");
    this.Put(kind + "Rate", "");
  }

  // a frame-by-frame log of a fast flight (DIAGNOSTICS): four seconds once over 8 m/s
  // a test (DIAGNOSTICS): the Octant's LMGs fire only this far off its nose (degrees either
  // side; 0 = anywhere, the default)
  // the payload a spawned Bombus carries (MOTOR POOL): 1 explosive, 2 high explosive, 3 toxic
  // gas, 4 shock (CMUDrone.Detonate)
  // the Bombus payloads' damage, times their own (a test slider, Omar: 'a bit more damage');
  // 100-1000%, 200% by default
  public func PayloadDmgPct() -> Int32 = Clamp(this.Int("payloadDmgPct", 200), 100, 1000)
  public func SetPayloadDmgPct(v: Int32) -> Void { this.PutInt("payloadDmgPct", Clamp(v, 100, 1000)); }
  public func BombusPayload() -> Int32 = Clamp(this.Int("bombusPayload", 1), 1, 4)
  public func SetBombusPayload(v: Int32) -> Void { this.PutInt("bombusPayload", Clamp(v, 1, 4)); }
  // the Octant's destroyed thruster pods: break off (true) or burn on (DIAGNOSTICS, a test)
  public func OctantPodsBreak() -> Bool = this.Flag("octantPodsBreak", true)
  public func SetOctantPodsBreak(on: Bool) -> Void { this.PutFlag("octantPodsBreak", on); }
  public func OctantLmgArc() -> Int32 = Clamp(this.Int("octantLmgArc", 0), 0, 90)   // 0, 17, 35 or 65
  public func SetOctantLmgArc(v: Int32) -> Void { this.PutInt("octantLmgArc", Clamp(v, 0, 90)); }

  public func TurnPct() -> Int32 = this.Int("turnPct", 175)
  public func SetTurnPct(v: Int32) -> Void { this.PutInt("turnPct", Clamp(v, 50, 300)); }

  // ---- the sensor (sight view) mount ----
  public func CamUpCm() -> Int32 = this.Int("camUpCm", this.MOUNT_UP_CM)
  public func CamFwdCm() -> Int32 = this.Int("camFwdCm", this.MOUNT_FWD_CM)
  public func SetCamUpCm(v: Int32) -> Void { this.PutInt("camUpCm", Clamp(v, 100, 450)); }
  public func SetCamFwdCm(v: Int32) -> Void { this.PutInt("camFwdCm", Clamp(v, 0, 500)); }

  // ---- the chase camera: distance behind, height above, and off to one shoulder ----
  // Each profile (CONFIG > PROFILE) has its own chase camera: the mech's keys as they
  // always were, a drone type's prefixed with its name and closer defaults.
  // No profile (or "mech") is the mech's.
  private static func IsDrone(prof: String) -> Bool = StrLen(prof) > 0 && NotEquals(prof, "mech")
  private static func DroneChaseDefault(prof: String, which: Int32) -> Int32 {
    // distance, height, side (cm)
    switch prof {
      case "bombus": return which == 0 ? 250 : (which == 1 ? 60 : 0);
      case "octant": return which == 0 ? 700 : (which == 1 ? 220 : 0);
    }
    return which == 0 ? 400 : (which == 1 ? 110 : 0);
  }
  public func ChaseDistCm(opt prof: String) -> Int32 = CMPilotSystem.IsDrone(prof) ? this.Int(prof + "ChaseDistCm", CMPilotSystem.DroneChaseDefault(prof, 0)) : this.Int("chaseDistCm", this.CHASE_DIST_CM)
  public func ChaseUpCm(opt prof: String) -> Int32 = CMPilotSystem.IsDrone(prof) ? this.Int(prof + "ChaseUpCm", CMPilotSystem.DroneChaseDefault(prof, 1)) : this.Int("chaseUpCm", this.CHASE_UP_CM)
  public func ChaseSideCm(opt prof: String) -> Int32 = CMPilotSystem.IsDrone(prof) ? this.Int(prof + "ChaseSideCm", CMPilotSystem.DroneChaseDefault(prof, 2)) : this.Int("chaseSideCm", this.CHASE_SIDE_CM)
  public func ShoulderLeft(opt prof: String) -> Bool = CMPilotSystem.IsDrone(prof) ? this.Flag(prof + "ShoulderLeft", false) : this.Flag("shoulderLeft", false)
  public func SetChaseDistCm(v: Int32, opt prof: String) -> Void {
    if CMPilotSystem.IsDrone(prof) { this.PutInt(prof + "ChaseDistCm", Clamp(v, 60, 1600)); } else { this.PutInt("chaseDistCm", Clamp(v, 300, 1600)); }
  }
  public func SetChaseUpCm(v: Int32, opt prof: String) -> Void {
    if CMPilotSystem.IsDrone(prof) { this.PutInt(prof + "ChaseUpCm", Clamp(v, 0, 900)); } else { this.PutInt("chaseUpCm", Clamp(v, 150, 900)); }
  }
  public func SetChaseSideCm(v: Int32, opt prof: String) -> Void {
    if CMPilotSystem.IsDrone(prof) { this.PutInt(prof + "ChaseSideCm", Clamp(v, 0, 400)); } else { this.PutInt("chaseSideCm", Clamp(v, 0, 400)); }
  }
  public func SetShoulderLeft(left: Bool, opt prof: String) -> Void {
    if CMPilotSystem.IsDrone(prof) { this.PutFlag(prof + "ShoulderLeft", left); } else { this.PutFlag("shoulderLeft", left); }
  }
  public func ResetChaseOf(prof: String) -> Void {
    if !CMPilotSystem.IsDrone(prof) {
      this.ResetChase();
      return;
    }
    this.Put(prof + "ChaseDistCm", "");
    this.Put(prof + "ChaseUpCm", "");
    this.Put(prof + "ChaseSideCm", "");
    this.Put(prof + "ShoulderLeft", "");
  }
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
