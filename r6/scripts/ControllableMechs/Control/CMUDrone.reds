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
  private let m_poseOk: Bool;          // measured at least once
  private let m_poseFrom: String;      // which slot (log)
  private let m_hull: array<Vector4>;  // contact points in the rest pose (CMDroneHull)
  private let m_pts: array<Vector4>;   // the same as drawn (turned by m_tq), entity frame
  private let m_c: Vector4;            // the drawn hull's centre, entity frame: the flight's
                                       // centre of mass sits here
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
    this.m_tq = CMUDrone.QIdentity();
    this.m_tt = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_poseOk = false;
    this.MeasurePose(drone, 1.0);
    this.UpdateHull();
    this.LoadSensor();
    let start = drone.GetWorldPosition() + CMFlight.QRot(drone.GetWorldOrientation(), this.m_tt + this.m_c);
    this.m_flight = CMFlight.Make(prof, start, CMPilotRig.YawOf(drone.GetWorldForward()));
    this.m_flight.level = Cast<Float>(cfg.DroneLevel(this.m_kind)) / 100.0;
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
    CMCSession.Log("drone: drawn pose " + (this.m_poseOk ? "via " + this.m_poseFrom : "not measured") + ", lift " + CMUDrone.V2(this.m_tt) + ", turned " + CMUDrone.V2(CMUDrone.QEuler(this.m_tq)) + " deg, " + IntToString(ArraySize(this.m_hull)) + " contact points, centre " + CMUDrone.V2(this.m_c) + ", sensor " + FloatToStringPrec(this.m_sensUp, 2) + " up " + FloatToStringPrec(this.m_sensFwd, 2) + " fwd");
    CMCSession.Log("drone: " + this.m_name + ", record " + TDBID.ToStringDEBUG(drone.GetRecordID())
      + (this.m_aiOff ? ", AI off" : ", AI on") + ", self-levelling " + IntToString(RoundF(this.m_flight.level * 100.0)) + "%, tilt " + FloatToStringPrec(prof.tilt, 0) + ", rate " + FloatToStringPrec(prof.tiltRate, 0) + ", move method " + CMUDrone.MethodName(this.m_method));
    return "";
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    let drone = this.m_drone;
    if IsDefined(drone) {
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
  // Where the camera anchors. The session moves the camera before this frame's flight
  // step, so the drone's last placement was a frame behind the drone that is about to be
  // drawn, and that gap swung with every change in frame time: the jitter at speed. The
  // anchor is led by a frame of the drone's velocity instead, to where it is drawn.
  public func Ground() -> Vector4 {
    if !IsDefined(this.m_flight) {
      return this.m_seen;
    }
    let p = this.Anchor() + this.m_flight.vel * this.m_dt;
    p.W = 1.0;
    return p;
  }
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
    // a stall: the model moved on but the drone stayed put this frame
    if Vector4.Length(this.m_flight.vel) > 0.5 && Vector4.Distance(actual, this.m_last) < 0.002 {
      this.m_stalls += 1;
    }
    this.m_last = actual;
    this.m_dt = dt;
    this.MeasurePose(drone, 0.1);
    this.UpdateHull();
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
    let from = this.m_flight.pos;
    // the flight model in small steps
    let left = dt;
    while left > 0.0001 {
      let h = MinF(this.SUBSTEP, left);
      this.m_flight.Step(h, f, side, climb, s.rig.yaw);
      left -= h;
    }
    this.Collide(drone, from);
    this.Contacts(drone);
    this.Place(drone, now);
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
    this.m_tq = CMUDrone.QBlend(this.m_tq, rot, k);
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
  private func Ray(from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
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
    let move = fl.pos - from;
    let len = Vector4.Length(move);
    let hit: TraceResult;
    if len > 0.0005 {
      let dir = move / len;
      // How far the body reaches along the way it moves: its radius sideways, its real
      // lowest point (belly, or a side as it tips) up and down. The sweep used the radius
      // in every direction, so a drone settling onto the road stopped a whole radius up:
      // the Bombus 0.30 m with its belly 0.13 m below its centre, every type floating a
      // hand's width over the road while the first-person view sat at its centre (a27).
      let ext = this.Extent(dir);
      if this.Ray(from, fl.pos + dir * ext, hit) {
        let at = Cast<Vector4>(hit.position);
        let n = Vector4.Normalize(Cast<Vector4>(hit.normal));
        fl.pos = at - dir * ext;
        fl.pos.W = 1.0;
        // floors are slid along with grip, walls give a little bounce; the height hold
        // takes the new height (it pulled back down into rising ground: the bobbing)
        let floorish = n.Z > 0.6;
        this.Impact(drone, fl.Contact(n, n * -ext, floorish ? 0.0 : 0.25, 0.3));
        if floorish && fl.holding {
          fl.holdZ = MaxF(fl.holdZ, fl.pos.Z);
        }
      }
    }
    // the ground under it: measured for the HUD, and a contact only when the drone is in
    // it. There is no minimum height; flying low is the pilot's call.
    // The lowest point of the body at its real attitude: the lowest of its contact points
    // (scanned from its mesh, as drawn). The ray starts a metre up, so a drone already
    // part-way in still finds the surface.
    let low = this.Lowest();
    let r0 = MaxF(0.02, -low.Z);
    fl.grounded = false;
    let clear = 1000.0;   // how far the lowest point is above the ground
    if this.Ray(fl.pos + new Vector4(0.0, 0.0, 1.0, 0.0), fl.pos - new Vector4(0.0, 0.0, 40.0, 0.0), hit) {
      let gz = hit.position.Z;
      this.m_groundFrom = FloatToStringPrec(fl.pos.Z + 1.0 - gz, 2) + " m below the ray start";
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
    for p in this.m_pts {
      let r = CMFlight.QRot(fl.q, p - this.m_c);
      let len = Vector4.Length(r);
      if len > 0.02 {
        let dir = r / len;
        let tip = fl.pos + r;
        if this.Ray(fl.pos, tip + dir * 0.02, hit) {
          let at = Cast<Vector4>(hit.position);
          let n = Vector4.Normalize(Cast<Vector4>(hit.normal));
          if Vector4.Dot(n, dir) > 0.0 {
            n = dir * -1.0;   // a back-facing hit: push straight back along the spoke
          }
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
    // its animation's hover height held at zero, so the model sits where the body is
    let alt = new AnimFeature_DroneActionAltitudeOffset();
    alt.desiredOffset = 0.0;
    AnimationControllerComponent.ApplyFeature(drone, n"ActionAltitudeOffset", alt);
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
    // heights above the surface the ground ray found: the sight-view eye, the drawn body's
    // centre and lowest point (rest pose, as placed)
    let heights = "";
    if this.m_ground >= 0.0 {
      let gz = fl.pos.Z - this.m_ground;
      let eye = this.Anchor().Z + this.SensorUp();
      heights = ", above the road: sight-view eye " + FloatToStringPrec(eye - gz, 2) + " m, body centre " + FloatToStringPrec(fl.pos.Z - gz, 2) + " m, body bottom " + FloatToStringPrec(fl.pos.Z - this.Extent(new Vector4(0.0, 0.0, -1.0, 0.0)) - gz, 2) + " m";
    }
    CMCSession.Log("drone: " + CMUDrone.MethodName(this.m_method) + ", " + IntToString(this.m_frames) + " frames"
      + (this.m_method == 2 ? "" : ", off by " + FloatToStringPrec(avg, 2) + " m avg / " + FloatToStringPrec(this.m_errMax, 2) + " m max, " + IntToString(stalls) + " stalled frames")
      + ", speed " + FloatToStringPrec(Vector4.Length(fl.vel), 1) + " m/s, climb " + FloatToStringPrec(fl.vel.Z, 1)
      + ", tilt p" + FloatToStringPrec(fl.pitch, 1) + " r" + FloatToStringPrec(fl.roll, 1)
      + ", spool " + FloatToStringPrec(fl.Spool() * 100.0, 0) + "%, " + FloatToStringPrec(this.m_ground, 1) + " m up"
      + ", rays hit " + IntToString(this.m_rayHits) + " / missed " + IntToString(this.m_rayMiss) + " (static " + IntToString(this.m_hitS) + ", dynamic " + IntToString(this.m_hitD) + ", vehicle " + IntToString(this.m_hitV) + "; ground " + this.m_groundFrom + ")" + ", at " + CMCHits.V(this.m_flight.pos)
      + ", gait " + NameToString(this.m_gait) + ", heading " + FloatToStringPrec(fl.yaw, 0)
      + ", drawn pose lift " + CMUDrone.V2(this.m_tt) + " turned " + CMUDrone.V2(CMUDrone.QEuler(this.m_tq))
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
