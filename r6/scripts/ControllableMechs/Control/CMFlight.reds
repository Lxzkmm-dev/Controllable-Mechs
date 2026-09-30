// =============================================================================
// MECHS OF NIGHT CITY - CONTROL FRAMEWORK: DRONE FLIGHT MODEL (0.7.0)
//
// A multirotor, simulated by the mod (docs/DRONES_TECHNICAL_DESIGN.md, section 5):
//   - lift along the body's up axis, so tilting the body is what moves it
//   - four rotors, each spooling toward its command with a lag and giving thrust by its
//     efficiency (damage lowers it); uneven thrust also rolls and pitches the body
//   - gravity, split horizontal and vertical drag, and a top speed past which thrust is
//     dropped rather than the speed clamped
//   - angle mode (default): the keys set a wanted tilt, eased near its limit, and a PD
//     loop brings the body to it; with no climb input a damped spring holds the altitude
//   - self-levelling is a blend (0-1, a per-drone setting): at 1 the angle mode above,
//     at 0 pure acro (the keys set roll and pitch rates, nothing levels it), between the
//     two the stick still flies the rates and the drone drifts back toward level
// Pure maths on its own state: the drone unit feeds it input and puts the drone where
// it says (AI teleport), and runs the collision checks. Nothing here touches the game.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

// one drone type's numbers
public class CMFlightProfile {
  public let mass: Float;          // kg
  public let thrust: Float;        // N per rotor at full spool
  public let spool: Float;         // s, rotor spool time constant
  public let tilt: Float;          // deg, the angle mode's limit
  public let tiltRate: Float;      // deg/s, acro's full-stick rate
  public let top: Float;           // m/s
  public let dragH: Float;         // 1/s
  public let dragV: Float;         // 1/s
  public let climb: Float;         // m/s, full climb or descent
  public let yawRate: Float;       // deg/s, the body follows the view this fast
  public let arm: Float;           // m, rotor distance from the centre
  public let impact: Float;        // m/s, a collision faster than this does damage
  public let radius: Float;        // m, its collision sphere
  public let agility: Float;       // 1/s, how quickly its rotors can swing the body (inertia)
  public let aero: Float;          // deg/s2 per m/s: airflow pushing the nose up and the tilt back
  public let yawAccel: Float;      // deg/s2, how hard it can wind into a turn
  public let com: Float;           // m, its centre of mass above the model's origin
}

public class CMFlight {
  public let pos: Vector4;
  public let vel: Vector4;
  public let yaw: Float;
  public let pitch: Float;         // nose down is negative
  public let roll: Float;          // right side down is positive
  public let pitchRate: Float;
  public let rollRate: Float;
  public let yawRate: Float;
  public let spool: array<Float>;  // four rotors, 0-1: front left, front right, back left, back right
  public let eff: array<Float>;    // each rotor's efficiency, 0-1 (damage)
  public let level: Float;         // self-levelling, 0 (acro) to 1 (angle mode)
  public let holdZ: Float;         // the altitude held with no climb input
  public let holding: Bool;
  public let p: ref<CMFlightProfile>;

  public static func Make(p: ref<CMFlightProfile>, pos: Vector4, yaw: Float) -> ref<CMFlight> {
    let f = new CMFlight();
    f.p = p;
    f.pos = pos;
    f.vel = new Vector4(0.0, 0.0, 0.0, 0.0);
    f.yaw = yaw;
    let hover = CMFlight.HoverSpool(p);
    let i = 0;
    while i < 4 {
      ArrayPush(f.spool, hover);
      ArrayPush(f.eff, 1.0);
      i += 1;
    }
    f.holdZ = pos.Z;
    f.holding = true;
    return f;
  }

  // the spool that holds the drone in the air, level and undamaged
  public static func HoverSpool(p: ref<CMFlightProfile>) -> Float = ClampF(p.mass * 9.81 / (4.0 * p.thrust), 0.0, 1.0)

