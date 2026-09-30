// =============================================================================
// CONTROLLABLE MECHS - PILOT CAMERA RIG (the weight)
//
// Pure math, no game calls. Each frame it takes where the pilot wants to look
// (aim yaw/pitch from the mouse), where the sensor mount is on the mech and the
// mech's ground position, and returns where the virtual camera is:
//   - turning is a spring with mass: it accelerates, is capped at the torso's
//     traverse rate, overshoots a little and settles
//   - the position is pinned to the mount (no lag: a lagging camera drifts off
//     the mech and shakes against its steps); the weight is added on top as
//     small offsets that settle back: a bob and a jolt plus roll on every
//     footfall, and a kick on every shot
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
  public let jumped: Float;         // metres the mech moved in one frame, when it's a jump (for the log)

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

  // tuning (set in Init: field defaults can't be negative)
  private let m_pitchMin: Float;
  private let m_pitchMax: Float;
  private let m_turnK: Float;
  private let m_turnDamp: Float;
  private let m_maxYawRate: Float;
  private let m_maxPitchRate: Float;
  private let m_stride: Float;
  private let m_bobAmp: Float;
  private let m_fovBase: Float;
  private let m_fovZoom: Float;

  public func Init(mount: Vector4, ground: Vector4, facingYaw: Float) -> Void {
    this.m_pitchMin = -35.0;
    this.m_pitchMax = 30.0;
    this.m_turnK = 26.0;        // stiffness of the torso turn
    this.m_turnDamp = 6.0;      // < 2*sqrt(K) ~ 10.2: underdamped, a slight overshoot
    this.m_maxYawRate = 80.0;   // deg/s: the torso can't whip around
    this.m_maxPitchRate = 55.0;
    this.m_stride = 2.4;        // metres per footfall
    this.m_bobAmp = 0.08;
    this.m_fovBase = 68.0;
    this.m_fovZoom = 34.0;

    this.aimYaw = facingYaw;
    this.aimPitch = 0.0;
    this.yaw = facingYaw;
    this.pitch = 0.0;
    this.roll = 0.0;
    this.pos = mount;
    this.fov = this.m_fovBase;
    this.speed = 0.0;
    this.jumped = 0.0;
    this.m_yawVel = 0.0;
    this.m_pitchVel = 0.0;
    this.m_rollVel = 0.0;
    this.m_jolt = 0.0;
    this.m_joltVel = 0.0;
    this.m_lastGround = ground;
    this.m_phase = 0.0;
    this.m_step = 0;
    this.m_side = 1.0;
    this.m_ready = true;
  }

  // mouse deltas, already scaled to degrees
  public func Look(dYaw: Float, dPitch: Float) -> Void {
    this.aimYaw = CMPilotRig.Wrap(this.aimYaw + dYaw);
    this.aimPitch = ClampF(this.aimPitch + dPitch, this.m_pitchMin, this.m_pitchMax);
  }

  // a shot: `k` 0..1 scales the kick
  public func Recoil(k: Float) -> Void {
    this.m_pitchVel += 16.0 * k;
    this.m_yawVel += RandRangeF(-7.0, 7.0) * k;
    this.m_joltVel -= 0.4 * k;
  }

  // `mount`: where the sensor is this frame; `ground`: the mech's own position
  public func Update(dt: Float, mount: Vector4, ground: Vector4, zoom: Bool) -> Void {
    if !this.m_ready {
      return;
    }
    // speed from the mech itself (the mount swings when the body turns)
    let d = ground - this.m_lastGround;
    d.Z = 0.0;
    let moved = Vector4.Length(d);
    this.m_lastGround = ground;
    this.jumped = 0.0;
    let v = dt > 0.0 ? moved / dt : 0.0;
    if moved > 3.0 {
      this.jumped = moved;   // the mech was moved by the game, not by walking
      v = this.speed;
    }
    this.speed += (v - this.speed) * MinF(1.0, dt * 4.0);

    // two substeps keep the springs stable on a slow frame
    let steps = dt > 0.02 ? 2 : 1;
    let h = dt / Cast<Float>(steps);
    let i = 0;
    while i < steps {
      this.Step(h);
      i += 1;
    }

    // stride: a jolt and a little roll on each footfall
    let walk = ClampF(this.speed / 3.0, 0.0, 1.0);
    if walk > 0.05 {
      this.m_phase += dt * this.speed / this.m_stride * Pi();
      let step = FloorF(this.m_phase / Pi());
      if step != this.m_step {
        this.m_step = step;
        this.m_side = -this.m_side;
        this.m_joltVel -= 0.9 * walk;
        this.m_pitchVel -= 5.0 * walk;
        this.m_rollVel += 8.0 * walk * this.m_side;
      }
    }

    // pinned to the mount, weight on top
    let bob = -this.m_bobAmp * walk * AbsF(SinF(this.m_phase));
    this.pos = new Vector4(mount.X, mount.Y, mount.Z + bob + this.m_jolt, 1.0);

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

    // roll and the vertical jolt settle back to zero
    this.m_rollVel += (-40.0 * this.roll - 7.0 * this.m_rollVel) * h;
    this.roll += this.m_rollVel * h;
    this.m_joltVel += (-120.0 * this.m_jolt - 14.0 * this.m_joltVel) * h;
    this.m_jolt = ClampF(this.m_jolt + this.m_joltVel * h, -0.25, 0.15);
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
