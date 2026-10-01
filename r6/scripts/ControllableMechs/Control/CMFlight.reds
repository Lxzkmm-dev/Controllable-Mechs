// =============================================================================
// MECHS OF NIGHT CITY - CONTROL FRAMEWORK: DRONE FLIGHT MODEL (0.7.0, 6-DOF)
//
// A multirotor as a rigid body, simulated by the mod (docs/DRONES_TECHNICAL_DESIGN.md).
// Nothing here is kinematic: every motion comes from forces and torques.
//   - state: position and velocity of the centre of mass, orientation as a quaternion
//     (no angle limits: it can loop and roll over), angular velocity in the body frame,
//     and per-axis inertia
//   - four rotors in an X at their real positions, each spooling toward its command and
//     giving thrust by its efficiency (damage); their counter-torque turns the body
//   - quadratic drag per body axis (the top speed is where drag meets thrust, there is no
//     cap), a little linear drag, blade-flapping moments from the airflow (speed pushes
//     the nose up and the tilt back), angular damping, gyroscopic coupling, gravity
//   - a flight controller that only commands rotors: an attitude loop (angle mode) and a
//     rate loop (acro) blended by the self-levelling setting, the yaw following the view,
//     and an altitude-hold assist on the collective. A mixer turns the wanted torques and
//     thrust into rotor commands, keeping the differentials when it saturates (air mode)
// Body frame: X right, Y forward, Z up (the game's). Body rates: X + nose up, Y + right
// side down, Z + turning left. Pure maths: the drone unit feeds input, sweeps collisions
// and puts the drone where it says. Mirrored in Python for tuning (offline checks).
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

// one drone type's numbers
public class CMFlightProfile {
  public let mass: Float;          // kg
  public let arm: Float;           // m, rotor distance from the centre
  public let thrust: Float;        // N per rotor at full spool
  public let spool: Float;         // s, rotor spool time constant
  public let kq: Float;            // m, a rotor's counter-torque per newton of thrust (yaw)
  public let agility: Float;       // 1/s, the rate loop's bandwidth (how quickly it can turn)
  public let tilt: Float;          // deg, the angle mode's tilt
  public let tiltRate: Float;      // deg/s, the full-stick rate (acro)
  public let yawRate: Float;       // deg/s, the most it turns toward the view
  public let climb: Float;         // m/s, full climb or descent
  public let cdh: Float;           // m2, drag area across the body's sides and front
  public let cdv: Float;           // m2, drag area flat on (vertical)
  public let flap: Float;          // N.m per m/s: blade flapping (airflow tilting it back)
  public let impact: Float;        // m/s, a collision faster than this does damage
  public let radius: Float;        // m, its collision sphere
  public let com: Float;           // m, its centre of mass above the model's origin
  public let bottom: Float;        // m, from the centre of mass down to its lowest point, level
  public let span: Float;          // m, from the centre out to its widest point (rotors, wings)
  public let ramp: Float;          // s, a key goes from nothing to full stick over this (keys are on/off)
  public let expo: Float;          // 0-1, stick expo: how soft the start of the stick travel is
  public let showTilt: Float;      // deg, the most the model is drawn tilted (90 = as flown)
}

public class CMFlight {
  public let pos: Vector4;         // centre of mass
  public let vel: Vector4;
  public let q: Quaternion;        // body to world
  public let w: Vector4;           // angular velocity, body frame, rad/s
  public let spool: array<Float>;  // front left, front right, back left, back right (0-1)
  public let eff: array<Float>;    // each rotor's efficiency, 0-1 (damage)
  public let level: Float;         // self-levelling, 0 (acro) to 1 (angle mode)
  public let holdZ: Float;         // the altitude held with no climb input
  public let holding: Bool;
  public let grounded: Bool;       // resting on the ground (set by the unit's contacts)
  public let p: ref<CMFlightProfile>;
  // derived each step, for the camera, the HUD and the log (degrees)
  public let yaw: Float;
  public let pitch: Float;
  public let roll: Float;

