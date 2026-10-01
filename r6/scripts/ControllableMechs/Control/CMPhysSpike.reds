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

  public func Kick() -> String {
    if !this.Ready() {
      return "!DROP A BOX FIRST";
    }
    let player = GetPlayer(this.GetGameInstance());
    let side = IsDefined(player) ? player.GetWorldRight() : new Vector4(1.0, 0.0, 0.0, 0.0);
    // 4 m/s sideways and a little up, on 20 kg
    let j = new Vector4(side.X * this.MASS * 4.0, side.Y * this.MASS * 4.0, this.MASS * 2.0, 0.0);
    this.m_body.AddLinearImpulse(j, true);
    CMPhysSpike.Log("R2 kick: impulse " + CMCHits.V(j) + " N s, simulated " + (this.m_body.IsSimulated() ? "yes" : "NO"));
    this.Start(0);
    return "*KICKED: IT SHOULD SLIDE TO YOUR RIGHT";
  }

  public func Hover() -> String {
    if !this.Ready() {
      return "!DROP A BOX FIRST";
    }
    let t = this.m_body.GetTransform();
    this.m_holdZ = t.position.Z + 2.0;
    this.m_errSum = 0.0;
    this.m_errMax = 0.0;
    this.m_errN = 0;
    CMPhysSpike.Log("R3 hover: holding at z " + FloatToStringPrec(this.m_holdZ, 2) + " for " + FloatToStringPrec(this.HOVER, 0) + " s on impulses alone");
    this.Start(1);
    return "*HOVERING FOR 30 S: IT SHOULD RISE 2 M AND HOLD";
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
    if !IsDefined(this.m_body) {
      return;
    }
    let t = this.m_body.GetTransform();
    let p = t.position;
    let dt = now - this.m_prevAt;
    if dt > 0.0001 {
      this.m_vel = (p - this.m_prev) / dt;
    }
    this.m_prev = p;
    this.m_prevAt = now;
    this.m_frames += 1;
    let age = now - this.m_started;
    if this.m_mode == 1 {
      // gravity, cancelled over this frame, and the height hold (a spring and a damper on
      // the measured climb rate), as one impulse through the centre of mass
      let h = MinF(dt, 0.05);
      let err = this.m_holdZ - p.Z;
      let up = this.MASS * (9.81 + err * 6.0 - this.m_vel.Z * 4.0) * h;
      let drift = new Vector4(-this.m_vel.X * this.MASS * 2.0 * h, -this.m_vel.Y * this.MASS * 2.0 * h, up, 0.0);
      this.m_body.AddLinearImpulse(drift, true);
      if age > 3.0 {
        // settled: how well it holds
        this.m_errSum += AbsF(err);
        this.m_errMax = MaxF(this.m_errMax, AbsF(err));
        this.m_errN += 1;
      }
    }
    if now >= this.m_logAt {
      this.m_logAt = now + 0.5;
      CMPhysSpike.Log((this.m_mode == 1 ? "R3 " : "watch ") + FloatToStringPrec(age, 1) + " s: body " + CMCHits.V(p) + ", entity " + CMCHits.V(e.GetWorldPosition()) + ", speed " + FloatToStringPrec(Vector4.Length(this.m_vel), 2) + " m/s (climb " + FloatToStringPrec(this.m_vel.Z, 2) + ")" + (this.m_mode == 1 ? ", off the hold by " + FloatToStringPrec(this.m_holdZ - p.Z, 3) + " m" : "") + ", simulated " + (this.m_body.IsSimulated() ? "yes" : "no") + ", " + IntToString(this.m_frames) + " frames");
    }
    let limit = this.m_mode == 1 ? this.HOVER : this.WATCH;
    if age >= limit {
      if this.m_mode == 1 {
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
