// =============================================================================
// CONTROLLABLE MECHS - PILOT CAMERA RIG (the weight)
//
// Pure math, no game calls. Each frame it takes where the pilot wants to look
// (aim yaw/pitch from the mouse), the mech's ground position and how high and
// far forward the sensor sits, and returns where the virtual camera is:
//   - turning is a spring with mass: it accelerates, is capped at the torso's
//     traverse rate, overshoots a little and settles
//   - the position rides a ring around the mech's centre: 'up' above its feet and
//     'fwd' ahead along the VIEW's facing, not the chassis's (the chassis turns in
//     jerky AI steps; tying the camera to it made the view lurch). The weight is
//     added on top as small offsets that settle back: a bob and a jolt plus roll
//     on every footfall; recoil is a separate shake of the view that never moves the aim
// Angles are degrees in the game's convention: yaw 0 faces +Y, positive yaw
// turns left, positive pitch looks up.
// =============================================================================
module ControllableMechs

public class CMPilotRig {
  // where the pilot asks to look
  public let aimYaw: Float;
  public let aimPitch: Float;
  // where the view is
  public let yaw: Float;
  public let pitch: Float;
  public let roll: Float;
  public let pos: Vector4;
  public let fov: Float;
  public let speed: Float;          // mech ground speed, m/s (smoothed)

  private let m_yawVel: Float;
  private let m_pitchVel: Float;
  private let m_rollVel: Float;
  private let m_jolt: Float;        // vertical offset from footfalls and recoil, settles to 0
  private let m_joltVel: Float;
  private let m_lastGround: Vector4;
  private let m_phase: Float;
  private let m_step: Int32;
  private let m_side: Float;
  private let m_ready: Bool;
  private let m_chase: Bool;        // third-person: no overshoot, and the orbit lags the aim
  private let m_orbitYaw: Float;    // where on the ring the camera sits (= yaw in the sensor view)

  // tuning (set in Init: field defaults can't be negative)
  private let m_pitchMin: Float;
  private let m_pitchMax: Float;
  private let m_turnK: Float;
  private let m_turnDamp: Float;
  private let m_maxYawRate: Float;
  private let m_maxPitchRate: Float;
  private let m_stride: Float;
  private let m_bobAmp: Float;
  private let m_noStride: Bool;   // a unit without footfalls (a drone): no stride bob or jolts
  private let m_fovBase: Float;
  private let m_fovZoom: Float;

  public func Init(ground: Vector4, up: Float, fwd: Float, facingYaw: Float) -> Void {
    this.m_pitchMin = -35.0;
    this.m_pitchMax = 30.0;
    this.m_turnK = 16.0;        // stiffness of the torso turn: slower to get going
    this.m_turnDamp = 5.2;      // < 2*sqrt(K) = 8: underdamped, a slight overshoot
    this.m_maxYawRate = 40.0;   // deg/s: the torso can't whip around (SetWeight overrides)
    this.m_maxPitchRate = 28.0;
    this.m_stride = 2.4;        // metres per footfall
    this.m_bobAmp = 0.08;
    this.m_fovBase = 68.0;
    this.m_fovZoom = 34.0;

    this.aimYaw = facingYaw;
    this.aimPitch = 0.0;
    this.yaw = facingYaw;
    this.pitch = 0.0;
    this.roll = 0.0;
    this.pos = CMPilotRig.Ring(ground, facingYaw, up, fwd);
    this.fov = this.m_fovBase;
    this.speed = 0.0;
    this.m_yawVel = 0.0;
    this.m_pitchVel = 0.0;
    this.m_rollVel = 0.0;
    this.kickYaw = 0.0;
    this.kickPitch = 0.0;
    this.m_kickYawVel = 0.0;
    this.m_kickPitchVel = 0.0;
    this.m_jolt = 0.0;
    this.m_joltVel = 0.0;
    this.m_lastGround = ground;
    this.m_phase = 0.0;
    this.m_step = 0;
    this.m_side = 1.0;
    this.m_orbitYaw = facingYaw;
    this.m_chase = false;
    this.m_ready = true;
  }

  // chase view: critically damped (no snap back), and the camera's place on the ring trails
  // the aim so turning swings the view round the mech smoothly instead of rigidly
  public func SetChase(on: Bool) -> Void {
    this.m_chase = on;
    this.m_turnDamp = on ? 2.0 * SqrtF(this.m_turnK) : 5.2;
    this.m_orbitYaw = this.yaw;
  }

  public func YawRate() -> Float = this.m_yawVel

  // the framework's heavier feel (M1): a softer spring, lower rate caps, and a lead limit:
  // the aim can only run `lead` degrees ahead of the view, so a flick doesn't leave the view
  // turning on its own for seconds afterwards (0 = no limit, the alpha's feel)
  private let m_lead: Float;