  // one step. f/s: forward/right stick (-1..1), c: climb (-1..1), view: the yaw to face
  public func Step(dt: Float, fwd: Float, side: Float, c: Float, view: Float) -> Void {
    let p = this.p;
    // a diagonal stick is no stronger than a straight one
    let stick = SqrtF(fwd * fwd + side * side);
    if stick > 1.0 {
      fwd /= stick;
      side /= stick;
    }
    // --- the body's attitude: angle mode aims for a tilt, acro for a rate ---
    // acro: the stick is a rate. Angle mode: the stick is a tilt the body is brought to.
    // The self-levelling setting blends the two.
    let acroPitch = -fwd * p.tiltRate;
    let acroRoll = side * p.tiltRate;
    let ka = p.agility * 0.4;
    let anglePitch = CMPilotRig.Wrap(-fwd * p.tilt - this.pitch) * ka;
    let angleRoll = CMPilotRig.Wrap(side * p.tilt - this.roll) * ka;
    let wantPitchRate = acroPitch + (anglePitch - acroPitch) * this.level;
    let wantRollRate = acroRoll + (angleRoll - acroRoll) * this.level;
    // --- the rotors: collective for the height, differential for the attitude ---
    let hover = CMFlight.HoverSpool(p);
    let lift = MaxF(0.5, CosF(Deg2Rad(this.pitch)) * CosF(Deg2Rad(this.roll)));
    let collective: Float;
    if AbsF(c) > 0.05 {
      this.holding = false;
      collective = hover / lift + (c * p.climb - this.vel.Z) * 0.08;
    } else {
      if !this.holding {
        this.holding = true;
        // where it will come to rest, not where it is: holding the release point made it
        // overshoot and sink back
        this.holdZ = this.pos.Z + this.vel.Z * 0.6;
      }
      // a damped spring onto the held altitude
      collective = hover / lift + ((this.holdZ - this.pos.Z) * 0.5 - this.vel.Z * 0.6) * 0.08;
    }
    // attitude from rotor differentials: what the rates need, clamped to the margin left
    // the rate loop answers at the type's agility: a Bombus snaps, an Octant swings slowly
    let inertia0 = p.mass * p.arm * p.arm * 0.5;
    let kp = p.agility / MaxF(0.001, 4.0 * p.thrust * p.arm / inertia0 * 57.3);
    let dp = ClampF((wantPitchRate - this.pitchRate) * kp, -0.25, 0.25);
    let dr = ClampF((wantRollRate - this.rollRate) * kp, -0.25, 0.25);
    // the attitude keeps its margin: the collective is held where both corrections fit
    // (with it saturated the drone could no longer right itself, and tumbled)
    let margin = AbsF(dp) + AbsF(dr);
    collective = MaxF(margin, MinF(1.0 - margin, collective));
    // front left, front right, back left, back right: more on the left rolls it right
    let cmd: array<Float> = [collective + dp + dr, collective + dp - dr, collective - dp + dr, collective - dp - dr];
    let k = MinF(1.0, dt / MaxF(0.01, p.spool));
    let i = 0;
    while i < 4 {
      this.spool[i] += (ClampF(cmd[i], 0.0, 1.0) - this.spool[i]) * k;
      i += 1;
    }
    let t0 = this.spool[0] * this.eff[0] * p.thrust;
    let t1 = this.spool[1] * this.eff[1] * p.thrust;
    let t2 = this.spool[2] * this.eff[2] * p.thrust;
    let t3 = this.spool[3] * this.eff[3] * p.thrust;
    let total = t0 + t1 + t2 + t3;
    // the torques uneven thrust makes: this is how a damaged rotor rolls the drone
    let inertia = p.mass * p.arm * p.arm * 0.5;
    let pitchTorque = ((t0 + t1) - (t2 + t3)) * p.arm;   // more at the front: nose up
    let rollTorque = ((t0 + t2) - (t1 + t3)) * p.arm;    // more on the left: right side down
    // the airflow: moving through the air pushes the nose up and the tilt back, harder the
    // faster it goes, so a tilt has to be held into the wind, and letting go flares it
    let bf = CMPilotRig.Dir(this.yaw, 0.0);
    let br = CMPilotRig.Dir(this.yaw - 90.0, 0.0);
    let vf = this.vel.X * bf.X + this.vel.Y * bf.Y;
    let vr = this.vel.X * br.X + this.vel.Y * br.Y;
    this.pitchRate += (pitchTorque / inertia * 57.3 + p.aero * vf - this.pitchRate * 2.0) * dt;
    this.rollRate += (rollTorque / inertia * 57.3 - p.aero * vr - this.rollRate * 2.0) * dt;
    // no limit: at low self-levelling it can loop and roll all the way over (the thrust
    // then points where the body does, so inverted it drives down)
    this.pitch = CMPilotRig.Wrap(this.pitch + this.pitchRate * dt);
    this.roll = CMPilotRig.Wrap(this.roll + this.rollRate * dt);
    // the body turns toward the view with its own inertia: it winds into the turn and can
    // run a little past, and the velocity keeps its direction, so it drifts wide
    let wantYaw = ClampF(CMPilotRig.Wrap(view - this.yaw) * 5.0, -p.yawRate, p.yawRate);
    this.yawRate += ClampF(wantYaw - this.yawRate, -p.yawAccel * dt, p.yawAccel * dt);
    this.yaw = CMPilotRig.Wrap(this.yaw + this.yawRate * dt);
    // --- thrust along the body's up axis, gravity and drag ---
    let up = CMFlight.BodyUp(this.yaw, this.pitch, this.roll);
    let speed = Vector4.Length(this.vel);
    let thrustAcc = speed > p.top ? 0.0 : total / p.mass;
    let ax = up.X * thrustAcc - this.vel.X * p.dragH;
    let ay = up.Y * thrustAcc - this.vel.Y * p.dragH;
    let az = up.Z * (speed > p.top ? total / p.mass : thrustAcc) - 9.81 - this.vel.Z * p.dragV;
    this.vel.X += ax * dt;
    this.vel.Y += ay * dt;
    this.vel.Z += az * dt;
    this.pos.X += this.vel.X * dt;
    this.pos.Y += this.vel.Y * dt;
    this.pos.Z += this.vel.Z * dt;
    this.pos.W = 1.0;
  }