  public static func Make(p: ref<CMFlightProfile>, pos: Vector4, yaw: Float) -> ref<CMFlight> {
    let f = new CMFlight();
    f.p = p;
    f.pos = pos;
    f.vel = new Vector4(0.0, 0.0, 0.0, 0.0);
    f.w = new Vector4(0.0, 0.0, 0.0, 0.0);
    let half = Deg2Rad(yaw) * 0.5;
    f.q.i = 0.0;
    f.q.j = 0.0;
    f.q.k = SinF(half);
    f.q.r = CosF(half);
    let hover = ClampF(p.mass * 9.81 / (4.0 * p.thrust), 0.0, 1.0);
    let i = 0;
    while i < 4 {
      ArrayPush(f.spool, hover);
      ArrayPush(f.eff, 1.0);
      i += 1;
    }
    f.holdZ = pos.Z;
    f.holding = true;
    f.Angles();
    return f;
  }

  // ---- quaternion maths (i, j, k, r = x, y, z, w) ----
  public static func QMul(a: Quaternion, b: Quaternion) -> Quaternion {
    let o: Quaternion;
    o.r = a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k;
    o.i = a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j;
    o.j = a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i;
    o.k = a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r;
    return o;
  }

  // v rotated by q
  public static func QRot(q: Quaternion, v: Vector4) -> Vector4 {
    let tx = 2.0 * (q.j * v.Z - q.k * v.Y);
    let ty = 2.0 * (q.k * v.X - q.i * v.Z);
    let tz = 2.0 * (q.i * v.Y - q.j * v.X);
    return new Vector4(v.X + q.r * tx + (q.j * tz - q.k * ty), v.Y + q.r * ty + (q.k * tx - q.i * tz), v.Z + q.r * tz + (q.i * ty - q.j * tx), 0.0);
  }

  // v rotated by q's inverse (world to body)
  public static func QInvRot(q: Quaternion, v: Vector4) -> Vector4 {
    let c: Quaternion;
    c.i = -q.i;
    c.j = -q.j;
    c.k = -q.k;
    c.r = q.r;
    return CMFlight.QRot(c, v);
  }

  public static func Cross(a: Vector4, b: Vector4) -> Vector4 = new Vector4(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X, 0.0)

  public func Up() -> Vector4 = CMFlight.QRot(this.q, new Vector4(0.0, 0.0, 1.0, 0.0))
  public func Forward() -> Vector4 = CMFlight.QRot(this.q, new Vector4(0.0, 1.0, 0.0, 0.0))
  public func Right() -> Vector4 = CMFlight.QRot(this.q, new Vector4(1.0, 0.0, 0.0, 0.0))

  // inertia per body axis (pitch and roll alike, yaw)
  private func Ix() -> Float = this.p.mass * this.p.arm * this.p.arm * 0.5
  private func Iz() -> Float = this.p.mass * this.p.arm * this.p.arm * 0.8

