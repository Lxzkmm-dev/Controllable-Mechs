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
  private let m_lift: Vector4;         // how far its animation holds the body off its origin,
                                       // past the rig's rest pose (in the body's frame)
  private let m_liftComp: CName;       // the slot measured for it (on the body bone)
  private let m_liftSlot: CName;
  private let m_bindZ: Float;          // the body bone's rest height in the rig
  private let m_probe: Int32;          // the old inline ground ray, kept as a control (log)
  private let m_groundFrom: String;    // what the last ground ray hit, and how far from its start (log)
  private let m_stickS: Float;

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
    // the model flies the centre of mass; the drone's origin hangs below it (Root())
    this.m_flight = CMFlight.Make(prof, drone.GetWorldPosition() + new Vector4(0.0, 0.0, prof.com, 0.0), CMPilotRig.YawOf(drone.GetWorldForward()));
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
    this.FindBody(drone);
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
    let p = this.Root() + this.m_flight.vel * this.m_dt;
    p.W = 1.0;
    return p;
  }
  public func Facing() -> Float = IsDefined(this.m_flight) ? this.m_flight.yaw : 0.0
  public func SensorUp() -> Float = 0.1
  public func SensorFwd() -> Float = 0.35
  public func AimSkip() -> Float = 1.5
  // the body's tilt, shown through the camera (the game won't tilt a drone's body)
  // The tilt as the model shows it (its lean capped per type), not the flight's own: with
  // the flight's, the sight view dived into the road while the model beside it stayed near
  // level, and the two never matched (Omar, a23 Bombus).
  public func CamTilt() -> Vector4 {
    if !IsDefined(this.m_flight) {
      return new Vector4(0.0, 0.0, 0.0, 0.0);
    }
    let q = this.m_flight.Shown(this.m_flight.p.showTilt);
    let f = CMFlight.QRot(q, new Vector4(0.0, 1.0, 0.0, 0.0));
    let r = CMFlight.QRot(q, new Vector4(1.0, 0.0, 0.0, 0.0));
    return new Vector4(Rad2Deg(AsinF(ClampF(f.Z, -1.0, 1.0))), Rad2Deg(AsinF(ClampF(-r.Z, -1.0, 1.0))), 0.0, 0.0);
  }
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
    this.MeasureLift(drone);
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
    let from = this.m_flight.pos;
    // the flight model in small steps
    let left = dt;
    while left > 0.0001 {
      let h = MinF(this.SUBSTEP, left);
      this.m_flight.Step(h, f, side, climb, s.rig.yaw);
      left -= h;
    }
    this.Collide(drone, from);
    this.PushOut(drone);
    this.Place(drone, now);
    this.Lean(drone, dt);
    if now >= this.m_logAt {
      this.m_logAt = now + 1.0;
      this.Report(drone);
    }
  }

  // Where the drone's origin goes: the body turns about its centre of mass (the model's
  // position), and the origin hangs below that along the body's up axis. Turning about the
  // origin itself, at the base of the Bombus and Wyvern, swung the body like a see-saw.
  // The origin also goes down by however far the drone's animation lifts the body off it,
  // so the body is drawn where the flight is.
  private func Root() -> Vector4 {
    let fl = this.m_flight;
    let q = fl.Shown(fl.p.showTilt);
    let r = fl.pos - CMFlight.QRot(q, new Vector4(0.0, 0.0, 1.0, 0.0)) * fl.p.com - CMFlight.QRot(q, this.m_lift);
    r.W = 1.0;
    return r;
  }

  // The drone's body bone, through a slot on it, and its rest height in the rig. Drones
  // are walking NPCs whose animations hover the body above the origin: with the origin
  // placed at the flight, the body was drawn that far above it, and the pilot "couldn't
  // get low" though the flight had touched the road (a21 log: 0.0 m up).
  private func FindBody(drone: ref<NPCPuppet>) -> Void {
    this.m_lift = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_liftComp = n"";
    this.m_bindZ = CMUDrone.BindZ(this.m_kind);
    let wt: WorldTransform;
    for comp in [n"fx_slots", n"Item_Attachment_Slot"] {
      let sc = drone.FindComponentByName(comp) as SlotComponent;
      if IsDefined(sc) {
        for slot in [n"Body", n"base", n"Base"] {
          if !IsNameValid(this.m_liftComp) && sc.GetSlotTransform(slot, wt) {
            this.m_liftComp = comp;
            this.m_liftSlot = slot;
          }
        }
      }
    }
    CMCSession.Log("drone: body bone " + (IsNameValid(this.m_liftComp) ? "via " + NameToString(this.m_liftComp) + "/" + NameToString(this.m_liftSlot) : "not found, its animation lift isn't corrected") + ", rest height " + FloatToStringPrec(this.m_bindZ, 3) + " m");
  }

  // the body bone's offset from the origin, in the drone's frame, past its rest pose;
  // smoothed (the slot reads last frame's pose) and kept within 3 m
  private func MeasureLift(drone: ref<NPCPuppet>) -> Void {
    if !IsNameValid(this.m_liftComp) {
      return;
    }
    let sc = drone.FindComponentByName(this.m_liftComp) as SlotComponent;
    let wt: WorldTransform;
    if !IsDefined(sc) || !sc.GetSlotTransform(this.m_liftSlot, wt) {
      return;
    }
    let at = WorldPosition.ToVector4(WorldTransform.GetWorldPosition(wt));
    let rel = CMFlight.QInvRot(drone.GetWorldOrientation(), at - drone.GetWorldPosition());
    rel.Z -= this.m_bindZ;
    rel.W = 0.0;
    let len = Vector4.Length(rel);
    if len > 3.0 {
      rel = rel * (3.0 / len);
    }
    this.m_lift += (rel - this.m_lift) * 0.1;
    this.m_lift.W = 0.0;
  }

  // the body bone's height in each rig's rest pose (WolvenKit, 2026-10-01)
  public static func BindZ(kind: String) -> Float {
    switch kind {
      case "bombus": return 0.127;
      case "octant": return 0.77;
    }
    return 0.0;   // griffin, wyvern
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
      if this.Ray(from, fl.pos + dir * r, hit) {
        let at = Cast<Vector4>(hit.position);
        let n = Vector4.Normalize(Cast<Vector4>(hit.normal));
        fl.pos = at - dir * r;
        fl.pos.W = 1.0;
        // floors are slid along with grip, walls give a little bounce; the height hold
        // takes the new height (it pulled back down into rising ground: the bobbing)
        let floorish = n.Z > 0.6;
        this.Impact(drone, fl.Contact(n, n * -r, floorish ? 0.0 : 0.25, 0.3));
        if floorish && fl.holding {
          fl.holdZ = MaxF(fl.holdZ, fl.pos.Z);
        }
      }
    }
    // the ground under it: measured for the HUD, and a contact only when the drone is in
    // it. There is no minimum height; flying low is the pilot's call.
    // the lowest point of the body as it is tilted (belly, rotor or wing tip), from its
    // measured size: the centre alone let the body sink through the ground. The ray starts
    // a metre up, so a drone already part-way in still finds the surface above it.
    // measured on the body as shown: the visible body is what touches the road, so the
    // model and the sight view (which rides on it) stop on the surface together. With the
    // flight's own steep tilt the belly reach shrank to nothing and the sight view sank to
    // the road while the capped model was still up off it.
    let shownUp = CMFlight.QRot(fl.Shown(fl.p.showTilt), new Vector4(0.0, 0.0, 1.0, 0.0));
    let r0 = fl.p.bottom * AbsF(ClampF(shownUp.Z, -1.0, 1.0));
    fl.grounded = false;

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
        this.Impact(drone, fl.Contact(up, up * -r0, 0.0, 0.3));
        if fl.holding {
          fl.holdZ = MaxF(fl.holdZ, fl.pos.Z);
        }
      }
    } else {
      this.m_ground = -1.0;
      this.m_groundFrom = "no ground found";
    }
  }
  // stick expo: x^3 blended in, soft near the centre, full at the end
  public static func Expo(x: Float, e: Float) -> Float = x * (1.0 - e) + x * x * x * e

  // Out of anything it is inside: four rays out from the centre (front, back, left, right)
  // against the world, dynamic objects and vehicles. Whatever is closer than the drone's
  // radius pushes it out along the surface and is a contact, so a car driving into it or
  // a wall it ended up in moves it instead of passing through.
  private func PushOut(drone: ref<NPCPuppet>) -> Void {
    let fl = this.m_flight;
    let r = fl.p.radius;
    let fwd = CMPilotRig.Dir(fl.yaw, 0.0);
    let right = CMPilotRig.Dir(fl.yaw - 90.0, 0.0);
    let dirs: array<Vector4> = [fwd, fwd * -1.0, right, right * -1.0];
    let hit: TraceResult;
    for d in dirs {
      if this.Ray(fl.pos, fl.pos + d * r, hit) {
        let at = Cast<Vector4>(hit.position);
        let depth = r - Vector4.Distance(fl.pos, at);
        if depth > 0.0 {
          let n = Vector4.Normalize(Cast<Vector4>(hit.normal));
          if Vector4.Dot(n, d) > 0.0 {
            n = d * -1.0;   // a back-facing hit: push straight back along the ray
          }
          fl.pos += n * depth;
          fl.pos.W = 1.0;
          this.Impact(drone, fl.Contact(n, d * r, 0.2, 0.3));
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
        WorldTransform.SetOrientation(wt, fl.Shown(fl.p.showTilt));   // as flown, or the model's lean capped

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
    CMCSession.Log("drone: " + CMUDrone.MethodName(this.m_method) + ", " + IntToString(this.m_frames) + " frames"
      + (this.m_method == 2 ? "" : ", off by " + FloatToStringPrec(avg, 2) + " m avg / " + FloatToStringPrec(this.m_errMax, 2) + " m max, " + IntToString(stalls) + " stalled frames")
      + ", speed " + FloatToStringPrec(Vector4.Length(fl.vel), 1) + " m/s, climb " + FloatToStringPrec(fl.vel.Z, 1)
      + ", tilt p" + FloatToStringPrec(fl.pitch, 1) + " r" + FloatToStringPrec(fl.roll, 1)
      + ", spool " + FloatToStringPrec(fl.Spool() * 100.0, 0) + "%, " + FloatToStringPrec(this.m_ground, 1) + " m up"
      + ", rays hit " + IntToString(this.m_rayHits) + " / missed " + IntToString(this.m_rayMiss) + " (static " + IntToString(this.m_hitS) + ", dynamic " + IntToString(this.m_hitD) + ", vehicle " + IntToString(this.m_hitV) + "; ground " + this.m_groundFrom + ")" + ", at " + CMCHits.V(this.m_flight.pos)
      + ", gait " + NameToString(this.m_gait) + ", heading " + FloatToStringPrec(fl.yaw, 0)
      + ", animation lift " + CMCHits.V(this.m_lift)
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