  // the body's up axis in the world, from its yaw, pitch and roll (degrees)
  public static func BodyUp(yaw: Float, pitch: Float, roll: Float) -> Vector4 {
    let fwd = CMPilotRig.Dir(yaw, 0.0);
    let right = CMPilotRig.Dir(yaw - 90.0, 0.0);
    let sp = SinF(Deg2Rad(pitch));
    let cp = CosF(Deg2Rad(pitch));
    let sr = SinF(Deg2Rad(roll));
    let cr = CosF(Deg2Rad(roll));
    // pitch nose down (negative) tips up forward; roll right (positive) tips up rightward
    let u = fwd * (-sp * cr) + right * (sr) + new Vector4(0.0, 0.0, cp * cr, 0.0);
    return Vector4.Normalize(u);
  }

  // a contact: the velocity into the surface removed (and a little of it bounced back);
  // returns how fast it hit
  public func Contact(normal: Vector4, restitution: Float) -> Float {
    let into = Vector4.Dot(this.vel, normal);
    if into >= 0.0 {
      return 0.0;
    }
    this.vel = this.vel - normal * (into * (1.0 + restitution));
    return -into;
  }

  // the spool of the four rotors on average, for the HUD and sound
  public func Spool() -> Float = (this.spool[0] + this.spool[1] + this.spool[2] + this.spool[3]) * 0.25
}

public abstract class CMDroneProfiles {
  // what the CONFIG profile sliders start at, per type: self-levelling (%), tilt limit
  // (deg) and full-stick rate (deg/s). With the stick held, the tilt settles where the rate
  // and the levelling balance: the limit + rate x (1 - level) / (0.4 x agility x level), so 65% on the
  // Bombus leans it about 55 deg, past its 35 deg limit; lower is more acro.
  public static func DefaultLevel(kind: String) -> Int32 {
    switch kind {
      case "bombus": return 65;
      case "octant": return 95;
    }
    return 85;
  }

  public static func For(kind: String) -> ref<CMFlightProfile> {
    let p = new CMFlightProfile();
    switch kind {
      case "bombus":
        p.mass = 6.0; p.thrust = 30.0; p.spool = 0.08; p.tilt = 35.0; p.tiltRate = 220.0; p.top = 18.0;
        p.dragH = 0.35; p.dragV = 0.8; p.climb = 5.0; p.yawRate = 200.0; p.arm = 0.2; p.impact = 6.0; p.radius = 0.3;
        p.agility = 18.0; p.aero = 30.0; p.yawAccel = 900.0; p.com = 0.13;
        break;
      case "octant":
        p.mass = 180.0; p.thrust = 900.0; p.spool = 0.15; p.tilt = 20.0; p.tiltRate = 90.0; p.top = 10.0;
        p.dragH = 0.5; p.dragV = 1.0; p.climb = 3.0; p.yawRate = 60.0; p.arm = 1.0; p.impact = 5.0; p.radius = 1.1;
        p.agility = 5.0; p.aero = 6.0; p.yawAccel = 90.0; p.com = 0.15;
        break;
      default:   // griffin, wyvern
        p.mass = 40.0; p.thrust = 190.0; p.spool = 0.11; p.tilt = 22.0; p.tiltRate = 120.0; p.top = 14.0;
        p.dragH = 0.45; p.dragV = 0.9; p.climb = 4.0; p.yawRate = 110.0; p.arm = 0.45; p.impact = 5.5; p.radius = 0.5;
        p.agility = 10.0; p.aero = 15.0; p.yawAccel = 300.0; p.com = Equals(kind, "wyvern") ? 0.22 : 0.0;
    }
    return p;
  }
}