  // one step. fwd/side: the keys (-1..1), c: climb (-1..1), view: the yaw the view looks at
  public func Step(dt: Float, fwd: Float, side: Float, c: Float, view: Float) -> Void {
    let p = this.p;
    let m = p.mass;
    let stick = SqrtF(fwd * fwd + side * side);
    if stick > 1.0 {
      fwd /= stick;
      side /= stick;
    }
    let up = this.Up();
    let heading = this.yaw;
    // --- the flight controller: wanted body rates ---
    // acro: the keys are rates
    let rate = Deg2Rad(p.tiltRate);
    let acroX = -fwd * rate;
    let acroY = side * rate;
    // angle mode: the keys are a tilt about the current heading; the error between the
    // body's up and the wanted up, in the body frame, is the rate to turn at
    let hy = Deg2Rad(heading) * 0.5;
    let tp = Deg2Rad(-fwd * p.tilt) * 0.5;
    let tr = Deg2Rad(side * p.tilt) * 0.5;
    let qy: Quaternion;
    qy.k = SinF(hy);
    qy.r = CosF(hy);
    let qp: Quaternion;
    qp.i = SinF(tp);
    qp.r = CosF(tp);
    let qr: Quaternion;
    qr.j = SinF(tr);
    qr.r = CosF(tr);
    let wantUp = CMFlight.QRot(CMFlight.QMul(CMFlight.QMul(qy, qp), qr), new Vector4(0.0, 0.0, 1.0, 0.0));
    let err = CMFlight.QInvRot(this.q, CMFlight.Cross(up, wantUp));
    let ka = p.agility * 0.4;
    let wantX = acroX + (err.X * ka - acroX) * this.level;
    let wantY = acroY + (err.Y * ka - acroY) * this.level;
    let dyaw = CMPilotRig.Wrap(view - heading);
    let wantZ = Deg2Rad(ClampF(dyaw * 5.0, -p.yawRate, p.yawRate));
    // the rate loop: torques
    let ix = this.Ix();
    let iz = this.Iz();
    let tx = ix * p.agility * (wantX - this.w.X);
    let ty = ix * p.agility * (wantY - this.w.Y);
    let tz = iz * p.agility * 0.5 * (wantZ - this.w.Z);
    // the collective: climb rate, or the altitude held
    let az: Float;
    if this.grounded && c <= 0.05 {
      // sitting on the ground: it settles there (the hold used to press it into the ground
      // and the contacts kicked back: the drone "freaking out" once it touched down)
      this.holding = true;
      this.holdZ = this.pos.Z;
      az = -1.0;
    } else if AbsF(c) > 0.05 {
      this.holding = false;
      az = (c * p.climb - this.vel.Z) * 1.6;
    } else {
      if !this.holding {
        this.holding = true;
        this.holdZ = this.pos.Z + this.vel.Z * 0.6;   // where it will come to rest
      }
      az = (this.holdZ - this.pos.Z) * 0.8 - this.vel.Z;
    }
    // tilted, more thrust holds the height; past ~70 deg (or inverted) it stops trying
    let tc = up.Z > 0.3 ? m * (9.81 + az) / up.Z : m * 9.81 * 0.6;
    // --- the mixer: thrust and torques to the four rotors ---
    let d = p.arm * 0.7071;
    let base = tc * 0.25;
    let px = tx / (4.0 * d);
    let py = ty / (4.0 * d);
    let pz = tz / (4.0 * p.kq);
    // front left, front right, back left, back right
    let cmd: array<Float> = [(base + px + py + pz) / p.thrust, (base + px - py - pz) / p.thrust, (base - px + py - pz) / p.thrust, (base - px - py + pz) / p.thrust];
    let lo = MinF(MinF(cmd[0], cmd[1]), MinF(cmd[2], cmd[3]));
    let hi = MaxF(MaxF(cmd[0], cmd[1]), MaxF(cmd[2], cmd[3]));
    let i = 0;
    while i < 4 {
      // air mode: the differentials are kept, the collective gives way
      if hi - lo > 1.0 {
        cmd[i] = (cmd[i] - lo) / (hi - lo);
      } else {
        if hi > 1.0 {
          cmd[i] -= hi - 1.0;
        } else {
          if lo < 0.0 {
            cmd[i] -= lo;
          }
        }
      }
      this.spool[i] += (cmd[i] - this.spool[i]) * MinF(1.0, dt / MaxF(0.01, p.spool));
      i += 1;
    }
    let t0 = this.spool[0] * this.eff[0] * p.thrust;
    let t1 = this.spool[1] * this.eff[1] * p.thrust;
    let t2 = this.spool[2] * this.eff[2] * p.thrust;
    let t3 = this.spool[3] * this.eff[3] * p.thrust;
    // --- torques on the body ---
    let bx = d * (t0 + t1 - t2 - t3);                // front heavier: nose up
    let by = d * (t0 - t1 + t2 - t3);                // left heavier: right side down
    let bz = p.kq * (t0 - t1 - t2 + t3);             // the rotors' counter-torque
    let vb = CMFlight.QInvRot(this.q, this.vel);
    bx += p.flap * vb.Y;                             // airflow: speed lifts the nose
    by -= p.flap * vb.X;                             // and leans it back from a slide
    // the air damps rotation a little; the ground, when it sits on it, a lot
    let damp = this.grounded ? 8.0 : 1.5;
    bx -= ix * damp * this.w.X;
    by -= ix * damp * this.w.Y;
    bz -= iz * (this.grounded ? 4.0 : 1.0) * this.w.Z;
    // Euler's equation, with the gyroscopic term
    let gx = this.w.Y * (iz * this.w.Z) - this.w.Z * (ix * this.w.Y);
    let gy = this.w.Z * (ix * this.w.X) - this.w.X * (iz * this.w.Z);
    let gz = this.w.X * (ix * this.w.Y) - this.w.Y * (ix * this.w.X);
    this.w.X += (bx - gx) / ix * dt;
    this.w.Y += (by - gy) / ix * dt;
    this.w.Z += (bz - gz) / iz * dt;
    // the orientation
    let wq: Quaternion;
    wq.i = this.w.X;
    wq.j = this.w.Y;
    wq.k = this.w.Z;
    wq.r = 0.0;
    let dq = CMFlight.QMul(this.q, wq);
    this.q.i += 0.5 * dq.i * dt;
    this.q.j += 0.5 * dq.j * dt;
    this.q.k += 0.5 * dq.k * dt;
    this.q.r += 0.5 * dq.r * dt;
    let n = SqrtF(this.q.i * this.q.i + this.q.j * this.q.j + this.q.k * this.q.k + this.q.r * this.q.r);
    this.q.i /= n;
    this.q.j /= n;
    this.q.k /= n;
    this.q.r /= n;
    // --- forces ---
    let force = CMFlight.QRot(this.q, new Vector4(0.0, 0.0, t0 + t1 + t2 + t3, 0.0));
    let drag = new Vector4(-0.6 * p.cdh * vb.X * AbsF(vb.X), -0.6 * p.cdh * vb.Y * AbsF(vb.Y), -0.6 * p.cdv * vb.Z * AbsF(vb.Z), 0.0);
    force += CMFlight.QRot(this.q, drag);
    force -= this.vel * (0.05 * m);
    force.Z -= m * 9.81;
    this.vel.X += force.X / m * dt;
    this.vel.Y += force.Y / m * dt;
    this.vel.Z += force.Z / m * dt;
    this.pos.X += this.vel.X * dt;
    this.pos.Y += this.vel.Y * dt;
    this.pos.Z += this.vel.Z * dt;
    this.pos.W = 1.0;
    this.Angles();
  }

