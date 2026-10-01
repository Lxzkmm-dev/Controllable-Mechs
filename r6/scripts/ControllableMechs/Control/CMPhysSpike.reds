// =============================================================================
// MECHS OF NIGHT CITY - PHYSICS SPIKE (R1-R3)
//
// The first spikes of "Research: Drones as Real Rigid Bodies" (Omar's doc, 2026-10-01):
// can the engine's own physics carry a drone? Test only, from DIAGNOSTICS > PHYSICS SPIKE.
//   DROP   (R1) a plain physics box (mnc\physics\proxy_box.ent: the game's cardboard box
//          mesh on a Dynamic box collider, 20 kg, tools/physics/proxy_box.py) 3 m ahead of
//          V and 2.5 m up. It should fall, land, and be pushed by V and by a car.
//   KICK   (R2) one sideways impulse through its physics body: does an impulse move it?
//   HOVER  (R3) holds it 2 m over where it is for 30 s with impulses alone: gravity
//          cancelled (m g dt a frame) and a height hold on top. Pass: within a few cm.
//   REMOVE takes it away.
// What the compiler says the body offers scripts (probe, 2026-10-01): AddLinearImpulse
// (impulse, Bool, opt offset), IsSimulated, SetIsKinematic, GetTransform / SetTransform.
// No velocity getter or setter, no mass, no torque: the velocity here is measured from
// the transform frame to frame. Everything it sees goes to the log ("CM physics spike").
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*
import Codeware.*

public class CMPhysSpike extends ScriptableSystem {
  private let m_id: EntityID;
  private let m_has: Bool;
  private let m_mode: Int32;           // 0 watch (after a drop or a kick), 1 hover
  private let m_gen: Int32;            // a new run stops the old one's callbacks
  private let m_started: Float;        // this run's start
  private let m_spawnAt: Float;        // when the spawn was asked for
  private let m_seen: Bool;            // the entity has turned up
  private let m_body: ref<PhysicalBodyInterface>;
  private let m_prev: Vector4;
  private let m_prevAt: Float;
  private let m_vel: Vector4;
  private let m_logAt: Float;
  private let m_holdZ: Float;
  private let m_errSum: Float;
  private let m_errMax: Float;
  private let m_errN: Int32;
  private let m_frames: Int32;
  private let m_holdSet: Bool;         // the hold height is known (the box was placed)
  private let m_q: Quaternion;         // the body's attitude last frame (its spin is measured)
  private let m_qOk: Bool;
  private let m_resp: array<Float>;    // R4: the spin each push variant gave (rad/s)
  private let m_best: Int32;           // R4: the variant that turns it (-1 until known)
  private let m_tiltSum: Float;
  private let m_tiltN: Int32;
  private let TILT_TIME: Float = 30.0;
  private let m_sign: Float;           // R4: +1 if the couple turns it the way asked, else -1
  private let m_inertia: Float;        // R4: measured, kg m2
  private let TWIST: Float = 0.3;      // N m, the calibration twist
  private let LEVER: Float = 0.25;     // m, half the couple's span
  private let INERTIA: Float = 0.6;    // kg m2, the box about a horizontal axis (about)
  private let MASS: Float = 20.0;      // the .ent's mass (the body can't be asked)
  private let WATCH: Float = 8.0;      // s of logging after a drop or a kick
  private let HOVER: Float = 30.0;

