// =============================================================================
// MECHS OF NIGHT CITY - CONTROL FRAMEWORK: DRONES (0.7.0, spike build)
//
// A linked drone (Bombus, Griffin, Wyvern, Octant) flown by the pilot session. This
// first build answers the spikes in docs/DRONES_TECHNICAL_DESIGN.md before the real
// flight model is built on top:
//   S0  what a drone is in game (its class and NPC type), logged at Begin
//   S1  how to put a flying puppet where the physics says, every frame: three methods,
//       picked under CONFIG > DIAGNOSTICS > DRONE MOVE METHOD, each logging once a
//       second how far the drone ended up from where it was sent
//   S2  whether its pitch and roll can be set (the commanded and the real tilt, logged)
// The flight here is the angle mode of the design at its simplest: WASD tilt the drone
// (up to 25 deg) and the tilt moves it, Space/Ctrl climb and descend, the mouse turns;
// drag, a top speed and a ground floor. Nothing runs unless a drone is piloted.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMUDrone extends CMCUnit {
  private let m_game: GameInstance;
  private let m_drone: wref<NPCPuppet>;
  private let m_pos: Vector4;          // where the flight model has the drone
  private let m_seen: Vector4;         // where the drone really is (the camera follows this)
  private let m_vel: Vector4;
  private let m_yaw: Float;
  private let m_pitch: Float;          // the body's tilt, degrees (nose down is negative)
  private let m_roll: Float;
  private let m_method: Int32;         // 0 facility teleport, 1 AI teleport, 2 AI move carrot,
                                       // 3 AI off + facility teleport
  private let m_cmd: ref<AICommand>;
  private let m_cmdAt: Float;
  private let m_logAt: Float;
  private let m_errSum: Float;
  private let m_errMax: Float;
  private let m_errN: Int32;
  private let m_frames: Int32;
  private let m_name: String;

  private let TILT: Float = 25.0;        // deg, the angle mode's limit
  private let TILT_RATE: Float = 6.0;    // how fast the body reaches the wanted tilt (1/s)
  private let CLIMB: Float = 4.0;        // m/s with Space or Ctrl
  private let TOP: Float = 15.0;         // m/s
  private let DRAG_H: Float = 0.45;      // 1/s, horizontal air drag
  private let DRAG_V: Float = 2.5;       // 1/s, how fast the climb rate is reached
  private let FLOOR: Float = 0.8;        // m, the lowest it hovers above ground

  public func Begin(s: ref<CMCSession>) -> String {
    this.m_game = s.GetGameInstance();
    let link = CMLinkSystem.Get(this.m_game);
    let drone = link.Unit();
    if !IsDefined(drone) {
      return "!NO DRONE LINKED";
    }
    if !ScriptedPuppet.IsAlive(drone) {
      return "!DRONE IS DESTROYED";
    }
    this.m_drone = drone;
    this.m_name = CMUDrone.TypeName(drone);
    link.Hold();
    link.SetOrder(CMOrder.Pilot());
    this.m_pos = drone.GetWorldPosition();
    this.m_seen = this.m_pos;
    this.m_vel = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_yaw = CMPilotRig.YawOf(drone.GetWorldForward());
    this.m_pitch = 0.0;
    this.m_roll = 0.0;
    this.m_method = CMPilotSystem.Get(this.m_game).DroneMove();
    this.m_logAt = s.Now() + 1.0;
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    this.m_frames = 0;
    this.Pacify(drone, true);
    // method 3: its AI controller off for the flight, so nothing moves it but the teleports
    if this.m_method == 3 {
      let ai = drone.GetAIControllerComponent();
      if IsDefined(ai) {
        ai.Toggle(false);
      }
    }
    // S0: what a drone is
    CMCSession.Log("drone: " + this.m_name + ", class " + NameToString(drone.GetClassName()) + ", record " + TDBID.ToStringDEBUG(drone.GetRecordID())
      + ", type " + EnumValueToString("gamedataNPCType", Cast<Int64>(EnumInt(drone.GetNPCType())))
      + ", move method " + CMUDrone.MethodName(this.m_method));
    return "";
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    let drone = this.m_drone;
    if IsDefined(drone) {
      this.Cancel(drone);
      if this.m_method == 3 {
        let ai = drone.GetAIControllerComponent();
        if IsDefined(ai) {
          ai.Toggle(true);
        }
      }
      this.Pacify(drone, false);
    }
    this.m_drone = null;
  }

  public func IsAlive() -> Bool {
    let drone = this.m_drone;
    return IsDefined(drone) && ScriptedPuppet.IsAlive(drone);
  }

  public func LostReason() -> String = "!DRONE DESTROYED"

  // ten times a second: the link and the uplink range (500 m for drones)
  public func SlowTick(s: ref<CMCSession>, now: Float) -> String {
    let link = CMLinkSystem.Get(this.m_game);
    if !link.IsLinked() {
      return "!ROBOT LINK LOST";
    }
    if link.Distance() > link.Range() {
      return "!SIGNAL LOST";
    }
    return "";
  }
  public func Name() -> String = this.m_name
  // the camera rides the drone as it really is, not the model a frame ahead of it: the
  // teleports land a frame late, and a camera on the model shook against the drone
  public func Ground() -> Vector4 = this.m_seen
  public func Facing() -> Float = this.m_yaw
  public func SensorUp() -> Float = 0.25
  public func SensorFwd() -> Float = 0.6
  public func AimSkip() -> Float = 1.5

  public func Tick(s: ref<CMCSession>, dt: Float, now: Float) -> Void {
    let drone = this.m_drone;
    if !IsDefined(drone) || dt <= 0.0 {
      return;
    }
    dt = MinF(dt, 0.1);
    this.m_frames += 1;
    // S1: how far the last placement landed from where it was sent
    let actual = drone.GetWorldPosition();
    this.m_seen = actual;
    if this.m_method == 2 {
      this.m_pos = actual;   // the AI does the moving: the model follows it
    } else {
      let err = Vector4.Distance(actual, this.m_pos);
      this.m_errSum += err;
      this.m_errMax = MaxF(this.m_errMax, err);
      this.m_errN += 1;
    }
    this.Fly(s, dt);
    this.Place(drone, now);
    if now >= this.m_logAt {
      this.m_logAt = now + 1.0;
      this.Report(drone);
    }
  }

  // the flight model, angle mode at its simplest
  private func Fly(s: ref<CMCSession>, dt: Float) -> Void {
    let f = (s.Key(CMCKey.W()) ? 1.0 : 0.0) - (s.Key(CMCKey.S()) ? 1.0 : 0.0);
    let side = (s.Key(CMCKey.D()) ? 1.0 : 0.0) - (s.Key(CMCKey.A()) ? 1.0 : 0.0);
    let climb = (s.Key(CMCKey.Up()) ? 1.0 : 0.0) - (s.Key(CMCKey.Down()) ? 1.0 : 0.0);
    // the body turns with the view, and tilts toward the wanted tilt
    this.m_yaw = s.rig.yaw;
    let k = MinF(1.0, this.TILT_RATE * dt);
    this.m_pitch += (-f * this.TILT - this.m_pitch) * k;
    this.m_roll += (side * this.TILT - this.m_roll) * k;
    // the tilt is what moves it: lift along the tilted up axis, level flight held
    let fwd = CMPilotRig.Dir(this.m_yaw, 0.0);
    let right = CMPilotRig.Dir(this.m_yaw - 90.0, 0.0);
    let g = 9.81;
    let ax = fwd * (g * TanF(Deg2Rad(-this.m_pitch))) + right * (g * TanF(Deg2Rad(this.m_roll)));
    this.m_vel.X += (ax.X - this.DRAG_H * this.m_vel.X) * dt;
    this.m_vel.Y += (ax.Y - this.DRAG_H * this.m_vel.Y) * dt;
    this.m_vel.Z += (climb * this.CLIMB - this.m_vel.Z) * MinF(1.0, this.DRAG_V * dt);
    let flat = SqrtF(this.m_vel.X * this.m_vel.X + this.m_vel.Y * this.m_vel.Y);
    if flat > this.TOP {
      this.m_vel.X *= this.TOP / flat;
      this.m_vel.Y *= this.TOP / flat;
    }
    let step = this.m_vel * dt;
    let next = this.m_pos + step;
    // walls: stop short of what is in the way
    let sq = GameInstance.GetSpatialQueriesSystem(this.m_game);
    let hit: TraceResult;
    if Vector4.Length(step) > 0.001 && sq.SyncRaycastByCollisionPreset(this.m_pos, next + Vector4.Normalize(step) * 0.6, n"World Static", hit, true) {
      next = this.m_pos;
      this.m_vel = new Vector4(0.0, 0.0, 0.0, 0.0);
    }
    // the ground: never below the floor height
    if sq.SyncRaycastByCollisionPreset(next + new Vector4(0.0, 0.0, 0.5, 0.0), next - new Vector4(0.0, 0.0, 50.0, 0.0), n"World Static", hit, true) {
      let floor = Cast<Vector4>(hit.position).Z + this.FLOOR;
      if next.Z < floor {
        next.Z = floor;
        this.m_vel.Z = MaxF(0.0, this.m_vel.Z);
      }
    }
    next.W = 1.0;
    this.m_pos = next;
  }

  // S1: put the drone where the model says, by the chosen method
  private func Place(drone: ref<NPCPuppet>, now: Float) -> Void {
    let e: EulerAngles;
    e.Yaw = this.m_yaw;
    e.Pitch = this.m_pitch;
    e.Roll = this.m_roll;
    switch this.m_method {
      case 0:
      case 3:
        GameInstance.GetTeleportationFacility(this.m_game).Teleport(drone, this.m_pos, e);
        break;
      case 1:
        let tp = new AITeleportCommand();
        tp.position = this.m_pos;
        tp.rotation = this.m_yaw;
        tp.doNavTest = false;
        this.Send(drone, tp);
        break;
      default:
        // a carrot half a second ahead, re-sent four times a second
        if now - this.m_cmdAt >= 0.25 {
          let at = this.m_pos + this.m_vel * 0.5;
          let world: WorldPosition;
          WorldPosition.SetVector4(world, at);
          let spec: AIPositionSpec;
          AIPositionSpec.SetWorldPosition(spec, world);
          let cmd = new AIMoveToCommand();
          cmd.movementTarget = spec;
          cmd.movementType = moveMovementType.Sprint;
          cmd.ignoreNavigation = true;
          cmd.finishWhenDestinationReached = true;
          cmd.desiredDistanceFromTarget = 0.3;
          this.Send(drone, cmd);
          this.m_cmdAt = now;
        }
    }
  }

  private func Send(drone: ref<NPCPuppet>, cmd: ref<AICommand>) -> Void {
    let ai = drone.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    if IsDefined(this.m_cmd) {
      ai.CancelCommand(this.m_cmd);
    }
    ai.SendCommand(cmd);
    this.m_cmd = cmd;
  }

  private func Cancel(drone: ref<NPCPuppet>) -> Void {
    let ai = drone.GetAIControllerComponent();
    if IsDefined(ai) && IsDefined(this.m_cmd) {
      ai.CancelCommand(this.m_cmd);
    }
    this.m_cmd = null;
  }

  // once a second (diagnostics): the S1 and S2 answers
  private func Report(drone: ref<NPCPuppet>) -> Void {
    let real = Quaternion.ToEulerAngles(drone.GetWorldOrientation());
    let avg = this.m_errN > 0 ? this.m_errSum / Cast<Float>(this.m_errN) : -1.0;
    CMCSession.Log("drone: " + CMUDrone.MethodName(this.m_method) + ", " + IntToString(this.m_frames) + " frames"
      + (this.m_method == 2 ? "" : ", off by " + FloatToStringPrec(avg, 2) + " m avg / " + FloatToStringPrec(this.m_errMax, 2) + " m max")
      + ", speed " + FloatToStringPrec(Vector4.Length(this.m_vel), 1) + " m/s"
      + ", tilt sent p" + FloatToStringPrec(this.m_pitch, 1) + " r" + FloatToStringPrec(this.m_roll, 1)
      + ", real p" + FloatToStringPrec(real.Pitch, 1) + " r" + FloatToStringPrec(real.Roll, 1) + " y" + FloatToStringPrec(real.Yaw, 1));
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    this.m_frames = 0;
  }

  public func Hud(s: ref<CMCSession>, st: ref<CMPilotHudState>) -> Void {
    let drone = this.m_drone;
    if IsDefined(drone) {
      st.integrity = GameInstance.GetStatPoolsSystem(this.m_game).GetStatPoolValue(Cast<StatsObjectID>(drone.GetEntityID()), gamedataStatPoolType.Health, true) / 100.0;
    }
    ArrayClear(st.parts);   // no Minotaur schematic for a drone
    st.hasL = false;
    st.hasR = false;
    st.missile = "";
    st.warning = "DRONE TEST: " + CMUDrone.MethodName(this.m_method);
  }

  // its own AI kept out of the way while flown: the threat and state wraps (the piloted
  // flag), its reactions, senses and target tracking
  private func Pacify(drone: ref<NPCPuppet>, on: Bool) -> Void {
    drone.m_cmPiloted = on;
    let reactions = drone.GetStimReactionComponent();
    if IsDefined(reactions) {
      reactions.Toggle(!on);
    }
    let senses = drone.GetSensesComponent();
    if IsDefined(senses) {
      senses.Toggle(!on);
    }
    let tracker = drone.GetTargetTrackerComponent();
    if IsDefined(tracker) {
      if on {
        tracker.ClearThreats();
      }
      tracker.Toggle(!on);
    }
  }

  public static func MethodName(m: Int32) -> String {
    switch m {
      case 0: return "FACILITY TELEPORT";
      case 1: return "AI TELEPORT";
      case 3: return "AI OFF + TELEPORT";
    }
    return "AI MOVE CARROT";
  }

  public static func TypeName(drone: ref<NPCPuppet>) -> String {
    let rec = StrLower(TDBID.ToStringDEBUG(drone.GetRecordID()));
    if StrContains(rec, "bombus") {
      return "ZETATECH BOMBUS";
    }
    if StrContains(rec, "griffin") {
      return "MILITECH GRIFFIN";
    }
    if StrContains(rec, "wyvern") {
      return "MILITECH WYVERN";
    }
    if StrContains(rec, "octant") {
      return "ZETATECH OCTANT";
    }
    return "DRONE";
  }
}
