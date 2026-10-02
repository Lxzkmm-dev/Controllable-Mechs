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
// turns it. The flight model (CMFlight) works out the rotors' and the air's force and torque; the MNC Physics plugin flies it as a PhysX body. CONFIG > PROFILE > (the drone) sets its self-levelling (0% = acro), tilt limit
// and rates.
// Collisions: the step is swept against the world; the velocity into a surface is
// removed with a little bounce, and a hard hit damages the drone (a crashed drone is
// lost). Nothing runs unless a drone is piloted.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*
import Codeware.*

public class CMUDrone extends CMCUnit {
  private let m_game: GameInstance;
  private let m_drone: wref<NPCPuppet>;
  private let m_flight: ref<CMFlight>;
  private let m_seen: Vector4;         // where the drone really is (the camera follows this)
  private let m_kind: String;          // bombus, griffin, wyvern, octant
  private let m_name: String;
  private let m_cmd: ref<AICommand>;
  private let m_logAt: Float;
  private let m_frames: Int32;
  private let m_gait: CName;           // the drone locomotion wrapper on (Walk, Run, Sprint)
  private let m_ground: Float;         // metres above the ground, last measured
  private let m_stickF: Float;         // the keys as a stick: ramped in, with expo
  private let m_rayHits: Int32;        // collision rays that found something / didn't (log)
  private let m_rayMiss: Int32;
  private let m_hitS: Int32;           // per query type: static, dynamic, vehicle (log)
  private let m_hitD: Int32;
  private let m_hitV: Int32;
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
  private let m_sight: Bool;           // the sight view is on (from the session, each tick)
  private let m_rigYaw: Float;         // the view's heading, this tick
  private let m_flBodyPrev: Vector4;   // the frame log: the body's place the frame before
  private let m_flLeft: Int32;         // frame-log lines left (-1 = not started)
  private let m_selfHits: Int32;       // rays that passed through the drone's own body (log)
  private let m_flOn: Bool;
  private let m_flT: Float;
  private let m_lastRoot: Vector4;     // where the entity was put last frame
  private let m_boneRel: Vector4;      // the body bone less the flight centre when the pose was held (log)
  private let m_seenAtTick: Vector4;   // where the engine had it at the start of this tick
  private let m_hideInSight: Bool;
  private let m_sensUp: Float;         // the sight-view sensor mount (m), from CONFIG
  private let m_sensFwd: Float;
  private let m_show: Float;           // deg, the most the model is drawn leaning, now
  private let m_bone: Vector4;         // the body bone, last measured (world, log)
  private let m_boneOff: Vector4;      // it less the flight's centre when last placed (log)
  private let m_placed: Vector4;       // the flight's centre at the last placement
  private let m_heldWt: WorldTransform; // the hull's transform from the frame before (placed a frame late)
  private let m_heldOk: Bool;
  private let m_aiSyncAt: Float;       // when its movement is next sent to where it is drawn
  private let m_aiOffAt: Float;        // when its AI goes off again after that (0: off)
  private let m_groundFrom: String;    // what the last ground ray hit, and how far from its start (log)
  private let m_stickS: Float;


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
    // drones fly as real PhysX bodies, which needs the MNC Physics plugin (version 3.1: the
    // body's force each physics step, and its own parts kept from pushing it)
    if !CMPhysStep.Present() || !CMPhysColl.Present() || !CMPhysPlugin.HasVelocity() {
      return "!DRONE FLIGHT NEEDS THE MNC PHYSICS PLUGIN (RED4EXT\\PLUGINS\\MNCPHYSICS)";
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
    this.StopWash();
    this.m_exposure = 1.0;
    this.m_exposureTo = 1.0;
    this.m_exposureAt = 0.0;
    this.m_tq = CMUDrone.QIdentity();
    this.m_tqSeen = CMUDrone.QIdentity();
    this.m_tt = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_poseOk = false;
    this.m_poseFrames = 0;
    this.m_flLeft = -1;
    this.m_flOn = cfg.DroneFrameLog();
    this.m_flT = 0.0;
    this.MeasurePose(drone, 1.0);
    this.UpdateHull();
    this.LoadSensor();
    let start = drone.GetWorldPosition() + CMFlight.QRot(drone.GetWorldOrientation(), this.m_tt + this.m_c);
    this.m_flight = CMFlight.Make(prof, start, CMPilotRig.YawOf(drone.GetWorldForward()));
    this.m_flight.level = Cast<Float>(cfg.DroneLevel(this.m_kind)) / 100.0;
    // its physics body: asked for now; until it is live the drone holds where it is
    this.m_proxyLive = false;
    this.m_proxySpawned = false;
    this.m_proxyBody = null;
    this.StartPhys(drone, s.Now());
    this.m_hidden = false;
    this.m_show = prof.showTilt;
    this.m_placed = this.m_flight.pos;
    this.m_seen = drone.GetWorldPosition();
    this.m_logAt = s.Now() + 1.0;
    this.m_frames = 0;
    this.m_gait = n"";
    this.m_rockets = this.ROCKET_POD;
    this.m_podReady = 0.0;
    this.ApplyParts(false);   // the parts' state as the link kept it (the flight exists now)
    this.m_aiSyncAt = 0.0;
    this.m_aiOffAt = 0.0;
    this.Pacify(drone, true);
    // the game keeps running it as an AI NPC, whose hover and altitude logic would hold the
    // model up: its AI controller is off for the flight (PhysX and the entity transform move
    // it; nothing needs its AI)
    let ai = drone.GetAIControllerComponent();
    if IsDefined(ai) {
      ai.Toggle(false);
    }
    this.LogLoadout(drone);
    CMCSession.Log("drone: drawn pose " + (this.m_poseOk ? "via " + this.m_poseFrom : "not measured") + ", lift " + CMUDrone.V2(this.m_tt) + ", turned " + CMUDrone.V2(CMUDrone.QEuler(this.m_tqSeen)) + " deg, centre " + CMUDrone.V2(this.m_c) + ", sensor " + FloatToStringPrec(this.m_sensUp, 2) + " up " + FloatToStringPrec(this.m_sensFwd, 2) + " fwd");
    CMCSession.Log("drone: " + this.m_name + ", record " + TDBID.ToStringDEBUG(drone.GetRecordID()) + ", self-levelling " + IntToString(RoundF(this.m_flight.level * 100.0)) + "%, tilt " + FloatToStringPrec(prof.tilt, 0) + ", rate " + FloatToStringPrec(prof.tiltRate, 0) + ", flown as a PhysX body (MNC Physics v" + IntToString(CMPhysPlugin.Version()) + ")");
    return "";
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    if ArraySize(this.m_partHp) > 0 && IsDefined(this.m_drone) {
      CMLinkSystem.Get(this.m_game).SetDroneParts(this.m_drone.GetEntityID(), this.m_partHp);
    }
    this.StopPartFx();
    this.UnhidePods();
    this.DropShots();
    this.StopWash();
    this.StopPhys(this.m_drone);
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
      this.Cancel(drone);
      this.SetGait(drone, n"Walk");   // the drone's own default
      // Flown, it is moved by its entity transform with its AI off, so the game's own idea
      // of where it is (its movement) stays where the flight began. Handed back like that,
      // its AI (or its death, for a destroyed drone) put it there again: the wreck appeared
      // in front of V where it was spawned (Omar, Phase 4). It is teleported to where it
      // really is first, then its AI is given back.
      // A destroyed drone keeps its AI off: switched back on, its AI put the wreck back where
      // the flight began (a27, Omar); a wreck needs no AI.
      let here = drone.GetWorldPosition();
      let face: EulerAngles;
      face.Yaw = IsDefined(this.m_flight) ? this.m_flight.yaw : CMPilotRig.YawOf(drone.GetWorldForward());
      let ai = drone.GetAIControllerComponent();
      if ScriptedPuppet.IsAlive(drone) {
        GameInstance.GetTeleportationFacility(this.m_game).Teleport(drone, here, face);
        if IsDefined(ai) {
          ai.Toggle(true);
          let tp = new AITeleportCommand();
          tp.position = here;
          tp.rotation = face.Yaw;
          tp.doNavTest = false;
          ai.SendCommand(tp);
        }
      } else {
        if IsDefined(ai) {
          ai.Toggle(false);
        }
        CMCSession.Log("drone: destroyed at " + CMCHits.V(here) + "; its AI stays off");
        let cb = new CMWreckLogCb();
        cb.drone = drone;
        cb.fell = here;
        GameInstance.GetDelaySystem(this.m_game).DelayCallback(cb, 2.0, false);

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
  // Where the camera anchors: the drawn body's origin, where the body is this frame (the
  // drone ticks before the camera: TickFirst). The camera frame lag (a37, DIAGNOSTICS > DRONE
  // CAMERA FRAME LAG) framed it from one or two frames back and was kept in the settings: the
  // first-person view trailed the drone from then on (Omar, Phase 4); removed in a21.
  public func Ground() -> Vector4 {
    if !IsDefined(this.m_flight) {
      return this.m_seen;
    }
    let fl = this.m_flight;
    if this.m_hold && this.m_sight {
      // the gunship hold: the sensor ball under the hull, at its centre (the ring's mount
      // reach and height taken back off), free to look anywhere
      let v = CMPilotRig.Dir(this.m_rigYaw, 0.0);
      return new Vector4(fl.pos.X - v.X * this.SensorFwd(), fl.pos.Y - v.Y * this.SensorFwd(), fl.pos.Z - fl.p.bottom - 0.25 - this.SensorUp(), 1.0);
    }
    let a = this.Anchor();
    if this.m_sight {
      // The sensor: level on the drone's heading (a43: not pitched with the model, which put
      // the eye inside the Bombus's shell at its resting lean; a48: not on the view's
      // heading, which put it inside a rotor pod while the body turned after the view). The
      // session's ring adds the mount's reach on the view's heading, so that is taken back off.
      let fwd = this.SensorFwd();
      let view = CMPilotRig.Dir(this.m_rigYaw, 0.0);
      let body = CMPilotRig.Dir(fl.yaw, 0.0);
      return new Vector4(a.X + (body.X - view.X) * fwd, a.Y + (body.Y - view.Y) * fwd, a.Z, 1.0);
    }
    return a;
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
        this.m_flBodyPrev = fl.pos;
        return;
      }
      this.m_flLeft = 240;
      CMCSession.Log("frame log: dt ms | speed | engine had it vs put last frame (m) | cam - origin (fwd, side, up m) | cam heading vs drone heading | drawn pitch roll | body bone - where the flight wants it (fwd, side, up m) | cam - body bone (fwd, side, up m) | body moved this frame vs its velocity x dt (m; 0 vs >0 = a stale read)");
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
    let moved = Vector4.Length(fl.pos - this.m_flBodyPrev);
    this.m_flBodyPrev = fl.pos;
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
      + " | " + FloatToStringPrec(shown.Pitch, 2) + " " + FloatToStringPrec(shown.Roll, 2) + " | " + bone + " | " + camBone
      + " | " + FloatToStringPrec(moved, 3) + " vs " + FloatToStringPrec(Vector4.Length(fl.vel) * dt, 3));
    if this.m_flLeft == 0 {
      CMCSession.Log("frame log: done");
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
  public func LightLook() -> Bool = true
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
    // ground effect: the rotors' cushion near the ground (its height from the last frame)
    this.m_flight.SetGround(this.m_ground);
    this.UpdateWind(now, dt);
    if !this.m_proxyLive {
      // its physics body isn't live yet (the first frames): it holds where it is
      this.TryProxy(now);
      this.m_flight.vel = new Vector4(0.0, 0.0, 0.0, 0.0);
      this.m_flight.w = new Vector4(0.0, 0.0, 0.0, 0.0);
    }
    if this.m_proxyLive {
      // PhysX flies and collides its body; the flight model gives the forces
      this.PhysFly(s, drone, f, side, climb, heading, dt, now);
    }
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
    this.Downwash(now);
    this.PartFx();
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
    this.m_lmgArc = Cast<Float>(cfg.OctantLmgArc());
    this.m_podsBreak = cfg.OctantPodsBreak();
    this.m_sensUp = Cast<Float>(cfg.DroneCamUpCm(this.m_kind)) / 100.0;
    this.m_sensFwd = Cast<Float>(cfg.DroneCamFwdCm(this.m_kind)) / 100.0;
    this.m_windK = Cast<Float>(cfg.WindPct()) / 100.0;
  }

  // ---- the wind (CMWind): the air the flight flies through, times CONFIG's WIND
  // STRENGTH and how open the drone is to it (shelter, looked for four times a second and
  // eased, so passing a building's corner isn't a step). Sitting on the ground it is still.
  private let m_windK: Float;
  private let m_exposure: Float;
  private let m_exposureTo: Float;
  private let m_exposureAt: Float;

  private func UpdateWind(now: Float, dt: Float) -> Void {
    let fl = this.m_flight;
    let w = CMWind.Get(this.m_game);
    if this.m_windK <= 0.0 || fl.grounded || !IsDefined(w) {
      fl.wind = new Vector4(0.0, 0.0, 0.0, 0.0);
      return;
    }
    if now >= this.m_exposureAt {
      this.m_exposureAt = now + 0.25;
      this.m_exposureTo = w.Exposure(fl.pos);
    }
    this.m_exposure += (this.m_exposureTo - this.m_exposure) * MinF(1.0, dt * 2.0);
    fl.wind = w.At(fl.pos, this.m_ground) * (this.m_windK * this.m_exposure);
  }

  // the wind on the HUD: where it blows from (compass) and how hard, here
  private func WindText() -> String {
    let w = CMWind.Get(this.m_game);
    if !IsDefined(w) || !IsDefined(this.m_flight) || this.m_windK <= 0.0 {
      return "WIND  OFF";
    }
    let from = RoundF(CMPilotRig.Wrap(-(w.Heading() + 180.0)));
    if from < 0 {
      from += 360;
    }
    let v = this.m_flight.wind;
    return "WIND  " + CMPilotHud.Pad3(from % 360) + " / " + IntToString(RoundF(SqrtF(v.X * v.X + v.Y * v.Y))) + " M/S";
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
    if !IsDefined(e) {
      return false;
    }
    let drone = this.m_drone;
    // the drone's physics body (invisible) is its own too
    return (IsDefined(drone) && e.GetEntityID() == drone.GetEntityID()) || (this.m_proxySpawned && e.GetEntityID() == this.m_proxyId);
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

  // What the drone really carries and what its record gives it to attack with, for the
  // weapons phase (the Octant first: its machine guns and the game's mortars)
  private static func Dist2(a: Vector4, h: TraceResult) -> Float {
    let x = h.position.X - a.X;
    let y = h.position.Y - a.Y;
    let z = h.position.Z - a.Z;
    return x * x + y * y + z * z;
  }

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

  // stick expo: x^3 blended in, soft near the centre, full at the end
  public static func Expo(x: Float, e: Float) -> Float = x * (1.0 - e) + x * x * x * e

  // a collision this fast (m/s): past the type's limit it costs health, more the harder
  // it hits; a crash can destroy the drone (a crashed drone is lost)
  private func Impact(drone: ref<NPCPuppet>, speed: Float) -> Void {
    let limit = this.m_flight.p.impact;
    if speed <= limit {
      return;
    }
    let over = speed - limit;
    let pct = MinF(100.0, over * over * 4.0);
    GameInstance.GetStatPoolsSystem(this.m_game).RequestChangingStatPoolValue(Cast<StatsObjectID>(drone.GetEntityID()), gamedataStatPoolType.Health, -pct, null, false, true);
    GameObject.PlaySoundEvent(drone, n"dev_generic_impact_metal");
    CMCSession.Log("drone: hit something at " + FloatToStringPrec(speed, 1) + " m/s, " + FloatToStringPrec(pct, 0) + "% of its health");
  }

  // put the drone where the model says, by the chosen method
  private func Place(drone: ref<NPCPuppet>, now: Float) -> Void {
    // the entity's own transform set each frame (Codeware) on its physics body's place, with
    // the body's full orientation (its AI is off for the flight: nothing else moves it)
    let fl = this.m_flight;
    let q = fl.Shown(this.m_show);
    let r = this.Root();
    let wt: WorldTransform;
    let world: WorldPosition;
    WorldPosition.SetVector4(world, r);
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, q);
    this.m_placed = fl.pos;
    this.SyncMovement(drone, fl, now);
    // A frame late (a23, confirmed by Omar): the engine draws the pilot camera two frames
    // after it is set and the drone one frame after (a21/a22 frame logs: the engine's camera
    // 2 x v x dt behind where it was put, the drone 1 x v x dt), so the view trailed the
    // drone by a frame however the camera was moved (Omar: the camera lags behind). The
    // hull is placed where the body was the frame before, so both are drawn the same frame.
    if this.m_proxyLive {
      if this.m_heldOk {
        drone.SetWorldTransform(this.m_heldWt);
      } else {
        drone.SetWorldTransform(wt);
      }
      this.m_heldWt = wt;
      this.m_heldOk = true;
      return;
    }
    this.m_heldOk = false;
    drone.SetWorldTransform(wt);
  }

  // The game's own position for it (its movement), kept with where it is drawn: flown by its
  // transform with its AI off, that stayed where the flight began, and a drone destroyed in
  // flight was put back there by its death, in front of V (a28/a29 logs: the wreck 64-68 m
  // from where it went down; moving the wreck after death, 15 times, didn't hold, nor did the
  // teleport facility in flight). The AI's own teleport (the 6-DOF era's way: it moved it
  // within centimetres) does: once a second its AI is on for a moment, sent there, and off.
  private func SyncMovement(drone: ref<NPCPuppet>, fl: ref<CMFlight>, now: Float) -> Void {
    let ai = drone.GetAIControllerComponent();
    if !IsDefined(ai) || !this.m_proxyLive || !this.m_heldOk {
      return;
    }
    if this.m_aiOffAt > 0.0 && now >= this.m_aiOffAt {
      ai.Toggle(false);
      this.m_aiOffAt = 0.0;
      return;
    }
    if now < this.m_aiSyncAt || this.m_aiOffAt > 0.0 {
      return;
    }
    this.m_aiSyncAt = now + 1.0;
    ai.Toggle(true);
    let tp = new AITeleportCommand();
    tp.position = WorldPosition.ToVector4(WorldTransform.GetWorldPosition(this.m_heldWt));
    tp.rotation = fl.yaw;
    tp.doNavTest = false;
    ai.SendCommand(tp);
    this.m_aiOffAt = now + 0.15;
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
    // heights above the surface the ground ray found: the sight-view eye and the body's centre
    let heights = "";
    if this.m_ground >= 0.0 {
      let gz = fl.pos.Z - this.m_ground;
      let eye = this.Anchor().Z + this.SensorUp();
      heights = ", above the road: sight-view eye " + FloatToStringPrec(eye - gz, 2) + " m, body centre " + FloatToStringPrec(fl.pos.Z - gz, 2) + " m";
    }
    if this.m_lmgRounds > 0 {
      heights += ", lmg " + IntToString(this.m_lmgRounds) + " rounds, " + IntToString(this.m_lmgHits) + " struck a target (last " + this.m_lmgLast + "), " + IntToString(this.m_shotSelf) + " steps past its own body";
      this.m_shotSelf = 0;
      this.m_lmgRounds = 0;
      this.m_lmgHits = 0;
    }
    let wv = fl.wind;
    let wname = IsDefined(CMWind.Get(this.m_game)) ? CMWind.Get(this.m_game).Weather() : "?";
    heights += ", wind " + FloatToStringPrec(SqrtF(wv.X * wv.X + wv.Y * wv.Y), 1) + " m/s (vert " + FloatToStringPrec(wv.Z, 1) + ", exposure " + FloatToStringPrec(this.m_exposure, 2) + ", weather " + wname + ")";
    heights += ", ground effect x" + FloatToStringPrec(fl.groundGain, 3) + (IsDefined(this.m_wash) ? " (downwash dust)" : "") + (this.m_hold ? ", gunship hold" : "");
    heights += ", own-body hits skipped " + IntToString(this.m_selfHits) + (this.m_hidden ? ", model hidden" : "");
    this.m_selfHits = 0;
    CMCSession.Log("drone: " + IntToString(this.m_frames) + " frames"
      + ", speed " + FloatToStringPrec(Vector4.Length(fl.vel), 1) + " m/s, climb " + FloatToStringPrec(fl.vel.Z, 1)
      + ", tilt p" + FloatToStringPrec(fl.pitch, 1) + " r" + FloatToStringPrec(fl.roll, 1)
      + ", spool " + FloatToStringPrec(fl.Spool() * 100.0, 0) + "%, " + FloatToStringPrec(this.m_ground, 1) + " m up"
      + ", rays hit " + IntToString(this.m_rayHits) + " / missed " + IntToString(this.m_rayMiss) + " (static " + IntToString(this.m_hitS) + ", dynamic " + IntToString(this.m_hitD) + ", vehicle " + IntToString(this.m_hitV) + "; ground " + this.m_groundFrom + ")" + ", at " + CMCHits.V(this.m_flight.pos)
      + ", gait " + NameToString(this.m_gait) + ", heading " + FloatToStringPrec(fl.yaw, 0)
      + ", drawn pose lift " + CMUDrone.V2(this.m_tt) + " turned " + CMUDrone.V2(CMUDrone.QEuler(this.m_tqSeen))
      + ", body bone " + CMUDrone.V2(this.m_bone) + " vs flight centre " + CMUDrone.V2(this.m_placed) + " (bone less centre " + CMUDrone.V2(this.m_boneOff) + "), model lean cap " + FloatToStringPrec(this.m_show, 0)
      + heights
      + ", real tilt p" + FloatToStringPrec(real.Pitch, 1) + " r" + FloatToStringPrec(real.Roll, 1));
    this.m_frames = 0;
    this.m_rayHits = 0;
    this.m_rayMiss = 0;
    this.m_hitS = 0;
    this.m_hitD = 0;
    this.m_hitV = 0;
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
    st.holdText = this.m_hold ? "GUNSHIP // HOLDING      [" + CMKeys.GunshipName(GetPlayer(this.m_game)) + "] RELEASE" : "";
    st.windText = this.WindText();
    if Equals(this.m_kind, "octant") && ArraySize(this.m_partHp) >= 6 {
      let now = s.Now();
      let gun = this.m_partHp[5] > 0.0;
      let mortar = this.m_partHp[8] > 0.0;
      let pods = this.RocketPods();
      st.priText = "MORTAR   x" + IntToString(this.MORTAR_SHELLS) + "  UNLTD   " + (!mortar ? "LOST" : (now >= this.m_mortarReady ? (this.m_impactOk ? "RDY" : "NO SOLN") : "RLD " + FloatToStringPrec(this.m_mortarReady - now, 1) + "S"));
      st.secText = "LMG x2         " + (!gun ? "LOST" : (this.m_overheat ? "OVERHEAT" : (this.m_offArc ? "OFF ARC" : "HEAT " + IntToString(RoundF(this.m_heat * 100.0)) + "%")));
      st.terText = "ROCKETS  LSR   " + IntToString(this.m_rockets) + "/" + IntToString(pods * 2) + "     " + (pods == 0 ? "LOST" : (this.m_rockets > 0 ? "RDY" : "RLD " + FloatToStringPrec(MaxF(0.0, this.m_podReady - now), 1) + "S"));
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
    // the damaged and lost parts, worst first
    let lostT = "";
    let dmgT = "";
    let i = 1;
    while i < ArraySize(this.m_partHp) {
      if this.m_partHp[i] <= 0.0 {
        lostT += (StrLen(lostT) > 0 ? "  " : "") + CMUDrone.OctantPartName(i);
      } else {
        if this.m_partHp[i] < 0.5 {
          dmgT += (StrLen(dmgT) > 0 ? "  " : "") + CMUDrone.OctantPartName(i);
        }
      }
      i += 1;
    }
    st.warning = (StrLen(lostT) > 0 ? "LOST: " + lostT : "") + (StrLen(lostT) > 0 && StrLen(dmgT) > 0 ? "   " : "") + (StrLen(dmgT) > 0 ? "DMG: " + dmgT : "");
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
  //     to MISSILE_SPEED; it bursts on what it strikes. A Hydra-style pod: ROCKET_POD back
  //     to back, then ROCKET_RELOAD while it reloads (FireMissile).
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
  private let m_lmgRounds: Int32;      // rounds fired and rounds that struck something (log)
  private let m_lmgHits: Int32;
  private let m_lmgLast: String;       // what the last one struck (log)
  private let m_shotSelf: Int32;       // the rounds' ray steps past its own body (log)
  private let m_lmgImpact: Bool;       // the heavy impact effect every other strike
  private let MORTAR_MIN: Float = 15.0;
  private let MORTAR_MAX: Float = 450.0;
  private let MORTAR_COOLDOWN: Float = 5.0;
  private let MORTAR_SHELLS: Int32 = 4;
  private let MORTAR_FALL: Float = 1.1;      // s, from the burst to the ground
  private let MORTAR_RADIUS: Float = 5.0;
  private let MORTAR_DAMAGE: Float = 450.0;  // each shell
  private let MISSILE_SPEED: Float = 90.0;
  private let ROCKET_POD: Int32 = 4;         // rockets in a pod (Omar: like a Hydra pod)
  private let ROCKET_GAP: Float = 0.22;      // s between rockets, back to back
  private let ROCKET_RELOAD: Float = 6.0;    // s for an empty pod to reload
  private let m_rockets: Int32;              // rockets left in the pod
  private let m_podReady: Float;             // when the reloading pod is full again
  private let m_rocketSide: Bool;            // the pod side the next rocket leaves from
  private let m_lmgArc: Float;               // DIAGNOSTICS: the LMGs fire only this far off the nose (deg; 0 = anywhere)
  private let m_offArc: Bool;                // the reticle is outside that arc (HUD)
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
      case 2: return "ROCKETS";
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
    let mortar = this.m_partHp[8] > 0.0;
    // the guns cool
    this.m_heat = MaxF(0.0, this.m_heat - this.LMG_COOL * dt);
    if this.m_overheat && this.m_heat < 0.33 {
      this.m_overheat = false;
      GameObject.PlaySoundEvent(drone, n"w_gun_hmg_militech_overheat_close");
    }
    // the rocket pod reloads once it is empty
    if this.m_rockets <= 0 && this.m_podReady > 0.0 && now >= this.m_podReady {
      this.m_rockets = this.RocketPods() * 2;
      this.m_podReady = 0.0;
      GameObject.PlaySoundEvent(drone, n"w_gun_hmg_militech_overheat_close");
    }
    // the mortar's mark: the ground the reticle is on, when it is in range
    this.AimMortar(s);
    if IsDefined(hud) {
      let o = this.Screen(s, this.m_impactAt);
      hud.SetImpact(gun && this.m_wpn == 0 && this.m_impactOk && AbsF(o.X) < 1900.0 && AbsF(o.Y) < 1050.0, o.X, o.Y, this.m_tof);
    }
    let firing = false;
    if s.Key(CMCKey.Lmb()) {
      if this.m_wpn == 1 {
        if gun {
          firing = this.FireLmg(s, now);
        }
      } else {
        if this.m_wpn == 2 {
          this.FireMissile(s, now);
        } else {
          if mortar {
            this.FireMortar(s, now);
          }
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
    if Equals(this.m_kind, "octant") && ArraySize(this.m_partHp) >= 6 {
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

  // Rockets from a Hydra-style pod (Omar, Phase 4): ROCKET_POD back to back, ROCKET_GAP
  // apart (held or pressed), from the left and right wing pods in turn; an empty pod
  // reloads in ROCKET_RELOAD. Each still flies at what the reticle is on.
  private func FireMissile(s: ref<CMCSession>, now: Float) -> Void {
    let pods = this.RocketPods();
    if now < this.m_missileReady || this.m_rockets <= 0 || pods == 0 {
      return;
    }
    this.m_missileReady = now + this.ROCKET_GAP;
    this.m_rockets -= 1;
    if this.m_rockets == 0 {
      this.m_podReady = now + this.ROCKET_RELOAD;
    }
    this.m_rocketSide = !this.m_rocketSide;
    // a lost pod's side fires nothing: the other pod's
    if ArraySize(this.m_partHp) >= CMUDrone.OctantParts() && pods == 1 {
      this.m_rocketSide = this.m_partHp[6] > 0.0;
    }
    let m = new CMDroneShot();
    m.kind = 2;
    m.pos = this.SlotPos(this.m_rocketSide ? n"Wing1" : n"Wing2", this.Muzzle(this.m_rocketSide ? -0.6 : 0.6));
    let dir = Vector4.Normalize(s.aim - m.pos);
    m.vel = dir * 30.0 + this.m_flight.vel;
    m.life = this.MISSILE_LIFE;
    let fx = GameInstance.GetFxSystem(this.m_game);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\vehicle_rocket_launcher\\w_special_vehicle_rocket_launcher.effect"), CMUMinotaur.At(m.pos, dir), true);
    m.fx = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\weapons\\v_vehicle_rocket_trail.effect"), CMUMinotaur.At(m.pos, dir), true);
    ArrayPush(this.m_shots, m);
    GameObject.PlaySoundEvent(this.m_drone, n"nme_boss_smasher_wpn_missile_fire_single");
    s.rig.Recoil(0.4);
    CMCSession.Log("rocket: launched at " + CMCHits.V(s.aim) + ", " + IntToString(this.m_rockets) + " left in the pod");
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
    // DIAGNOSTICS > OCTANT LMG ARC (a test): the guns only bear this far off the nose
    this.m_offArc = false;
    if this.m_lmgArc > 0.0 {
      let nose = CMFlight.QRot(this.m_flight.q, new Vector4(0.0, 1.0, 0.0, 0.0));
      let to = Vector4.Normalize(s.aim - this.m_flight.pos);
      if Rad2Deg(AcosF(ClampF(Vector4.Dot(nose, to), -1.0, 1.0))) > this.m_lmgArc {
        this.m_offArc = true;
        this.m_lmgNext = MaxF(this.m_lmgNext, now);
        return false;
      }
    }
    let fired = false;
    while now >= this.m_lmgNext {
      this.m_lmgNext = MaxF(this.m_lmgNext + this.LMG_RATE, now - this.LMG_RATE);
      this.m_lmgLeft = !this.m_lmgLeft;
      let muzzle = this.SlotPos(this.m_lmgLeft ? n"front_weapon_l_barrel" : n"front_weapon_r_barrel", this.Muzzle(this.m_lmgLeft ? -0.12 : 0.12));
      let aim = s.aim;
      let dist = Vector4.Distance(muzzle, aim);
      let worn = ArraySize(this.m_partHp) >= CMUDrone.OctantParts() && this.m_partHp[5] < 0.5;
      let spread = dist * (worn ? 0.014 : 0.006);
      aim += new Vector4(RandRangeF(-spread, spread), RandRangeF(-spread, spread), RandRangeF(-spread, spread), 0.0);
      let dir = Vector4.Normalize(aim - muzzle);
      let fx = GameInstance.GetFxSystem(this.m_game);
      // the flash: the HMG's first-person flash through the sensor (the third-person one
      // is too small to see from the nose), its third-person one from the chase view
      if s.SightView() {
        fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\militech_hmg\\w_special_hmg_muzzle.effect"), CMUMinotaur.At(muzzle, dir), true);
      } else {
        fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\militech_hmg\\w_special_hmg_muzzle_tpp.effect"), CMUMinotaur.At(muzzle, dir), true);
      }
      // the round: what's on its line takes it
      let hit: TraceResult;
      let far = muzzle + dir * (dist + 3.0);
      far.W = 1.0;
      let end = far;
      let struck = false;
      let target: wref<GameObject>;
      if this.ShotRay(muzzle, far, hit) {
        end = Cast<Vector4>(hit.position);
        end.W = 1.0;
        struck = true;
        target = TraceResult.GetHitEntity(hit) as GameObject;
      }
      // the barrel's ray missed what the reticle is on (it starts lower, under the nose):
      // the reticle's target, when the round's line passes within 1.5 m of it (a58-a23
      // asked for the round's end within 2.5 m of it, and a round that went on to the
      // ground behind the target never counted)
      let toAim = s.aim - muzzle;
      let along = Vector4.Dot(toAim, dir);
      let off = toAim - dir * along;
      off.W = 0.0;
      if !IsDefined(target) && IsDefined(s.aimEntity) && along > 0.0 && along <= Vector4.Distance(muzzle, end) + 2.0 && Vector4.Length(off) < 1.5 {
        target = s.aimEntity as GameObject;
        end = s.aim;
        end.W = 1.0;
        struck = true;
      }
      // the tracer: a trail stretched from the barrel to where the round ends (a52-a55 gave
      // it no end, so it was drawn zero long: no tracers)
      // the player's HMG trail (heavier and quicker to read than the NPC one, Omar: larger
      // and faster rounds), the Minotaur's treatment
      let tracer = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\trails\\power\\w_trail_power_hmg.effect"), CMUMinotaur.At(muzzle, dir), true);
      if IsDefined(tracer) {
        let wp: WorldPosition;
        WorldPosition.SetVector4(wp, end);
        tracer.UpdateTargetPosition(wp);
      }
      this.m_lmgRounds += 1;
      if struck {
        // the MK.31's explosive-bullet impact every other strike (a look only), else a plain one
        this.m_lmgImpact = !this.m_lmgImpact;
        if this.m_lmgImpact {
          fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\militech_hmg\\w_special_hmg_explosive_bullet.effect"), CMUMinotaur.At(end, -dir), true);
        } else {
          fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\impacts\\default\\imp_default_norm.effect"), CMUMinotaur.At(end, -dir), true);
        }
      }
      s.rig.Recoil(0.12);
      let drone = this.m_drone;
      if IsDefined(target) && (!IsDefined(drone) || target.GetEntityID() != drone.GetEntityID()) {
        // The round's damage straight onto what it struck, V the instigator. a55-a27 sent it
        // as a small area attack: its record's 0.6 m reach left nothing for a target a metre
        // from the area's centre, and its explosion effect went off on every round (Omar).
        let pools = GameInstance.GetStatPoolsSystem(this.m_game);
        let tid = Cast<StatsObjectID>(target.GetEntityID());
        let wasAlive = pools.GetStatPoolValue(tid, gamedataStatPoolType.Health, false) > 0.0;
        pools.RequestChangingStatPoolValue(tid, gamedataStatPoolType.Health, -this.RoundDamage(target), GetPlayer(this.m_game), false, false);
        // the hit marker (the damage pipeline's hook, which shows it for the mech, never
        // sees a direct hit), a kill when this round finished it
        s.RoundHit(wasAlive && pools.GetStatPoolValue(tid, gamedataStatPoolType.Health, false) <= 0.0);
        this.m_lmgHits += 1;
        this.m_lmgLast = NameToString(target.GetClassName());
      }
      this.m_heat += this.LMG_HEAT * (ArraySize(this.m_partHp) >= CMUDrone.OctantParts() && this.m_partHp[5] < 0.5 ? 1.5 : 1.0);
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
  // the drone itself (its shell and its physics body are passed through); what it struck is
  // the hit's entity. The Octant's barrels sit inside its physics body (1.45 m forward of a
  // box 1.70 m deep): a ray from inside it hits it where it starts, and a58-a23 stepped on
  // 5 cm at a time, four times, so no round ever got out of it (Omar: the rounds phase
  // through everything). Half-metre steps, up to ten, clear any of the drones' bodies.
  private func ShotRay(a: Vector4, b: Vector4, out hit: TraceResult) -> Bool {
    let best = -1.0;
    let w: TraceResult;
    if CMGround.World(this.m_game, a, b, w) {
      hit = w;
      best = Vector4.Distance(a, Cast<Vector4>(w.position));
    }
    let from = a;
    let dir = Vector4.Normalize(b - a);
    let i = 0;
    while i < 10 {
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
      this.m_shotSelf += 1;
      from = MaxF(Vector4.Dot(p - a, dir), Vector4.Dot(from - a, dir)) > 0.0 ? a + dir * (MaxF(Vector4.Dot(p - a, dir), Vector4.Dot(from - a, dir)) + 0.5) : a + dir * 0.5;
      from.W = 1.0;
      i += 1;
    }
    return best >= 0.0;
  }

  // A slot on the drawn model (the Octant's barrels and wing pods, from its entity file):
  // where its effects and rounds leave from. a52-a24 worked the barrels out from the hull's
  // centre and put the flashes under the Octant (Omar). `fallback` when no slot has it.
  private func SlotPos(name: CName, fallback: Vector4) -> Vector4 {
    let drone = this.m_drone;
    if IsDefined(drone) {
      for c in drone.GetComponents() {
        let sc = c as SlotComponent;
        let wt: WorldTransform;
        if IsDefined(sc) && sc.GetSlotTransform(name, wt) {
          let p = WorldPosition.ToVector4(WorldTransform.GetWorldPosition(wt));
          if Vector4.Distance(p, this.m_flight.pos) < 6.0 {
            p.W = 1.0;
            return p;
          }
        }
      }
    }
    return fallback;
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

  // ---- the physics body (MNC Physics, version 3 and up; every drone since 0.7.1-a13, when
  // the scripted 6-DOF flight was retired; Omar, 2026-10-01). The drone NPC stays the drone (its health,
  // targeting, hits and kills, its look) and is placed on an invisible physics body every
  // frame (mnc\physics\proxy_<kind>.ent: a box round its hull, its flight profile's mass).
  // PhysX moves and collides the body: it shoves cars and props and is shoved back, with
  // the game's own gravity. Each frame the flight model reads the body's real state (place,
  // attitude, velocity, spin), works out what the rotors and the air do (CMFlight.Step's
  // force and torque) and the plugin applies that force before every physics step; the drone turns with its
  // own inertia from the spin the body has now (so a knock's spin is kept), set through the
  // body's own spin. The NPC's own physical parts stop colliding while it flies (they would
  // shove the body: the old self-collision), and get it back after. Until the body is live
  // (and while a lost one is asked for again) the drone holds where it is.
  private let m_proxyId: EntityID;
  private let m_proxySpawned: Bool;
  private let m_proxyLive: Bool;
  private let m_proxyAt: Float;
  private let m_proxyLiveAt: Float;    // when the body went live (knocks do no damage while it settles)
  private let m_proxyBody: ref<PhysicalBodyInterface>;
  private let m_physOffColliders: array<wref<IComponent>>;
  private let m_physOffMeshes: array<wref<IComponent>>;
  private let m_physVel: Vector4;
  private let m_physLogAt: Float;
  private let m_physKnock: Float;      // the biggest change of velocity in a frame since the last log
  private let m_physSkinned: array<wref<IComponent>>;  // its own physical skinned meshes (the Griffin's body)
  private let m_podBodies: array<ref<PhysicalBodyInterface>>;  // its own physical meshes' bodies
                                       // (the Octant's thruster pods), kept from pushing the body

  private func StartPhys(drone: ref<NPCPuppet>, now: Float) -> Void {
    this.PhysCollisions(drone, false);
    // the bodies of its own physical meshes (the Octant's four thruster pods): kinematic,
    // moved with the NPC onto the physics body every frame, so inside it; PhysX shoved the
    // body out at 16-18 m/s the moment it went live (a10). Each frame they are asked to push
    // nothing (MNC Physics v3.1; bullets and rays still hit them).
    ArrayClear(this.m_podBodies);
    for c in this.m_physOffMeshes {
      let pm = c as PhysicalMeshComponent;
      if IsDefined(pm) {
        let b = pm.CreatePhysicalBodyInterface();
        if IsDefined(b) {
          ArrayPush(this.m_podBodies, b);
        }
      }
    }
    // a physical skinned mesh (the Griffin's body) has no script-declared body accessor: its
    // CreatePhysicalBodyInterface through Codeware's Reflection
    // (MNC Physics v3.2 hands it over: the native makes it, scripts just get nothing back)
    let skinned = 0;
    for c in this.m_physSkinned {
      let sb = CMPhysBodies.Of(c);
      if !IsDefined(sb) {
        sb = CMUDrone.SkinnedBody(c);
      }
      if IsDefined(sb) {
        ArrayPush(this.m_podBodies, sb);
        skinned += 1;
      }
    }
    if ArraySize(this.m_physOffMeshes) + ArraySize(this.m_physSkinned) > 0 {
      CMCSession.Log("drone body: its own physical parts: " + IntToString(ArraySize(this.m_physOffMeshes)) + " meshes, " + IntToString(ArraySize(this.m_physSkinned)) + " skinned meshes (" + IntToString(skinned) + " bodies taken" + (ArraySize(this.m_physSkinned) > skinned ? (CMPhysBodies.Present() ? "; some gave no body" : "; NEEDS MNC PHYSICS 3.2") : "") + "); " + IntToString(ArraySize(this.m_podBodies)) + " kept from pushing the body");
    }
    // the pods go off first; the body is spawned a quarter second later (TryProxy), once the
    // plugin has taken them off at its physics steps, so nothing of its own is inside it
    this.PodsOff();
    this.m_proxySpawned = false;
    this.m_proxyLive = false;
    this.m_proxyAt = now;
    this.m_physKnock = 0.0;
  }

  private func SpawnProxy(now: Float) -> Void {
    let spec = new DynamicEntitySpec();
    switch this.m_kind {
      case "octant":
        spec.templatePath = r"mnc\\physics\\proxy_octant.ent";
        break;
      case "bombus":
        spec.templatePath = r"mnc\\physics\\proxy_bombus.ent";
        break;
      case "griffin":
        spec.templatePath = r"mnc\\physics\\proxy_griffin.ent";
        break;
      default:
        spec.templatePath = r"mnc\\physics\\proxy_wyvern.ent";
    }
    spec.position = this.m_flight.pos;
    let face: EulerAngles;
    face.Yaw = this.m_flight.yaw;
    spec.orientation = EulerAngles.ToQuat(face);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"MNCPhysDrone"];
    this.m_proxyId = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    this.m_proxySpawned = true;
    this.m_proxyLive = false;
    this.m_proxyAt = now;
    this.m_physKnock = 0.0;
    CMCSession.Log("drone body: physics body asked for at " + CMCHits.V(spec.position) + " (" + "proxy_" + this.m_kind + "), " + IntToString(ArraySize(this.m_physOffColliders)) + " of its colliders and " + IntToString(ArraySize(this.m_physOffMeshes)) + " physical meshes off");
  }

  // the body, once it is placed and simulated: the flight hands its motion over to it
  private func TryProxy(now: Float) -> Void {
    this.PodsOff();
    if !this.m_proxySpawned {
      if now - this.m_proxyAt >= 0.25 {
        this.SpawnProxy(now);
      }
      return;
    }
    let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_proxyId);
    if !IsDefined(e) || Vector4.Length(e.GetWorldPosition()) < 1.0 {
      if now - this.m_proxyAt > 10.0 {
        // (is mnc\physics\proxy_<kind>.ent in the archive?) asked for again
        CMCSession.Log("drone body: the physics body never appeared in 10 s; asking again");
        GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_proxyId);
        this.m_proxySpawned = false;
        this.m_proxyAt = now;
      }
      return;
    }
    let body = this.PhysBody(e);
    if !IsDefined(body) || !body.IsSimulated() {
      return;
    }
    let fl = this.m_flight;
    this.m_proxyLive = true;
    this.m_proxyLiveAt = now;
    this.m_physVel = fl.vel;
    CMPhysPlugin.SetVelocity(body, fl.vel);
    CMPhysPlugin.SetSpin(body, CMFlight.QRot(fl.q, fl.w));
    CMCSession.Log("drone body: physics body live after " + FloatToStringPrec(now - this.m_proxyAt, 2) + " s, at " + CMCHits.V(e.GetWorldPosition()) + "; PhysX flies it now");
  }

  // a working handle on the body (taken again whenever it isn't simulated)
  private func PhysBody(e: ref<Entity>) -> ref<PhysicalBodyInterface> {
    if IsDefined(this.m_proxyBody) && this.m_proxyBody.IsSimulated() {
      return this.m_proxyBody;
    }
    let c = e.FindComponentByName(n"proxy_body") as ColliderComponent;
    if IsDefined(c) {
      this.m_proxyBody = c.CreatePhysicalBodyInterface();
    }
    return this.m_proxyBody;
  }

  // its own pods push nothing while it flies (asked again every frame, as the wishes
  // are dropped 0.3 s after the last ask)
  private func PodsOff() -> Int32 {
    let n = 0;
    for b in this.m_podBodies {
      if IsDefined(b) && CMPhysColl.SetCollision(b, false) {
        n += 1;
      }
    }
    return n;
  }

  private func PhysFly(s: ref<CMCSession>, drone: ref<NPCPuppet>, f: Float, side: Float, climb: Float, heading: Float, dt: Float, now: Float) -> Void {
    let fl = this.m_flight;
    this.PodsOff();
    let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_proxyId);
    let body = IsDefined(e) ? this.PhysBody(e) : null;
    if !IsDefined(body) {
      // the body is gone (streamed out, removed): a new one is asked for where the drone is,
      // which holds still meanwhile
      CMCSession.Log("drone body: the physics body was lost; asking for a new one");
      if IsDefined(e) {
        GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_proxyId);
      }
      this.m_proxyLive = false;
      this.m_proxySpawned = false;
      this.m_proxyBody = null;
      this.m_proxyAt = now;
      return;
    }
    // the body's real state
    fl.pos = e.GetWorldPosition();
    fl.pos.W = 1.0;
    fl.q = e.GetWorldOrientation();
    let v = CMPhysStep.Velocity(body);
    fl.vel = v;
    fl.w = CMFlight.QInvRot(fl.q, CMPhysStep.Spin(body));
    fl.Sync();
    // a knock: a sudden change of velocity (a crash, or something hit it)
    let dv = Vector4.Length(v - this.m_physVel);
    this.m_physVel = v;
    this.m_physKnock = MaxF(this.m_physKnock, dv);
    // a knock does damage once the body has settled: in its first half second a push from
    // anything it was spawned into is logged, not taken as a crash (a12's Griffin died to
    // its own parts at link-in)
    if dv > fl.p.impact {
      if now - this.m_proxyLiveAt >= 0.5 {
        this.Impact(drone, dv);
      } else {
        CMCSession.Log("drone body: knocked at " + FloatToStringPrec(dv, 1) + " m/s while settling (no damage)");
      }
    }
    this.PhysGround();
    // what the rotors and the air do (the flight model, forces only)
    fl.Step(dt, f, side, climb, heading);
    // it turns with its own inertia, from the spin it has now
    let t = fl.outTorque;
    let wb = fl.w + new Vector4(t.X / fl.Ix() * dt, t.Y / fl.Ix() * dt, t.Z / fl.Iz() * dt, 0.0);
    CMPhysPlugin.SetSpin(body, CMFlight.QRot(fl.q, wb));
    CMPhysStep.SetForce(body, fl.outForce, new Vector4(0.0, 0.0, 0.0, 0.0));
    // the Wind Framework's prop drag leaves it alone (MNC's flight model has the air)
    CMPhysWind.IgnoreNear(7310 + CMUDrone.KindIndex(this.m_kind), fl.pos, fl.p.span + 1.0);
    if now >= this.m_physLogAt {
      this.m_physLogAt = now + 1.0;
      CMCSession.Log("drone body: at " + CMCHits.V(fl.pos) + ", speed " + FloatToStringPrec(Vector4.Length(v), 1) + " m/s, spin " + FloatToStringPrec(Vector4.Length(fl.w), 2) + " rad/s, rotor force " + CMCHits.V(fl.outForce) + " N, " + FloatToStringPrec(this.m_ground, 1) + " m up, biggest knock " + FloatToStringPrec(this.m_physKnock, 1) + " m/s; " + CMPhysStep.Info(body) + (ArraySize(this.m_podBodies) > 0 ? "; pods (" + IntToString(ArraySize(this.m_podBodies)) + ", collision " + (CMPhysColl.Present() ? "off" : "NOT HANDLED: needs MNC Physics 3.1") + "): first " + CMPhysStep.Info(this.m_podBodies[0]) : ""));
      this.m_physKnock = 0.0;
    }
  }

  // the ground under it (the HUD, the ground effect, the height hold's settling); PhysX
  // does the touching
  private func PhysGround() -> Void {
    let fl = this.m_flight;
    let hit: TraceResult;
    let top = fl.pos.Z + 1.0;
    if this.Ray(new Vector4(fl.pos.X, fl.pos.Y, top, 1.0), fl.pos - new Vector4(0.0, 0.0, 40.0, 0.0), hit) {
      this.m_ground = fl.pos.Z - hit.position.Z;
      this.m_groundFrom = "body ground ray";
      fl.grounded = this.m_ground < fl.p.bottom + 0.08 && Vector4.Length(fl.vel) < 2.0;
    } else {
      this.m_ground = -1.0;
      fl.grounded = false;
    }
    this.m_show = 90.0;   // drawn as flown: the body is real
  }

  // the NPC's own colliders and physical meshes, off while it flies (back on after)
  private func PhysCollisions(drone: ref<NPCPuppet>, on: Bool) -> Void {
    if !on {
      ArrayClear(this.m_physOffColliders);
      ArrayClear(this.m_physOffMeshes);
      ArrayClear(this.m_physSkinned);
      for c in drone.GetComponents() {
        if c.IsA(n"entColliderComponent") || c.IsA(n"entSimpleColliderComponent") {
          if c.IsEnabled() {
            c.Toggle(false);
            ArrayPush(this.m_physOffColliders, c);
          }
        } else {
          if c.IsA(n"entPhysicalMeshComponent") && CMUDrone.MeshCollision(c, false) {
            ArrayPush(this.m_physOffMeshes, c);
          } else {
            if c.IsA(n"entPhysicalSkinnedMeshComponent") {
              ArrayPush(this.m_physSkinned, c);   // (the Griffin's body: its body is taken off in StartPhys)
            }
          }
        }
      }
      return;
    }
    for c in this.m_physOffColliders {
      if IsDefined(c) {
        c.Toggle(true);
      }
    }
    for c in this.m_physOffMeshes {
      if IsDefined(c) {
        CMUDrone.MeshCollision(c, true);
      }
    }
    ArrayClear(this.m_physOffColliders);
    ArrayClear(this.m_physOffMeshes);
  }

  // a physical skinned mesh's body (body 0), through Reflection; none if it won't give one
  private static func SkinnedBody(c: ref<IComponent>) -> ref<PhysicalBodyInterface> {
    let cls = Reflection.GetClass(n"entPhysicalSkinnedMeshComponent");
    let fn = IsDefined(cls) ? cls.GetFunction(n"CreatePhysicalBodyInterface") : null;
    if !IsDefined(fn) {
      return null;
    }
    let ok = false;
    let args: array<Variant>;
    let params = fn.GetParameters();
    if ArraySize(params) > 0 {
      if Equals(params[0].GetType().GetName(), n"Uint32") {
        ArrayPush(args, ToVariant(0u));
      } else {
        ArrayPush(args, ToVariant(0));
      }
    }
    let v = fn.Call(c, args, ok);
    if !ok || !IsDefined(v) {
      return null;
    }
    return FromVariant<ref<PhysicalBodyInterface>>(v);
  }

  // PhysicalMeshComponent.ToggleCollision: in the engine's type info with its parameter, but
  // not declared to scripts; called through Codeware's Reflection
  private static func MeshCollision(c: ref<IComponent>, on: Bool) -> Bool {
    let cls = Reflection.GetClass(n"entPhysicalMeshComponent");
    let fn = IsDefined(cls) ? cls.GetFunction(n"ToggleCollision") : null;
    if !IsDefined(fn) {
      return false;
    }
    let ok = false;
    fn.Call(c, [ToVariant(on)], ok);
    return ok;
  }

  private func StopPhys(drone: ref<NPCPuppet>) -> Void {
    // (also when the link closes before the body was spawned: the drone's own collisions
    // and pods were already taken off)
    if !this.m_proxySpawned && ArraySize(this.m_podBodies) == 0 && ArraySize(this.m_physOffColliders) == 0 && ArraySize(this.m_physOffMeshes) == 0 {
      return;
    }
    if this.m_proxySpawned {
      let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_proxyId);
      if IsDefined(e) {
        let body = this.PhysBody(e);
        if IsDefined(body) {
          CMPhysStep.Release(body);
        }
      }
      GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_proxyId);
    }
    this.m_proxySpawned = false;
    this.m_proxyLive = false;
    this.m_proxyBody = null;
    for b in this.m_podBodies {
      if IsDefined(b) {
        CMPhysColl.SetCollision(b, true);
      }
    }
    ArrayClear(this.m_podBodies);
    if IsDefined(drone) {
      this.PhysCollisions(drone, true);
    }
    CMCSession.Log("drone body: physics body removed, the drone's own collisions back on");
  }

  // ---- the downwash: low over the ground, the rotors kick up dust (the game's AV dust
  // kick-up, moved under the drone every frame). Its emitters loop for an effect 6 s long,
  // so a fresh one takes over every WASH_RENEW seconds. Below WashHeight() only: the
  // bigger the drone, the higher its wash reaches the ground.
  private let m_wash: ref<FxInstance>;
  private let m_washAt: Float;
  private let WASH_RENEW: Float = 4.0;

  private func WashHeight() -> Float {
    switch this.m_kind {
      case "bombus": return 1.2;
      case "octant": return 6.0;
    }
    return 3.5;
  }

  private func Downwash(now: Float) -> Void {
    let fl = this.m_flight;
    if this.m_ground < 0.0 || this.m_ground > this.WashHeight() {
      this.StopWash();
      return;
    }
    let p = new Vector4(fl.pos.X, fl.pos.Y, fl.pos.Z - this.m_ground + 0.05, 1.0);
    let up = new Vector4(0.0, 0.0, 1.0, 0.0);
    if !IsDefined(this.m_wash) || now >= this.m_washAt {
      if IsDefined(this.m_wash) {
        this.m_wash.BreakLoop();
      }
      this.m_wash = GameInstance.GetFxSystem(this.m_game).SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\av\\v_av_dust_kickup_no_debris.effect"), CMUMinotaur.At(p, up), true);
      this.m_washAt = now + this.WASH_RENEW;
      return;
    }
    this.m_wash.UpdateTransform(CMUMinotaur.At(p, up));
  }

  private func StopWash() -> Void {
    if IsDefined(this.m_wash) {
      this.m_wash.BreakLoop();
    }
    this.m_wash = null;
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
  private let m_holdTrim: Vector4;     // the lean the wind needs, learned (key units, world)
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
      this.m_holdTrim = new Vector4(0.0, 0.0, 0.0, 0.0);
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
    // a steady wind needs a steady lean into it: a slow trim learns it, so the hold sits on
    // its place instead of a little downwind of it
    this.m_holdTrim += err * (0.06 * dt);
    let tn = Vector4.Length(this.m_holdTrim);
    if tn > 0.6 {
      this.m_holdTrim = this.m_holdTrim * (0.6 / tn);
    }
    let k = (want - fl.vel) * 0.3 + this.m_holdTrim;
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

  // ---- part damage (the Octant): its hull and nine parts ----------------------------------
  // 0 hull, 1-4 the thruster pods (front left, front right, back left, back right: the flight
  // model's rotors 0-3), 5 the LMG turret under the nose, 6 and 7 the left and right rocket
  // pods, 8 the mortar launcher on top, 9 the sensor. A hit lands on the part whose point on
  // the drawn model (its entity's slots: Engine1-4, the barrels, Wing1/2, Perception; the
  // mortar on top of the hull) is nearest, within that part's reach, else on the hull. A part
  // wears down by the hit's damage over its share of the hull (OctantShare).
  //   pods: thrust falls with damage (35% left just before it goes, nothing once destroyed),
  //     smoke under half, fire and sparks when destroyed; destroyed, it either breaks off
  //     (its mesh gone, a burst) or burns on (DIAGNOSTICS > OCTANT POD DESTROYED)
  //   LMG: damaged, wider spread and quicker heat; destroyed, offline
  //   rocket pods: each its half of the salvo; mortar: destroyed, no mortar
  //   sensor: damaged, a warning; destroyed, no optics (as the Minotaur's)
  //   hull: smoke under half its health, fire under a quarter
  // The parts' state is kept by the link while the drone stays linked (CMLinkSystem), so
  // DIAGNOSTICS can break or restore them between flights.
  private let m_partHp: array<Float>;
  private let m_partFx: array<ref<FxInstance>>;   // each part's smoke or fire (looping)
  private let m_partFx2: array<ref<FxInstance>>;  // each part's sparks (looping)
  private let m_partLevel: array<Int32>;          // 0 whole, 1 smoking, 2 burning / gone
  private let m_partSlot: array<wref<SlotComponent>>;
  private let m_partSlotName: array<CName>;
  private let m_podsBreak: Bool;                  // a destroyed pod breaks off (else it burns on)
  private let m_podHidden: array<wref<IComponent>>;
  private let m_podMasks: array<Uint64>;

  public static func OctantParts() -> Int32 = 10

  // the rocket pods still on (0-2)
  private func RocketPods() -> Int32 {
    if ArraySize(this.m_partHp) < CMUDrone.OctantParts() {
      return 2;
    }
    return (this.m_partHp[6] > 0.0 ? 1 : 0) + (this.m_partHp[7] > 0.0 ? 1 : 0);
  }

  public static func OctantPartName(i: Int32) -> String {
    switch i {
      case 1: return "THR FL";
      case 2: return "THR FR";
      case 3: return "THR BL";
      case 4: return "THR BR";
      case 5: return "LMG";
      case 6: return "RKT L";
      case 7: return "RKT R";
      case 8: return "MORTAR";
      case 9: return "SENSOR";
    }
    return "HULL";
  }

  // the parts' share of the hull: a hit worth that much of the hull's maximum destroys it
  public static func OctantShare(i: Int32) -> Float {
    if i == 0 { return 1.0; }
    if i <= 4 { return 0.2; }
    if i == 5 || i == 8 { return 0.15; }
    if i == 9 { return 0.1; }
    return 0.12;
  }

  // the slot on the model each part is found by, and how far from it a hit still counts
  private static func OctantSlot(i: Int32) -> CName {
    switch i {
      case 1: return n"Engine4";
      case 2: return n"Engine2";
      case 3: return n"Engine3";
      case 4: return n"Engine1";
      case 5: return n"gun_front";
      case 6: return n"Wing1";
      case 7: return n"Wing2";
      case 9: return n"Perception";
    }
    return n"";
  }
  private static func OctantReach(i: Int32) -> Float = i <= 4 ? 1.0 : (i == 5 ? 0.9 : 0.7)

  private func ResetParts() -> Void {
    ArrayClear(this.m_partHp);
    this.StopPartFx();
    ArrayClear(this.m_partSlot);
    ArrayClear(this.m_partSlotName);
    ArrayClear(this.m_podHidden);
    ArrayClear(this.m_podMasks);
    if !Equals(this.m_kind, "octant") {
      return;
    }
    let link = CMLinkSystem.Get(this.m_game);
    let kept = link.DroneParts(this.m_drone.GetEntityID(), CMUDrone.OctantParts());
    let i = 0;
    while i < CMUDrone.OctantParts() {
      ArrayPush(this.m_partHp, kept[i]);
      ArrayPush(this.m_partLevel, 0);
      ArrayPush(this.m_partFx, null);
      ArrayPush(this.m_partFx2, null);
      ArrayPush(this.m_partSlotName, CMUDrone.OctantSlot(i));
      ArrayPush(this.m_partSlot, this.FindSlot(CMUDrone.OctantSlot(i)));
      i += 1;
    }
    this.ApplyParts(false);
  }

  // the slot component that has `name` (looked up once, then read every frame)
  private func FindSlot(name: CName) -> wref<SlotComponent> {
    let drone = this.m_drone;
    if !IsDefined(drone) || Equals(name, n"") {
      return null;
    }
    for c in drone.GetComponents() {
      let sc = c as SlotComponent;
      let wt: WorldTransform;
      if IsDefined(sc) && sc.GetSlotTransform(name, wt) {
        return sc;
      }
    }
    return null;
  }

  // where a part is on the drawn model now (world)
  private func PartPos(i: Int32) -> Vector4 {
    let fl = this.m_flight;
    if i == 8 || i == 0 {
      // the mortar on top of the hull, the hull at its centre
      let p = fl.pos + CMFlight.QRot(fl.q, new Vector4(0.0, 0.0, i == 8 ? 0.7 : 0.0, 0.0));
      p.W = 1.0;
      return p;
    }
    if i < ArraySize(this.m_partSlot) {
      let sc = this.m_partSlot[i];
      let wt: WorldTransform;
      if IsDefined(sc) && sc.GetSlotTransform(this.m_partSlotName[i], wt) {
        let p = WorldPosition.ToVector4(WorldTransform.GetWorldPosition(wt));
        if Vector4.Distance(p, fl.pos) < 6.0 {
          p.W = 1.0;
          return p;
        }
      }
    }
    // no slot: the rig's places (pods at x +-0.88, y +-0.58; the gun under the nose)
    let local = new Vector4(0.0, 1.45, -0.45, 0.0);
    switch i {
      case 1: local = new Vector4(-0.88, 0.59, 0.0, 0.0); break;
      case 2: local = new Vector4(0.88, 0.59, 0.0, 0.0); break;
      case 3: local = new Vector4(-0.88, -0.57, 0.0, 0.0); break;
      case 4: local = new Vector4(0.88, -0.57, 0.0, 0.0); break;
      case 6: local = new Vector4(-0.9, 0.0, 0.2, 0.0); break;
      case 7: local = new Vector4(0.9, 0.0, 0.2, 0.0); break;
      case 9: local = new Vector4(0.0, 1.6, 0.0, 0.0); break;
      default: break;
    }
    let q = fl.pos + CMFlight.QRot(fl.q, local - this.m_c);
    q.W = 1.0;
    return q;
  }

  // the part a hit at `p` (world) landed on
  private func PartAt(p: Vector4) -> Int32 {
    let best = 0;
    let bestD = 9999.0;
    let i = 1;
    while i < CMUDrone.OctantParts() {
      let d = Vector4.Distance(p, this.PartPos(i));
      if d < CMUDrone.OctantReach(i) && d < bestD {
        best = i;
        bestD = d;
      }
      i += 1;
    }
    return best;
  }

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
    let part = this.PartAt(hit.hitPosition);
    if part == 0 {
      return;   // the body is the hull
    }
    this.DamagePart(part, dmg);
  }

  private func DamagePart(part: Int32, dmg: Float) -> Void {
    let drone = this.m_drone;
    let hull = GameInstance.GetStatPoolsSystem(this.m_game).GetStatPoolMaxPointValue(Cast<StatsObjectID>(drone.GetEntityID()), gamedataStatPoolType.Health);
    let before = this.m_partHp[part];
    this.m_partHp[part] = MaxF(0.0, before - dmg / MaxF(1.0, hull * CMUDrone.OctantShare(part)));
    if before > 0.0 && this.m_partHp[part] <= 0.0 {
      CMCSession.Log("drone: " + CMUDrone.OctantPartName(part) + " destroyed");
    }
    this.ApplyParts(true);
  }

  // what the parts' state does: the pods' thrust, the effects, the optics
  private func ApplyParts(live: Bool) -> Void {
    if ArraySize(this.m_partHp) < CMUDrone.OctantParts() || !IsDefined(this.m_flight) {
      return;
    }
    let fl = this.m_flight;
    let i = 1;
    while i <= 4 {
      let hp = this.m_partHp[i];
      // a damaged pod pushes less; a destroyed one, nothing (the flight model's rotor i-1)
      fl.eff[i - 1] = hp > 0.0 ? 0.35 + 0.65 * hp : 0.0;
      i += 1;
    }
    // the rocket pods' load: two rockets for each pod still on
    let pods = (this.m_partHp[6] > 0.0 ? 1 : 0) + (this.m_partHp[7] > 0.0 ? 1 : 0);
    this.m_rockets = Min(this.m_rockets, pods * 2);
    let p = 1;
    while p < CMUDrone.OctantParts() {
      let hp = this.m_partHp[p];
      let level = hp <= 0.0 ? 2 : (hp < 0.5 ? 1 : 0);
      if level != this.m_partLevel[p] {
        this.PartLook(p, level, live);
        this.m_partLevel[p] = level;
      }
      p += 1;
    }
    let link = CMLinkSystem.Get(this.m_game);
    link.SetDroneParts(this.m_drone.GetEntityID(), this.m_partHp);
  }

  // a part's effects for its state: smoke when damaged; fire and sparks when destroyed, or
  // for a pod set to break off, a burst and the pod's mesh gone
  private func PartLook(p: Int32, level: Int32, live: Bool) -> Void {
    let fx = GameInstance.GetFxSystem(this.m_game);
    let at = CMUMinotaur.At(this.PartPos(p), new Vector4(0.0, 0.0, 1.0, 0.0));
    if IsDefined(this.m_partFx[p]) {
      this.m_partFx[p].BreakLoop();
      this.m_partFx[p] = null;
    }
    if IsDefined(this.m_partFx2[p]) {
      this.m_partFx2[p].BreakLoop();
      this.m_partFx2[p] = null;
    }
    if level == 1 {
      this.m_partFx[p] = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\drone\\octant\\octant_damage_smoke.effect"), at, true);
      return;
    }
    if level == 2 {
      if live {
        fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\drone\\octant\\octant_explosion_engine.effect"), at, true);
        GameObject.PlaySoundEvent(this.m_drone, n"dev_generic_impact_metal");
      }
      if p >= 1 && p <= 4 && this.m_podsBreak {
        this.HidePod(p);
        this.m_partFx[p] = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\drone\\octant\\octant_damage_smoke.effect"), at, true);
        return;
      }
      this.m_partFx[p] = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\quest\\placeholders\\sq009_drone_fire.effect"), at, true);
      this.m_partFx2[p] = fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\quest\\placeholders\\sq009_drone_electric_short.effect"), at, true);
    }
  }

  // the effects ride the parts every frame; the hull smokes under half, burns under a quarter
  private func PartFx() -> Void {
    if ArraySize(this.m_partHp) < CMUDrone.OctantParts() {
      return;
    }
    let drone = this.m_drone;
    let hullFrac = 1.0;
    if IsDefined(drone) {
      let pools = GameInstance.GetStatPoolsSystem(this.m_game);
      let id = Cast<StatsObjectID>(drone.GetEntityID());
      hullFrac = pools.GetStatPoolValue(id, gamedataStatPoolType.Health, false) / MaxF(1.0, pools.GetStatPoolMaxPointValue(id, gamedataStatPoolType.Health));
    }
    let hullLevel = hullFrac < 0.25 ? 2 : (hullFrac < 0.5 ? 1 : 0);
    if hullLevel != this.m_partLevel[0] {
      this.PartLook(0, hullLevel, false);
      this.m_partLevel[0] = hullLevel;
    }
    let up = new Vector4(0.0, 0.0, 1.0, 0.0);
    let i = 0;
    while i < CMUDrone.OctantParts() {
      if IsDefined(this.m_partFx[i]) || IsDefined(this.m_partFx2[i]) {
        let at = CMUMinotaur.At(this.PartPos(i), up);
        if IsDefined(this.m_partFx[i]) {
          this.m_partFx[i].UpdateTransform(at);
        }
        if IsDefined(this.m_partFx2[i]) {
          this.m_partFx2[i].UpdateTransform(at);
        }
      }
      i += 1;
    }
  }

  private func StopPartFx() -> Void {
    for f in this.m_partFx {
      if IsDefined(f) {
        f.BreakLoop();
      }
    }
    for f in this.m_partFx2 {
      if IsDefined(f) {
        f.BreakLoop();
      }
    }
    ArrayClear(this.m_partFx);
    ArrayClear(this.m_partFx2);
    ArrayClear(this.m_partLevel);
  }

  // a pod broken off: its thruster and sticker meshes drawn with none of their chunks
  private func HidePod(p: Int32) -> Void {
    let drone = this.m_drone;
    if !IsDefined(drone) {
      return;
    }
    let code = p == 1 ? "fl" : (p == 2 ? "fr" : (p == 3 ? "bl" : "br"));
    for c in drone.GetComponents() {
      let n = NameToString(c.GetName());
      if StrContains(n, "thruster_" + code) || StrContains(n, "sticker_" + code) || StrContains(n, "stickers_" + code) {
        let m = c as MeshComponent;
        if IsDefined(m) && m.chunkMask != 0ul {
          ArrayPush(this.m_podHidden, c);
          ArrayPush(this.m_podMasks, m.chunkMask);
          m.chunkMask = 0ul;
        }
      }
    }
  }

  // every hidden pod drawn again (restored parts; the end of the flight)
  private func UnhidePods() -> Void {
    let i = 0;
    while i < ArraySize(this.m_podHidden) {
      let m = this.m_podHidden[i] as MeshComponent;
      if IsDefined(m) {
        m.chunkMask = this.m_podMasks[i];
      }
      i += 1;
    }
    ArrayClear(this.m_podHidden);
    ArrayClear(this.m_podMasks);
  }

  public func OpticsOnline() -> Bool = ArraySize(this.m_partHp) < CMUDrone.OctantParts() || this.m_partHp[9] > 0.0

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

  public static func KindIndex(kind: String) -> Int32 {
    switch kind {
      case "octant": return 0;
      case "wyvern": return 1;
      case "griffin": return 2;
    }
    return 3;
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

// where a destroyed drone's wreck is two seconds on, against where it went down (the wreck
// that turned up in front of V, Phase 4)
public class CMWreckLogCb extends DelayCallback {
  public let drone: wref<NPCPuppet>;
  public let fell: Vector4;

  public func Call() -> Void {
    let d = this.drone;
    if !IsDefined(d) {
      CMCSession.Log("drone: the wreck is gone two seconds on");
      return;
    }
    let p = d.GetWorldPosition();
    CMCSession.Log("drone: the wreck two seconds on is at " + CMCHits.V(p) + ", " + FloatToStringPrec(Vector4.Distance(p, this.fell), 1) + " m from where it went down");
  }
}