  public func SetZoomFov(fov: Float) -> Void {
    this.m_fovZoom = fov;
  }

  // M1's stomp: footfall jolt, dip and roll scaled by k (0 = the alpha's 1.0), and the
  // walking bob with them
  private let m_stepK: Float;

  public func SetStepWeight(k: Float) -> Void {
    this.m_stepK = k;
  }

  // Off for units that don't walk. StepK() reads a weight of 0 as 1 (unset), so a drone
  // (step weight 0) got the full stride: the camera bobbed 5 cm and kicked on every
  // "footfall" as it flew (a41 frame log: the camera's height over the drone swinging
  // 0.79-0.90 m every 0.4 s): the chase-view jitter.
  public func SetStride(on: Bool) -> Void {
    this.m_noStride = !on;
  }

  private func StepK() -> Float = this.m_stepK > 0.0 ? this.m_stepK : 1.0

  // a lurch: the body pitching into a start or rocking back on a stop
  public func Nudge(pitchVel: Float, joltVel: Float) -> Void {
    this.m_pitchVel += pitchVel;
    this.m_joltVel += joltVel;
  }

  public func SetWeight(stiffness: Float, damping: Float, maxYawRate: Float, maxPitchRate: Float, lead: Float) -> Void {
    this.m_turnK = stiffness;
    this.m_turnDamp = damping;
    this.m_maxYawRate = maxYawRate;
    this.m_maxPitchRate = maxPitchRate;
    this.m_lead = lead;
  }

  // how far the view may look down and up (deg; the drone's gunship hold looks far down)
  public func SetPitchLimits(lo: Float, hi: Float) -> Void {
    this.m_pitchMin = lo;
    this.m_pitchMax = hi;
    this.aimPitch = ClampF(this.aimPitch, lo, hi);
  }

  // mouse deltas, already scaled to degrees
  public func Look(dYaw: Float, dPitch: Float) -> Void {
    this.aimYaw = CMPilotRig.Wrap(this.aimYaw + dYaw);
    this.aimPitch = ClampF(this.aimPitch + dPitch, this.m_pitchMin, this.m_pitchMax);
    if this.m_lead > 0.0 {
      let d = CMPilotRig.Wrap(this.aimYaw - this.yaw);
      if d > this.m_lead {
        this.aimYaw = CMPilotRig.Wrap(this.yaw + this.m_lead);
      } else {
        if d < -this.m_lead {
          this.aimYaw = CMPilotRig.Wrap(this.yaw - this.m_lead);
        }
      }
      this.aimPitch = ClampF(this.aimPitch, this.pitch - this.m_lead, this.pitch + this.m_lead);
    }
  }

  // Recoil is a shake of the camera only: kickYaw / kickPitch are added to the view when
  // it is drawn and never to where it aims, so the reticle point and the guns stay put.
  // Each kick is a random shove with a slight upward lean on a stiff spring, so rapid fire
  // shakes instead of climbing, and the offset is capped at 1.5 degrees up.
  public let kickYaw: Float;
  public let kickPitch: Float;
  private let m_kickYawVel: Float;
  private let m_kickPitchVel: Float;
  private let m_kickScale: Float;   // the RECOIL setting + 1, so 0 means "not set" (100%)

  public func SetRecoilScale(k: Float) -> Void {
    this.m_kickScale = MaxF(0.0, k) + 1.0;
  }

  // a shot: `deg` is roughly how far this one kick throws the view, in degrees
  public func Recoil(deg: Float) -> Void {
    let v = deg * 33.0 * (this.m_kickScale > 0.0 ? this.m_kickScale - 1.0 : 1.0);
    this.m_kickPitchVel += RandRangeF(-0.6, 1.0) * v;
    this.m_kickYawVel += RandRangeF(-1.0, 1.0) * v;
    this.m_joltVel -= 0.004 * v;
  }

