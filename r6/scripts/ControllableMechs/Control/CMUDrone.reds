// =============================================================================
// MECHS OF NIGHT CITY - CONTROL FRAMEWORK: DRONES (0.7.0)
//
// A linked drone (Bombus, Griffin, Wyvern, Octant) flown by the pilot session on the
// mod's own flight model (CMFlight; docs/DRONES_TECHNICAL_DESIGN.md).
//
// What the spikes settled (Omar's test flights, 2026-09-30):
//   - a drone is an NPCPuppet of type Drone, not a vehicle: no rigid body to push
//   - TeleportationFacility.Teleport does not move it; an AITeleportCommand each frame
//     puts it within centimetres of where it was sent (AI TELEPORT, the default)
//   - its pitch and roll can't be set: the tilt is shown through the camera instead
// The camera rides where the drone really is (the teleports land a frame late).
// Keys: WASD tilt it and the tilt moves it, Space/Ctrl climb and descend, the mouse
// turns it. CONFIG > PROFILE > (the drone) sets its self-levelling (0% = acro), tilt limit
// and rates.
// Collisions: the step is swept against the world; the velocity into a surface is
// removed with a little bounce, and a hard hit damages the drone (a crashed drone is
// lost). Nothing runs unless a drone is piloted.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMUDrone extends CMCUnit {
  private let m_game: GameInstance;
  private let m_drone: wref<NPCPuppet>;
  private let m_flight: ref<CMFlight>;
  private let m_seen: Vector4;         // where the drone really is (the camera follows this)
  private let m_kind: String;          // bombus, griffin, wyvern, octant
  private let m_name: String;
  private let m_method: Int32;         // 0 facility teleport, 1 AI teleport, 2 AI move carrot,
                                       // 3 AI off + facility teleport
  private let m_cmd: ref<AICommand>;
  private let m_cmdAt: Float;
  private let m_logAt: Float;
  private let m_errSum: Float;
  private let m_errMax: Float;
  private let m_errN: Int32;
  private let m_frames: Int32;
  private let m_hits: Int32;
  private let m_stalls: Int32;         // frames the drone didn't move though it was sent on
  private let m_last: Vector4;         // where it was the frame before
  private let m_dt: Float;             // the last frame's length (the teleport leads by one)
  private let m_gait: CName;           // the drone locomotion wrapper on (Walk, Run, Sprint)
  private let m_lastYaw: Float;
  private let m_ground: Float;         // metres above the ground, last measured

  private let SUBSTEP: Float = 0.008;  // s, the flight model's step

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
    this.m_kind = CMUDrone.Kind(drone);
    this.m_name = CMUDrone.TypeName(this.m_kind);
    link.Hold();
    link.SetOrder(CMOrder.Pilot());
    let cfg = CMPilotSystem.Get(this.m_game);
    let prof = CMDroneProfiles.For(this.m_kind);
    prof.tilt = Cast<Float>(cfg.DroneTilt(this.m_kind, RoundF(prof.tilt)));
    prof.tiltRate = Cast<Float>(cfg.DroneRate(this.m_kind, RoundF(prof.tiltRate)));
    this.m_flight = CMFlight.Make(prof, drone.GetWorldPosition(), CMPilotRig.YawOf(drone.GetWorldForward()));
    this.m_flight.level = Cast<Float>(cfg.DroneLevel(this.m_kind)) / 100.0;
    this.m_seen = drone.GetWorldPosition();
    this.m_method = cfg.DroneMove();
    this.m_logAt = s.Now() + 1.0;
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    this.m_frames = 0;
    this.m_hits = 0;
    this.m_stalls = 0;
    this.m_last = drone.GetWorldPosition();
    this.m_dt = 0.016;
    this.m_gait = n"";
    this.m_lastYaw = this.m_flight.yaw;
    this.Pacify(drone, true);
    if this.m_method == 3 {
      let ai = drone.GetAIControllerComponent();
      if IsDefined(ai) {
        ai.Toggle(false);
      }
    }
    CMCSession.Log("drone: " + this.m_name + ", record " + TDBID.ToStringDEBUG(drone.GetRecordID())
      + ", self-levelling " + IntToString(RoundF(this.m_flight.level * 100.0)) + "%, tilt " + FloatToStringPrec(prof.tilt, 0) + ", rate " + FloatToStringPrec(prof.tiltRate, 0) + ", move method " + CMUDrone.MethodName(this.m_method));
    return "";
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    let drone = this.m_drone;
    if IsDefined(drone) {
      this.Cancel(drone);
      this.SetGait(drone, n"Walk");   // the drone's own default
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
  // the camera rides the drone as it really is, not the model a frame ahead of it
  public func Ground() -> Vector4 = this.m_seen
  public func Facing() -> Float = IsDefined(this.m_flight) ? this.m_flight.yaw : 0.0
  public func SensorUp() -> Float = 0.1
  public func SensorFwd() -> Float = 0.35
  public func AimSkip() -> Float = 1.5
  // the body's tilt, shown through the camera (the game won't tilt a drone's body)
  public func CamTilt() -> Vector4 = IsDefined(this.m_flight) ? new Vector4(this.m_flight.pitch, this.m_flight.roll, 0.0, 0.0) : new Vector4(0.0, 0.0, 0.0, 0.0)
  public func StepWeight() -> Float = 0.0   // no footfalls
  public func CamProfile() -> String = this.m_kind

  public func Tick(s: ref<CMCSession>, dt: Float, now: Float) -> Void {
    let drone = this.m_drone;
    if !IsDefined(drone) || !IsDefined(this.m_flight) || dt <= 0.0 {
      return;
    }
    dt = MinF(dt, 0.1);
    this.m_frames += 1;
    let actual = drone.GetWorldPosition();
    this.m_seen = actual;
    // a stall: the model moved on but the drone stayed put this frame
    if Vector4.Length(this.m_flight.vel) > 0.5 && Vector4.Distance(actual, this.m_last) < 0.002 {
      this.m_stalls += 1;
    }
    this.m_last = actual;
    this.m_dt = dt;
    if this.m_method == 2 {
      this.m_flight.pos = actual;   // the AI does the moving: the model follows it
    } else {
      let err = Vector4.Distance(actual, this.m_flight.pos);
      this.m_errSum += err;
      this.m_errMax = MaxF(this.m_errMax, err);
      this.m_errN += 1;
    }
    let f = (s.Key(CMCKey.W()) ? 1.0 : 0.0) - (s.Key(CMCKey.S()) ? 1.0 : 0.0);
    let side = (s.Key(CMCKey.D()) ? 1.0 : 0.0) - (s.Key(CMCKey.A()) ? 1.0 : 0.0);
    let climb = (s.Key(CMCKey.Up()) ? 1.0 : 0.0) - (s.Key(CMCKey.Down()) ? 1.0 : 0.0);
    let from = this.m_flight.pos;
    // the flight model in small steps
    let left = dt;
    while left > 0.0001 {
      let h = MinF(this.SUBSTEP, left);
      this.m_flight.Step(h, f, side, climb, s.rig.yaw);
      left -= h;
    }
    this.Collide(drone, from);
    this.Place(drone, now);
    this.Lean(drone, dt);
    if now >= this.m_logAt {
      this.m_logAt = now + 1.0;
      this.Report(drone);
    }
  }

  // The step from `from` to where the model went, swept against the world: into a wall
  // or the ground, the drone stops at the surface, the velocity into it is removed with
  // a little bounce, and a hard hit damages it.
  private func Collide(drone: ref<NPCPuppet>, from: Vector4) -> Void {
    let fl = this.m_flight;
    let sq = GameInstance.GetSpatialQueriesSystem(this.m_game);
    let to = fl.pos;
    let move = to - from;
    let len = Vector4.Length(move);
    let hit: TraceResult;
    if len > 0.0005 {
      let dir = move / len;
      let r = fl.p.radius;
      if sq.SyncRaycastByCollisionPreset(from, to + dir * r, n"World Static", hit, true) {
        let at = Cast<Vector4>(hit.position);
        let n = Vector4.Normalize(Cast<Vector4>(hit.normal));
        fl.pos = at - dir * r;
        fl.pos.W = 1.0;
        this.Impact(drone, fl.Contact(n, 0.3));
      }
    }
    // the ground under it: measured for the HUD, and a contact only when the drone is
    // actually in it. There is no minimum height (a floor held it half a metre up and
    // bounced it over every curb and bump in the road); flying low is the pilot's call.
    let r0 = fl.p.radius * 0.5;
    if sq.SyncRaycastByCollisionPreset(fl.pos + new Vector4(0.0, 0.0, r0, 0.0), fl.pos - new Vector4(0.0, 0.0, 40.0, 0.0), n"World Static", hit, true) {
      let gz = Cast<Vector4>(hit.position).Z;
      this.m_ground = fl.pos.Z - gz;
      if fl.pos.Z < gz + r0 {
        fl.pos.Z = gz + r0;
        this.Impact(drone, fl.Contact(new Vector4(0.0, 0.0, 1.0, 0.0), 0.25));
        if fl.holding {
          fl.holdZ = MaxF(fl.holdZ, fl.pos.Z);
        }
      }
    } else {
      this.m_ground = -1.0;
    }
  }

  // a collision this fast (m/s): past the type's limit it costs health, more the harder
  // it hits; a crash can destroy the drone (a crashed drone is lost)
  private func Impact(drone: ref<NPCPuppet>, speed: Float) -> Void {
    let limit = this.m_flight.p.impact;
    if speed <= limit {
      return;
    }
    let over = speed - limit;
    let pct = MinF(100.0, over * over * 4.0);
    this.m_hits += 1;
    GameInstance.GetStatPoolsSystem(this.m_game).RequestChangingStatPoolValue(Cast<StatsObjectID>(drone.GetEntityID()), gamedataStatPoolType.Health, -pct, null, false, true);
    GameObject.PlaySoundEvent(drone, n"dev_generic_impact_metal");
    CMCSession.Log("drone: hit something at " + FloatToStringPrec(speed, 1) + " m/s, " + FloatToStringPrec(pct, 0) + "% of its health");
  }

  // put the drone where the model says, by the chosen method
  private func Place(drone: ref<NPCPuppet>, now: Float) -> Void {
    let fl = this.m_flight;
    switch this.m_method {
      case 4:
        // the entity's own transform set each frame (Codeware), with the body's full
        // tilt; an AI teleport four times a second keeps its movement component where
        // the body is
        let wt: WorldTransform;
        let world: WorldPosition;
        WorldPosition.SetVector4(world, fl.pos);
        WorldTransform.SetWorldPosition(wt, world);
        let q: EulerAngles;
        q.Yaw = fl.yaw;
        q.Pitch = fl.pitch;
        q.Roll = fl.roll;
        WorldTransform.SetOrientation(wt, EulerAngles.ToQuat(q));
        drone.SetWorldTransform(wt);
        if now - this.m_cmdAt >= 0.25 {
          let sync = new AITeleportCommand();
          sync.position = fl.pos;
          sync.rotation = fl.yaw;
          sync.doNavTest = false;
          let ai4 = drone.GetAIControllerComponent();
          if IsDefined(ai4) {
            ai4.SendCommand(sync);
          }
          this.m_cmdAt = now;
        }
        break;
      case 0:
      case 3:
        let e: EulerAngles;
        e.Yaw = fl.yaw;
        e.Pitch = fl.pitch;
        e.Roll = fl.roll;
        GameInstance.GetTeleportationFacility(this.m_game).Teleport(drone, fl.pos, e);
        break;
      case 1:
        // a teleport lands the frame after it is sent: sent one frame ahead, it lands
        // where the model is when that frame is drawn. It completes at once, so the last
        // one isn't cancelled (cancelling could drop one still pending: a stalled frame)
        let tp = new AITeleportCommand();
        tp.position = fl.pos + fl.vel * this.m_dt;
        tp.rotation = fl.yaw;
        tp.doNavTest = false;
        let ai = drone.GetAIControllerComponent();
        if IsDefined(ai) {
          ai.SendCommand(tp);
        }
        break;
      default:
        if now - this.m_cmdAt >= 0.25 {
          let at = fl.pos + fl.vel * 0.5;
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

  // The body's lean. The game won't take a pitch or roll for a drone, but its animation
  // graph (drone_humanoid) leans and tilts it procedurally from its locomotion: speed,
  // turn speed and which movement set is on (DroneComponent sets the walk, run or sprint
  // wrapper; the tilt coefficients come from its record). Our flight feeds those, since
  // the teleports leave the drone's own movement at a standstill.
  private func Lean(drone: ref<NPCPuppet>, dt: Float) -> Void {
    let fl = this.m_flight;
    let flat = SqrtF(fl.vel.X * fl.vel.X + fl.vel.Y * fl.vel.Y);
    let turn = CMPilotRig.Wrap(fl.yaw - this.m_lastYaw) / MaxF(0.001, dt);
    this.m_lastYaw = fl.yaw;
    let loco = new AnimFeature_DroneLocomotion();
    loco.speed = flat;
    loco.desiredSpeed = flat;
    loco.angularSpeed = turn;
    loco.lookAtAngle = 0.0;
    loco.pathCurvative = 0.0;
    AnimationControllerComponent.ApplyFeature(drone, n"DroneLocomotion", loco);
    this.SetGait(drone, flat < 4.0 ? n"Walk" : (flat < 9.0 ? n"Run" : n"Sprint"));
  }

  private func SetGait(drone: ref<NPCPuppet>, gait: CName) -> Void {
    if Equals(gait, this.m_gait) {
      return;
    }
    this.m_gait = gait;
    AnimationControllerComponent.SetAnimWrapperWeight(drone, n"DroneLocomotion_Walk", Equals(gait, n"Walk") ? 1.0 : 0.0);
    AnimationControllerComponent.SetAnimWrapperWeight(drone, n"DroneLocomotion_Run", Equals(gait, n"Run") ? 1.0 : 0.0);
    AnimationControllerComponent.SetAnimWrapperWeight(drone, n"DroneLocomotion_Sprint", Equals(gait, n"Sprint") ? 1.0 : 0.0);
  }

  // once a second (diagnostics)
  private func Report(drone: ref<NPCPuppet>) -> Void {
    let fl = this.m_flight;
    let real = Quaternion.ToEulerAngles(drone.GetWorldOrientation());
    let avg = this.m_errN > 0 ? this.m_errSum / Cast<Float>(this.m_errN) : -1.0;
    let stalls = this.m_stalls;
    this.m_stalls = 0;
    CMCSession.Log("drone: " + CMUDrone.MethodName(this.m_method) + ", " + IntToString(this.m_frames) + " frames"
      + (this.m_method == 2 ? "" : ", off by " + FloatToStringPrec(avg, 2) + " m avg / " + FloatToStringPrec(this.m_errMax, 2) + " m max, " + IntToString(stalls) + " stalled frames")
      + ", speed " + FloatToStringPrec(Vector4.Length(fl.vel), 1) + " m/s, climb " + FloatToStringPrec(fl.vel.Z, 1)
      + ", tilt p" + FloatToStringPrec(fl.pitch, 1) + " r" + FloatToStringPrec(fl.roll, 1)
      + ", spool " + FloatToStringPrec(fl.Spool() * 100.0, 0) + "%, " + FloatToStringPrec(this.m_ground, 1) + " m up"
      + ", gait " + NameToString(this.m_gait)
      + ", real tilt p" + FloatToStringPrec(real.Pitch, 1) + " r" + FloatToStringPrec(real.Roll, 1));
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
    if IsDefined(this.m_flight) {
      st.speed = Vector4.Length(this.m_flight.vel);
      st.title = this.m_name + "  //  LEVEL " + IntToString(RoundF(this.m_flight.level * 100.0)) + "%  ALT " + (this.m_ground >= 0.0 ? FloatToStringPrec(this.m_ground, 1) + " M" : "---") + "  SPOOL " + IntToString(RoundF(this.m_flight.Spool() * 100.0)) + "%";
    }
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
      case 4: return "ENTITY TRANSFORM";
    }
    return "AI MOVE CARROT";
  }

  public static func Kind(drone: ref<NPCPuppet>) -> String {
    let rec = StrLower(TDBID.ToStringDEBUG(drone.GetRecordID()));
    if StrContains(rec, "bombus") {
      return "bombus";
    }
    if StrContains(rec, "griffin") {
      return "griffin";
    }
    if StrContains(rec, "octant") {
      return "octant";
    }
    return "wyvern";
  }

  public static func TypeName(kind: String) -> String {
    switch kind {
      case "bombus": return "ZETATECH BOMBUS";
      case "griffin": return "MILITECH GRIFFIN";
      case "octant": return "ZETATECH OCTANT";
    }
    return "MILITECH WYVERN";
  }
}
