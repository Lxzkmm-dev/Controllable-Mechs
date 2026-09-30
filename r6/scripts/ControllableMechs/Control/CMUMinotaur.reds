// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: THE MINOTAUR (M1)
//
// The body is the linked Militech Minotaur itself; no skin (design doc, section
// 11, route B). Its own MK.31s aim through its own animation:
//   - an invisible marker entity is moved to the aim point every frame, and four
//     look-at requests (RightWeapon, LeftWeapon, Weapon, Chassis) follow it
//     (spikes S6 / S7: the barrels settle within a few degrees of the reticle)
//   - each gun fires only while its barrel is within GATE_DEG of the reticle, and
//     the rounds leave along the barrel, so flash, tracer and hit line up
//   - the fire call (who owns the rounds) is the session's setting (CMFireCall)
//   - the legs: AI walk orders from WASD relative to the view, targets clipped
//     short of walls (the alpha's proven driving)
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMUMinotaur extends CMCUnit {
  private let m_game: GameInstance;
  private let m_mechID: EntityID;
  private let m_guns: ref<CMPilotGuns>;

  private let m_markerID: EntityID;
  private let m_marker: wref<Entity>;
  private let m_lookAts: array<ref<LookAtAddEvent>>;

  private let m_moveCmd: ref<AICommand>;
  private let m_turnCmd: ref<AICommand>;
  private let m_moving: Bool;
  private let m_moveDir: Vector4;
  private let m_moveTarget: Vector4;
  private let m_moveSent: Float;
  private let m_moveYaw: Float;
  // standing still: a hold order keeps the mech's own AI from walking or turning it
  // (it has no order otherwise, and its combat behaviour takes over)
  private let m_holdCmd: ref<AICommand>;
  private let m_holdSent: Float;
  private let m_calmChecked: Float;
  private let m_calmResets: Int32;

  // the aim log while firing: once a second
  private let m_triggerWas: Bool;
  private let m_logNext: Float;
  private let m_held: Int32;
  private let m_shots: Int32;
  private let m_target: wref<GameObject>;
  private let m_targetHP: Float;

  // the weighted chassis turn while standing: the body turns toward the view at a capped
  // rate, easing in and out (the look-ats cover the last TURN_START_DEG on their own)
  private let m_bodyYaw: Float;
  private let m_turnVel: Float;
  private let m_turning: Bool;
  private let TURN_RATE: Float = 35.0;       // deg/s, top speed
  private let TURN_ACCEL: Float = 60.0;      // deg/s², how hard it spins up and brakes
  private let TURN_K: Float = 2.5;           // wanted speed per degree still to go
  private let TURN_START_DEG: Float = 20.0;  // the view may be this far off before the body follows
  private let TURN_START_SWEEP_DEG: Float = 8.0;  // ... or this far while the view is still swinging
  private let LOOKAT_FOLLOW: Float = 3.0;    // look-at following speed factor (NPC default ~1)
  private let LOOKAT_BLEND: Float = 3.0;     // look-at blend-in speed

  private let ROUND_SPEED: Float = 4.0;      // x the MK.31's smart-round velocity while piloted
  private let KICK: Float = 0.6;             // camera kick per round (alpha: 0.45)
  private let SPIN_UP: Float = 0.5;          // seconds from still to full spin
  private let SPIN_DOWN: Float = 0.9;        // seconds from full spin to still
  private let SPIN_FIRE: Float = 0.3;        // spin fraction at which rounds start
  private let m_spin: Float;
  private let MUZZLE_AHEAD: Float = 1.2;     // metres ahead of the weapon item where the flash sits
  private let START_LURCH: Float = 9.0;      // pitch kick into the first step, deg/s
  private let STOP_ROCK: Float = 7.0;        // pitch kick back on stopping, deg/s
  // the servo: the game's sensor-camera servo loops while the view traverses, with a heavy
  // servo thunk on each start (state changes only)
  private let m_servoOn: Bool;
  private let m_servoHit: Float;
  private let m_impactToggle: Bool;

  private let GATE_DEG: Float = 4.0;
  private let SPREAD_DEG: Float = 0.6;
  private let SIGNAL_RANGE: Float = 250.0;

  public func Name() -> String = "MILITECH MINOTAUR"

  private func Mech() -> ref<NPCPuppet> = GameInstance.FindEntityByID(this.m_game, this.m_mechID) as NPCPuppet

  // ---------------------------------------------------------------------------
  // Begin / End
  // ---------------------------------------------------------------------------
  public func Begin(s: ref<CMCSession>) -> String {
    this.m_game = s.GetGameInstance();
    let link = CMLinkSystem.Get(this.m_game);
    let mech = link.Unit();
    if !link.IsLinked() || !IsDefined(mech) {
      return "!NO UNIT LINKED";
    }
    if NotEquals(mech.GetNPCType(), gamedataNPCType.Mech) {
      return "!PILOT MODE NEEDS A MECH";
    }
    if !ScriptedPuppet.IsAlive(mech) {
      return "!MECH IS DESTROYED";
    }
    this.m_mechID = mech.GetEntityID();
    link.Hold();
    link.SetOrder(CMOrder.Pilot());
    this.m_guns = new CMPilotGuns();
    this.m_guns.Init(mech);
    // rounds go to the reticle point (the alpha's damaging path); the look-ats aim the
    // barrels there and the gate holds each gun until it's on it, so the flash lines up
    this.m_guns.SetAimMode(CMAimMode.Reticle());
    this.m_guns.call = s.FireCall();
    this.m_moving = false;
    this.m_triggerWas = false;
    this.m_bodyYaw = CMPilotRig.YawOf(mech.GetWorldForward());
    this.m_turnVel = 0.0;
    this.m_turning = false;
    ArrayClear(this.m_lookAts);

    // the look-at target: never activated, just a point that follows the reticle
    let spec = new StaticEntitySpec();
    spec.templatePath = r"base\\entities\\cameras\\simple_free_camera.ent";
    spec.position = mech.GetWorldPosition() + mech.GetWorldForward() * 30.0 + new Vector4(0.0, 0.0, 2.0, 0.0);
    spec.orientation = CMCSession.Identity();
    spec.attached = true;
    this.m_markerID = GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
    this.m_marker = null;
    this.Pacify(mech, true);
    CMCSession.Log("Minotaur: guns " + this.m_guns.Describe());
    CMCSession.Log("rounds: " + this.m_guns.SpeedUp(this.m_game, this.ROUND_SPEED));
    return "";
  }

  // While piloted the mech's own combat AI must not act: with its senses and target
  // tracking off it perceives no threats, and its high-level state is put back to
  // relaxed if combat still reaches it (checked once a second). All restored on exit.
  private func Pacify(mech: ref<NPCPuppet>, on: Bool) -> Void {
    if !IsDefined(mech) {
      return;
    }
    let senses = mech.GetSensesComponent();
    if IsDefined(senses) {
      senses.Toggle(!on);
    }
    let tracker = mech.GetTargetTrackerComponent();
    if IsDefined(tracker) {
      tracker.Toggle(!on);
    }
    if on {
      NPCPuppet.ChangeHighLevelState(mech, gamedataNPCHighLevelState.Relaxed);
    }
    CMCSession.Log("AI " + (on ? "suppressed (senses and target tracking off, relaxed)" : "restored") + ", state now " + EnumValueToString("gamedataNPCHighLevelState", Cast<Int64>(EnumInt(mech.GetHighLevelStateFromBlackboard()))));
  }

  private func KeepCalm(mech: ref<NPCPuppet>, now: Float) -> Void {
    if now - this.m_calmChecked < 1.0 {
      return;
    }
    this.m_calmChecked = now;
    let state = mech.GetHighLevelStateFromBlackboard();
    if Equals(state, gamedataNPCHighLevelState.Combat) || Equals(state, gamedataNPCHighLevelState.Alerted) {
      NPCPuppet.ChangeHighLevelState(mech, gamedataNPCHighLevelState.Relaxed);
      this.m_calmResets += 1;
      if this.m_calmResets <= 10 {
        CMCSession.Log("AI went to " + EnumValueToString("gamedataNPCHighLevelState", Cast<Int64>(EnumInt(state))) + ", set back to relaxed (" + IntToString(this.m_calmResets) + ")");
      }
    }
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    let mech = this.Mech();
    this.StopServo(mech);
    this.Pacify(mech, false);
    if IsDefined(mech) {
      this.CancelCmd(mech, this.m_moveCmd);
      this.CancelCmd(mech, this.m_turnCmd);
      this.CancelCmd(mech, this.m_holdCmd);
      for ev in this.m_lookAts {
        let r = new LookAtRemoveEvent();
        r.lookAtRef = ev.outLookAtRef;
        mech.QueueEvent(r);
      }
    }
    ArrayClear(this.m_lookAts);
    this.m_moveCmd = null;
    this.m_turnCmd = null;
    this.m_holdCmd = null;
    this.m_marker = null;
    if EntityID.IsDefined(this.m_markerID) {
      GameInstance.GetStaticEntitySystem().DespawnEntity(this.m_markerID);
    }
    let empty: EntityID;
    this.m_markerID = empty;
    // the mech's own hits are its own again (and the alpha's never credit V)
    if IsDefined(this.m_guns) {
      this.SetCredit(false);
      this.m_guns.SlowDown(this.m_game);
    }
    let link = CMLinkSystem.Get(this.m_game);
    if IsDefined(link) && link.IsLinked() {
      link.Hold();
    }
    this.m_guns = null;
  }

  public func IsAlive() -> Bool {
    let mech = this.Mech();
    return IsDefined(mech) && ScriptedPuppet.IsAlive(mech);
  }

  public func Ground() -> Vector4 = this.Mech().GetWorldPosition()
  public func Facing() -> Float = CMPilotRig.YawOf(this.Mech().GetWorldForward())
  public func SensorUp() -> Float = Cast<Float>(CMPilotSystem.Get(this.m_game).CamUpCm()) / 100.0
  public func SensorFwd() -> Float = Cast<Float>(CMPilotSystem.Get(this.m_game).CamFwdCm()) / 100.0
  public func AimSkip() -> Float = 4.5

  // ---------------------------------------------------------------------------
  // Every frame: the marker onto the aim point, the gate, the guns
  // ---------------------------------------------------------------------------
  public func Tick(s: ref<CMCSession>, dt: Float, now: Float) -> Void {
    let mech = this.Mech();
    this.MoveMarker(s.aim);
    this.TurnChassis(s, mech, dt);
    this.SetCredit(s.CreditV());
    let split = s.FireMode() == CMFireMode.Split();
    let trigger = s.Key(CMCKey.Lmb()) || (split && s.Key(CMCKey.Rmb()));
    // the barrels spin up while the trigger is held and wind down after: no rounds until
    // SPIN_FIRE, then the rate climbs from 35% to full
    if trigger {
      this.m_spin = MinF(1.0, this.m_spin + dt / this.SPIN_UP);
    } else {
      this.m_spin = MaxF(0.0, this.m_spin - dt / this.SPIN_DOWN);
    }
    this.m_guns.rate = 0.35 + 0.65 * this.m_spin;
    let spun = this.m_spin >= this.SPIN_FIRE;
    let lmb = spun && s.Key(CMCKey.Lmb());
    let rmb = spun && split && s.Key(CMCKey.Rmb());
    if trigger {
      let offL = CMCSession.AimError(this.m_guns.left.weapon, s.aim) > this.GATE_DEG;
      let offR = CMCSession.AimError(this.m_guns.right.weapon, s.aim) > this.GATE_DEG;
      this.m_guns.left.offAim = offL;
      this.m_guns.right.offAim = offR;
      if offL || offR {
        this.m_held += 1;
      }
    }
    let flashL = this.m_guns.left.flash;
    let flashR = this.m_guns.right.flash;
    let shots = this.m_guns.Update(mech, now, dt, lmb, rmb, s.FireMode(), s.aim, this.SPREAD_DEG, s.rig.pos);
    if shots > 0 {
      this.m_shots += shots;
      s.rig.Recoil(this.KICK * Cast<Float>(shots));
      // which barrel just fired: its flash timer was reset this frame
      if this.m_guns.left.flash > flashL {
        this.RoundFx(this.m_guns.left.weapon, s.aim);
      }
      if this.m_guns.right.flash > flashR && this.m_guns.right.weapon != this.m_guns.left.weapon {
        this.RoundFx(this.m_guns.right.weapon, s.aim);
      }
    }
    this.AimLog(s, trigger, now);
    this.Servo(s, mech, now);
    let hud = s.Hud();
    if IsDefined(hud) {
      hud.FadeHit(dt);
      hud.Flash(this.m_guns.left.flash > 0.0, this.m_guns.right.flash > 0.0);
      let range = s.aimDist > 1.0 ? s.aimDist : 150.0;
      let l = s.PipOffset(this.m_guns.BarrelPoint(this.m_guns.left, range));
      let r = s.PipOffset(this.m_guns.BarrelPoint(this.m_guns.right, range));
      hud.SetPips(l.X, l.Y, this.m_guns.left.Ready() && AbsF(l.X) < 1900.0 && AbsF(l.Y) < 1050.0, r.X, r.Y, this.m_guns.right.Ready() && AbsF(r.X) < 1900.0 && AbsF(r.Y) < 1050.0);
    }
  }

  // while a trigger is held, once a second: each barrel's error to the reticle, rounds
  // fired and frames a gun was held back
  private func AimLog(s: ref<CMCSession>, trigger: Bool, now: Float) -> Void {
    if trigger && !this.m_triggerWas {
      this.m_logNext = now;
      this.m_held = 0;
      this.m_shots = 0;
      // what the pilot's reticle is on (V's own look-at target is the mech itself)
      this.m_target = s.aimEntity as GameObject;
      this.m_targetHP = CMSpike2System.Health(this.m_target);
      CMCSession.Log("fire (" + CMFireCall.Name(this.m_guns.call) + "): target " + CMSpike2System.Describe(this.m_target) + ", health " + FloatToStringPrec(this.m_targetHP, 1));
      let mech = this.Mech();
      CMCSession.Log(CMHitLog.Muzzle("R", this.m_guns.right.weapon, mech, s.rig.pos, s.aim) + "; " + CMHitLog.Muzzle("L", this.m_guns.left.weapon, mech, s.rig.pos, s.aim));
    }
    if !trigger && this.m_triggerWas && IsDefined(this.m_target) {
      let cb = new CMUMinotaurReportCb();
      cb.unit = this;
      GameInstance.GetDelaySystem(this.m_game).DelayCallback(cb, 1.0, false);
    }
    if trigger && now >= this.m_logNext {
      this.m_logNext = now + 1.0;
      CMCSession.Log("aim error right " + FloatToStringPrec(CMCSession.AimError(this.m_guns.right.weapon, s.aim), 1)
        + " deg, left " + FloatToStringPrec(CMCSession.AimError(this.m_guns.left.weapon, s.aim), 1)
        + " deg, reticle " + FloatToStringPrec(s.aimDist, 0) + " m, rounds " + IntToString(this.m_shots) + ", frames held " + IntToString(this.m_held));
    }
    this.m_triggerWas = trigger;
  }

  public func Report() -> Void {
    let hp = CMSpike2System.Health(this.m_target);
    CMCSession.Log("result: target " + CMSpike2System.Describe(this.m_target) + ", health " + FloatToStringPrec(this.m_targetHP, 1) + " -> " + FloatToStringPrec(hp, 1));
  }

  // standing still: the body swings round toward the view with weight (a rate cap, spin-up
  // and braking), one rotation-only teleport a frame and only while it turns. Walking hands
  // the facing back to the walk orders, which already face the view.
  private func TurnChassis(s: ref<CMCSession>, mech: ref<NPCPuppet>, dt: Float) -> Void {
    if this.m_moving {
      this.m_bodyYaw = CMPilotRig.YawOf(mech.GetWorldForward());
      this.m_turnVel = 0.0;
      this.m_turning = false;
      return;
    }
    if !this.m_turning {
      // between turns, take the body's real heading: never teleport it back against a
      // rotation something else made (that was a source of the fight-back)
      this.m_bodyYaw = CMPilotRig.YawOf(mech.GetWorldForward());
    }
    let off = CMPilotRig.Wrap(s.rig.yaw - this.m_bodyYaw);
    if !this.m_turning {
      // the chassis leads a sweep: it starts sooner while the view is moving
      let start = AbsF(s.rig.YawRate()) > 15.0 ? this.TURN_START_SWEEP_DEG : this.TURN_START_DEG;
      if AbsF(off) < start {
        return;
      }
      this.m_turning = true;
      GameObject.PlaySoundEvent(mech, AbsF(off) > 120.0 ? n"enm_mech_minotaur_loco_idle_to_idle_180_l" : n"enm_mech_minotaur_loco_idle_to_idle_90");
    }
    let want = ClampF(off * this.TURN_K, -this.TURN_RATE, this.TURN_RATE);
    let step = this.TURN_ACCEL * dt;
    this.m_turnVel += ClampF(want - this.m_turnVel, -step, step);
    if AbsF(off) < 1.0 && AbsF(this.m_turnVel) < 3.0 {
      this.m_turnVel = 0.0;
      this.m_turning = false;
      return;
    }
    this.m_bodyYaw = CMPilotRig.Wrap(this.m_bodyYaw + this.m_turnVel * dt);
    let e: EulerAngles;
    e.Yaw = this.m_bodyYaw;
    GameInstance.GetTeleportationFacility(this.m_game).Teleport(mech, mech.GetWorldPosition(), e);
  }

  // A heavier round, visually: the Militech HMG's own big muzzle flash and a power-HMG
  // trail at the barrel, and every other round the HMG's explosive-bullet impact where the
  // reticle is. Spawned from the game's effect files (nothing vanilla is edited); at most
  // three effects a round, only while piloting.
  private func RoundFx(weapon: ref<WeaponObject>, aim: Vector4) -> Void {
    if !IsDefined(weapon) {
      return;
    }
    let fx = GameInstance.GetFxSystem(this.m_game);
    let dir = Vector4.Normalize(aim - weapon.GetWorldPosition());
    let muzzle = weapon.GetWorldPosition() + dir * this.MUZZLE_AHEAD;
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\militech_hmg\\w_special_hmg_muzzle_tpp.effect"), CMUMinotaur.At(muzzle, dir), true);
    fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\trails\\power\\w_trail_power_hmg_npc.effect"), CMUMinotaur.At(muzzle, dir), true);
    this.m_impactToggle = !this.m_impactToggle;
    if this.m_impactToggle {
      fx.SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\weapons\\firearms\\special\\militech_hmg\\w_special_hmg_explosive_bullet.effect"), CMUMinotaur.At(aim, -dir), true);
    }
  }

  private static func Fx(path: ResRef) -> FxResource {
    let ref: ResourceAsyncRef;
    ResourceAsyncRef.SetPath(ref, path);
    let fx: FxResource;
    fx.effect = ref;
    return fx;
  }

  private static func At(p: Vector4, dir: Vector4) -> WorldTransform {
    let wp: WorldPosition;
    WorldPosition.SetVector4(wp, p);
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, wp);
    WorldTransform.SetOrientationFromDir(wt, dir);
    return wt;
  }

  private func Servo(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Void {
    let rate = AbsF(s.rig.YawRate());
    if !this.m_servoOn && (rate > 8.0 || this.m_turning) {
      this.m_servoOn = true;
      GameObject.PlaySoundEvent(mech, n"dev_surveillance_camera_rotating");
      if now - this.m_servoHit > 0.6 {
        this.m_servoHit = now;
        GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_lcm_servo_short");
      }
    } else {
      if this.m_servoOn && rate < 3.0 && !this.m_turning {
        this.StopServo(mech);
      }
    }
  }

  private func StopServo(mech: ref<NPCPuppet>) -> Void {
    if !this.m_servoOn {
      return;
    }
    this.m_servoOn = false;
    if IsDefined(mech) {
      GameObject.StopSoundEvent(mech, n"dev_surveillance_camera_rotating");
      GameObject.PlaySoundEvent(mech, n"dev_surveillance_camera_rotating_stop");
    }
  }

  // the MK.31s' hits credit V while this is on (CMHitLog's pipeline hook reads it)
  private func SetCredit(on: Bool) -> Void {
    if IsDefined(this.m_guns.left.weapon) {
      this.m_guns.left.weapon.m_cmCreditV = on;
    }
    if IsDefined(this.m_guns.right.weapon) {
      this.m_guns.right.weapon.m_cmCreditV = on;
    }
  }

  private func MoveMarker(at: Vector4) -> Void {
    if !IsDefined(this.m_marker) {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, at);
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, CMCSession.Identity());
    this.m_marker.SetWorldTransform(wt);
  }

  // ---------------------------------------------------------------------------
  // Ten times a second: exits, look-ats, the legs
  // ---------------------------------------------------------------------------
  public func SlowTick(s: ref<CMCSession>, now: Float) -> String {
    let link = CMLinkSystem.Get(this.m_game);
    let mech = this.Mech();
    if !link.IsLinked() || !IsDefined(mech) {
      return "!ROBOT LINK LOST";
    }
    if !ScriptedPuppet.IsAlive(mech) {
      return "!MECH DESTROYED";
    }
    if link.Distance() > this.SIGNAL_RANGE {
      return "!SIGNAL LOST";
    }
    this.SendLookAts(mech);
    this.KeepCalm(mech, now);
    this.Drive(s, mech, now);
    return "";
  }

  // once the marker has attached: the four gun-part look-ats, pointed at it
  private func SendLookAts(mech: ref<NPCPuppet>) -> Void {
    if ArraySize(this.m_lookAts) > 0 || !EntityID.IsDefined(this.m_markerID) {
      return;
    }
    if !IsDefined(this.m_marker) {
      this.m_marker = GameInstance.FindEntityByID(this.m_game, this.m_markerID);
      if !IsDefined(this.m_marker) {
        return;
      }
    }
    for part in [n"RightWeapon", n"LeftWeapon", n"Weapon", n"Chassis"] {
      let ev = new LookAtAddEvent();
      ev.SetEntityTarget(this.m_marker, n"", new Vector4(0.0, 0.0, 0.0, 0.0));
      ev.bodyPart = part;
      ev.SetStyle(animLookAtStyle.Normal);
      ev.SetLimits(animLookAtLimitDegreesType.Wide, animLookAtLimitDegreesType.Wide, animLookAtLimitDistanceType.None, animLookAtLimitDegreesType.Wide);
      // follow a moving target faster than the NPC default (the guns trailed a sweep by 15-20 deg)
      ev.request.followingSpeedFactorOverride = this.LOOKAT_FOLLOW;
      ev.request.transitionSpeed = this.LOOKAT_BLEND;
      mech.QueueEvent(ev);
      ArrayPush(this.m_lookAts, ev);
    }
    CMCSession.Log("look-ats sent: RightWeapon, LeftWeapon, Weapon, Chassis (follow x" + FloatToStringPrec(this.LOOKAT_FOLLOW, 1) + ")");
  }

  // WASD relative to where the view looks; the mech walks there on its own legs
  private func Drive(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Void {
    let f = (s.Key(CMCKey.W()) ? 1.0 : 0.0) - (s.Key(CMCKey.S()) ? 1.0 : 0.0);
    let side = (s.Key(CMCKey.D()) ? 1.0 : 0.0) - (s.Key(CMCKey.A()) ? 1.0 : 0.0);
    let dir = CMPilotRig.Dir(s.rig.yaw, 0.0) * f + CMPilotRig.Dir(s.rig.yaw - 90.0, 0.0) * side;
    let pos = mech.GetWorldPosition();
    if Vector4.Length(dir) < 0.1 {
      if this.m_moving {
        this.CancelCmd(mech, this.m_moveCmd);
        this.m_moveCmd = null;
        this.m_moving = false;
        CMCSession.Log("walk: stop (keys released)");
        s.rig.Nudge(this.STOP_ROCK, -0.25);   // the body rocks back as it plants
      }
      this.Hold(mech, now);
      return;   // standing: TurnChassis turns the body, every frame
    }
    dir = Vector4.Normalize(dir);
    let turned = !this.m_moving || Vector4.Dot(dir, this.m_moveDir) < 0.94;
    let close = Vector4.Distance(pos, this.m_moveTarget) < 4.0;
    let stale = now - this.m_moveSent > 1.5;
    let swung = AbsF(CMPilotRig.Wrap(s.rig.yaw - this.m_moveYaw)) > 25.0;
    if !(turned || close || stale || swung) {
      return;
    }
    // never order it into a wall (an unreachable target is when the game teleports it):
    // stop 2.5 m short of the first static hit along the way, or don't move at all
    let reach = 9.0;
    let from = new Vector4(pos.X, pos.Y, pos.Z + 1.2, 1.0);
    let hit: TraceResult;
    if GameInstance.GetSpatialQueriesSystem(this.m_game).SyncRaycastByCollisionGroup(from + dir * 2.0, from + dir * (reach + 2.5), n"Static", hit, true, false) {
      reach = Vector4.Distance(from, Cast<Vector4>(hit.position)) - 2.5;
    }
    if reach < 1.5 {
      if this.m_moving {
        this.CancelCmd(mech, this.m_moveCmd);
        this.m_moveCmd = null;
        this.m_moving = false;
        CMCSession.Log("walk: stop (wall ahead)");
      }
      this.Hold(mech, now);
      return;
    }
    if !this.m_moving {
      CMCSession.Log("walk: start");
      s.rig.Nudge(-this.START_LURCH, -0.3);   // it leans into the first step
    }
    let target = pos + dir * reach;
    let world: WorldPosition;
    WorldPosition.SetVector4(world, target);
    let spec: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(spec, world);
    let face: WorldPosition;
    WorldPosition.SetVector4(face, pos + CMPilotRig.Dir(s.rig.yaw, 0.0) * 30.0);
    let faceSpec: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(faceSpec, face);
    let cmd = new AIMoveToCommand();
    cmd.movementTarget = spec;
    cmd.facingTarget = faceSpec;
    cmd.rotateEntityTowardsFacingTarget = true;
    cmd.movementType = moveMovementType.Walk;
    cmd.ignoreNavigation = false;
    cmd.useStart = !this.m_moving;
    cmd.useStop = true;
    cmd.finishWhenDestinationReached = true;
    cmd.desiredDistanceFromTarget = 0.5;
    this.Send(mech, cmd, true);
    this.m_moveYaw = s.rig.yaw;
    this.m_moving = true;
    this.m_moveDir = dir;
    this.m_moveTarget = target;
    this.m_moveSent = now;
  }

  // a hold order while standing, renewed every 5 s (one command, not per frame)
  private func Hold(mech: ref<NPCPuppet>, now: Float) -> Void {
    if IsDefined(this.m_holdCmd) && now - this.m_holdSent < 5.0 {
      return;
    }
    let ai = mech.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    this.CancelCmd(mech, this.m_holdCmd);
    let cmd = new AIHoldPositionCommand();
    cmd.duration = 10.0;
    ai.SendCommand(cmd);
    this.m_holdCmd = cmd;
    this.m_holdSent = now;
  }

  private func Send(mech: ref<NPCPuppet>, cmd: ref<AICommand>, move: Bool) -> Void {
    let ai = mech.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    this.CancelCmd(mech, this.m_moveCmd);
    this.CancelCmd(mech, this.m_turnCmd);
    this.CancelCmd(mech, this.m_holdCmd);
    this.m_moveCmd = null;
    this.m_turnCmd = null;
    this.m_holdCmd = null;
    ai.SendCommand(cmd);
    if move {
      this.m_moveCmd = cmd;
    } else {
      this.m_turnCmd = cmd;
    }
  }

  private func CancelCmd(mech: ref<NPCPuppet>, cmd: ref<AICommand>) -> Void {
    if !IsDefined(cmd) {
      return;
    }
    let ai = mech.GetAIControllerComponent();
    if IsDefined(ai) {
      ai.CancelCommand(cmd);
    }
  }

  // ---------------------------------------------------------------------------
  // HUD
  // ---------------------------------------------------------------------------
  public func Hud(s: ref<CMCSession>, st: ref<CMPilotHudState>) -> Void {
    let link = CMLinkSystem.Get(this.m_game);
    let name = link.UnitName();
    if StrLen(name) > 0 {
      st.title = StrUpper(name) + (s.IsChase() ? "  //  CHASE CAM" : "  //  NEURAL LINK") + "  //  FRAMEWORK M1";
    }
    st.integrity = link.HealthFraction();
    st.signal = link.SignalFraction();
    st.distance = link.Distance();
    st.heatL = this.m_guns.left.heat;
    st.heatR = this.m_guns.right.heat;
    st.lockedL = this.m_guns.left.locked;
    st.lockedR = this.m_guns.right.locked;
    st.hasL = this.m_guns.left.Ready();
    st.hasR = this.m_guns.right.Ready();
    if st.integrity < 0.3 {
      st.warning = "INTEGRITY CRITICAL";
    } else {
      if st.signal < 0.2 {
        st.warning = "SIGNAL DEGRADED - RETURN TO OPERATOR";
      } else {
        if this.m_guns.left.offAim && this.m_guns.right.offAim && s.Key(CMCKey.Lmb()) {
          st.warning = "GUNS TRAVERSING";
        } else {
          if s.Key(CMCKey.Lmb()) && this.m_spin < 1.0 {
            st.warning = "SPINNING UP";
          }
        }
      }
    }
  }
}

public class CMUMinotaurReportCb extends DelayCallback {
  public let unit: wref<CMUMinotaur>;
  public func Call() -> Void {
    if IsDefined(this.unit) {
      this.unit.Report();
    }
  }
}
