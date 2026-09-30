// =============================================================================
// CONTROLLABLE MECHS - PILOT CAMERA RIG (the weight)
//
// Pure math, no game calls. Each frame it takes where the pilot wants to look
// (aim yaw/pitch from the mouse) and where the sensor mount is on the mech, and
// returns where the virtual camera actually is:
//   - turning is a spring with mass: it accelerates, is capped at the torso's
//     traverse rate, overshoots a little and settles
//   - the camera position hangs off the mount on a stiff spring, so starts and
//     stops lag and then catch up
//   - the mech's speed drives a stride: a vertical bob plus a jolt and a small
//     roll on every footfall
//   - each shot kicks the view (recoil)
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
  private let m_posVel: Vector4;
  private let m_lastMount: Vector4;
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
  private let m_posK: Float;
  private let m_posDamp: Float;
  private let m_stride: Float;
  private let m_bobAmp: Float;
  private let m_fovBase: Float;
  private let m_fovZoom: Float;

  public func Init(mount: Vector4, facingYaw: Float) -> Void {
    this.m_pitchMin = -35.0;
    this.m_pitchMax = 30.0;
    this.m_turnK = 26.0;        // stiffness of the torso turn
    this.m_turnDamp = 6.0;      // < 2*sqrt(K) ~ 10.2: underdamped, a slight overshoot
    this.m_maxYawRate = 80.0;   // deg/s: the torso can't whip around
    this.m_maxPitchRate = 55.0;
    this.m_posK = 90.0;
    this.m_posDamp = 15.0;
    this.m_stride = 2.4;        // metres per footfall
    this.m_bobAmp = 0.10;
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
    this.m_yawVel = 0.0;
    this.m_pitchVel = 0.0;
    this.m_rollVel = 0.0;
    this.m_posVel = new Vector4(0.0, 0.0, 0.0, 0.0);
    this.m_lastMount = mount;
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
    this.m_posVel.X += RandRangeF(-0.15, 0.15) * k;
    this.m_posVel.Y += RandRangeF(-0.15, 0.15) * k;
  }

  public func Update(dt: Float, mount: Vector4, zoom: Bool) -> Void {
    if !this.m_ready {
      return;
    }
    // two substeps keep the springs stable on a slow frame
    let steps = dt > 0.02 ? 2 : 1;
    let h = dt / Cast<Float>(steps);
    let i = 0;
    while i < steps {
      this.Step(h, mount);
      i += 1;
    }
    // speed from how far the mount moved (smoothed)
    let d = mount - this.m_lastMount;
    d.Z = 0.0;
    let v = dt > 0.0 ? Vector4.Length(d) / dt : 0.0;
    if v > 30.0 {
      v = 0.0;   // a teleport, not a stride
    }
    this.speed += (v - this.speed) * MinF(1.0, dt * 4.0);
    this.m_lastMount = mount;

    // stride: bob and a jolt on each footfall
    let walk = ClampF(this.speed / 3.0, 0.0, 1.0);
    if walk > 0.05 {
      this.m_phase += dt * this.speed / this.m_stride * Pi();
      let step = FloorF(this.m_phase / Pi());
      if step != this.m_step {
        this.m_step = step;
        this.m_side = -this.m_side;
        this.m_posVel.Z -= 1.4 * walk;
        this.m_pitchVel -= 6.0 * walk;
        this.m_rollVel += 9.0 * walk * this.m_side;
      }
    }

    // zoom
    let target = zoom ? this.m_fovZoom : this.m_fovBase;
    this.fov += (target - this.fov) * MinF(1.0, dt * 7.0);
  }

  private func Step(h: Float, mount: Vector4) -> Void {
    // torso yaw: spring toward the aim, rate-capped
    let dy = CMPilotRig.Wrap(this.aimYaw - this.yaw);
    this.m_yawVel += (this.m_turnK * dy - this.m_turnDamp * this.m_yawVel) * h;
    this.m_yawVel = ClampF(this.m_yawVel, -this.m_maxYawRate, this.m_maxYawRate);
    this.yaw = CMPilotRig.Wrap(this.yaw + this.m_yawVel * h);

    let dp = this.aimPitch - this.pitch;
    this.m_pitchVel += (this.m_turnK * dp - this.m_turnDamp * this.m_pitchVel) * h;
    this.m_pitchVel = ClampF(this.m_pitchVel, -this.m_maxPitchRate, this.m_maxPitchRate);
    this.pitch = ClampF(this.pitch + this.m_pitchVel * h, this.m_pitchMin - 4.0, this.m_pitchMax + 4.0);

    // roll settles back to level
    this.m_rollVel += (-40.0 * this.roll - 7.0 * this.m_rollVel) * h;
    this.roll += this.m_rollVel * h;

    // position hangs off the mount; a big jump (teleport) snaps
    let bob = this.walkBob();
    let goal = new Vector4(mount.X, mount.Y, mount.Z + bob, 1.0);
    let off = goal - this.pos;
    if Vector4.Length(off) > 8.0 {
      this.pos = goal;
      this.m_posVel = new Vector4(0.0, 0.0, 0.0, 0.0);
      return;
    }
    this.m_posVel.X += (this.m_posK * off.X - this.m_posDamp * this.m_posVel.X) * h;
    this.m_posVel.Y += (this.m_posK * off.Y - this.m_posDamp * this.m_posVel.Y) * h;
    this.m_posVel.Z += (this.m_posK * off.Z - this.m_posDamp * this.m_posVel.Z) * h;
    this.pos.X += this.m_posVel.X * h;
    this.pos.Y += this.m_posVel.Y * h;
    this.pos.Z += this.m_posVel.Z * h;
  }

  private func walkBob() -> Float {
    let walk = ClampF(this.speed / 3.0, 0.0, 1.0);
    return -this.m_bobAmp * walk * AbsF(SinF(this.m_phase));
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