  // `ground`: the mech's own position; `up` / `fwd`: the sensor's height and reach
  public func Update(dt: Float, ground: Vector4, up: Float, fwd: Float, zoom: Bool) -> Void {
    if !this.m_ready {
      return;
    }
    // speed from the mech itself (the mount swings when the body turns)
    let d = ground - this.m_lastGround;
    d.Z = 0.0;
    let moved = Vector4.Length(d);
    this.m_lastGround = ground;
    let v = dt > 0.0 ? moved / dt : 0.0;
    if moved > 3.0 {   // moved by the game, not walked: keep the last speed
      v = this.speed;
    }
    this.speed += (v - this.speed) * MinF(1.0, dt * 4.0);

    // substeps of at most 10 ms keep the springs stable on a slow frame (a drone's stiff
    // gimbal spring needs them; two fixed halves went unstable past 30 ms frames)
    let steps = Max(1, CeilF(dt / 0.01));
    let h = dt / Cast<Float>(steps);
    let i = 0;
    while i < steps {
      this.Step(h);
      i += 1;
    }

    // stride: a jolt and a little roll on each footfall
    let walk = this.m_noStride ? 0.0 : ClampF(this.speed / 3.0, 0.0, 1.0);
    if walk > 0.05 {
      this.m_phase += dt * this.speed / this.m_stride * Pi();
      let step = FloorF(this.m_phase / Pi());
      if step != this.m_step {
        this.m_step = step;
        this.m_side = -this.m_side;
        let k = this.StepK();
        this.m_joltVel -= 0.9 * walk * k;
        this.m_pitchVel -= 5.0 * walk * k;
        this.m_rollVel += 8.0 * walk * this.m_side * k;
      }
    }

    // on the ring, weight on top
    let bob = -this.m_bobAmp * this.StepK() * walk * AbsF(SinF(this.m_phase));
    if this.m_chase {
      this.m_orbitYaw = CMPilotRig.Wrap(this.m_orbitYaw + CMPilotRig.Wrap(this.yaw - this.m_orbitYaw) * MinF(1.0, dt * 3.0));
    } else {
      this.m_orbitYaw = this.yaw;
    }
    this.pos = CMPilotRig.Ring(ground, this.m_orbitYaw, up + bob + this.m_jolt, fwd);

    let target = zoom ? this.m_fovZoom : this.m_fovBase;
    this.fov += (target - this.fov) * MinF(1.0, dt * 7.0);
  }

  private func Step(h: Float) -> Void {
    // torso yaw: spring toward the aim, rate-capped
    let dy = CMPilotRig.Wrap(this.aimYaw - this.yaw);
    this.m_yawVel += (this.m_turnK * dy - this.m_turnDamp * this.m_yawVel) * h;
    this.m_yawVel = ClampF(this.m_yawVel, -this.m_maxYawRate, this.m_maxYawRate);
    this.yaw = CMPilotRig.Wrap(this.yaw + this.m_yawVel * h);

    let dp = this.aimPitch - this.pitch;
    this.m_pitchVel += (this.m_turnK * dp - this.m_turnDamp * this.m_pitchVel) * h;
    this.m_pitchVel = ClampF(this.m_pitchVel, -this.m_maxPitchRate, this.m_maxPitchRate);
    this.pitch = ClampF(this.pitch + this.m_pitchVel * h, this.m_pitchMin - 4.0, this.m_pitchMax + 4.0);

    // the recoil shake: stiff and well damped, back to zero within a quarter second
    this.m_kickPitchVel += (-220.0 * this.kickPitch - 22.0 * this.m_kickPitchVel) * h;
    this.kickPitch = ClampF(this.kickPitch + this.m_kickPitchVel * h, -1.0, 1.5);
    this.m_kickYawVel += (-220.0 * this.kickYaw - 22.0 * this.m_kickYawVel) * h;
    this.kickYaw = ClampF(this.kickYaw + this.m_kickYawVel * h, -1.2, 1.2);

    // roll and the vertical jolt settle back to zero
    this.m_rollVel += (-40.0 * this.roll - 7.0 * this.m_rollVel) * h;
    this.roll += this.m_rollVel * h;
    this.m_joltVel += (-120.0 * this.m_jolt - 14.0 * this.m_joltVel) * h;
    this.m_jolt = ClampF(this.m_jolt + this.m_joltVel * h, -0.25, 0.15);
  }

  public static func Ring(ground: Vector4, yaw: Float, up: Float, fwd: Float) -> Vector4 {
    let d = CMPilotRig.Dir(yaw, 0.0);
    return new Vector4(ground.X + d.X * fwd, ground.Y + d.Y * fwd, ground.Z + up, 1.0);
  }

  // where the reticle points
  public func Forward() -> Vector4 = CMPilotRig.Dir(this.yaw, this.pitch)

  public static func Dir(yaw: Float, pitch: Float) -> Vector4 {
    let y = Deg2Rad(yaw);
    let p = Deg2Rad(pitch);
    let c = CosF(p);
    return new Vector4(-SinF(y) * c, CosF(y) * c, SinF(p), 0.0);
  }

  // yaw of a direction on the ground plane
  public static func YawOf(v: Vector4) -> Float {
    return Rad2Deg(AtanF(-v.X, v.Y));
  }

  public static func Wrap(a: Float) -> Float {
    let r = a;
    while r > 180.0 { r -= 360.0; }
    while r < -180.0 { r += 360.0; }
    return r;
  }
}