  // heading, pitch (nose up +) and roll (right side down +), in degrees
  private func Angles() -> Void {
    let f = this.Forward();
    let r = this.Right();
    this.yaw = Rad2Deg(AtanF(-f.X, f.Y));
    this.pitch = Rad2Deg(AsinF(ClampF(f.Z, -1.0, 1.0)));
    this.roll = Rad2Deg(AsinF(ClampF(-r.Z, -1.0, 1.0)));
  }

  // A contact at `r` from the centre of mass (world), against a surface facing `normal`:
  // an impulse at that point stops the motion into it (with `bounce` of it back) and
  // takes off up to `grip` x it of the sliding, so a glancing or off-centre hit spins the
  // drone. Returns how fast it hit.
  public func Contact(normal: Vector4, r: Vector4, bounce: Float, grip: Float) -> Float {
    let wWorld = CMFlight.QRot(this.q, this.w);
    let vc = this.vel + CMFlight.Cross(wWorld, r);
    let vn = Vector4.Dot(vc, normal);
    if vn >= 0.0 {
      return 0.0;
    }
    let m = this.p.mass;
    let ix = this.Ix();
    let iz = this.Iz();
    // the effective mass at the contact
    let rn = CMFlight.QInvRot(this.q, CMFlight.Cross(r, normal));
    let irn = CMFlight.QRot(this.q, new Vector4(rn.X / ix, rn.Y / ix, rn.Z / iz, 0.0));
    let k = 1.0 / m + Vector4.Dot(CMFlight.Cross(irn, r), normal);
    let j = -(1.0 + bounce) * vn / MaxF(0.0001, k);
    // friction along the surface
    let vt = vc - normal * vn;
    let slide = Vector4.Length(vt);
    let impulse = normal * j;
    if slide > 0.001 {
      // the effective mass along the slide (its lever arm differs from the normal's)
      let tdir = vt / slide;
      let rt = CMFlight.QInvRot(this.q, CMFlight.Cross(r, tdir));
      let irt = CMFlight.QRot(this.q, new Vector4(rt.X / ix, rt.Y / ix, rt.Z / iz, 0.0));
      let kt = 1.0 / m + Vector4.Dot(CMFlight.Cross(irt, r), tdir);
      impulse -= tdir * MinF(grip * j, slide / MaxF(0.0001, kt));
    }
    this.vel += impulse / m;
    let ang = CMFlight.QInvRot(this.q, CMFlight.Cross(r, impulse));
    this.w.X += ang.X / ix;
    this.w.Y += ang.Y / ix;
    this.w.Z += ang.Z / iz;
    this.LimitSpin();
    return -vn;
  }

  // a tumble is capped at about 1,150 deg/s (a light drone scraping the ground at speed
  // could otherwise be flung into an unreadable spin)
  private func LimitSpin() -> Void {
    let s = Vector4.Length(this.w);
    if s > 20.0 {
      this.w = this.w * (20.0 / s);
    }
  }

