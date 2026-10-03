// =============================================================================
// MECHS OF NIGHT CITY - THE MECH'S PHYSICS BODY (0.9.0-a2, a3)
//
// What the drones got in 0.7.1 (MNC Physics), for the Minotaur (Omar, 2026-10-02: "create
// a new Mech entity with a rigid body with physics"; the walk and the turning stay as they
// are). The mech NPC stays the mech (its walk, its turning, its guns, its health, its
// look); an invisible PhysX body rides with it (mnc\physics\proxy_minotaur.ent: a 6 t box
// round the hull, its bottom LIFT above the feet so kerbs and steps pass under it).
// Two ways round:
//   following   the mech walks and turns on its own legs (the AI's orders, unchanged), and
//               the body's velocity is set onto it every frame: it shoves cars, props and
//               bodies out of the way with six tonnes behind it, and contacts never throw
//               it (a3: in a2 a force spring let a parked car's contact launch the mech)
//   leading     shoved by a blast, walked off a drop or left hanging in the air: the body
//               leads and the mech is placed on it every frame. It slides, falls for real
//               and lands on spring legs (the landing is the unit's: camera, hull, legs),
//               then hands back to the walk once it has settled. Nothing under it for 0.6 s
//               (through the floor): the mech goes back to where it last stood.
// The body is kept upright with its facing, the mech's own; the mech's colliders and
// physical meshes stop colliding while the body is there (they would shove it) and get it
// back after.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMMechBody {
  private let m_game: GameInstance;
  private let m_id: EntityID;
  private let m_spawned: Bool;
  private let m_live: Bool;
  private let m_askedAt: Float;
  private let m_liveAt: Float;
  private let m_body: ref<PhysicalBodyInterface>;
  private let m_offColliders: array<wref<IComponent>>;
  private let m_offMeshes: array<wref<IComponent>>;
  private let m_ownBodies: array<ref<PhysicalBodyInterface>>;

  public let led: Bool;              // the body leads (the mech is placed on it)
  public let landing: Float;         // a landing this frame: its speed down (m/s), else 0
  public let knock: Float;           // a knock this frame: its change of velocity (m/s), else 0
  public let why: String;            // why the body leads
  public let failed: Bool;           // the body never came: the mech walks without one
  public let blocked: Bool;          // something holds the body back: the walk must stop
  public let blockDir: Vector4;      // the way it is held back from (the body to the mech)
  public let blockAt: Vector4;       // where the mech's feet go (under the body)
  private let m_heldT: Float;
  private let m_ledAt: Float;
  private let m_still: Float;        // seconds settled on its legs (hands back at SETTLE)
  private let m_air: Float;          // seconds its legs have been off the ground
  private let m_fallVz: Float;       // the fastest it fell in this air time
  private let m_stepDir: Vector4;
  private let m_stepUntil: Float;
  private let m_lastFeet: Vector4;
  private let m_feetVel: Vector4;
  private let m_vel: Vector4;
  private let m_heldQ: Quaternion;   // the mech's facing while the body leads
  private let m_heldFwd: Vector4;
  private let m_placed: Vector4;     // where the mech was put last frame
  private let m_snaps: Int32;        // frames its own movement put it back elsewhere
  private let m_aiOff: Bool;         // its AI is switched off while the body leads (after snaps)
  private let m_aiIsOff: Bool;
  private let m_logAt: Float;
  private let m_knockMax: Float;
  private let m_gap: Float;
  private let m_safe: Vector4;       // where its feet last stood on something
  private let m_noGround: Float;

  private let MASS: Float = 6000.0;
  private let HALF_Z: Float = 1.5;      // the box's half height (proxy_minotaur.ent)
  private let LIFT: Float = 0.6;        // its bottom above the feet
  private let G: Float = 9.81;
  private let W_FOLLOW: Float = 8.0;    // 1/s, how fast the body closes a gap to the mech
  private let W_LEG: Float = 9.0;       // the legs' spring when the body leads (rad/s)
  private let LEG_DAMP: Float = 0.7;
  private let FRICTION: Float = 4.0;    // 1/s, its feet on the ground braking a slide
  private let SETTLE: Float = 0.45;     // s still on its legs before the walk has it back
  private let STEP_SPEED: Float = 3.5;  // m/s, stepping off a drop
  private let SPIN_K: Float = 8.0;      // 1/s, how hard it is held upright and to its facing

  public static func Make(game: GameInstance) -> ref<CMMechBody> {
    let b = new CMMechBody();
    b.m_game = game;
    return b;
  }

  public func Live() -> Bool = this.m_live

  // its own collisions off, the body asked for a quarter second later
  public func Start(mech: ref<NPCPuppet>, now: Float) -> Void {
    this.m_mechRef = mech;
    this.Collisions(mech, false);
    this.OwnBodiesOff();
    this.m_spawned = false;
    this.m_live = false;
    this.led = false;
    this.m_askedAt = now;
    this.m_lastFeet = new Vector4(0.0, 0.0, 0.0, 0.0);
    CMCSession.Log("mech body: starting (" + IntToString(ArraySize(this.m_offColliders)) + " of its colliders and " + IntToString(ArraySize(this.m_offMeshes)) + " physical meshes off, " + IntToString(ArraySize(this.m_ownBodies)) + " bodies kept from pushing)");
  }

  public func Stop(mech: ref<NPCPuppet>) -> Void {
    if this.led && IsDefined(mech) {
      this.HandBack(mech, "the link closed");
    }
    if this.m_spawned {
      let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_id);
      if IsDefined(e) {
        let body = this.Body(e);
        if IsDefined(body) {
          CMPhysStep.Release(body);
        }
      }
      GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_id);
    }
    this.m_spawned = false;
    this.m_live = false;
    this.m_body = null;
    for b in this.m_ownBodies {
      if IsDefined(b) {
        CMPhysColl.SetCollision(b, true);
      }
    }
    ArrayClear(this.m_ownBodies);
    if IsDefined(mech) {
      this.Collisions(mech, true);
    }
    CMCSession.Log("mech body: removed, the mech's own collisions back on");
  }

  // ---- every frame ----
  public func Tick(mech: ref<NPCPuppet>, dt: Float, now: Float) -> Void {
    this.landing = 0.0;
    this.knock = 0.0;
    if !IsDefined(mech) || dt <= 0.0 {
      return;
    }
    this.OwnBodiesOff();
    if !this.m_live {
      this.TryLive(mech, now);
      return;
    }
    let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_id);
    let body = IsDefined(e) ? this.Body(e) : null;
    if !IsDefined(body) {
      CMCSession.Log("mech body: the body was lost; asking for a new one");
      if IsDefined(e) {
        GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_id);
      }
      if this.led {
        this.HandBack(mech, "the body was lost");
      }
      this.m_live = false;
      this.m_spawned = false;
      this.m_body = null;
      this.m_askedAt = now;
      return;
    }
    CMWatch.Mark("mech body");
    let p = e.GetWorldPosition();
    p.W = 1.0;
    let q = e.GetWorldOrientation();
    let v = CMPhysStep.Velocity(body);
    v.W = 0.0;
    // how much contacts changed its velocity in a frame (logged only: in a2 a parked car's
    // contact read as a 5.9 m/s ram, and the body launched the mech over a barrier; only
    // blasts, drops and falls make the body lead now)
    let dv = v - this.m_vel;
    dv.Z = 0.0;
    this.m_knockMax = MaxF(this.m_knockMax, Vector4.Length(dv));
    if this.led {
      this.Leading(mech, body, p, v, dt, now);
    } else {
      this.Following(mech, body, p, v, dt, now);
    }
    if !this.m_live {
      return;   // (rescued: a new body is on its way)
    }
    this.Upright(body, q);
    CMPhysWind.IgnoreNear(7320, p, 3.5);
    if now >= this.m_logAt {
      this.m_logAt = now + 2.0;
      CMCSession.Log("mech body: " + (this.led ? "LEADING (" + this.why + ")" : "following") + ", at " + CMCHits.V(p) + ", " + FloatToStringPrec(Vector4.Length(v), 1) + " m/s, " + FloatToStringPrec(Vector4.Distance(p, this.Target(mech.GetWorldPosition())), 2) + " m off the mech, biggest knock " + FloatToStringPrec(this.m_knockMax, 1) + " m/s; " + CMPhysStep.Info(body));
      this.m_knockMax = 0.0;
    }
  }

  // where the body's centre goes for feet at `feet`
  private func Target(feet: Vector4) -> Vector4 = new Vector4(feet.X, feet.Y, feet.Z + this.LIFT + this.HALF_Z, 1.0)

  // the mech walks; the body is pulled onto it
  private func Following(mech: ref<NPCPuppet>, body: ref<PhysicalBodyInterface>, p: Vector4, v: Vector4, dt: Float, now: Float) -> Void {
    let feet = mech.GetWorldPosition();
    if this.m_lastFeet.W > 0.5 {
      let fv = (feet - this.m_lastFeet) * (1.0 / dt);
      fv.W = 0.0;
      if Vector4.Length(fv) > 30.0 {
        fv = new Vector4(0.0, 0.0, 0.0, 0.0);   // a teleport, not a walk
      }
      this.m_feetVel = this.m_feetVel + (fv - this.m_feetVel) * MinF(1.0, dt * 10.0);
    }
    this.m_lastFeet = feet;
    this.m_lastFeet.W = 1.0;
    this.m_safe = feet;
    this.m_safe.W = 1.0;
    // its velocity is set every frame: the mech's own, plus what closes the gap (a3; the a2
    // force spring let contacts throw it). Gravity is held off by a constant force. It
    // pushes what it walks into and nothing pushes it.
    let err = this.Target(feet) - p;
    err.W = 0.0;
    let want = this.m_feetVel + err * this.W_FOLLOW;
    want.W = 0.0;
    if Vector4.Length(want) > 4.0 {
      want = Vector4.Normalize(want) * 4.0;   // (a2: a body far behind was driven hard into what held it)
    }
    // held back (a car it can't shove, a post): the mech mustn't walk on through it (a2: it
    // walked through a parked car, the body pressed inside it, and the car threw it). Past
    // 0.5 m for 0.15 s the unit stops the walk and sets the mech back under the body.
    let off = new Vector4(err.X, err.Y, 0.0, 0.0);
    this.blocked = false;
    if Vector4.Length(off) > 0.5 {
      this.m_heldT += dt;
      if this.m_heldT >= 0.15 {
        this.blocked = true;
        this.blockDir = Vector4.Normalize(off) * -1.0;
        this.blockAt = new Vector4(p.X, p.Y, feet.Z, 1.0);
      }
    } else {
      this.m_heldT = 0.0;
    }
    CMPhysPlugin.SetVelocity(body, want);
    this.m_vel = want;
    CMPhysStep.SetForce(body, new Vector4(0.0, 0.0, this.G * this.MASS, 0.0), new Vector4(0.0, 0.0, 0.0, 0.0));
  }

  // the body leads: legs, a slide braked by its feet, or a step off a drop; the mech on it
  private func Leading(mech: ref<NPCPuppet>, body: ref<PhysicalBodyInterface>, p: Vector4, v: Vector4, dt: Float, now: Float) -> Void {
    let bottom = p.Z - this.HALF_Z;
    let hit: TraceResult;
    let ground = CMGround.Down(this.m_game, new Vector4(p.X, p.Y, p.Z + this.HALF_Z, 1.0), new Vector4(p.X, p.Y, p.Z - 120.0, 1.0), hit);
    // nothing under it for most of a second (it went through the floor: a2 fell 140 m under
    // the canal): back where it last stood, and a new body
    if ground {
      this.m_noGround = 0.0;
    } else {
      this.m_noGround += dt;
      if this.m_noGround >= 0.6 {
        this.Rescue(mech, now);
        return;
      }
    }
    let gz = ground ? Cast<Vector4>(hit.position).Z : -100000.0;
    let gap = bottom - gz;
    this.m_gap = ground ? gap : -1.0;
    let onLegs = ground && gap < this.LIFT + 0.05;
    let a = new Vector4(0.0, 0.0, 0.0, 0.0);
    if onLegs {
      a.Z = this.G + this.W_LEG * this.W_LEG * (this.LIFT - gap) - 2.0 * this.LEG_DAMP * this.W_LEG * v.Z;
    }
    let stepping = now < this.m_stepUntil;
    let vh = new Vector4(v.X, v.Y, 0.0, 0.0);
    if stepping {
      let want = this.m_stepDir * this.STEP_SPEED - vh;
      a.X += want.X * 3.0;
      a.Y += want.Y * 3.0;
    } else {
      if onLegs {
        a.X -= vh.X * this.FRICTION;
        a.Y -= vh.Y * this.FRICTION;
      }
    }
    CMPhysStep.SetForce(body, a * this.MASS, new Vector4(0.0, 0.0, 0.0, 0.0));
    // in the air: how fast it falls; back on its legs after that: a landing
    if onLegs {
      if this.m_air > 0.25 && this.m_fallVz < -1.0 {
        this.landing = -this.m_fallVz;
        CMCSession.Log("mech body: landed at " + FloatToStringPrec(this.landing, 1) + " m/s after " + FloatToStringPrec(this.m_air, 2) + " s in the air");
      }
      this.m_air = 0.0;
      this.m_fallVz = 0.0;
      this.m_safe = new Vector4(p.X, p.Y, gz, 1.0);
    } else {
      this.m_air += dt;
      this.m_fallVz = MinF(this.m_fallVz, v.Z);
    }
    this.m_vel = v;
    // the mech on the body: its feet LIFT under the box, never under the ground
    let feet = new Vector4(p.X, p.Y, bottom - this.LIFT, 1.0);
    if ground && feet.Z < gz {
      feet.Z = gz;
    }
    this.Place(mech, feet);
    // settled: the walk has it back
    if onLegs && !stepping && Vector4.Length(v) < 0.6 {
      this.m_still += dt;
    } else {
      this.m_still = 0.0;
    }
    if this.m_still >= this.SETTLE {
      this.HandBack(mech, "settled");
    } else {
      if now - this.m_ledAt > 20.0 {
        this.HandBack(mech, "led for 20 s");   // never stuck leading
      }
    }
  }

  // the mech put on the body. If its own movement keeps putting it back elsewhere, its AI is
  // switched off while the body leads (the drones' way), from then on.
  private func Place(mech: ref<NPCPuppet>, feet: Vector4) -> Void {
    if this.m_placed.W > 0.5 && Vector4.Distance(mech.GetWorldPosition(), this.m_placed) > 0.3 {
      this.m_snaps += 1;
      if this.m_snaps == 5 && !this.m_aiOff {
        this.m_aiOff = true;
        CMCSession.Log("mech body: its own movement keeps moving it off the body (" + CMCHits.V(mech.GetWorldPosition()) + " against " + CMCHits.V(this.m_placed) + "); its AI goes off while the body leads");
      }
    }
    if this.m_aiOff && !this.m_aiIsOff {
      let ai = mech.GetAIControllerComponent();
      if IsDefined(ai) {
        ai.Toggle(false);
        this.m_aiIsOff = true;
      }
    }
    let wt: WorldTransform;
    let world: WorldPosition;
    WorldPosition.SetVector4(world, feet);
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, this.m_heldQ);
    mech.SetWorldTransform(wt);
    this.m_placed = feet;
    this.m_placed.W = 1.0;
  }

  // held upright, facing where the mech faces (following) or faced (leading)
  private func Upright(body: ref<PhysicalBodyInterface>, q: Quaternion) -> Void {
    let up = CMFlight.QRot(q, new Vector4(0.0, 0.0, 1.0, 0.0));
    let fwd = CMFlight.QRot(q, new Vector4(0.0, 1.0, 0.0, 0.0));
    let want = this.m_heldFwd;
    if !this.led {
      let mech = this.m_mechRef;
      if IsDefined(mech) {
        want = mech.GetWorldForward();
      }
    }
    // up x Z: the axis that brings it upright
    let w = new Vector4(up.Y, -up.X, 0.0, 0.0) * this.SPIN_K;
    let fh = new Vector4(fwd.X, fwd.Y, 0.0, 0.0);
    let th = new Vector4(want.X, want.Y, 0.0, 0.0);
    if Vector4.Length(fh) > 0.1 && Vector4.Length(th) > 0.1 {
      fh = Vector4.Normalize(fh);
      th = Vector4.Normalize(th);
      let turn = AtanF(fh.X * th.Y - fh.Y * th.X, fh.X * th.X + fh.Y * th.Y);
      w.Z = ClampF(turn * this.SPIN_K, -3.0, 3.0);
    }
    CMPhysPlugin.SetSpin(body, w);
  }

  private let m_mechRef: wref<NPCPuppet>;

  // ---- the body takes the lead ----
  public func Lead(mech: ref<NPCPuppet>, now: Float, reason: String) -> Void {
    if !this.m_live || this.led {
      return;
    }
    this.led = true;
    this.why = reason;
    this.m_ledAt = now;
    this.m_still = 0.0;
    this.m_air = 0.0;
    this.m_fallVz = 0.0;
    this.m_snaps = 0;
    this.m_placed = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_heldQ = mech.GetWorldOrientation();
    this.m_heldFwd = mech.GetWorldForward();
    CMCSession.Log("mech body: the body leads (" + reason + ")" + (this.m_aiOff ? ", its AI off" : ""));
  }

  // knocked: a change of velocity (a blast: away from it, a little up)
  public func Push(mech: ref<NPCPuppet>, dv: Vector4, now: Float, reason: String) -> Void {
    if !this.m_live || !IsDefined(this.m_body) {
      return;
    }
    let v = CMPhysStep.Velocity(this.m_body);
    v.W = 0.0;
    CMPhysPlugin.SetVelocity(this.m_body, v + dv);
    this.m_vel = v + dv;   // (not taken for a knock again next frame)
    this.knock = Vector4.Length(dv);
    this.Lead(mech, now, reason);
  }

  // off a drop it was walked to: a step out over the edge
  public func StepOff(mech: ref<NPCPuppet>, dir: Vector4, now: Float) -> Void {
    if !this.m_live || this.led {
      return;
    }
    this.m_stepDir = dir;
    this.m_stepUntil = now + 1.2;
    this.Lead(mech, now, "stepped off a drop");
  }

  // nothing under its feet: it falls
  public func Fall(mech: ref<NPCPuppet>, gap: Float, now: Float) -> Void {
    if !this.m_live || this.led {
      return;
    }
    this.Lead(mech, now, "nothing under it (" + FloatToStringPrec(gap, 1) + " m)");
  }

  // through the floor: the mech set back where it last stood, the body asked for again
  private func Rescue(mech: ref<NPCPuppet>, now: Float) -> Void {
    CMCSession.Log("mech body: nothing under the body for 0.6 s (through the floor?); the mech back at " + CMCHits.V(this.m_safe) + ", a new body");
    this.m_placed = this.m_safe.W > 0.5 ? this.m_safe : this.m_placed;
    this.HandBack(mech, "rescued");
    let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_id);
    if IsDefined(e) {
      let body = this.Body(e);
      if IsDefined(body) {
        CMPhysStep.Release(body);
      }
    }
    GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_id);
    this.m_live = false;
    this.m_spawned = false;
    this.m_body = null;
    this.m_askedAt = now;
    this.m_noGround = 0.0;
  }

  // the walk has it back, where the body put it
  private func HandBack(mech: ref<NPCPuppet>, reason: String) -> Void {
    this.led = false;
    this.m_stepUntil = 0.0;
    this.m_still = 0.0;
    let ai = mech.GetAIControllerComponent();
    if IsDefined(ai) {
      if this.m_aiIsOff {
        ai.Toggle(true);
        this.m_aiIsOff = false;
      }
      let at = this.m_placed.W > 0.5 ? this.m_placed : mech.GetWorldPosition();
      let tp = new AITeleportCommand();
      tp.position = new Vector4(at.X, at.Y, at.Z, 1.0);
      tp.rotation = CMPilotRig.YawOf(this.m_heldFwd);
      tp.doNavTest = false;
      ai.SendCommand(tp);
    }
    this.m_lastFeet = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_feetVel = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_placed = new Vector4(0.0, 0.0, 0.0, 0.0);
    CMCSession.Log("mech body: the walk has it back (" + reason + ")");
  }

  // ---- the body itself ----
  private func TryLive(mech: ref<NPCPuppet>, now: Float) -> Void {
    this.m_mechRef = mech;
    if !this.m_spawned {
      if now - this.m_askedAt >= 0.25 {
        this.Spawn(mech, now);
      }
      return;
    }
    let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_id);
    if !IsDefined(e) || Vector4.Length(e.GetWorldPosition()) < 1.0 {
      if now - this.m_askedAt > 10.0 {
        // (an archive from before 0.9.0-a2 has no mnc\physics\proxy_minotaur.ent): no body this
        // link, and the mech's own collisions back
        CMCSession.Log("mech body: the body never appeared in 10 s (is mnc\\physics\\proxy_minotaur.ent in the archive?); walking without one this link");
        this.Stop(mech);
        this.failed = true;
      }
      return;
    }
    let body = this.Body(e);
    if !IsDefined(body) || !body.IsSimulated() {
      return;
    }
    this.m_live = true;
    this.m_liveAt = now;
    this.m_vel = new Vector4(0.0, 0.0, 0.0, 0.0);
    CMPhysPlugin.SetVelocity(body, this.m_vel);
    CMCSession.Log("mech body: live after " + FloatToStringPrec(now - this.m_askedAt, 2) + " s at " + CMCHits.V(e.GetWorldPosition()) + " (the mech at " + CMCHits.V(mech.GetWorldPosition()) + ")");
  }

  private func Spawn(mech: ref<NPCPuppet>, now: Float) -> Void {
    let spec = new DynamicEntitySpec();
    spec.templatePath = r"mnc\\physics\\proxy_minotaur.ent";
    spec.position = this.Target(mech.GetWorldPosition());
    spec.orientation = mech.GetWorldOrientation();
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"MNCPhysMech"];
    this.m_id = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    this.m_spawned = true;
    this.m_live = false;
    this.m_askedAt = now;
    CMCSession.Log("mech body: asked for at " + CMCHits.V(spec.position));
  }

  private func Body(e: ref<Entity>) -> ref<PhysicalBodyInterface> {
    if IsDefined(this.m_body) && this.m_body.IsSimulated() {
      return this.m_body;
    }
    let c = e.FindComponentByName(n"proxy_body") as ColliderComponent;
    if IsDefined(c) {
      this.m_body = c.CreatePhysicalBodyInterface();
    }
    return this.m_body;
  }

  // its own physical meshes push nothing while the body is there (asked every frame: the
  // plugin drops a wish 0.3 s after the last ask)
  private func OwnBodiesOff() -> Void {
    for b in this.m_ownBodies {
      if IsDefined(b) {
        CMPhysColl.SetCollision(b, false);
      }
    }
  }

  // the mech's own colliders and physical meshes off while the body is there, back on after
  private func Collisions(mech: ref<NPCPuppet>, on: Bool) -> Void {
    if !on {
      ArrayClear(this.m_offColliders);
      ArrayClear(this.m_offMeshes);
      ArrayClear(this.m_ownBodies);
      for c in mech.GetComponents() {
        if c.IsA(n"entColliderComponent") || c.IsA(n"entSimpleColliderComponent") {
          if c.IsEnabled() {
            c.Toggle(false);
            ArrayPush(this.m_offColliders, c);
          }
        } else {
          if c.IsA(n"entPhysicalMeshComponent") {
            let pm = c as PhysicalMeshComponent;
            if CMUDrone.MeshCollision(c, false) {
              ArrayPush(this.m_offMeshes, c);
            }
            if IsDefined(pm) {
              let b = pm.CreatePhysicalBodyInterface();
              if IsDefined(b) {
                ArrayPush(this.m_ownBodies, b);
              }
            }
          } else {
            if c.IsA(n"entPhysicalSkinnedMeshComponent") {
              let sb = CMPhysBodies.Of(c);
              if !IsDefined(sb) {
                sb = CMUDrone.SkinnedBody(c);
              }
              if IsDefined(sb) {
                ArrayPush(this.m_ownBodies, sb);
              }
            }
          }
        }
      }
      return;
    }
    for c in this.m_offColliders {
      if IsDefined(c) {
        c.Toggle(true);
      }
    }
    for c in this.m_offMeshes {
      if IsDefined(c) {
        CMUDrone.MeshCollision(c, true);
      }
    }
    ArrayClear(this.m_offColliders);
    ArrayClear(this.m_offMeshes);
  }

  // for the HUD and the log
  public func Gap() -> Float = this.m_gap
}
