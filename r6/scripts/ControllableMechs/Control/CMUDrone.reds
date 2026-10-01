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
// turns it. The flight is a 6-DOF rigid body (CMFlight). CONFIG > PROFILE > (the drone) sets its self-levelling (0% = acro), tilt limit
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
  private let m_stickF: Float;         // the keys as a stick: ramped in, with expo
  private let m_rayHits: Int32;        // collision rays that found something / didn't (log)
  private let m_rayMiss: Int32;
  private let m_hitS: Int32;           // per query type: static, dynamic, vehicle (log)
  private let m_hitD: Int32;
  private let m_hitV: Int32;
  private let m_hitG: Int32;
  private let m_touchLogged: Bool;
  private let m_aiOff: Bool;           // its AI controller switched off for the flight
  // The drawn body: the hover animation poses the skeleton's body bone away from its rest
  // pose (lifted, and turned: the Wyvern rests on its side). The pose is measured through a
  // skeleton-bound slot (MeasurePose) as a transform from the rest pose to as drawn, in
  // the entity's frame; the entity is lowered by its translation and the scanned hull is
  // turned by its rotation.
  private let m_tq: Quaternion;        // rest pose -> drawn, rotation
  private let m_tt: Vector4;           // rest pose -> drawn, translation (the hover lift)
  private let m_tqSeen: Quaternion;    // the measured turn (log only)
  private let m_poseOk: Bool;          // measured at least once
  private let m_poseFrom: String;      // which slot (log)
  private let m_poseFrames: Int32;     // frames measured; held after 30
  private let m_hull: array<Vector4>;  // contact points in the rest pose (CMDroneHull)
  private let m_pts: array<Vector4>;   // the same as drawn (turned by m_tq), entity frame
  private let m_c: Vector4;            // the drawn hull's centre, entity frame: the flight's
                                       // centre of mass sits here
  private let m_hidden: Bool;          // its model hidden (the sight view, CONFIG)
  private let m_anchors: array<Vector4>; // the drawn body's origin, this frame and the last two
  private let m_mounts: array<Vector4>;  // the sensor on the drawn body, the same frames
  private let m_sight: Bool;           // the sight view is on (from the session, each tick)
  private let m_rigYaw: Float;         // the view's heading, this tick
  private let m_camLag: Int32;         // frames the camera follows behind (DIAGNOSTICS)
  private let m_visTest: Int32;        // which NPC systems are off while flown (DIAGNOSTICS)
  // Its own collision: the Octant's shell and thrusters (and the Griffin's body) are physical
  // meshes our rays hit, so every ray out from its centre struck its own shell and pushed
  // it: the slide on take-over. Each contact ray's distance to its own shell is learned in
  // the first frames (m_self, -1 = nothing of its own on that ray); a hit there is its own.
  private let m_self: array<Float>;
  private let m_flLeft: Int32;         // frame-log lines left (-1 = not started)
  private let m_selfHits: Int32;       // rays that passed through the drone's own body (log)
  private let m_flOn: Bool;
  private let m_flT: Float;
  private let m_lastRoot: Vector4;     // where the entity was put last frame
  private let m_boneRel: Vector4;      // the body bone less the flight centre when the pose was held (log)
  private let m_seenAtTick: Vector4;   // where the engine had it at the start of this tick
  private let m_selfFrames: Int32;
  private let m_hasSelf: Bool;
  private let m_hideInSight: Bool;
  private let m_fastHits: Int32;       // contact-ray hits (log)
  private let m_fastOff: Bool;         // the one-query filter found nothing where it should:
  private let m_fastMiss: Int32;       // per-group rays instead (frames on the ground, no hit)
  private let m_prevQ: Quaternion;     // the attitude a frame ago (the swept contact points)
  private let m_sensUp: Float;         // the sight-view sensor mount (m), from CONFIG
  private let m_sensFwd: Float;
  private let m_show: Float;           // deg, the most the model is drawn leaning, now
  private let m_bone: Vector4;         // the body bone, last measured (world, log)
  private let m_boneOff: Vector4;      // it less the flight's centre when last placed (log)
  private let m_placed: Vector4;       // the flight's centre at the last placement
  private let m_probe: Int32;          // the old inline ground ray, kept as a control (log)
  private let m_groundFrom: String;    // what the last ground ray hit, and how far from its start (log)
  private let m_stickS: Float;
  private let m_climb: Float;          // the climb keys this frame (-1..1)

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
    prof.showTilt = Cast<Float>(cfg.DroneShowTilt(this.m_kind, RoundF(prof.showTilt)));
    prof.tilt = Cast<Float>(cfg.DroneTilt(this.m_kind, RoundF(prof.tilt)));
    prof.tiltRate = Cast<Float>(cfg.DroneRate(this.m_kind, RoundF(prof.tiltRate)));
    // the contact hull from the mesh scan, turned by the drawn pose; the flight starts at the
    // drawn body's centre, so taking over doesn't make it jump
    this.m_hull = CMDroneHull.Points(this.m_kind);
    this.ResetParts();
    this.m_hold = false;
    this.DropShots();
    this.m_tq = CMUDrone.QIdentity();
    this.m_tqSeen = CMUDrone.QIdentity();
    this.m_tt = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_poseOk = false;
    this.m_poseFrames = 0;
    this.m_selfFrames = 10;   // (no learning: each ray skips the drone's own body itself)
    this.m_flLeft = -1;
    this.m_flOn = cfg.DroneFrameLog();
    this.m_flT = 0.0;
    this.m_hasSelf = false;
    ArrayClear(this.m_self);
    this.MeasurePose(drone, 1.0);
    this.UpdateHull();
    this.LoadSensor();
    let start = drone.GetWorldPosition() + CMFlight.QRot(drone.GetWorldOrientation(), this.m_tt + this.m_c);
    this.m_flight = CMFlight.Make(prof, start, CMPilotRig.YawOf(drone.GetWorldForward()));
    this.m_flight.level = Cast<Float>(cfg.DroneLevel(this.m_kind)) / 100.0;
    this.m_prevQ = this.m_flight.q;
    this.m_hidden = false;
    this.m_show = prof.showTilt;
    this.m_placed = this.m_flight.pos;
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
    // Omar's idea: the game keeps running it as an AI NPC, whose hover and altitude logic
    // holds the model up. With the setting on (default), its AI controller is off for the
    // flight (our physics and the entity transform move it; nothing needs its AI).
    this.m_aiOff = this.m_method == 3 || (this.m_method == 4 && cfg.DroneAiOff());
    if this.m_aiOff {
      let ai = drone.GetAIControllerComponent();
      if IsDefined(ai) {
        ai.Toggle(false);
      }
    }
    // the drone's own NPC machinery switched off for the flight (DIAGNOSTICS > DRONE NPC
    // SYSTEMS OFF): its movement and/or its animation, after the pose was measured
    this.m_visTest = cfg.DroneVisualTest();
    this.NpcSystems(drone, false);
    if this.m_visTest >= 2 {
      this.m_poseFrames = 30;   // the skeleton is frozen as measured: hold that pose
    }
    CMCSession.Log("drone: NPC systems off for the flight: " + CMUDrone.VisTestName(this.m_visTest));
    this.LogLoadout(drone);
    CMCSession.Log("drone: drawn pose " + (this.m_poseOk ? "via " + this.m_poseFrom : "not measured") + ", lift " + CMUDrone.V2(this.m_tt) + ", turned " + CMUDrone.V2(CMUDrone.QEuler(this.m_tqSeen)) + " deg, " + IntToString(ArraySize(this.m_hull)) + " contact points, centre " + CMUDrone.V2(this.m_c) + ", sensor " + FloatToStringPrec(this.m_sensUp, 2) + " up " + FloatToStringPrec(this.m_sensFwd, 2) + " fwd");
    CMCSession.Log("drone: " + this.m_name + ", record " + TDBID.ToStringDEBUG(drone.GetRecordID())
      + (this.m_aiOff ? ", AI off" : ", AI on") + ", self-levelling " + IntToString(RoundF(this.m_flight.level * 100.0)) + "%, tilt " + FloatToStringPrec(prof.tilt, 0) + ", rate " + FloatToStringPrec(prof.tiltRate, 0) + ", move method " + CMUDrone.MethodName(this.m_method));
    return "";
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    this.DropShots();
    if this.m_hold {
      // the chase view it was in before the hold, for next time
      this.m_hold = false;
      if this.m_holdChase {
        CMPilotSystem.Get(this.m_game).PutFlag("chaseView", true);
      }
    }
    let drone = this.m_drone;
    if IsDefined(drone) {
      if this.m_hidden {
        this.ShowModel(drone, true);
      }
      if this.m_lmgSound {
        GameObject.PlaySoundEvent(drone, n"w_gun_hmg_militech_fire_auto_stop");
        this.m_lmgSound = false;
      }
      this.NpcSystems(drone, true);
      this.Cancel(drone);
      this.SetGait(drone, n"Walk");   // the drone's own default
      if this.m_aiOff {
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
    this.LoadSensor();   // CONFIG changes apply while flying
    return "";
  }

  public func Name() -> String = this.m_name
  // Where the camera anchors: the drawn body's origin. The drone ticks before the camera
  // (TickFirst), so this is where it is drawn this frame; no lead or guess.

  public func Ground() -> Vector4 {
    if !IsDefined(this.m_flight) {
      return this.m_seen;
    }
    // A frame behind (DIAGNOSTICS > DRONE CAMERA FRAME LAG, 1 by default): the drone is an
    // animated NPC, and its mesh is drawn from the transform it had the frame before, while
    // the camera is drawn where it is set. Framing the current transform, the drawn drone
    // trailed the camera by a frame of its motion, and with every change in frame length
    // that gap changed: the third-person jitter (first person, with nothing of the drone in
    // view, was smooth). The camera now frames the transform the mesh is drawn from.
    let n = ArraySize(this.m_anchors);
    if n == 0 {
      return this.Anchor();
    }
    let i = Max(0, n - 1 - this.m_camLag);
    if this.m_hold && this.m_sight {
      // the gunship hold: the sensor ball under the hull, at its centre (the ring's mount
      // reach and height taken back off), free to look anywhere
      let fl = this.m_flight;
      let v = CMPilotRig.Dir(this.m_rigYaw, 0.0);
      return new Vector4(fl.pos.X - v.X * this.SensorFwd(), fl.pos.Y - v.Y * this.SensorFwd(), fl.pos.Z - fl.p.bottom - 0.25 - this.SensorUp(), 1.0);
    }
    if this.m_sight && IsDefined(this.m_flight) {
      // The sensor is mounted on the drone's heading, level (not pitched or rolled with the
      // model, which put the eye inside the Bombus's shell at its resting lean: a43). It used
      // to sit on the view's heading: when the view swung faster than the drone could turn
      // after it, the eye went out to the drone's side, inside a rotor pod, until the body
      // caught up (Omar: the camera lags behind and plays catch-up). The session's ring adds
      // the mount's reach on the view's heading, so that is taken back off here.
      let fwd = this.SensorFwd();
      let body = CMPilotRig.Dir(this.m_flight.yaw, 0.0);
      let view = CMPilotRig.Dir(this.m_rigYaw, 0.0);
      let a = this.m_anchors[i];
      return new Vector4(a.X + (body.X - view.X) * fwd, a.Y + (body.Y - view.Y) * fwd, a.Z, 1.0);
    }
    return this.m_anchors[i];
  }

  // DIAGNOSTICS > DRONE FRAME LOG: every frame for four seconds, the first time the drone
  // passes 8 m/s. Per frame: its length; the flight's centre; how far the engine had the
  // entity from where it was put the frame before (anything else moving it); where it was
  // put now; the camera's position relative to the drawn origin, and its heading against
  // the drone's. A jitter shows as whichever of these jumps from frame to frame.
  public func FrameLog(s: ref<CMCSession>, dt: Float) -> Void {
    let drone = this.m_drone;
    if !this.m_flOn || !IsDefined(drone) || !IsDefined(this.m_flight) {
      return;
    }
    let fl = this.m_flight;
    if this.m_flLeft < 0 {
      if Vector4.Length(fl.vel) < 8.0 {
        this.m_lastRoot = this.Root();
        return;
      }
      this.m_flLeft = 240;
      CMCSession.Log("frame log: dt ms | speed | engine had it vs put last frame (m) | cam - origin (fwd, side, up m) | cam heading vs drone heading | drawn pitch roll | body bone - where the flight wants it (fwd, side, up m) | cam - body bone (fwd, side, up m)");
    }
    if this.m_flLeft == 0 {
      return;
    }
    this.m_flLeft -= 1;
    this.m_flT += dt;
    let root = this.Root();
    let drift = this.m_seenAtTick - this.m_lastRoot;
    drift.W = 0.0;
    this.m_lastRoot = root;
    let a = this.Ground();
    let rel = s.rig.pos - a;
    let yr = Deg2Rad(this.m_flight.yaw);
    let fwd = new Vector4(-SinF(yr), CosF(yr), 0.0, 0.0);
    let right = new Vector4(CosF(yr), SinF(yr), 0.0, 0.0);
    let shown = Quaternion.ToEulerAngles(fl.Shown(this.m_show));
    // the drawn body: its skeleton-bound body bone, against where the flight puts the body
    // (the flight's centre less the hull's centre, plus the bone's rest place) and against
    // the camera, in the drone's heading frame
    let bone = "n/a";
    let camBone = "n/a";
    let sc = drone.FindComponentByName(Equals(this.m_kind, "octant") ? n"Slot8842" : n"Item_Attachment_Slot") as SlotComponent;
    let wt: WorldTransform;
    if IsDefined(sc) && sc.GetSlotTransform(Equals(this.m_kind, "octant") ? n"l_front_01" : n"Center", wt) {
      let b = WorldPosition.ToVector4(WorldTransform.GetWorldPosition(wt));
      let off = (b - fl.pos) - this.m_boneRel;
      let cb = s.rig.pos - b;
      bone = FloatToStringPrec(Vector4.Dot(off, fwd), 3) + " " + FloatToStringPrec(Vector4.Dot(off, right), 3) + " " + FloatToStringPrec(off.Z, 3);
      camBone = FloatToStringPrec(Vector4.Dot(cb, fwd), 3) + " " + FloatToStringPrec(Vector4.Dot(cb, right), 3) + " " + FloatToStringPrec(cb.Z, 3);
    }
    CMCSession.Log("frame " + FloatToStringPrec(this.m_flT, 3) + " | " + FloatToStringPrec(dt * 1000.0, 1) + " | " + FloatToStringPrec(Vector4.Length(fl.vel), 1)
      + " | " + FloatToStringPrec(Vector4.Length(drift), 3)
      + " | " + FloatToStringPrec(Vector4.Dot(rel, fwd), 3) + " " + FloatToStringPrec(Vector4.Dot(rel, right), 3) + " " + FloatToStringPrec(rel.Z, 3)
      + " | " + FloatToStringPrec(CMPilotRig.Wrap(s.rig.yaw - fl.yaw), 2)
      + " | " + FloatToStringPrec(shown.Pitch, 2) + " " + FloatToStringPrec(shown.Roll, 2) + " | " + bone + " | " + camBone);
    if this.m_flLeft == 0 {
      CMCSession.Log("frame log: done");
    }
  }

  // this frame's drawn origin and sensor, kept for the camera's frame lag
  private func Remember() -> Void {
    let fl = this.m_flight;
    let a = this.Anchor();
    let m = a + CMFlight.QRot(fl.Shown(this.m_show), new Vector4(0.0, this.SensorFwd(), this.SensorUp(), 0.0));
    m.W = 1.0;
    ArrayPush(this.m_anchors, a);
    ArrayPush(this.m_mounts, m);
    if ArraySize(this.m_anchors) > 3 {
      ArrayErase(this.m_anchors, 0);
      ArrayErase(this.m_mounts, 0);
    }
  }
  public func TickFirst() -> Bool = true
  public func Facing() -> Float = IsDefined(this.m_flight) ? this.m_flight.yaw : 0.0
  // the sight view's sensor mount (CONFIG > the drone > OPTICS // SENSOR MOUNT), from the
  // drawn body's origin; by default at its nose, at its centre's height (the mesh scan)
  public func SensorUp() -> Float = this.m_sensUp
  public func SensorFwd() -> Float = this.m_sensFwd
  public func AimSkip() -> Float = 1.5
  // the flight's own tilt, through the camera: the sight view is the true attitude (Omar:
  // in first person it crashes into the floor correctly)
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
    this.m_seenAtTick = actual;
    // a stall: the model moved on but the drone stayed put this frame
    if Vector4.Length(this.m_flight.vel) > 0.5 && Vector4.Distance(actual, this.m_last) < 0.002 {
      this.m_stalls += 1;
    }
    this.m_last = actual;
    this.m_dt = dt;
    // the drawn pose: measured over the first half second (settling from the drone's own
    // hover into ours), then held. Re-measured every frame (a33) it carried the hover
    // animation's sway and a frame's lag at speed into the placement: the jitter.
    if this.m_poseFrames < 30 {
      this.m_poseFrames += 1;
      this.MeasurePose(drone, 0.2);
      this.UpdateHull();
      if this.m_poseFrames == 30 {
        this.m_boneRel = this.m_bone - this.m_placed;   // at rest: the bone's place on the body
      }
    }
    if this.m_method == 2 {
      this.m_flight.pos = actual + new Vector4(0.0, 0.0, this.m_flight.p.com, 0.0);   // the AI does the moving
    } else {
      let err = Vector4.Distance(actual, this.Root());
      this.m_errSum += err;
      this.m_errMax = MaxF(this.m_errMax, err);
      this.m_errN += 1;
    }
    // keys are on or off; a stick isn't: each key ramps the stick in over the type's ramp
    // time, and expo softens the start of its travel, so W eases the drone over instead
    // of slamming it to full tilt
    let keyF = (s.Key(CMCKey.W()) ? 1.0 : 0.0) - (s.Key(CMCKey.S()) ? 1.0 : 0.0);
    let keyS = (s.Key(CMCKey.D()) ? 1.0 : 0.0) - (s.Key(CMCKey.A()) ? 1.0 : 0.0);
    let k = MinF(1.0, dt / MaxF(0.01, this.m_flight.p.ramp));
    this.m_stickF += (keyF - this.m_stickF) * k;
    this.m_stickS += (keyS - this.m_stickS) * k;
    let f = CMUDrone.Expo(this.m_stickF, this.m_flight.p.expo);
    let side = CMUDrone.Expo(this.m_stickS, this.m_flight.p.expo);
    let climb = (s.Key(CMCKey.Up()) ? 1.0 : 0.0) - (s.Key(CMCKey.Down()) ? 1.0 : 0.0);
    this.m_climb = climb;
    // the gunship hold: the keys hold its place, the view looks on its own (the chase
    // view lets go)
    let heading = s.rig.yaw;
    if this.m_hold && !s.SightView() {
      this.SetHold(s, false);
    }
    if this.m_hold {
      this.HoldKeys(s, dt, f, side);
      heading = this.m_holdYaw;
    }
    let from = this.m_flight.pos;
    // the flight model in small steps
    let left = dt;
    while left > 0.0001 {
      let h = MinF(this.SUBSTEP, left);
      this.m_flight.Step(h, f, side, climb, heading);
      left -= h;
    }
    this.Collide(drone, from);
    let fastBefore = this.m_fastHits;
    this.Sweep(drone, from);
    this.Contacts(drone);
    // a self-check: sitting on the ground (the per-group ground ray says so) its lowest
    // contact point must hit; if the one-query filter never does (as the preset queries
    // once returned nothing), the contact rays go back to the per-group queries
    if !this.m_fastOff && this.m_ground >= 0.0 && this.m_ground < -this.Lowest().Z + 0.01 {
      this.m_fastMiss = this.m_fastHits > fastBefore ? 0 : this.m_fastMiss + 1;
      if this.m_fastMiss > 60 {
        this.m_fastOff = true;
        CMCSession.Log("drone: the one-query contact rays found nothing on the ground; per-group rays from now on");
      }
    }
    this.m_prevQ = this.m_flight.q;
    // its own model hidden while looking through its sensor (CONFIG; the Bombus by default)
    let hide = this.m_hideInSight && s.SightView();
    if NotEquals(hide, this.m_hidden) {
      this.ShowModel(drone, !hide);
    }
    this.Place(drone, now);
    this.m_sight = s.SightView();
    this.m_rigYaw = s.rig.yaw;
    let hud = s.Hud() as CMDroneHud;
    if IsDefined(hud) {
      let fl = this.m_flight;
      hud.SetFlight(fl.pitch, fl.roll, Vector4.Length(fl.vel), this.m_ground, fl.vel.Z);
    }
    this.Weapons(s, now, dt, hud);
    this.Remember();
    this.Lean(drone, dt);
    if now >= this.m_logAt {
      this.m_logAt = now + 1.0;
      this.Report(drone);
    }
  }

  // Where the drone's entity origin goes. The flight flies the drawn body's centre (m_c);
  // the body turns about it, and the origin sits off it by the hull's centre and by the
  // hover animation's lift (m_tt): the hover animation holds the body bone well above the
  // origin (the Bombus: 1.68 m), so the origin goes that far down and the drawn body lands
  // on the flight. The origin is then under the road, so nothing else may anchor to it:
  // the cameras use Anchor().
  private func Root() -> Vector4 {
    let fl = this.m_flight;
    let q = fl.Shown(this.m_show);
    let r = this.Anchor() - CMFlight.QRot(q, this.m_tt);
    r.W = 1.0;
    return r;
  }

  // the drawn body's origin (the rest-pose origin, with the lift taken off): the sight
  // view's sensor mount and the chase pivot hang off this. a28 anchored the cameras to the
  // entity origin and the first-person view went 1.7 m under the road.
  private func Anchor() -> Vector4 {
    let fl = this.m_flight;
    let q = fl.Shown(this.m_show);
    let r = fl.pos - CMFlight.QRot(q, this.m_c);
    r.W = 1.0;
    return r;
  }

  // The hover animation's pose of the body bone, as a transform from the rest pose to as
  // drawn, in the entity's frame. Read through skeleton-bound slots (the entity files,
  // WolvenKit): the slot's own offset and turn on the bone are taken off, then the bone's
  // rest pose. Smoothed by `k` per call (the slot reads last frame's pose).
  //   Bombus, Griffin, Wyvern: Item_Attachment_Slot/Center on the body bone (the Wyvern's
  //     sits 0.2 m along the bone; the Bombus's is turned 90 deg about X)
  //   Octant: its Center slot names a Spine bone its rig lacks; Slot8842's two front arm
  //     roots (children of the body bone) are used, their rest positions from the rig
  // Never fx_slots: it isn't bound to the skeleton and gives the entity origin (a23-a26).
  private func MeasurePose(drone: ref<NPCPuppet>, k: Float) -> Void {
    let bindQ = CMUDrone.Q(0.0, 0.7071068, 0.7071068, 0.0);   // every drone rig's body bone
    let comps: array<CName>;
    let slots: array<CName>;
    let relT: array<Vector4>;
    let relQ: array<Quaternion>;
    let bindT: array<Vector4>;
    let none = new Vector4(0.0, 0.0, 0.0, 0.0);
    switch this.m_kind {
      case "bombus":
        comps = [n"Item_Attachment_Slot"];
        slots = [n"Center"];
        relT = [none];
        relQ = [CMUDrone.Q(0.7071068, 0.0, 0.0, 0.7071068)];
        bindT = [new Vector4(0.0, -0.002, 0.127, 0.0)];
        break;
      case "wyvern":
        comps = [n"Item_Attachment_Slot"];
        slots = [n"Center"];
        relT = [new Vector4(0.0, 0.2, 0.0, 0.0)];
        relQ = [CMUDrone.QIdentity()];
        bindT = [none];
        break;
      case "octant":
        comps = [n"Slot8842", n"Slot8842"];
        slots = [n"l_front_01", n"r_front_01"];
        relT = [none, none];
        relQ = [bindQ, bindQ];
        bindT = [new Vector4(-0.75, 0.614, 0.761, 0.0), new Vector4(0.75, 0.614, 0.761, 0.0)];
        break;
      default:   // griffin
        comps = [n"Item_Attachment_Slot"];
        slots = [n"Center"];
        relT = [none];
        relQ = [CMUDrone.QIdentity()];
        bindT = [none];
    }
    let qe = drone.GetWorldOrientation();
    let pe = drone.GetWorldPosition();
    let sumT = new Vector4(0.0, 0.0, 0.0, 0.0);
    let n = 0;
    let rot = CMUDrone.QIdentity();
    let i = 0;
    while i < ArraySize(comps) {
      let sc = drone.FindComponentByName(comps[i]) as SlotComponent;
      let wt: WorldTransform;
      if IsDefined(sc) && sc.GetSlotTransform(slots[i], wt) {
        let sq = WorldTransform.GetOrientation(wt);
        let st = WorldPosition.ToVector4(WorldTransform.GetWorldPosition(wt));
        // the slot's turn on the bone, taken off on either side: whichever leaves the
        // smaller pose turn is the engine's order (they agree when the slot isn't turned)
        let bq1 = CMFlight.QMul(sq, CMUDrone.Conj(relQ[i]));
        let bq2 = CMFlight.QMul(CMUDrone.Conj(relQ[i]), sq);
        let tq1 = CMFlight.QMul(CMFlight.QMul(CMUDrone.Conj(qe), bq1), CMUDrone.Conj(bindQ));
        let tq2 = CMFlight.QMul(CMFlight.QMul(CMUDrone.Conj(qe), bq2), CMUDrone.Conj(bindQ));
        let bq = CMUDrone.QAngle(tq1) <= CMUDrone.QAngle(tq2) ? bq1 : bq2;
        let tq = CMUDrone.QAngle(tq1) <= CMUDrone.QAngle(tq2) ? tq1 : tq2;
        let bt = st - CMFlight.QRot(bq, relT[i]);
        let lt = CMFlight.QInvRot(qe, bt - pe);
        sumT += lt - CMFlight.QRot(tq, bindT[i]);
        n += 1;
        if i == 0 {
          rot = tq;
          this.m_bone = bt;
          this.m_boneOff = bt - this.m_placed;
        }
      }
      i += 1;
    }
    if n == 0 {
      return;
    }
    let t = sumT / Cast<Float>(n);
    t.W = 0.0;
    let len = Vector4.Length(t);
    if len > 4.0 {
      t = t * (4.0 / len);
    }
    if !this.m_poseOk {
      k = 1.0;
      this.m_poseFrom = NameToString(comps[0]) + "/" + NameToString(slots[0]);
    }
    this.m_tt += (t - this.m_tt) * k;
    this.m_tt.W = 0.0;
    // the turn is logged, not applied: in flight it is only the hover animation's sway
    // (Wyvern -5..-10, Octant -20..+13 deg, depending on the moment of take-over; a33 log),
    // and held into the hull it tilted the contact points for the whole flight
    this.m_tqSeen = CMUDrone.QBlend(this.m_tqSeen, rot, k);
    this.m_poseOk = true;
  }

  // the contact hull as drawn (turned by the pose), and its centre: the flight's centre
  // of mass. With the rest pose this is the profile's own centre (Bombus 0.13 m up).
  private func UpdateHull() -> Void {
    ArrayClear(this.m_pts);
    let lo = new Vector4(1000.0, 1000.0, 1000.0, 0.0);
    let hi = new Vector4(-1000.0, -1000.0, -1000.0, 0.0);
    for p in this.m_hull {
      let d = CMFlight.QRot(this.m_tq, p);
      ArrayPush(this.m_pts, d);
      lo = new Vector4(MinF(lo.X, d.X), MinF(lo.Y, d.Y), MinF(lo.Z, d.Z), 0.0);
      hi = new Vector4(MaxF(hi.X, d.X), MaxF(hi.Y, d.Y), MaxF(hi.Z, d.Z), 0.0);
    }
    if ArraySize(this.m_pts) == 0 {
      let com = IsDefined(this.m_flight) ? this.m_flight.p.com : CMDroneProfiles.For(this.m_kind).com;
      this.m_c = new Vector4(0.0, 0.0, com, 0.0);
      return;
    }
    this.m_c = (lo + hi) * 0.5;
    this.m_c.W = 0.0;
  }

  // the sight-view sensor mount from CONFIG (per drone type)
  private func LoadSensor() -> Void {
    let cfg = CMPilotSystem.Get(this.m_game);
    this.m_hideInSight = cfg.DroneHideInSight(this.m_kind);
    this.m_camLag = cfg.DroneCamLag();
    this.m_sensUp = Cast<Float>(cfg.DroneCamUpCm(this.m_kind)) / 100.0;
    this.m_sensFwd = Cast<Float>(cfg.DroneCamFwdCm(this.m_kind)) / 100.0;
  }

  // ---- quaternions (i, j, k, r) ----
  public static func Q(i: Float, j: Float, k: Float, r: Float) -> Quaternion {
    let q: Quaternion;
    q.i = i;
    q.j = j;
    q.k = k;
    q.r = r;
    return q;
  }
  public static func QIdentity() -> Quaternion = CMUDrone.Q(0.0, 0.0, 0.0, 1.0)
  public static func Conj(q: Quaternion) -> Quaternion = CMUDrone.Q(-q.i, -q.j, -q.k, q.r)
  // how far it turns, degrees
  public static func QAngle(q: Quaternion) -> Float = Rad2Deg(2.0 * AcosF(ClampF(AbsF(q.r), 0.0, 1.0)))
  // a step of `k` from a toward b (normalised blend, the short way round)
  public static func QBlend(a: Quaternion, b: Quaternion, k: Float) -> Quaternion {
    let s = a.i * b.i + a.j * b.j + a.k * b.k + a.r * b.r < 0.0 ? -1.0 : 1.0;
    let q = CMUDrone.Q(a.i + (b.i * s - a.i) * k, a.j + (b.j * s - a.j) * k, a.k + (b.k * s - a.k) * k, a.r + (b.r * s - a.r) * k);
    let n = SqrtF(q.i * q.i + q.j * q.j + q.k * q.k + q.r * q.r);
    return n > 0.0001 ? CMUDrone.Q(q.i / n, q.j / n, q.k / n, q.r / n) : CMUDrone.QIdentity();
  }
  // pitch, roll, yaw in degrees (the log)
  public static func QEuler(q: Quaternion) -> Vector4 {
    let e = Quaternion.ToEulerAngles(q);
    return new Vector4(e.Pitch, e.Roll, e.Yaw, 0.0);
  }

  // The nearest thing between two points: the static world, dynamic objects (props the
  // game or a physics mod makes movable) and vehicles. Static-only rays let the drone fly
  // through cars and loose props.
  // The contact rays (24 a frame): one query against the same groups as Ray(), combined in
  // one filter, instead of five.
  // Every ray skips the drone itself: a hit whose entity is the drone (the Octant's shell
  // and thruster pods, the Griffin's body are physical meshes) is passed through, and the
  // ray goes on from just beyond it, up to four times. So the drones that have a body of
  // their own keep every contact (cars shoving them included) and none of their own body
  // counts (Codeware: TraceResult.GetHitEntity).
  private func IsSelf(hit: TraceResult) -> Bool {
    let e = TraceResult.GetHitEntity(hit);
    let drone = this.m_drone;
    return IsDefined(e) && IsDefined(drone) && e.GetEntityID() == drone.GetEntityID();
  }

  private func RayFast(from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    let a = from;
    let i = 0;
    while i < 4 {
      if !this.RayFastOnce(a, to, hit) {
        return false;
      }
      if !this.IsSelf(hit) {
        return true;
      }
      this.m_selfHits += 1;
      let dir = Vector4.Normalize(to - a);
      a = Cast<Vector4>(hit.position) + dir * 0.02;
      a.W = 1.0;
      if Vector4.Dot(to - a, dir) <= 0.0 {
        return false;
      }
      i += 1;
    }
    return false;
  }

  private func Ray(from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    let a = from;
    let i = 0;
    while i < 4 {
      if !this.RayOnce(a, to, hit) {
        return false;
      }
      if !this.IsSelf(hit) {
        return true;
      }
      this.m_selfHits += 1;
      let dir = Vector4.Normalize(to - a);
      a = Cast<Vector4>(hit.position) + dir * 0.02;
      a.W = 1.0;
      if Vector4.Dot(to - a, dir) <= 0.0 {
        return false;
      }
      i += 1;
    }
    return false;
  }

  private func RayFastOnce(from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    if this.m_fastOff {
      return this.RayOnce(from, to, hit);
    }
    let filter: QueryFilter;
    QueryFilter.AddGroup(filter, n"Static");
    QueryFilter.AddGroup(filter, n"Terrain");
    QueryFilter.AddGroup(filter, n"Destructible");
    QueryFilter.AddGroup(filter, n"Dynamic");
    QueryFilter.AddGroup(filter, n"Vehicle");
    let got = GameInstance.GetSpatialQueriesSystem(this.m_game).SyncRaycastByQueryFilter(from, to, filter, hit);
    if got {
      this.m_fastHits += 1;
    }
    return got;
  }

  private func RayOnce(from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    let sq = GameInstance.GetSpatialQueriesSystem(this.m_game);
    // each query in its own result, the nearest kept. The distance is worked out from the
    // X, Y and Z alone: the 6-DOF build compared Vector4 distances against a cast position
    // and no ray ever counted (no ground, no walls: the drones phased through everything)
    let hs: TraceResult;
    let hd: TraceResult;
    let hv: TraceResult;
    // By collision group only. The "World Static" preset queries returned nothing from
    // 2026-09-30 evening on, with or without VAXIS (a19 log: preset 0, group hits every
    // frame), so presets aren't used. Static and Terrain are the world, Destructible the
    // breakables and fences, Dynamic the movable props, Vehicle the cars.
    let gotS = sq.SyncRaycastByCollisionGroup(from, to, n"Static", hs, true, false);
    let ht: TraceResult;
    let gotT = sq.SyncRaycastByCollisionGroup(from, to, n"Terrain", ht, true, false);
    if gotT && (!gotS || CMUDrone.Dist2(from, ht) < CMUDrone.Dist2(from, hs)) {
      hs = ht;
      gotS = true;
    }
    let hx: TraceResult;
    let gotX = sq.SyncRaycastByCollisionGroup(from, to, n"Destructible", hx, true, false);
    if gotX && (!gotS || CMUDrone.Dist2(from, hx) < CMUDrone.Dist2(from, hs)) {
      hs = hx;
      gotS = true;
    }
    let gotD = sq.SyncRaycastByCollisionGroup(from, to, n"Dynamic", hd, true, false);
    let gotV = sq.SyncRaycastByCollisionGroup(from, to, n"Vehicle", hv, true, false);
    let gotG = false;
    let hg: TraceResult;
    let best = 1000000.0;
    let found = false;
    if gotS {
      best = CMUDrone.Dist2(from, hs);
      hit = hs;
      found = true;
    }
    if gotD && CMUDrone.Dist2(from, hd) < best {
      best = CMUDrone.Dist2(from, hd);
      hit = hd;
      found = true;
    }
    if gotV && CMUDrone.Dist2(from, hv) < best {
      best = CMUDrone.Dist2(from, hv);
      hit = hv;
      found = true;
    }
    if gotG && CMUDrone.Dist2(from, hg) < best {
      hit = hg;
      found = true;
    }
    if gotG {
      this.m_hitG += 1;
    }
    if gotS {
      this.m_hitS += 1;
    }
    if gotD {
      this.m_hitD += 1;
    }
    if gotV {
      this.m_hitV += 1;
    }
    if found {
      this.m_rayHits += 1;
    } else {
      this.m_rayMiss += 1;
    }
    return found;
  }

  private static func Dist2(a: Vector4, h: TraceResult) -> Float {
    let x = h.position.X - a.X;
    let y = h.position.Y - a.Y;
    let z = h.position.Z - a.Z;
    return x * x + y * y + z * z;
  }
  // The step from `from` to where the model went, swept against the world. A contact is a
  // rigid-body impulse at the point of the drone that touched (CMFlight.Contact): it stops
  // the motion into the surface, bounces a little off walls, grips and slides on floors,
  // and an off-centre or glancing hit spins it. A hard hit damages it.
  private func Collide(drone: ref<NPCPuppet>, from: Vector4) -> Void {
    let fl = this.m_flight;
    let r = fl.p.radius;
    let hit: TraceResult;
    // (the step is swept by its leading contact points, Sweep(); a ray from the centre
    // crossed the drone's own shell on the way out)
    // the ground under it: measured for the HUD, and a contact only when the drone is in
    // it. There is no minimum height; flying low is the pilot's call.
    // The lowest point of the body at its real attitude: the lowest of its contact points
    // (scanned from its mesh, as drawn). The ray starts a metre up, so a drone already
    // part-way in still finds the surface.
    let low = this.Lowest();
    let r0 = MaxF(0.02, -low.Z);
    fl.grounded = false;
    let clear = 1000.0;   // how far the lowest point is above the ground
    // a drone with a shell of its own looks for the ground from just under its lowest point
    let top = fl.pos.Z + 1.0;   // (the drone's own body is skipped by the ray itself)
    if this.Ray(new Vector4(fl.pos.X, fl.pos.Y, top, 1.0), fl.pos - new Vector4(0.0, 0.0, 40.0, 0.0), hit) {
      let gz = hit.position.Z;
      this.m_groundFrom = FloatToStringPrec(top - gz, 2) + " m below the ray start";
      this.m_ground = fl.pos.Z - gz;
      if fl.pos.Z < gz + r0 + 0.02 {
        fl.grounded = Vector4.Length(fl.vel) < 2.0;
        if !this.m_touchLogged {
          this.m_touchLogged = true;
          CMCSession.Log("drone: touched the ground, base " + FloatToStringPrec(fl.pos.Z - r0 - gz, 2) + " m above the surface the ray found");
        }
      } else {
        this.m_touchLogged = false;
      }
      if fl.pos.Z < gz + r0 {
        fl.pos.Z = gz + r0;
        let up = new Vector4(0.0, 0.0, 1.0, 0.0);
        // at the point that touches: off the centre, it tips the drone onto its other points
        this.Impact(drone, fl.Contact(up, low, 0.0, 0.3));
        if fl.holding {
          fl.holdZ = MaxF(fl.holdZ, fl.pos.Z);
        }
      }
      clear = fl.pos.Z - gz - r0;
      // Settling: released within 30 cm of the ground with no climb key and barely moving,
      // the height hold aims at the ground instead of where the keys were let go, so the
      // drone lands on the road. It used to hold the height Ctrl was released at and hover
      // a hand's width up, which looked like the third-person model floating above where
      // the first-person view sat (a25 log: 0.3 m up, the model exactly at the physics).
      if !fl.grounded && clear < 0.3 && this.m_climb <= 0.05 && this.m_climb >= -0.05 && Vector4.Length(fl.vel) < 1.5 && fl.holding {
        fl.holdZ = gz + r0;
      }
    } else {
      this.m_ground = -1.0;
      this.m_groundFrom = "no ground found";
    }
    // The model's lean cap opens up near the ground: the body touching the road is drawn
    // at its real attitude, pivoting about the centre of mass like the flight, so the third
    // person model sits on the road where the physics (and the first-person view) does.
    // A capped, near-level model held at a steeply pitched body's centre floated above the
    // road (Omar, a23). Within half a metre it blends to the full attitude.
    let near = ClampF(1.0 - clear / 0.5, 0.0, 1.0);
    let want = fl.p.showTilt + (90.0 - fl.p.showTilt) * near;
    this.m_show += (want - this.m_show) * MinF(1.0, this.m_dt * 8.0);
  }
  // the body's reach from its centre along `dir` (unit): the farthest of its contact
  // points that way (the radius and lowest point before the scan)
  private func Extent(dir: Vector4) -> Float {
    let fl = this.m_flight;
    if ArraySize(this.m_pts) == 0 {
      let uz = AbsF(ClampF(fl.Up().Z, -1.0, 1.0));
      let vert = fl.p.bottom * uz + fl.p.span * SqrtF(MaxF(0.0, 1.0 - uz * uz));
      let h = SqrtF(dir.X * dir.X + dir.Y * dir.Y) * fl.p.radius;
      let v = AbsF(dir.Z) * vert;
      return SqrtF(h * h + v * v);
    }
    let best = 0.05;
    for p in this.m_pts {
      best = MaxF(best, Vector4.Dot(CMFlight.QRot(fl.q, p - this.m_c), dir));
    }
    return best;
  }

  // the lowest contact point, from the centre (world axes)
  private func Lowest() -> Vector4 {
    let fl = this.m_flight;
    if ArraySize(this.m_pts) == 0 {
      return new Vector4(0.0, 0.0, -fl.p.bottom, 0.0);
    }
    let low = new Vector4(0.0, 0.0, 1000.0, 0.0);
    for p in this.m_pts {
      let r = CMFlight.QRot(fl.q, p - this.m_c);
      if r.Z < low.Z {
        low = r;
      }
    }
    return low;
  }

  // What the drone really carries and what its record gives it to attack with, for the
  // weapons phase (the Octant first: its machine guns and the game's mortars)
  private func LogLoadout(drone: ref<NPCPuppet>) -> Void {
    let items: array<wref<gameItemData>>;
    GameInstance.GetTransactionSystem(this.m_game).GetItemList(drone, items);
    let names = "";
    for item in items {
      names += (StrLen(names) > 0 ? ", " : "") + TDBID.ToStringDEBUG(ItemID.GetTDBID(item.GetID()));
    }
    CMCSession.Log("drone: carries " + (StrLen(names) > 0 ? names : "nothing"));
    let rec = TweakDBInterface.GetCharacterRecord(drone.GetRecordID());
    if IsDefined(rec) {
      let ab = "";
      let list: array<wref<GameplayAbility_Record>>;
      rec.Abilities(list);
      for a in list {
        ab += (StrLen(ab) > 0 ? ", " : "") + TDBID.ToStringDEBUG(a.GetID());
      }
      CMCSession.Log("drone: record abilities " + ab);

    }
  }

  // The drone's own NPC systems while flown: off as DIAGNOSTICS says, back on at the end.
  // Movement: its character movement, motion planner and drone component (they can smooth
  // or pull the drawn position). Animation: its skeleton and animation controller.
  private func NpcSystems(drone: ref<NPCPuppet>, on: Bool) -> Void {
    let names: array<CName>;
    if this.m_visTest == 1 || this.m_visTest == 3 {
      ArrayPush(names, n"MoveComponent");
      ArrayPush(names, n"moveMotionPlanner5034");
      ArrayPush(names, n"Drone4625");
    }
    if this.m_visTest >= 2 {
      ArrayPush(names, n"root");
      ArrayPush(names, n"AnimationControllerComponent");
    }
    for name in names {
      let c = drone.FindComponentByName(name);
      if IsDefined(c) {
        c.Toggle(on);
      }
    }
  }

  public static func VisTestName(v: Int32) -> String {
    switch v {
      case 1: return "MOVEMENT";
      case 2: return "ANIMATION";
      case 3: return "MOVEMENT + ANIMATION";
    }
    return "NONE";
  }

  // The drone's own model on or off: every mesh, skinned and rigid, drawn with none of its
  // chunks (chunkMask 0), each one's own mask kept to put back. The first try toggled only
  // MeshComponent, and the Bombus's visible parts are entSkinnedMeshComponents (not a kind of
  // MeshComponent): nothing was hidden.
  private let m_hideComps: array<wref<IComponent>>;
  private let m_hideMasks: array<Uint64>;

  private func ShowModel(drone: ref<NPCPuppet>, on: Bool) -> Void {
    if !on {
      ArrayClear(this.m_hideComps);
      ArrayClear(this.m_hideMasks);
      for c in drone.GetComponents() {
        let sk = c as entSkinnedMeshComponent;
        if IsDefined(sk) {
          ArrayPush(this.m_hideComps, c);
          ArrayPush(this.m_hideMasks, sk.chunkMask);
          sk.chunkMask = 0ul;
        } else {
          let m = c as MeshComponent;
          if IsDefined(m) {
            ArrayPush(this.m_hideComps, c);
            ArrayPush(this.m_hideMasks, m.chunkMask);
            m.chunkMask = 0ul;
          }
        }
      }
      CMCSession.Log("drone: model hidden in the sight view (" + IntToString(ArraySize(this.m_hideComps)) + " meshes)");
    } else {
      let i = 0;
      while i < ArraySize(this.m_hideComps) {
        let c = this.m_hideComps[i];
        let sk = c as entSkinnedMeshComponent;
        if IsDefined(sk) {
          sk.chunkMask = this.m_hideMasks[i];
        } else {
          let m = c as MeshComponent;
          if IsDefined(m) {
            m.chunkMask = this.m_hideMasks[i];
          }
        }
        i += 1;
      }
      ArrayClear(this.m_hideComps);
      ArrayClear(this.m_hideMasks);
    }
    this.m_hidden = !on;
  }

  // Each contact point swept from where it was a frame ago to where it is now: a thin post
  // or a fence rail the drone flies into is crossed by the point that hits it, even when it
  // passes between the rays from the centre. The point stops at the surface; the rest is a
  // contact there.
  private func Sweep(drone: ref<NPCPuppet>, from: Vector4) -> Void {
    let fl = this.m_flight;
    if Vector4.Distance(fl.pos, from) < 0.02 {
      return;
    }
    let hit: TraceResult;
    for p in this.m_pts {
      let was = from + CMFlight.QRot(this.m_prevQ, p - this.m_c);
      let r = CMFlight.QRot(fl.q, p - this.m_c);
      let now = fl.pos + r;
      let move = now - was;
      let len = Vector4.Length(move);
      // leading points only: a trailing point's path runs back through the drone's own body
      if len > 0.01 && Vector4.Dot(r, move) > 0.0 && this.m_selfFrames >= 10 {
        let dir = move / len;
        if this.RayFast(was, now + dir * 0.02, hit) && Vector4.Distance(was, Cast<Vector4>(hit.position)) > 0.02 {
          let at = Cast<Vector4>(hit.position);
          let n = CMUDrone.Normal(hit, dir);
          let depth = Vector4.Dot(at - now, n);
          if depth > 0.0 {
            fl.pos += n * (depth + 0.005);
            fl.pos.W = 1.0;
            let floorish = n.Z > 0.6;
            this.Impact(drone, fl.Contact(n, at - fl.pos, floorish ? 0.0 : 0.2, 0.3));
          }
        }
      }
    }
  }

  // A hit's surface normal, facing back along `dir` (the way in). Some hits (cars, props)
  // come back without a usable normal: a zero vector normalised to nothing, so the drone
  // was never pushed out and flew through. Those, and back faces, push straight back.
  public static func Normal(hit: TraceResult, dir: Vector4) -> Vector4 {
    let raw = Cast<Vector4>(hit.normal);
    raw.W = 0.0;
    if Vector4.Length(raw) < 0.5 {
      return dir * -1.0;
    }
    let n = Vector4.Normalize(raw);
    if Vector4.Dot(n, dir) > -0.05 {
      return dir * -1.0;
    }
    return n;
  }

  // The first ten frames of a flight (it is hovering where its AI left it): each contact
  // ray's nearest hit is taken as the drone's own shell. No contacts are made meanwhile.
  private func LearnSelf() -> Void {
    let fl = this.m_flight;
    let hit: TraceResult;
    if ArraySize(this.m_self) != ArraySize(this.m_pts) {
      ArrayClear(this.m_self);
      for p in this.m_pts {
        ArrayPush(this.m_self, -1.0);
      }
    }
    let i = 0;
    for p in this.m_pts {
      let r = CMFlight.QRot(fl.q, p - this.m_c);
      let len = Vector4.Length(r);
      if len > 0.02 && this.RayFast(fl.pos, fl.pos + r + (r / len) * 0.02, hit) {
        let d = Vector4.Distance(fl.pos, Cast<Vector4>(hit.position));
        if this.m_self[i] < 0.0 || d < this.m_self[i] {
          this.m_self[i] = d;
        }
      }
      i += 1;
    }
    this.m_selfFrames += 1;
    if this.m_selfFrames == 10 {
      let n = 0;
      for d in this.m_self {
        if d >= 0.0 {
          n += 1;
        }
      }
      this.m_hasSelf = n > 0;
      CMCSession.Log("drone: its own shell found on " + IntToString(n) + " of " + IntToString(ArraySize(this.m_self)) + " contact rays" + (this.m_hasSelf ? " (ignored on those; the ground ray starts under it)" : ""));
    }
  }

  // the types whose bodies are physical meshes (entity files: entPhysicalMeshComponent
  // thrusters on the Octant, entPhysicalSkinnedMeshComponent body on the Griffin)
  private func ShellKind() -> Bool = Equals(this.m_kind, "octant") || Equals(this.m_kind, "griffin")

  // stick expo: x^3 blended in, soft near the centre, full at the end
  public static func Expo(x: Float, e: Float) -> Float = x * (1.0 - e) + x * x * x * e

  // The mesh contact points: a ray from the centre out to each of the drone's contact
  // points (scanned from its real mesh: rotor and wing tips, nose, tail, belly, gun) against
  // the world, dynamic objects and vehicles. A point inside something pushes the drone out
  // along the surface and is a rigid-body contact at that point, so it rests on whatever
  // part touches, a rotor clipping a wall tips it, and a car driving into it moves it. This
  // replaces the four flat rays at one radius (the drone as a disc).
  private func Contacts(drone: ref<NPCPuppet>) -> Void {
    let fl = this.m_flight;
    let hit: TraceResult;

    let i = -1;
    for p in this.m_pts {
      i += 1;
      let r = CMFlight.QRot(fl.q, p - this.m_c);
      let len = Vector4.Length(r);
      if len > 0.02 {
        let dir = r / len;
        let tip = fl.pos + r;
        let mine = i < ArraySize(this.m_self) ? this.m_self[i] : -1.0;
        // something nearer than its own shell on this ray is the world inside it
        if this.RayFast(fl.pos, tip + dir * 0.02, hit) && (mine < 0.0 || Vector4.Distance(fl.pos, Cast<Vector4>(hit.position)) < mine - 0.03) {
          let at = Cast<Vector4>(hit.position);
          let n = CMUDrone.Normal(hit, dir);
          let depth = Vector4.Dot(at - tip, n);
          if depth > 0.0 {
            fl.pos += n * depth;
            fl.pos.W = 1.0;
            let floorish = n.Z > 0.6;
            this.Impact(drone, fl.Contact(n, at - fl.pos, floorish ? 0.0 : 0.2, 0.3));
            if floorish {
              if Vector4.Length(fl.vel) < 2.0 {
                fl.grounded = true;
              }
              if fl.holding {
                fl.holdZ = MaxF(fl.holdZ, fl.pos.Z);
              }
            }
          }
        }
      }
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
        // orientation; an AI teleport four times a second keeps its movement component where
        // the body is
        let wt: WorldTransform;
        let root = this.Root();
        let world: WorldPosition;
        WorldPosition.SetVector4(world, root);
        WorldTransform.SetWorldPosition(wt, world);
        WorldTransform.SetOrientation(wt, fl.Shown(this.m_show));   // as flown, or the model's lean capped
        this.m_placed = fl.pos;

        drone.SetWorldTransform(wt);
        // the sync lands a frame or more later, by when a fast drone has moved on: sent
        // where it will be, and only once a second (four a second snapped it back at speed:
        // the jitter when flying fast)
        if !this.m_aiOff && now - this.m_cmdAt >= 1.0 {
          let sync = new AITeleportCommand();
          sync.position = root + fl.vel * 0.1;
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
        GameInstance.GetTeleportationFacility(this.m_game).Teleport(drone, this.Root(), e);
        break;
      case 1:
        // a teleport lands the frame after it is sent: sent one frame ahead, it lands
        // where the model is when that frame is drawn. It completes at once, so the last
        // one isn't cancelled (cancelling could drop one still pending: a stalled frame)
        let tp = new AITeleportCommand();
        tp.position = this.Root() + fl.vel * this.m_dt;
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

  // The drone's own locomotion animation, held at a hover in place. Its graph
  // (drone_humanoid) leans, bobs and shifts the body with speed, turn speed and the walk,
  // run or sprint set; the flight's body orientation does all of that now, and an
  // animation pose that changed with speed moved the drawn body off the flight (the
  // jitter in a33, with the pose re-measured every frame).
  private func Lean(drone: ref<NPCPuppet>, dt: Float) -> Void {
    let fl = this.m_flight;
    this.m_lastYaw = fl.yaw;
    let loco = new AnimFeature_DroneLocomotion();
    loco.speed = 0.0;
    loco.desiredSpeed = 0.0;
    loco.angularSpeed = 0.0;
    loco.lookAtAngle = 0.0;
    loco.pathCurvative = 0.0;
    AnimationControllerComponent.ApplyFeature(drone, n"DroneLocomotion", loco);
    // its animation's hover height held at zero, so the model sits where the body is
    let alt = new AnimFeature_DroneActionAltitudeOffset();
    alt.desiredOffset = 0.0;
    AnimationControllerComponent.ApplyFeature(drone, n"ActionAltitudeOffset", alt);
    this.SetGait(drone, n"Walk");
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
    // heights above the surface the ground ray found: the sight-view eye, the drawn body's
    // centre and lowest point (rest pose, as placed)
    let heights = "";
    if this.m_ground >= 0.0 {
      let gz = fl.pos.Z - this.m_ground;
      let eye = this.Anchor().Z + this.SensorUp();
      heights = ", above the road: sight-view eye " + FloatToStringPrec(eye - gz, 2) + " m, body centre " + FloatToStringPrec(fl.pos.Z - gz, 2) + " m, body bottom " + FloatToStringPrec(fl.pos.Z - this.Extent(new Vector4(0.0, 0.0, -1.0, 0.0)) - gz, 2) + " m";
    }
    heights += ", own-body hits skipped " + IntToString(this.m_selfHits) + ", contact rays hit " + IntToString(this.m_fastHits) + (this.m_fastOff ? " (per-group)" : "") + (this.m_hidden ? ", model hidden" : "");
    this.m_fastHits = 0;
    this.m_selfHits = 0;
    CMCSession.Log("drone: " + CMUDrone.MethodName(this.m_method) + ", " + IntToString(this.m_frames) + " frames"
      + (this.m_method == 2 ? "" : ", off by " + FloatToStringPrec(avg, 2) + " m avg / " + FloatToStringPrec(this.m_errMax, 2) + " m max, " + IntToString(stalls) + " stalled frames")
      + ", speed " + FloatToStringPrec(Vector4.Length(fl.vel), 1) + " m/s, climb " + FloatToStringPrec(fl.vel.Z, 1)
      + ", tilt p" + FloatToStringPrec(fl.pitch, 1) + " r" + FloatToStringPrec(fl.roll, 1)
      + ", spool " + FloatToStringPrec(fl.Spool() * 100.0, 0) + "%, " + FloatToStringPrec(this.m_ground, 1) + " m up"
      + ", rays hit " + IntToString(this.m_rayHits) + " / missed " + IntToString(this.m_rayMiss) + " (static " + IntToString(this.m_hitS) + ", dynamic " + IntToString(this.m_hitD) + ", vehicle " + IntToString(this.m_hitV) + "; ground " + this.m_groundFrom + ")" + ", at " + CMCHits.V(this.m_flight.pos)
      + ", gait " + NameToString(this.m_gait) + ", heading " + FloatToStringPrec(fl.yaw, 0)
      + ", drawn pose lift " + CMUDrone.V2(this.m_tt) + " turned " + CMUDrone.V2(CMUDrone.QEuler(this.m_tqSeen))
      + ", body bone " + CMUDrone.V2(this.m_bone) + " vs flight centre " + CMUDrone.V2(this.m_placed) + " (bone less centre " + CMUDrone.V2(this.m_boneOff) + "), model lean cap " + FloatToStringPrec(this.m_show, 0)
      + heights
      + ", real tilt p" + FloatToStringPrec(real.Pitch, 1) + " r" + FloatToStringPrec(real.Roll, 1));
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    this.m_frames = 0;
    this.m_rayHits = 0;
    this.m_rayMiss = 0;
    this.m_hitS = 0;
    this.m_hitD = 0;
    this.m_hitV = 0;
    this.m_hitG = 0;
    this.m_probe = 0;
  }

  // its own display (CMDroneHud), with the damage schematic of its type
  public func NewHud() -> ref<CMPilotHud> {
    let h = new CMDroneHud();
    h.SetKind(this.m_kind);
    return h;
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
    let link = CMLinkSystem.Get(this.m_game);
    st.signal = link.SignalFraction();
    st.distance = MaxF(0.0, link.Distance());
    st.title = this.m_name;
    st.role = CMUDrone.Role(this.m_kind);
    if IsDefined(this.m_flight) {
      let fl = this.m_flight;
      st.speed = Vector4.Length(fl.vel);
      st.alt = this.m_ground >= 0.0 ? this.m_ground : -1.0;
      st.vs = fl.vel.Z;
      st.pitch = fl.pitch;
      st.roll = fl.roll;
      st.spool = fl.Spool();
    }
    // weapons (the Octant's: the mortar, unlimited; the two machine guns, on heat; the
    // missile), the selected one bright
    st.weapon = this.m_wpn;
    st.secSelected = this.m_wpn == 1;
    st.secHeat = this.m_heat;
    st.holdText = this.m_hold ? "GUNSHIP // HOLDING      [H] RELEASE" : "";
    if Equals(this.m_kind, "octant") && ArraySize(this.m_partHp) >= 6 {
      let now = s.Now();
      let gun = this.m_partHp[5] > 0.0;
      st.priText = "MORTAR   x" + IntToString(this.MORTAR_SHELLS) + "  UNLTD   " + (!gun ? "LOST" : (now >= this.m_mortarReady ? (this.m_impactOk ? "RDY" : "NO SOLN") : "RLD " + FloatToStringPrec(this.m_mortarReady - now, 1) + "S"));
      st.secText = "LMG x2         " + (!gun ? "LOST" : (this.m_overheat ? "OVERHEAT" : "HEAT " + IntToString(RoundF(this.m_heat * 100.0)) + "%"));
      st.terText = "MISSILE  LSR   UNLTD   " + (!gun ? "LOST" : (now >= this.m_missileReady ? "RDY" : "RLD " + FloatToStringPrec(this.m_missileReady - now, 1) + "S"));
    } else {
      st.weapon = 0;
      st.priText = "PRI  ----";
      st.secText = "SEC  ----";
      st.terText = "";
    }
    ArrayClear(st.droneParts);
    for hp in this.m_partHp {
      ArrayPush(st.droneParts, hp);
    }
    let lost = 0;
    let i = 0;
    while i < 4 && i < ArraySize(this.m_partHp) {
      if this.m_partHp[i + 1] <= 0.0 {
        lost += 1;
      }
      i += 1;
    }
    st.warning = lost > 0 ? IntToString(lost) + " THRUSTER" + (lost > 1 ? "S" : "") + " LOST" : "";
  }

  public static func Role(kind: String) -> String {
    switch kind {
      case "octant": return "OVERWATCH";
      case "bombus": return "RECON";
      case "griffin": return "STRIKE";
    }
    return "ESCORT";
  }

  // ---- weapons (the Octant): a mortar, two light machine guns, a missile ---------------
  // The Octant carries no weapon items (a44 log: "carries nothing"), so like the Minotaur's
  // missile its weapons are ours: the game's attack system for the damage (V's, so V's
  // kills and heat), the game's effects and sounds for the look. B selects (MORTAR, LMG x2,
  // MISSILE), LMB fires the selected one, G fires a missile whatever is selected.
  //   Mortar, after the Hellhound's (Omar's clip, a55): indirect fire on the ground the
  //     reticle is on, MORTAR_MIN to MORTAR_MAX away. The carrier shell climbs steeply off
  //     the drone, arcs over and bursts high above the spot; MORTAR_SHELLS rounds rain from
  //     the burst onto the ground round it, a blast each. The HUD marks the spot and the
  //     time to impact. Unlimited, MORTAR_COOLDOWN between salvos.
  //   LMG x2: the barrels under the nose take turns at LMG_RATE. A round is a ray from the
  //     barrel through the reticle point with a little spread; what it strikes takes the
  //     hit (a share of its health, LMG_SHARE, between LMG_DAMAGE and LMG_CAP) and nothing
  //     else does. Heat: LMG_HEAT a round, LMG_COOL a second; at full heat they lock until
  //     they're under a third. (a52's rounds were small explosions: weak, and they burst.)
  //   Missile: laser guided (it flies at what the reticle is on while it flies), boosting
  //     to MISSILE_SPEED; it bursts on what it strikes. MISSILE_COOLDOWN apart.
  // Shells and missiles in the air move each frame (Fly); they're dropped when the link
  // closes.
  private let m_wpn: Int32;            // the selected weapon: 0 mortar, 1 LMG x2, 2 missile
  private let m_mortarReady: Float;
  private let m_missileReady: Float;
  private let m_heat: Float;
  private let m_overheat: Bool;
  private let m_lmgNext: Float;
  private let m_lmgLeft: Bool;
  private let m_lmgSound: Bool;
  private let m_impactAt: Vector4;
  private let m_impactOk: Bool;
  private let m_tof: Float;
  private let m_shots: array<ref<CMDroneShot>>;
  private let MORTAR_MIN: Float = 15.0;
  private let MORTAR_MAX: Float = 450.0;
  private let MORTAR_COOLDOWN: Float = 5.0;
  private let MORTAR_SHELLS: Int32 = 4;
  private let MORTAR_FALL: Float = 1.1;      // s, from the burst to the ground
  private let MORTAR_RADIUS: Float = 5.0;
  private let MORTAR_DAMAGE: Float = 450.0;  // each shell
  private let MISSILE_SPEED: Float = 90.0;
  private let MISSILE_COOLDOWN: Float = 3.0;
  private let MISSILE_RADIUS: Float = 4.5;
  private let MISSILE_DAMAGE: Float = 900.0;
  private let MISSILE_LIFE: Float = 7.0;
  private let LMG_RATE: Float = 0.075;
  private let LMG_DAMAGE: Float = 60.0;
  private let LMG_SHARE: Float = 0.05;
  private let LMG_CAP: Float = 400.0;
  private let LMG_HEAT: Float = 0.022;
  private let LMG_COOL: Float = 0.35;

  public static func WeaponName(i: Int32) -> String {
    switch i {
      case 1: return "LMG x2";
      case 2: return "MISSILE";
    }
    return "MORTAR";
  }

  private func Weapons(s: ref<CMCSession>, now: Float, dt: Float, hud: ref<CMDroneHud>) -> Void {
    this.Fly(s, dt);
    if !Equals(this.m_kind, "octant") || ArraySize(this.m_partHp) < 6 {
      return;
    }
    let drone = this.m_drone;
    let gun = this.m_partHp[5] > 0.0;
    // the guns cool
    this.m_heat = MaxF(0.0, this.m_heat - this.LMG_COOL * dt);
    if this.m_overheat && this.m_heat < 0.33 {
      this.m_overheat = false;
      GameObject.PlaySoundEvent(drone, n"w_gun_hmg_militech_overheat_close");
    }
    // the mortar's mark: the ground the reticle is on, when it is in range
    this.AimMortar(s);
    if IsDefined(hud) {
      let o = this.Screen(s, this.m_impactAt);
      hud.SetImpact(gun && this.m_wpn == 0 && this.m_impactOk && AbsF(o.X) < 1900.0 && AbsF(o.Y) < 1050.0, o.X, o.Y, this.m_tof);
    }
    let firing = false;
    if s.Key(CMCKey.Lmb()) && gun {
      if this.m_wpn == 1 {
        firing = this.FireLmg(s, now);
      } else {
        if this.m_wpn == 2 {
          this.FireMissile(s, now);
        } else {
          this.FireMortar(s, now);
        }
      }
    }
    if NotEquals(firing, this.m_lmgSound) {
      this.m_lmgSound = firing;
      GameObject.PlaySoundEvent(drone, firing ? n"w_gun_hmg_militech_fire_auto" : n"w_gun_hmg_militech_fire_auto_stop");
    }
  }

  // B: the next weapon (the Octant's; the other drones have none yet)
  public func Select(s: ref<CMCSession>) -> Bool {
    if !Equals(this.m_kind, "octant") {
      return false;
    }
    this.m_wpn = (this.m_wpn + 1) % 3;
    CMCSession.Log("weapons: " + CMUDrone.WeaponName(this.m_wpn) + " selected");
    return true;
  }

  // G: a missile, whatever is selected
  public func Secondary(s: ref<CMCSession>) -> Void {
    if Equals(this.m_kind, "octant") && ArraySize(this.m_partHp) >= 6 && this.m_partHp[5] > 0.0 {
      this.FireMissile(s, s.Now());
    }
  }

  private func AimMortar(s: ref<CMCSession>) -> Void {
    this.m_impactOk = false;
    if s.aimDist <= 0.0 {
      return;
    }
    let at = s.aim;
    at.W = 1.0;
    this.m_impactAt = at;
    let d = Vector4.Distance(this.m_flight.pos, at);
    this.m_impactOk = d >= this.MORTAR_MIN && d <= this.MORTAR_MAX;
    this.m_tof = this.CarrierTime(at) + this.MORTAR_FALL;
  }

  // the carrier shell's flight: longer the further it goes
  private func CarrierTime(at: Vector4) -> Float = 1.8 + CMUDrone.Flat(this.m_flight.pos, at) / 110.0

  public static func Flat(a: Vector4, b: Vector4) -> Float {
    let dx = b.X - a.X;
    let dy = b.Y - a.Y;
    return SqrtF(dx * dx + dy * dy);
  }

  private func FireMortar(s: ref<CMCSession>, now: Float) -> Void {
    if now < this.m_mortarReady {
      return;
    }
    if !this.m_impactOk {
      GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"ui_hacking_press_fail");
      this.m_mortarReady = now + 0.4;
      return;
    }
    this.m_mortarReady = now + this.MORTAR_COOLDOWN;
    let target = this.m_impactAt;
    let flat = CMUDrone.Flat(this.m_flight.pos, target);
    // off the top of the hull, nearly straight up; over the top of an arc that peaks a
    // quarter of the way along; to the burst, high over the spot
    let shot = new CMDroneShot();
    shot.kind = 0;
    shot.from = this.m_flight.pos + new Vector4(0.0, 0.0, 0.7, 0.0);
    shot.from.W = 1.0;
    shot.to = target + new Vector4(0.0, 0.0, MinF(60.0, 32.0 + flat * 0.06), 0.0);
    shot.to.W = 1.0;
    shot.via = new Vector4(shot.from.X * 0.8 + shot.to.X * 0.2, shot.from.Y * 0.8 + shot.to.Y * 0.2, MaxF(shot.from.Z, shot.to.Z) + 30.0 + flat * 0.25, 1.0);
    shot.target = target;
    shot.life = this.CarrierTime(target);
    shot.pos = shot.from;
    let up = new Vector4(0.0, 0.0, 1.0, 0.0);
    let fx = GameInstance.GetFxSystem(this.m_game);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\av\\av_panzer\\weapons\\v_panzer_rocket_launcher_muzzle.effect"), CMUMinotaur.At(shot.from, up), true);
    shot.fx = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\trails\\smart\\w_trail_rocket_luncher.effect"), CMUMinotaur.At(shot.from, up), true);
    ArrayPush(this.m_shots, shot);
    GameObject.PlaySoundEvent(this.m_drone, n"nme_boss_smasher_wpn_missile_fire_single");
    s.rig.Recoil(0.5);
    CMCSession.Log("mortar: salvo fired at " + CMCHits.V(target) + ", " + FloatToStringPrec(flat, 0) + " m, impact in " + FloatToStringPrec(this.m_tof, 1) + " s");
  }

  // the carrier bursts high over the spot: its rounds fall from there onto the ground
  // round it, a little apart
  private func Burst(c: ref<CMDroneShot>) -> Void {
    let fx = GameInstance.GetFxSystem(this.m_game);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\explosives\\w_explosion_small.effect"), CMUMinotaur.At(c.to, new Vector4(0.0, 0.0, -1.0, 0.0)), true);
    let spread = 3.0 + CMUDrone.Flat(c.from, c.target) * 0.012;
    let i = 0;
    while i < this.MORTAR_SHELLS {
      let a = RandRangeF(0.0, 6.2832);
      let r = spread * SqrtF(RandRangeF(0.05, 1.0));
      let p = new Vector4(c.target.X + CosF(a) * r, c.target.Y + SinF(a) * r, c.target.Z, 1.0);
      // onto the ground there
      let hit: TraceResult;
      if CMGround.World(this.m_game, p + new Vector4(0.0, 0.0, 12.0, 0.0), p - new Vector4(0.0, 0.0, 25.0, 0.0), hit) {
        p = Cast<Vector4>(hit.position);
        p.W = 1.0;
      }
      let r1 = new CMDroneShot();
      r1.kind = 1;
      r1.from = c.to;
      r1.to = p;
      r1.target = p;
      r1.pos = c.to;
      r1.age = -0.14 * Cast<Float>(i);   // waits its turn
      r1.life = this.MORTAR_FALL;
      ArrayPush(this.m_shots, r1);
      i += 1;
    }
  }

  private func Land(p: Vector4) -> Void {
    GameInstance.GetFxSystem(this.m_game).SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\explosives\\w_explosion_medium.effect"), CMUMinotaur.At(p, new Vector4(0.0, 0.0, 1.0, 0.0)), true);
    this.Blast(p, t"Attacks.CM_Mortar", this.MORTAR_RADIUS, this.MORTAR_DAMAGE);
  }

  private func FireMissile(s: ref<CMCSession>, now: Float) -> Void {
    if now < this.m_missileReady {
      return;
    }
    this.m_missileReady = now + this.MISSILE_COOLDOWN;
    let m = new CMDroneShot();
    m.kind = 2;
    m.pos = this.Muzzle(0.0);
    let dir = Vector4.Normalize(s.aim - m.pos);
    m.vel = dir * 30.0 + this.m_flight.vel;
    m.life = this.MISSILE_LIFE;
    let fx = GameInstance.GetFxSystem(this.m_game);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\vehicle_rocket_launcher\\w_special_vehicle_rocket_launcher.effect"), CMUMinotaur.At(m.pos, dir), true);
    m.fx = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\weapons\\v_vehicle_rocket_trail.effect"), CMUMinotaur.At(m.pos, dir), true);
    ArrayPush(this.m_shots, m);
    GameObject.PlaySoundEvent(this.m_drone, n"nme_boss_smasher_wpn_missile_fire_single");
    s.rig.Recoil(0.4);
    CMCSession.Log("missile: launched at " + CMCHits.V(s.aim));
  }

  private func MissileBurst(p: Vector4, dir: Vector4) -> Void {
    let fx = GameInstance.GetFxSystem(this.m_game);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\weapons\\v_vehicle_rocket_impact.effect"), CMUMinotaur.At(p, -dir), true);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\explosives\\w_explosion_medium.effect"), CMUMinotaur.At(p, new Vector4(0.0, 0.0, 1.0, 0.0)), true);
    this.Blast(p, t"Attacks.CM_Missile", this.MISSILE_RADIUS, this.MISSILE_DAMAGE);
  }

  // everything in the air, a frame on
  private func Fly(s: ref<CMCSession>, dt: Float) -> Void {
    let i = 0;
    while i < ArraySize(this.m_shots) {
      let sh = this.m_shots[i];
      sh.age += dt;
      let done = false;
      if sh.kind == 2 {
        done = this.FlyMissile(s, sh, dt);
      } else {
        if sh.age >= 0.0 {
          let u = ClampF(sh.age / sh.life, 0.0, 1.0);
          let p: Vector4;
          if sh.kind == 0 {
            // the carrier: along its arc (a quadratic curve through `via`)
            let a = 1.0 - u;
            p = sh.from * (a * a) + sh.via * (2.0 * a * u) + sh.to * (u * u);
          } else {
            // a round: falling, faster as it goes
            p = sh.from + (sh.to - sh.from) * (u * u);
          }
          p.W = 1.0;
          let dir = Vector4.Normalize(p - sh.pos);
          if !IsDefined(sh.fx) && sh.kind == 1 {
            sh.fx = GameInstance.GetFxSystem(this.m_game).SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\trails\\smart\\w_trail_rocket_luncher.effect"), CMUMinotaur.At(p, dir), true);
          }
          if IsDefined(sh.fx) && Vector4.Length(p - sh.pos) > 0.001 {
            sh.fx.UpdateTransform(CMUMinotaur.At(p, dir));
          }
          sh.pos = p;
          if u >= 1.0 {
            if sh.kind == 0 {
              this.Burst(sh);
            } else {
              this.Land(sh.to);
            }
            done = true;
          }
        }
      }
      if done {
        if IsDefined(sh.fx) {
          sh.fx.BreakLoop();
        }
        ArrayErase(this.m_shots, i);
      } else {
        i += 1;
      }
    }
  }

  // a missile a frame on: it boosts, turns toward the reticle point (the laser) and bursts
  // on what it strikes, or in the air at the end of its fuel. True when it's gone.
  private func FlyMissile(s: ref<CMCSession>, m: ref<CMDroneShot>, dt: Float) -> Bool {
    let speed = MinF(this.MISSILE_SPEED, Vector4.Length(m.vel) + 120.0 * dt);
    let dir = Vector4.Normalize(m.vel);
    if s.aimDist > 0.0 && m.age > 0.15 {
      let want = Vector4.Normalize(s.aim - m.pos);
      dir = Vector4.Normalize(dir + (want - dir) * MinF(1.0, 4.0 * dt));
    }
    m.vel = dir * speed;
    let next = m.pos + m.vel * dt;
    next.W = 1.0;
    let hit: TraceResult;
    if this.ShotRay(m.pos, next, hit) {
      let p = Cast<Vector4>(hit.position);
      p.W = 1.0;
      this.MissileBurst(p, dir);
      return true;
    }
    m.pos = next;
    if IsDefined(m.fx) {
      m.fx.UpdateTransform(CMUMinotaur.At(next, dir));
    }
    if m.age >= m.life {
      this.MissileBurst(next, dir);
      return true;
    }
    return false;
  }

  // the link closed: what's in the air goes with it
  private func DropShots() -> Void {
    for sh in this.m_shots {
      if IsDefined(sh.fx) {
        sh.fx.Kill();
      }
    }
    ArrayClear(this.m_shots);
  }

  private func FireLmg(s: ref<CMCSession>, now: Float) -> Bool {
    if this.m_overheat {
      return false;
    }
    let fired = false;
    while now >= this.m_lmgNext {
      this.m_lmgNext = MaxF(this.m_lmgNext + this.LMG_RATE, now - this.LMG_RATE);
      this.m_lmgLeft = !this.m_lmgLeft;
      let muzzle = this.Muzzle(this.m_lmgLeft ? -0.12 : 0.12);
      let aim = s.aim;
      let dist = Vector4.Distance(muzzle, aim);
      let spread = dist * 0.006;
      aim += new Vector4(RandRangeF(-spread, spread), RandRangeF(-spread, spread), RandRangeF(-spread, spread), 0.0);
      let dir = Vector4.Normalize(aim - muzzle);
      let fx = GameInstance.GetFxSystem(this.m_game);
      fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\militech_hmg\\w_special_hmg_muzzle_tpp.effect"), CMUMinotaur.At(muzzle, dir), true);
      fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\trails\\power\\w_trail_power_hmg_npc.effect"), CMUMinotaur.At(muzzle, dir), true);
      // the round: what's on its line takes it
      let hit: TraceResult;
      let far = muzzle + dir * (dist + 3.0);
      far.W = 1.0;
      if this.ShotRay(muzzle, far, hit) {
        let p = Cast<Vector4>(hit.position);
        p.W = 1.0;
        fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\impacts\\default\\imp_default_norm.effect"), CMUMinotaur.At(p, -dir), true);
        let obj = TraceResult.GetHitEntity(hit) as GameObject;
        if IsDefined(obj) {
          this.Blast(p, t"Attacks.CM_DroneRound", 0.5, this.RoundDamage(obj));
        }
      }
      this.m_heat += this.LMG_HEAT;
      fired = true;
      if this.m_heat >= 1.0 {
        this.m_heat = 1.0;
        this.m_overheat = true;
        GameObject.PlaySoundEvent(this.m_drone, n"w_gun_hmg_militech_overheat_open");
        GameObject.PlaySoundEvent(this.m_drone, n"w_gun_hmg_militech_overheat_steam");
        return false;
      }
    }
    return fired || now < this.m_lmgNext;
  }

  // a round's damage on what it struck: a share of its health, within limits (flat damage
  // was nothing to the game's tougher enemies)
  private func RoundDamage(obj: ref<GameObject>) -> Float {
    let max = GameInstance.GetStatPoolsSystem(this.m_game).GetStatPoolMaxPointValue(Cast<StatsObjectID>(obj.GetEntityID()), gamedataStatPoolType.Health);
    return ClampF(max * this.LMG_SHARE, this.LMG_DAMAGE, this.LMG_CAP);
  }

  // the nearest thing on the line from `a` to `b`, the world or anything that moves, never
  // the drone itself (its shell is passed through); what it struck is the hit's entity
  private func ShotRay(a: Vector4, b: Vector4, out hit: TraceResult) -> Bool {
    let best = -1.0;
    let w: TraceResult;
    if CMGround.World(this.m_game, a, b, w) {
      hit = w;
      best = Vector4.Distance(a, Cast<Vector4>(w.position));
    }
    let from = a;
    let i = 0;
    while i < 4 {
      let m: TraceResult;
      if !CMGround.Movers(this.m_game, from, b, m) {
        break;
      }
      let p = Cast<Vector4>(m.position);
      if !this.IsSelf(m) {
        let d = Vector4.Distance(a, p);
        if best < 0.0 || d < best {
          hit = m;
          best = d;
        }
        break;
      }
      from = p + Vector4.Normalize(b - a) * 0.05;
      i += 1;
    }
    return best >= 0.0;
  }

  // the gun under the nose (the Octant's front gun mesh, rig frame), `side` metres across
  private func Muzzle(side: Float) -> Vector4 {
    let fl = this.m_flight;
    let p = fl.pos + CMFlight.QRot(fl.q, new Vector4(side, 1.45, -0.45, 0.0) - this.m_c);
    p.W = 1.0;
    return p;
  }

  // an area attack at `at`, V's (her kills, XP and heat), on those it hits the drone's
  private func Blast(at: Vector4, rec: TweakDBID, radius: Float, damage: Float) -> Void {
    let player = GetPlayer(this.m_game);
    if !IsDefined(player) {
      return;
    }
    let record = TweakDBInterface.GetAttackRecord(rec) as Attack_GameEffect_Record;
    if !IsDefined(record) {
      record = TweakDBInterface.GetAttackRecord(t"Attacks.FragGrenade") as Attack_GameEffect_Record;
    }
    if !IsDefined(record) {
      return;
    }
    let ctx: AttackInitContext;
    ctx.record = record;
    ctx.instigator = player;
    ctx.source = player;
    let attack = IAttack.Create(ctx) as Attack_GameEffect;
    if !IsDefined(attack) {
      return;
    }
    attack.AddStatModifier(RPGManager.CreateStatModifier(gamedataStatType.PhysicalDamage, gameStatModifierType.Additive, damage));
    let statMods: array<ref<gameStatModifierData>>;
    attack.GetStatModList(statMods);
    let flags: array<SHitFlag>;
    let effect = attack.PrepareAttack(player);
    EffectData.SetFloat(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.radius, radius);
    EffectData.SetVector(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.position, at);
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.attack, ToVariant(attack));
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.attackStatModList, ToVariant(statMods));
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.flags, ToVariant(flags));
    let drone = this.m_drone;
    if IsDefined(drone) {
      CMCHits.Blame(drone, 0.6);
    }
    attack.StartAttack();
  }

  // ---- the gunship hold (H, the Octant): it holds its place, height and heading, and the
  // view is a sensor ball under the hull that looks anywhere (far down too), as a gunship
  // circling a target does. WASD nudge the held place along the view, Space/Ctrl its
  // height. It flies there on its own flight model: the keys it would be given are worked
  // out from where it is against where it should be. H again (or the chase view) lets go.
  private let m_hold: Bool;
  private let m_holdPos: Vector4;
  private let m_holdYaw: Float;
  private let m_holdChase: Bool;       // the chase view was on before (back on letting go)
  private let HOLD_NUDGE: Float = 4.0;  // m/s, WASD moving the held place

  public func Hold(s: ref<CMCSession>) -> Void {
    if !Equals(this.m_kind, "octant") || !IsDefined(this.m_flight) {
      return;
    }
    this.SetHold(s, !this.m_hold);
  }

  private func SetHold(s: ref<CMCSession>, on: Bool) -> Void {
    if Equals(on, this.m_hold) {
      return;
    }
    this.m_hold = on;
    if on {
      let fl = this.m_flight;
      this.m_holdPos = fl.pos + fl.vel * 0.5;   // where it comes to rest
      this.m_holdPos.W = 1.0;
      this.m_holdYaw = fl.yaw;
      this.m_holdChase = !s.SightView();
      if this.m_holdChase {
        s.SetChaseView(false);
      }
      s.rig.SetPitchLimits(-85.0, 30.0);
      CMCSession.Log("gunship: holding at " + CMCHits.V(this.m_holdPos) + ", heading " + FloatToStringPrec(this.m_holdYaw, 0));
    } else {
      s.rig.SetPitchLimits(-35.0, 30.0);
      if this.m_holdChase {
        s.SetChaseView(true);
      }
      CMCSession.Log("gunship: released");
    }
  }

  // the keys that hold it: a speed toward the held place (and the nudge), turned into the
  // tilt keys about its heading
  private func HoldKeys(s: ref<CMCSession>, dt: Float, out f: Float, out side: Float) -> Void {
    let fl = this.m_flight;
    let nf = (s.Key(CMCKey.W()) ? 1.0 : 0.0) - (s.Key(CMCKey.S()) ? 1.0 : 0.0);
    let ns = (s.Key(CMCKey.D()) ? 1.0 : 0.0) - (s.Key(CMCKey.A()) ? 1.0 : 0.0);
    let vf = CMPilotRig.Dir(s.rig.yaw, 0.0);
    let vr = new Vector4(vf.Y, -vf.X, 0.0, 0.0);
    let nudge = (vf * nf + vr * ns) * this.HOLD_NUDGE;
    this.m_holdPos += nudge * dt;
    this.m_holdPos.Z = fl.pos.Z;   // the height is the climb keys' and the flight's own hold
    let err = this.m_holdPos - fl.pos;
    err.Z = 0.0;
    let want = err * 0.8;
    let n = Vector4.Length(want);
    if n > 8.0 {
      want = want * (8.0 / n);
    }
    want += nudge;
    let k = (want - fl.vel) * 0.3;
    let bf = CMPilotRig.Dir(fl.yaw, 0.0);
    let br = new Vector4(bf.Y, -bf.X, 0.0, 0.0);
    f = ClampF(k.X * bf.X + k.Y * bf.Y, -1.0, 1.0);
    side = ClampF(k.X * br.X + k.Y * br.Y, -1.0, 1.0);
  }

  // a world point on the HUD, 4K units from the centre, through the camera as it is drawn
  // (its heading and pitch, and the drone's tilt the camera carries); far off when behind
  private func Screen(s: ref<CMCSession>, p: Vector4) -> Vector2 {
    let tilt = this.CamTilt();
    let k = s.SightView() ? 1.0 : 0.35;
    let e: EulerAngles;
    e.Yaw = s.rig.yaw;
    e.Pitch = s.rig.pitch + tilt.X * k;
    e.Roll = s.rig.roll + tilt.Y * k;
    let d = CMFlight.QInvRot(EulerAngles.ToQuat(e), p - s.rig.pos);
    if d.Y < 0.5 {
      return Vector2(9999.0, 9999.0);
    }
    let scale = 1080.0 / TanF(Deg2Rad(s.rig.fov * 0.5));
    return Vector2(d.X / d.Y * scale, -d.Z / d.Y * scale);
  }

  // ---- part damage (the Octant first): body, the four thrusters, the gun ---------------
  // Each hit lands on the part nearest to where it struck, in the drawn body's frame: the
  // thrusters' pods hang off its sides (rig: front pods at x +-0.88, y 0.59; back at
  // x +-0.88, y -0.57; their meshes reach 0.35 m further out), the gun under the nose. A
  // part wears down by the hit's damage over its share of the hull; a thruster at nothing
  // loses its thrust in the flight model (a quad with a dead rotor can't hold itself up).
  private let m_partHp: array<Float>;

  private func ResetParts() -> Void {
    ArrayClear(this.m_partHp);
    let n = Equals(this.m_kind, "octant") ? 6 : 0;
    let i = 0;
    while i < n {
      ArrayPush(this.m_partHp, 1.0);
      i += 1;
    }
  }

  public static func OctantPartAt(p: Vector4) -> Int32 {
    if p.Y > 1.0 && p.Z < 0.4 {
      return 5;   // the gun
    }
    if AbsF(p.X) > 1.0 {
      if p.Y > 0.0 {
        return p.X < 0.0 ? 1 : 2;   // front left, front right
      }
      return p.X < 0.0 ? 3 : 4;     // back left, back right
    }
    return 0;
  }

  // the parts' share of the hull: a hit worth that much of the hull's maximum destroys it
  public static func OctantShare(i: Int32) -> Float = i == 0 ? 1.0 : (i == 5 ? 0.15 : 0.2)

  public func TakeHit(s: ref<CMCSession>, hit: ref<gameHitEvent>) -> Void {
    let drone = this.m_drone;
    if !IsDefined(drone) || !IsDefined(hit) || !IsDefined(this.m_flight) || ArraySize(this.m_partHp) == 0 {
      return;
    }
    if !IsDefined(hit.attackData) || hit.attackData.HasFlag(hitFlag.DealNoDamage) {
      return;
    }
    let dmg = hit.attackComputed.GetTotalAttackValue(gamedataStatPoolType.Health);
    if dmg <= 0.0 {
      return;
    }
    let fl = this.m_flight;
    // where it struck, in the drawn body's frame (from its origin)
    let local = CMFlight.QInvRot(fl.q, hit.hitPosition - fl.pos) + this.m_c;
    let part = CMUDrone.OctantPartAt(local);
    if part == 0 {
      return;   // the body is the hull
    }
    let hull = GameInstance.GetStatPoolsSystem(this.m_game).GetStatPoolMaxPointValue(Cast<StatsObjectID>(drone.GetEntityID()), gamedataStatPoolType.Health);
    let before = this.m_partHp[part];
    this.m_partHp[part] = MaxF(0.0, before - dmg / MaxF(1.0, hull * CMUDrone.OctantShare(part)));
    if part >= 1 && part <= 4 {
      // front left, front right, back left, back right: the flight model's rotors 0-3
      fl.eff[part - 1] = this.m_partHp[part] > 0.0 ? 1.0 : 0.0;
    }
    if before > 0.0 && this.m_partHp[part] <= 0.0 {
      CMCSession.Log("drone: part " + IntToString(part) + " destroyed (hit " + CMUDrone.V2(local) + ")");
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

  // a vector to the centimetre, for the log
  public static func V2(v: Vector4) -> String = "(" + FloatToStringPrec(v.X, 2) + ", " + FloatToStringPrec(v.Y, 2) + ", " + FloatToStringPrec(v.Z, 2) + ")"

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

// a shell or a missile in the air (CMUDrone.Fly)
public class CMDroneShot {
  public let kind: Int32;        // 0 the mortar's carrier, 1 a mortar round, 2 a missile
  public let from: Vector4;      // carrier and rounds: their path's start, bend and end
  public let via: Vector4;
  public let to: Vector4;
  public let target: Vector4;    // the carrier: the spot its rounds fall round
  public let pos: Vector4;
  public let vel: Vector4;       // the missile
  public let age: Float;         // s in the air (a round below zero waits its turn)
  public let life: Float;        // s: the carrier's and a round's flight, the missile's fuel
  public let fx: ref<FxInstance>;
}