  // How far below the centre of mass the model's base is, as it is tilted now. Only the
  // body counts, not the rotor or wing tips: with them the contact sat a rotor's reach
  // above the road and the drone could never get down onto it (Omar: "I could not get low
  // enough to touch the floor"). A tip that clips the road on a hard bank is the pilot's
  // problem, as it would be for a real drone.
  public func Reach() -> Float {
    return this.p.bottom * AbsF(ClampF(this.Up().Z, -1.0, 1.0));
  }

  // The orientation the model is drawn with: the flown one, or with its pitch and roll
  // held within `limit` degrees (the heading always as flown). Omar: the physics stays
  // unlimited, only how far the Bombus model leans is capped, so it doesn't look as if it
  // is planting its face in the floor.
  public func Shown(limit: Float) -> Quaternion {
    if limit >= 89.0 {
      return this.q;
    }
    let hy = Deg2Rad(this.yaw) * 0.5;
    let hp = Deg2Rad(ClampF(this.pitch, -limit, limit)) * 0.5;
    let hr = Deg2Rad(ClampF(this.roll, -limit, limit)) * 0.5;
    let qy: Quaternion;
    qy.k = SinF(hy);
    qy.r = CosF(hy);
    let qp: Quaternion;
    qp.i = SinF(hp);
    qp.r = CosF(hp);
    let qr: Quaternion;
    qr.j = SinF(hr);
    qr.r = CosF(hr);
    return CMFlight.QMul(CMFlight.QMul(qy, qp), qr);
  }

  // the spool of the four rotors on average, for the HUD
  public func Spool() -> Float = (this.spool[0] + this.spool[1] + this.spool[2] + this.spool[3]) * 0.25
}

public abstract class CMDroneProfiles {
  // what the CONFIG self-levelling slider starts at, per type (%). With a key held the
  // tilt settles where the rate and the levelling balance, past the tilt setting when the
  // levelling is low; lower is more acro.
  public static func DefaultLevel(kind: String) -> Int32 {
    switch kind {
      case "bombus": return 75;
      case "octant": return 95;
    }
    return 85;
  }

  public static func For(kind: String) -> ref<CMFlightProfile> {
    let p = new CMFlightProfile();
    switch kind {
      case "bombus":
        // Omar: it pitched forward far too hard and too fast; gentler defaults
        p.mass = 6.0; p.arm = 0.2; p.thrust = 30.0; p.spool = 0.06; p.kq = 0.02; p.agility = 11.0;
        p.tilt = 25.0; p.tiltRate = 140.0; p.yawRate = 200.0; p.climb = 5.0;
        p.cdh = 0.3; p.cdv = 0.45; p.flap = 0.06; p.impact = 6.0; p.radius = 0.3; p.com = 0.13;
        p.bottom = 0.13; p.span = 0.27; p.ramp = 0.3; p.expo = 0.6; p.showTilt = 25.0;
        break;
      case "octant":
        p.mass = 180.0; p.arm = 1.0; p.thrust = 900.0; p.spool = 0.14; p.kq = 0.08; p.agility = 4.5;
        p.tilt = 20.0; p.tiltRate = 90.0; p.yawRate = 60.0; p.climb = 3.0;
        p.cdh = 10.7; p.cdv = 16.0; p.flap = 2.0; p.impact = 5.0; p.radius = 1.1; p.com = 0.15;
        p.bottom = 0.92; p.span = 1.4; p.ramp = 0.2; p.expo = 0.3; p.showTilt = 90.0;
        break;
      default:   // griffin, wyvern
        p.mass = 40.0; p.arm = 0.45; p.thrust = 190.0; p.spool = 0.10; p.kq = 0.04; p.agility = 9.0;
        p.tilt = 22.0; p.tiltRate = 120.0; p.yawRate = 110.0; p.climb = 4.0;
        p.cdh = 1.9; p.cdv = 2.8; p.flap = 0.35; p.impact = 5.5; p.radius = 0.5; p.com = Equals(kind, "wyvern") ? 0.22 : 0.0;
        // measured on their meshes: the Griffin's origin is at its middle, the Wyvern's at its base
        p.bottom = Equals(kind, "wyvern") ? 0.22 : 0.48; p.span = Equals(kind, "wyvern") ? 0.5 : 0.62; p.ramp = 0.2; p.expo = 0.3; p.showTilt = 90.0;
    }
    return p;
  }
}