  public static func Get(game: GameInstance) -> ref<CMPhysSpike> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMPhysSpike") as CMPhysSpike;
  }

  private func Clock() -> Float = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()))

  private static func Log(s: String) -> Void {
    CMCSession.Log("physics spike: " + s);
  }

  // ---- the buttons -------------------------------------------------------------------
  public func Drop() -> String {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return "!NO PLAYER";
    }
    this.Remove();
    let fwd = player.GetWorldForward();
    let spec = new DynamicEntitySpec();
    spec.templatePath = r"mnc\\physics\\proxy_box.ent";
    spec.position = player.GetWorldPosition() + new Vector4(fwd.X * 3.0, fwd.Y * 3.0, 2.5, 0.0);
    spec.orientation = player.GetWorldOrientation();
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"MNCPhysSpike"];
    this.m_id = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    this.m_has = true;
    this.m_seen = false;
    this.m_body = null;
    this.m_spawnAt = this.Clock();
    CMPhysSpike.Log("R1 drop: box asked for at " + CMCHits.V(spec.position));
    this.Start(0);
    return "*BOX DROPPED AHEAD OF YOU: WATCH IT FALL, THEN WALK INTO IT OR DRIVE INTO IT";
  }

  // R2, two ways (a1: the body handle taken the frame it spawned read "not simulated" at
  // 0,0,0 and its pushes did nothing, though the box fell under the engine's gravity):
  //   event: a PhysicalImpulseEvent queued on the entity (how NitroBoost and TDO push cars)
  //   body:  a fresh body handle from the collider, taken now, not at spawn
  public func Kick(viaBody: Bool) -> String {
    let e = this.Box();
    if !IsDefined(e) {
      return "!DROP A BOX FIRST";
    }
    let player = GetPlayer(this.GetGameInstance());
    let side = IsDefined(player) ? player.GetWorldRight() : new Vector4(1.0, 0.0, 0.0, 0.0);
    // 4 m/s sideways and a little up, on 20 kg
    let j = new Vector4(side.X * this.MASS * 4.0, side.Y * this.MASS * 4.0, this.MASS * 2.0, 0.0);
    if viaBody {
      let c = e.FindComponentByName(n"proxy_body") as ColliderComponent;
      if IsDefined(c) {
        this.m_body = c.CreatePhysicalBodyInterface();
      }
      if !IsDefined(this.m_body) {
        CMPhysSpike.Log("R2 kick (body): no body handle");
        return "!NO BODY HANDLE";
      }
      let t = this.m_body.GetTransform();
      CMPhysSpike.Log("R2 kick (body): fresh handle reads " + CMCHits.V(t.position) + ", simulated " + (this.m_body.IsSimulated() ? "yes" : "NO") + "; impulse " + CMCHits.V(j) + " N s");
      this.m_body.AddLinearImpulse(j, true);
    } else {
      this.Push(e, j);
      CMPhysSpike.Log("R2 kick (event): impulse " + CMCHits.V(j) + " N s at " + CMCHits.V(this.Centre(e)));
    }
    this.Start(0);
    return "*KICKED: IT SHOULD SLIDE TO YOUR RIGHT";
  }

  // REFLECT: what the engine's own type info says the physics classes can do (the script
  // compiler only knows what the game's scripts declare; NativeDB lists velocity setters on
  // the body with no parameters). Every function, its parameters and return type, to the
  // log; then, with a box out, the velocity getters called through Codeware's Reflection.
  public func Reflect() -> String {
    let names: array<String> = ["entPhysicalBodyInterface", "entColliderComponent", "entIPlacedComponent", "entPhysicalMeshComponent", "PhysicalImpulseEvent"];
    let total = 0;
    for cls in names {
      let c = Reflection.GetClass(StringToName(cls));
      if !IsDefined(c) {
        CMPhysSpike.Log("reflect: " + cls + " not found");
      } else {
        total += this.ReflectClass(cls, c);
      }
    }
    this.ReflectCalls();
    return "*REFLECTED " + IntToString(total) + " FUNCTIONS: SEE THE LOG";
  }

  private func ReflectClass(cls: String, c: ref<ReflectionClass>) -> Int32 {
      let total = 0;
      let fns = c.GetFunctions();
      CMPhysSpike.Log("reflect: " + cls + " (parent " + (IsDefined(c.GetParent()) ? NameToString(c.GetParent().GetName()) : "none") + "): " + IntToString(ArraySize(fns)) + " functions, " + IntToString(ArraySize(c.GetProperties())) + " properties");
      for f in fns {
        let ps = "";
        for prm in f.GetParameters() {
          ps += (StrLen(ps) > 0 ? ", " : "") + NameToString(prm.GetName()) + ": " + NameToString(prm.GetType().GetName());
        }
        let ret = f.GetReturnType();
        CMPhysSpike.Log("reflect:   " + NameToString(f.GetName()) + "(" + ps + ")" + (IsDefined(ret) ? " -> " + NameToString(ret.GetName()) : "") + (f.IsNative() ? "" : " [script]"));
        total += 1;
      }
      for prop in c.GetProperties() {
        CMPhysSpike.Log("reflect:   ." + NameToString(prop.GetName()) + ": " + NameToString(prop.GetType().GetName()));
      }
      return total;
  }

  // the getters, called for real on the box's body
  private func ReflectCalls() -> Void {
    let e = this.Box();
    if IsDefined(e) {
      let col = e.FindComponentByName(n"proxy_body") as ColliderComponent;
      let body = IsDefined(col) ? col.CreatePhysicalBodyInterface() : null;
      let bc = Reflection.GetClass(n"entPhysicalBodyInterface");
      if IsDefined(body) && IsDefined(bc) {
        for fname in [n"GetLinearVelocity", n"GetAngularVelocity", n"GetMass", n"IsSimulated", n"GetTransform"] {
          let f = bc.GetFunction(fname);
          if !IsDefined(f) {
            CMPhysSpike.Log("reflect: call " + NameToString(fname) + ": no such function");
          } else {
            let ok = false;
            let v = f.Call(body, [], ok);
            CMPhysSpike.Log("reflect: call " + NameToString(fname) + ": " + (ok ? "ran" : "FAILED") + ", gave " + NameToString(VariantTypeName(v)) + " " + CMPhysSpike.Show(v));
          }
        }
      }
    }
  }

  private static func Show(v: Variant) -> String {
    let t = VariantTypeName(v);
    if Equals(t, n"Vector4") {
      return CMCHits.V(FromVariant<Vector4>(v));
    }
    if Equals(t, n"Float") {
      return FloatToStringPrec(FromVariant<Float>(v), 3);
    }
    if Equals(t, n"Bool") {
      return FromVariant<Bool>(v) ? "true" : "false";
    }
    return "";
  }

  private func Box() -> ref<Entity> {
    if !this.m_has {
      return null;
    }
    return GameInstance.GetDynamicEntitySystem().GetEntity(this.m_id);
  }

  // the box's middle (the entity's origin is its base)
  private func Centre(e: ref<Entity>) -> Vector4 = e.GetWorldPosition() + new Vector4(0.0, 0.0, 0.2, 0.0)

  // an impulse through the box's middle, as an event on the entity
  private func Push(e: ref<Entity>, j: Vector4) -> Void {
    let c = this.Centre(e);
    let ev = new PhysicalImpulseEvent();
    ev.worldPosition.X = c.X;
    ev.worldPosition.Y = c.Y;
    ev.worldPosition.Z = c.Z;
    ev.worldImpulse.X = j.X;
    ev.worldImpulse.Y = j.Y;
    ev.worldImpulse.Z = j.Z;
    e.QueueEvent(ev);
  }

  public func Hover() -> String {
    let e = this.Box();
    if !IsDefined(e) {
      return "!DROP A BOX FIRST";
    }
    if !IsDefined(this.Fresh(e)) {
      return "!NO BODY HANDLE";
    }
    this.m_holdSet = false;   // taken from the first frame the box is placed (Tick)
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    CMPhysSpike.Log("R3 hover: holding at z " + FloatToStringPrec(this.m_holdZ, 2) + " for " + FloatToStringPrec(this.HOVER, 0) + " s on impulses alone");
    this.Start(1);
    return "*HOVERING FOR 30 S: IT SHOULD RISE 2 M AND HOLD";
  }

  // R4: hover, and hold a 20 deg lean with off-centre pushes (the body has no torque call).
  // How AddLinearImpulse places an offset push isn't documented, so the first 12 s try
  // three readings with a fixed one-second twist each and measure the spin each gives:
  //   0  originInCOM true,  offset relative to the centre
  //   1  originInCOM false, offset relative to the centre
  //   2  originInCOM false, offset as a world position
  // then the lean is held with whichever turned it most.
  public func TiltTest() -> String {
    let e = this.Box();
    if !IsDefined(e) {
      return "!DROP A BOX FIRST";
    }
    this.m_holdSet = false;   // taken from the first frame the box is placed (Tick)
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    this.m_tiltSum = 0.0;
    this.m_tiltN = 0;
    this.m_best = -1;
    this.m_resp = [0.0, 0.0, 0.0];
    CMPhysSpike.Log("R4 tilt: hovering at z " + FloatToStringPrec(this.m_holdZ, 2) + "; 12 s finding how an offset push turns it, then holding a 20 deg lean to world +X");
    this.Start(2);
    return "*TILT TEST: IT RISES, TWITCHES THREE TIMES, THEN LEANS 20 DEG AND HOLDS";
  }

  // a body handle that works: taken again whenever the last one isn't simulated (a1: one
  // taken the frame the box spawned, before it was placed, never worked)
  private func Fresh(e: ref<Entity>) -> ref<PhysicalBodyInterface> {
    if IsDefined(this.m_body) && this.m_body.IsSimulated() {
      return this.m_body;
    }
    let c = e.FindComponentByName(n"proxy_body") as ColliderComponent;
    if IsDefined(c) {
      this.m_body = c.CreatePhysicalBodyInterface();
    }
    return this.m_body;
  }

  private func Tilt(body: ref<PhysicalBodyInterface>, q: Quaternion, w: Vector4, age: Float, h: Float) -> Void {
    let up = CMFlight.QRot(q, new Vector4(0.0, 0.0, 1.0, 0.0));
    if age < 12.0 {
      // per variant: half a second of twist about world +X (the spin it gave, signed, is
      // measured at its end), then half a second back the other way, so the box is left
      // about as it was whichever way the push turned out to turn it (a5: one-way twists
      // and a levelling with guessed sign and inertia left it spinning at 5-8 rad/s)
      let k = Min(2, FloorF(age / 4.0));
      let inPhase = age - Cast<Float>(k) * 4.0;
      if inPhase < 0.5 {
        this.Couple(body, new Vector4(this.TWIST, 0.0, 0.0, 0.0), k, h);
        if inPhase > 0.4 && AbsF(w.X) > AbsF(this.m_resp[k]) {
          this.m_resp[k] = w.X;
        }
      } else {
        if inPhase < 1.0 {
          this.Couple(body, new Vector4(-this.TWIST, 0.0, 0.0, 0.0), k, h);
        }
      }
      return;
    }
    if this.m_best < 0 {
      this.m_best = 0;
      let i = 1;
      while i < 3 {
        if AbsF(this.m_resp[i]) > AbsF(this.m_resp[this.m_best]) {
          this.m_best = i;
        }
        i += 1;
      }
      let r = this.m_resp[this.m_best];
      // the spin a 0.5 s twist gave: inertia = twist x time / spin; the sign says whether
      // the couple turns it the way it was asked
      this.m_sign = r < 0.0 ? -1.0 : 1.0;
      this.m_inertia = ClampF(this.TWIST * 0.5 / MaxF(0.01, AbsF(r)), 0.01, 5.0);
      CMPhysSpike.Log("R4 calibration: spin about +X after a 0.5 s twist of " + FloatToStringPrec(this.TWIST, 1) + " N m: variant 0 " + FloatToStringPrec(this.m_resp[0], 2) + ", 1 " + FloatToStringPrec(this.m_resp[1], 2) + ", 2 " + FloatToStringPrec(this.m_resp[2], 2) + " rad/s; variant " + IntToString(this.m_best) + ", inertia " + FloatToStringPrec(this.m_inertia, 3) + " kg m2, sign " + FloatToStringPrec(this.m_sign, 0));
    }
    // hold a 20 deg lean toward world +X: a spring on the angle, a damper on the spin, sized
    // to the measured inertia (about 4 rad/s, well damped)
    let want = new Vector4(SinF(Deg2Rad(20.0)), 0.0, CosF(Deg2Rad(20.0)), 0.0);
    let tq = (CMFlight.Cross(up, want) * 16.0 - w * 6.4) * (this.m_inertia * this.m_sign);
    this.Couple(body, tq, this.m_best, h);
    if age > 17.0 {
      this.m_tiltSum += Rad2Deg(AcosF(ClampF(Vector4.Dot(up, want), -1.0, 1.0)));
      this.m_tiltN += 1;
    }
  }

  // a pure turning push (torque tq, N m, over h s): two opposite pushes LEVER either side
  // of the centre, at right angles to the axis, through push variant k (TiltTest)
  private func Couple(body: ref<PhysicalBodyInterface>, tq: Vector4, k: Int32, h: Float) -> Void {
    let n = Vector4.Length(tq);
    if n < 0.0001 {
      return;
    }
    let axis = tq / n;
    let other = AbsF(axis.Z) < 0.9 ? new Vector4(0.0, 0.0, 1.0, 0.0) : new Vector4(1.0, 0.0, 0.0, 0.0);
    let r = Vector4.Normalize(CMFlight.Cross(axis, other)) * this.LEVER;
    let j = CMFlight.Cross(tq, r) * (h / (2.0 * this.LEVER * this.LEVER));
    if k == 0 {
      body.AddLinearImpulse(j, true, r);
      body.AddLinearImpulse(-j, true, -r);
    } else {
      if k == 1 {
        body.AddLinearImpulse(j, false, r);
        body.AddLinearImpulse(-j, false, -r);
      } else {
        let c = body.GetTransform().position;
        body.AddLinearImpulse(j, false, c + r);
        body.AddLinearImpulse(-j, false, c - r);
      }
    }
  }

  // PLUGIN: MNC Physics v0's inspection (its log: red4ext/logs/mncphysics-*.log), and the
  // body handle's own bytes when a box is out
  public func PluginInspect() -> String {
    if !CMPhysPlugin.Present() {
      CMPhysSpike.Log("plugin: MNC Physics is not loaded");
      return "!MNC PHYSICS PLUGIN NOT LOADED";
    }
    let msg = CMPhysPlugin.Inspect();
    CMPhysSpike.Log("plugin: MNC Physics v" + IntToString(CMPhysPlugin.Version()) + ": " + msg);
    let e = this.Box();
    if IsDefined(e) {
      let body = this.Fresh(e);
      if IsDefined(body) {
        CMPhysSpike.Log("plugin: box body " + CMPhysPlugin.BodyBits(body));
      }
    }
    return "*" + StrUpper(msg) + ": SEE RED4EXT'S MNCPHYSICS LOG";
  }

  public static func QId() -> Quaternion {
    let q: Quaternion;
    q.r = 1.0;
    return q;
  }

  public static func QConj(q: Quaternion) -> Quaternion {
    let o: Quaternion;
    o.i = -q.i;
    o.j = -q.j;
    o.k = -q.k;
    o.r = q.r;
    return o;
  }

  public func Remove() -> String {
    this.m_gen += 1;
    if this.m_has {
      GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_id);
      CMPhysSpike.Log("box removed");
    }
    this.m_has = false;
    this.m_seen = false;
    this.m_body = null;
    return "BOX REMOVED";
  }

  public func Has() -> Bool = this.m_has

  private func Ready() -> Bool = this.m_has && this.m_seen && IsDefined(this.m_body)

  // ---- every frame while a run is on ---------------------------------------------------
  private func Start(mode: Int32) -> Void {
    this.m_gen += 1;
    this.m_mode = mode;
    this.m_started = this.Clock();
    this.m_logAt = 0.0;
    this.m_frames = 0;
    this.Next();
  }

  private func Next() -> Void {
    let cb = new CMPhysSpikeCb();
    cb.sys = this;
    cb.gen = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.0, false);
  }

  public func Tick(gen: Int32) -> Void {
    if gen != this.m_gen || !this.m_has {
      return;
    }
    let now = this.Clock();
    let e = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_id);
    if !IsDefined(e) {
      if now - this.m_spawnAt > 10.0 {
        CMPhysSpike.Log("R1 FAIL: the box never spawned in 10 s (is mnc\\physics\\proxy_box.ent in the archive?)");
        this.m_has = false;
        return;
      }
      this.Next();
      return;
    }
    if !this.m_seen {
      this.m_seen = true;
      let c = e.FindComponentByName(n"proxy_body") as ColliderComponent;
      if !IsDefined(c) {
        CMPhysSpike.Log("R1 FAIL: the box spawned without its collider (proxy_body)");
        return;
      }
      this.m_body = c.CreatePhysicalBodyInterface();
      if !IsDefined(this.m_body) {
        CMPhysSpike.Log("R2 FAIL: CreatePhysicalBodyInterface gave nothing");
        return;
      }
      let t0 = this.m_body.GetTransform();
      this.m_prev = t0.position;
      this.m_prevAt = now;
      CMPhysSpike.Log("R1 spawned after " + FloatToStringPrec(now - this.m_spawnAt, 2) + " s: body at " + CMCHits.V(t0.position) + ", entity at " + CMCHits.V(e.GetWorldPosition()) + ", simulated " + (this.m_body.IsSimulated() ? "yes" : "NO"));
    }
    // measured from the entity: it followed the body down in a1, the body handle didn't
    let p = e.GetWorldPosition();
    let bodyAt = IsDefined(this.m_body) ? this.m_body.GetTransform().position : new Vector4(0.0, 0.0, 0.0, 0.0);
    let bodySim = IsDefined(this.m_body) && this.m_body.IsSimulated();
    let dt = now - this.m_prevAt;
    if dt > 0.0001 {
      this.m_vel = (p - this.m_prev) / dt;
    }
    this.m_prev = p;
    this.m_prevAt = now;
    this.m_frames += 1;
    let body = this.Fresh(e);
    // the attitude from the entity: the body handle's transform reads all zeros (a4)
    let q = e.GetWorldOrientation();
    // the hold height, from the first frame the box is really placed (a4: HOVER and TILT
    // pressed in the terminal, with the game paused, read it unplaced at 0 and held it 8 m
    // under the street)
    if !this.m_holdSet && this.m_mode >= 1 && Vector4.Length(p) > 1.0 {
      this.m_holdSet = true;
      this.m_holdZ = p.Z + 2.0;
      this.m_started = now;   // the run's clock starts once it can hold
      CMPhysSpike.Log("hold height set from the placed box: z " + FloatToStringPrec(this.m_holdZ, 2));
    }
    let age = now - this.m_started;
    let w = new Vector4(0.0, 0.0, 0.0, 0.0);
    if dt > 0.0001 && this.m_qOk {
      // the spin, from the turn since last frame (2 x the turn quaternion's vector / dt)
      let dq = CMFlight.QMul(q, CMPhysSpike.QConj(this.m_q));
      let s = dq.r < 0.0 ? -2.0 : 2.0;
      w = new Vector4(dq.i * s / dt, dq.j * s / dt, dq.k * s / dt, 0.0);
    }
    this.m_q = q;
    this.m_qOk = true;
    if this.m_mode >= 1 && IsDefined(body) && this.m_holdSet {
      // gravity, cancelled over this frame, and the height hold (a spring and a damper on
      // the measured climb rate), as one impulse through the centre of mass, through a body
      // handle taken after the box was placed (a2: the event route moves only vehicles)
      let h = MinF(dt, 0.05);
      let err = this.m_holdZ - p.Z;
      let up = this.MASS * (9.81 + err * 6.0 - this.m_vel.Z * 4.0) * h;
      let drift = new Vector4(-this.m_vel.X * this.MASS * 2.0 * h, -this.m_vel.Y * this.MASS * 2.0 * h, up, 0.0);
      body.AddLinearImpulse(drift, true);
      if this.m_mode == 2 {
        this.Tilt(body, q, w, age, h);
      }
      if age > 3.0 {
        // settled: how well it holds
        this.m_errSum += AbsF(err);
        this.m_errMax = MaxF(this.m_errMax, AbsF(err));
        this.m_errN += 1;
      }
    }
    if now >= this.m_logAt {
      this.m_logAt = now + 0.5;
      CMPhysSpike.Log((this.m_mode == 2 ? "R4 lean " + FloatToStringPrec(Rad2Deg(AcosF(ClampF(CMFlight.QRot(q, new Vector4(0.0, 0.0, 1.0, 0.0)).Z, -1.0, 1.0))), 1) + " deg, spin " + FloatToStringPrec(Vector4.Length(w), 2) + " rad/s, " : (this.m_mode == 1 ? "R3 " : "watch ")) + FloatToStringPrec(age, 1) + " s: entity " + CMCHits.V(p) + ", speed " + FloatToStringPrec(Vector4.Length(this.m_vel), 2) + " m/s (climb " + FloatToStringPrec(this.m_vel.Z, 2) + ")" + (this.m_mode >= 1 ? ", off the hold by " + FloatToStringPrec(this.m_holdZ - p.Z, 3) + " m" : "") + "; body handle " + CMCHits.V(bodyAt) + (bodySim ? " simulated" : " not simulated") + ", " + IntToString(this.m_frames) + " frames");
    }
    let limit = this.m_mode == 2 ? this.TILT_TIME : (this.m_mode == 1 ? this.HOVER : this.WATCH);
    if age >= limit {
      if this.m_mode == 2 {
        let avgT = this.m_tiltN > 0 ? this.m_tiltSum / Cast<Float>(this.m_tiltN) : -1.0;
        CMPhysSpike.Log("R4 " + (this.m_tiltN > 0 && avgT < 3.0 ? "PASS" : "RESULT") + ": with variant " + IntToString(this.m_best) + ", the tilt was off its 20 deg by " + FloatToStringPrec(avgT, 2) + " deg on average over " + IntToString(this.m_tiltN) + " frames");
      }
      if this.m_mode >= 1 {
        let avg = this.m_errN > 0 ? this.m_errSum / Cast<Float>(this.m_errN) : -1.0;
        CMPhysSpike.Log("R3 " + (this.m_errN > 0 && this.m_errMax < 0.1 ? "PASS" : "RESULT") + ": held within " + FloatToStringPrec(avg, 3) + " m on average, " + FloatToStringPrec(this.m_errMax, 3) + " m at most, over " + IntToString(this.m_errN) + " frames (it now drops)");
      } else {
        CMPhysSpike.Log("watch done: resting at " + CMCHits.V(p));
      }
      return;
    }
    this.Next();
  }
}

public class CMPhysSpikeCb extends DelayCallback {
  public let sys: wref<CMPhysSpike>;
  public let gen: Int32;
  public func Call() -> Void {
    if IsDefined(this.sys) {
      this.sys.Tick(this.gen);
    }
  }
}
