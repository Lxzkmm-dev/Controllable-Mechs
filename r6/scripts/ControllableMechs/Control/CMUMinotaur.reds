// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: THE MINOTAUR
//
// The body is the linked Militech Minotaur itself; no skin (design doc, section
// 11, route B). Its own MK.31s aim through its own animation:
//   - an invisible marker entity is moved to the aim point every frame, and four
//     look-at requests (RightWeapon, LeftWeapon, Weapon, Chassis) follow it
//     (spikes S6 / S7: the barrels settle within a few degrees of the reticle)
//   - the guns fire while they swing onto the reticle (the rounds go to the reticle
//     point); optionally each gun waits until its barrel is within GATE_DEG of it
//   - the rounds are fired at the reticle point with the mech as owner (the one call
//     that deals damage); the damage pipeline hook (CMCHits) credits the hits to V
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
  private let m_calmResets: Int32;
  private let m_threatClears: Int32;
  private let m_gunsLost: Bool;
  // what the AI still does on its own, for the log: the body moving or turning while we
  // gave no order
  private let m_stoodPos: Vector4;
  private let m_stoodAt: Float;
  private let m_strayLogs: Int32;
  private let m_strayYawAt: Float;

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
  private let m_turnMiss: Float;      // seconds the body has not followed our rotation
  private let m_turnByOrder: Bool;    // the fallback: AI turn orders instead
  private let m_turnSent: Float;
  private let m_turnOrders: Int32;
  private let m_lookMiss: Int32;      // slow ticks the guns have been off with the body on
  private let m_lookSent: Float;
  private let m_turning: Bool;
  private let TURN_RATE: Float = 35.0;       // deg/s, top speed at TURN SPEED 100% (the setting scales it)
  private let TURN_ACCEL: Float = 60.0;      // deg/s², how hard it spins up and brakes, likewise
  private let m_turnRate: Float;
  private let m_turnAccel: Float;
  private let TURN_K: Float = 2.5;           // wanted speed per degree still to go
  private let TURN_START_DEG: Float = 20.0;  // the view may be this far off before the body follows
  private let TURN_START_SWEEP_DEG: Float = 8.0;  // ... or this far while the view is still swinging
  private let LOOKAT_FOLLOW: Float = 3.0;    // look-at following speed factor (NPC default ~1)
  private let LOOKAT_BLEND: Float = 3.0;     // look-at blend-in speed

  private let ROUND_SPEED: Float = 4.0;      // x the MK.31's smart-round velocity while piloted
  private let KICK: Float = 0.1;             // degrees of camera shake per round (CONFIG > RECOIL scales it)
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
  private let MISSILE_COOLDOWN: Float = 6.0;   // seconds between missiles
  private let MISSILE_SPEED: Float = 70.0;     // m/s, for the flight time to the reticle point
  private let MISSILE_RADIUS: Float = 5.0;     // blast radius, metres
  private let MISSILE_DAMAGE: Float = 900.0;   // physical damage added to the blast
  private let m_missileReady: Float;
  private let m_launchL: wref<WeaponObject>;
  private let m_launchR: wref<WeaponObject>;
  private let m_launchLeft: Bool;
  private let m_audioTrigger: Bool;
  private let m_fireLoop: Bool;
  private let m_heatWarned: Bool;
  private let m_audioLocked: Bool;
  private let m_lowAlarm: Bool;
  private let m_hull: Float;          // 0..1, the mech's health against its maximum
  private let m_beepNext: Float;
  private let m_armour: ref<gameStatModifierData>;
  private let m_impactToggle: Bool;

  private let GATE_DEG: Float = 4.0;
  private let m_gate: Bool;           // CONFIG: hold a gun's fire until its barrel is on the reticle
  private let SPREAD_DEG: Float = 0.6;
  private let SIGNAL_RANGE: Float = 250.0;

  public func Name() -> String = "MILITECH MINOTAUR"
  public func LostReason() -> String = "!MECH DESTROYED"

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
    this.m_moving = false;
    this.m_triggerWas = false;
    this.m_bodyYaw = CMPilotRig.YawOf(mech.GetWorldForward());
    this.m_turnVel = 0.0;
    this.m_turning = false;
    this.m_turnMiss = 0.0;
    this.m_turnByOrder = false;
    this.m_turnOrders = 0;
    let turn = Cast<Float>(CMPilotSystem.Get(this.m_game).TurnPct()) / 100.0;
    this.m_turnRate = this.TURN_RATE * turn;
    this.m_gate = CMPilotSystem.Get(this.m_game).FireGate();
    this.m_turnAccel = this.TURN_ACCEL * turn;
    this.m_stoodPos = mech.GetWorldPosition();
    this.m_lookMiss = 0;
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
    GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"ui_q110_personal_link_01");   // link established
    CMCSession.Log("Minotaur: guns " + this.m_guns.Describe());
    this.LogInventory(mech);
    this.FindLaunchers(mech);
    this.m_missileReady = 0.0;
    this.m_hull = -1.0;
    this.Armour(mech, s.HullMult());
    this.ReadHull(mech);
    CMCSession.Log("rounds: " + this.m_guns.SpeedUp(this.m_game, this.ROUND_SPEED));
    return "";
  }

  // While piloted the mech's own AI must not act. Three things woke it, and each is shut:
  //   - being hit, and threats shared by its squad, made whoever shot it a combat target
  //     (it turned to them, walked at them and swung at them when close): the flag set
  //     here makes the game's threat functions skip this puppet (CMCCalm)
  //   - gunfire and explosions are stimuli that put it in the Alerted state: its reaction
  //     component is switched off
  //   - its own senses and target tracking: switched off, the threat list cleared
  // Ten times a second its state is put back to relaxed and its threat list emptied if
  // anything still got through. All restored on exit.
  private func Pacify(mech: ref<NPCPuppet>, on: Bool) -> Void {
    if !IsDefined(mech) {
      return;
    }
    mech.m_cmPiloted = on;
    this.Shield(mech, on);
    let reactions = mech.GetStimReactionComponent();
    if IsDefined(reactions) {
      reactions.Toggle(!on);
    }
    let senses = mech.GetSensesComponent();
    if IsDefined(senses) {
      senses.Toggle(!on);
    }
    let tracker = mech.GetTargetTrackerComponent();
    if IsDefined(tracker) {
      if on {
        tracker.ClearThreats();
      }
      tracker.Toggle(!on);
    }
    if on {
      NPCPuppet.ChangeHighLevelState(mech, gamedataNPCHighLevelState.Relaxed);
    }
    this.m_calmResets = 0;
    this.m_threatClears = 0;
    this.m_strayLogs = 0;
    CMCSession.Log("AI " + (on ? "suppressed (stimulus reactions" + (IsDefined(reactions) ? "" : " [no component]") + ", senses and target tracking off, relaxed)" : "restored") + ", state now " + CMUMinotaur.StateName(mech));
  }

  private static func StateName(mech: ref<NPCPuppet>) -> String {
    return EnumValueToString("gamedataNPCHighLevelState", Cast<Int64>(EnumInt(mech.GetHighLevelStateFromBlackboard())));
  }

  // ten times a second: one blackboard read and two flag reads unless something is wrong
  private func KeepCalm(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Void {
    let state = mech.GetHighLevelStateFromBlackboard();
    if Equals(state, gamedataNPCHighLevelState.Combat) || Equals(state, gamedataNPCHighLevelState.Alerted) {
      NPCPuppet.ChangeHighLevelState(mech, gamedataNPCHighLevelState.Relaxed);
      let tracker = mech.GetTargetTrackerComponent();
      if IsDefined(tracker) {
        tracker.ClearThreats();
      }
      this.m_calmResets += 1;
      if this.m_calmResets <= 20 {
        CMCSession.Log("AI went to " + EnumValueToString("gamedataNPCHighLevelState", Cast<Int64>(EnumInt(state))) + ", set back to relaxed (" + IntToString(this.m_calmResets) + "); " + (this.m_moving ? "walking" : "standing") + (this.m_turning ? ", turning" : ""));
      }
    }
    // a threat that got in some other way: out again
    let threats = mech.GetTargetTrackerComponent();
    if IsDefined(threats) && threats.HasHostileThreat(false) {
      threats.ClearThreats();
      this.m_threatClears += 1;
      if this.m_threatClears <= 20 {
        CMCSession.Log("AI had a hostile threat, threat list cleared (" + IntToString(this.m_threatClears) + ")");
      }
    }
    this.WatchGuns(s, mech);
    // something switched its reactions back on (a quest or a system re-initialising it)
    let reactions = mech.GetStimReactionComponent();
    if IsDefined(reactions) && reactions.IsEnabled() {
      reactions.Toggle(false);
      CMCSession.Log("AI: stimulus reactions were back on, switched off again");
    }
    // standing, a second or more after the last walk order: has the body moved by itself?
    let pos = mech.GetWorldPosition();
    if !this.m_moving && now - this.m_stoodAt > 1.5 && this.m_strayLogs < 20 {
      let moved = Vector4.Distance2D(pos, this.m_stoodPos);
      if moved > 0.6 {
        this.m_strayLogs += 1;
        CMCSession.Log("NOT OURS: the mech moved " + FloatToStringPrec(moved, 1) + " m while standing, state " + CMUMinotaur.StateName(mech));
        this.m_stoodPos = pos;
      }
    } else {
      this.m_stoodPos = pos;
      if this.m_moving {
        this.m_stoodAt = now;
      }
    }
  }

  // The Minotaur's weak spots (its arms and weapon mounts) are objects of their own with
  // little health; shot off, the MK.31 on that arm is gone. While piloted they take no
  // damage (the hull multiplier would mean nothing if the guns fell off first).
  private func Shield(mech: ref<NPCPuppet>, on: Bool) -> Void {
    let comp = mech.GetWeakspotComponent();
    if !IsDefined(comp) {
      return;
    }
    let spots: array<wref<WeakspotObject>>;
    comp.GetWeakspots(spots);
    let gods = GameInstance.GetGodModeSystem(this.m_game);
    for spot in spots {
      if IsDefined(spot) {
        if on {
          gods.AddGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"ControllableMechs");
        } else {
          gods.RemoveGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"ControllableMechs");
        }
      }
    }
    CMCSession.Log("weak spots: " + IntToString(ArraySize(spots)) + (on ? " shielded" : " unshielded"));
  }

  // ten times a second: a gun whose weapon object has gone is looked up again; the log
  // says when one is lost and what the mech still carries, and when it comes back
  private func WatchGuns(s: ref<CMCSession>, mech: ref<NPCPuppet>) -> Void {
    let ready = (this.m_guns.left.Ready() ? 1 : 0) + (this.m_guns.right.Ready() ? 1 : 0);
    if ready == 2 {
      this.m_gunsLost = false;
      return;
    }
    if !this.m_gunsLost {
      this.m_gunsLost = true;
      CMCSession.Log("WEAPON LOST: left " + (this.m_guns.left.Ready() ? "ok" : "gone") + ", right " + (this.m_guns.right.Ready() ? "ok" : "gone") + ", hull " + IntToString(RoundF(this.m_hull * 100.0)) + "%");
      this.LogInventory(mech);
    }
    if this.m_guns.Refresh(mech) {
      this.m_gunsLost = false;
      CMCSession.Log("weapons found again: " + this.m_guns.Describe());
      CMCSession.Log("rounds: " + this.m_guns.SpeedUp(this.m_game, this.ROUND_SPEED));
    }
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    let mech = this.Mech();
    this.StopServo(mech);
    this.StopFireLoop(mech);
    if IsDefined(mech) {
      this.Armour(mech, 1.0);   // its own health again (the percentage carries over)
    }
    GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"q110_sc_08c_personal_link_disconnected");
    this.Pacify(mech, false);
    if IsDefined(mech) {
      this.CancelCmd(mech, this.m_moveCmd);
      this.CancelCmd(mech, this.m_turnCmd);
      for ev in this.m_lookAts {
        let r = new LookAtRemoveEvent();
        r.lookAtRef = ev.outLookAtRef;
        mech.QueueEvent(r);
      }
    }
    ArrayClear(this.m_lookAts);
    this.m_moveCmd = null;
    this.m_turnCmd = null;
    this.m_marker = null;
    if EntityID.IsDefined(this.m_markerID) {
      GameInstance.GetStaticEntitySystem().DespawnEntity(this.m_markerID);
    }
    let empty: EntityID;
    this.m_markerID = empty;
    // the mech's own hits are its own again (and the alpha's never credit V)
    if IsDefined(this.m_guns) {
      this.SetFlags(false, false);
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
    this.SetFlags(true, s.CreditV());
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
    // each barrel against the fire gate, every frame: it holds that gun's fire, and the
    // gun's reticle shows it (tight and bright when locked on)
    let offL = CMCSession.AimError(this.m_guns.left.weapon, s.aim) > this.GATE_DEG;
    let offR = CMCSession.AimError(this.m_guns.right.weapon, s.aim) > this.GATE_DEG;
    // By default the guns fire while they are still swinging onto the reticle: the rounds
    // go to the reticle point either way. With CONFIG > HOLD FIRE UNTIL ON TARGET a gun
    // waits until its barrel is within GATE_DEG of it. The gun reticles show the barrels'
    // state in both cases.
    this.m_guns.left.offAim = this.m_gate && offL;
    this.m_guns.right.offAim = this.m_gate && offR;
    if this.m_gate && trigger && (offL || offR) {
      this.m_held += 1;
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
    this.GunAudio(mech, trigger, shots > 0);
    let hud = s.Hud();
    if IsDefined(hud) {
      hud.FadeHit(dt);
      hud.SetGunState(!offL, this.m_guns.left.heat, !offR, this.m_guns.right.heat);
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
      s.FlashTag(CMPilotHud.TagFire());
      this.m_logNext = now;
      this.m_held = 0;
      this.m_shots = 0;
      // what the pilot's reticle is on (V's own look-at target is the mech itself)
      this.m_target = s.aimEntity as GameObject;
      this.m_targetHP = CMCHits.Health(this.m_target);
      CMCSession.Log("fire: target " + CMCHits.Describe(this.m_target) + ", health " + FloatToStringPrec(this.m_targetHP, 1));
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
    let hp = CMCHits.Health(this.m_target);
    CMCSession.Log("result: target " + CMCHits.Describe(this.m_target) + ", health " + FloatToStringPrec(this.m_targetHP, 1) + " -> " + FloatToStringPrec(hp, 1));
  }

  // Standing still, the chassis heading is ours: the body swings round toward the view
  // with weight (a rate cap, spin-up and braking), by one rotation-only teleport a frame
  // while it turns. Walking hands the facing back to the walk orders, which face the view.
  //
  // The game sometimes puts the body back on an old heading (the log showed it snapping
  // tens of degrees back to where it stood when the session began). So every frame the
  // body's real heading is compared with where we last put it:
  //   - a jump that brings it nearer the view is taken as it is
  //   - a jump away from the view is put back the same frame
  // Only if the body does not follow at all for 2 s does the rest of the session fall back
  // to the AI's own turn order, which turns in steps.
  private func TurnChassis(s: ref<CMCSession>, mech: ref<NPCPuppet>, dt: Float) -> Void {
    let real = CMPilotRig.YawOf(mech.GetWorldForward());
    let now = s.Now();
    if this.m_moving || now - this.m_stoodAt < 0.8 {
      // walking, or settling out of a walk: the walk order owns the facing
      this.m_bodyYaw = real;
      this.m_turnVel = 0.0;
      this.m_turning = false;
      this.m_turnMiss = 0.0;
      return;
    }
    if this.m_turnByOrder {
      this.TurnByOrder(s, mech, real);
      return;
    }
    let lag = CMPilotRig.Wrap(real - this.m_bodyYaw);
    if AbsF(lag) > 2.0 + AbsF(this.m_turnVel) * dt * 3.0 {
      let nearer = AbsF(CMPilotRig.Wrap(s.rig.yaw - real)) < AbsF(CMPilotRig.Wrap(s.rig.yaw - this.m_bodyYaw));
      this.m_turnMiss += dt;
      if AbsF(lag) > 8.0 && now - this.m_strayYawAt > 0.5 && this.m_strayLogs < 30 {
        this.m_strayYawAt = now;
        this.m_strayLogs += 1;
        CMCSession.Log("chassis: the body jumped " + FloatToStringPrec(lag, 1) + " deg on its own to " + FloatToStringPrec(real, 1) + (nearer ? " (nearer the view: kept)" : " (away from the view: put back)") + ", state " + CMUMinotaur.StateName(mech) + (this.m_turning ? ", mid-turn" : ", between turns"));
      }
      if nearer {
        this.m_bodyYaw = real;
      }
    } else {
      this.m_turnMiss = 0.0;
    }
    if this.m_turnMiss > 2.0 {
      CMCSession.Log("CHASSIS: THE BODY HAS NOT FOLLOWED OUR ROTATION FOR 2 S (body at " + FloatToStringPrec(real, 1) + " deg, put at " + FloatToStringPrec(this.m_bodyYaw, 1) + "), state " + CMUMinotaur.StateName(mech) + ": falling back to AI turn orders, which turn in steps");
      this.m_turnByOrder = true;
      this.m_turning = false;
      this.m_turnVel = 0.0;
      this.m_turnMiss = 0.0;
      this.m_bodyYaw = real;
      return;
    }
    let off = CMPilotRig.Wrap(s.rig.yaw - this.m_bodyYaw);
    if !this.m_turning {
      // the chassis leads a sweep: it starts sooner while the view is moving
      let start = AbsF(s.rig.YawRate()) > 15.0 ? this.TURN_START_SWEEP_DEG : this.TURN_START_DEG;
      if AbsF(off) < start {
        // at rest: hold the heading against anything that moved it
        if AbsF(CMPilotRig.Wrap(real - this.m_bodyYaw)) > 0.5 {
          this.Face(mech, this.m_bodyYaw);
        }
        return;
      }
      this.m_turning = true;
      GameObject.PlaySoundEvent(mech, AbsF(off) > 120.0 ? n"enm_mech_minotaur_loco_idle_to_idle_180_l" : n"enm_mech_minotaur_loco_idle_to_idle_90");
    }
    let want = ClampF(off * this.TURN_K, -this.m_turnRate, this.m_turnRate);
    let step = this.m_turnAccel * dt;
    this.m_turnVel += ClampF(want - this.m_turnVel, -step, step);
    if AbsF(off) < 1.0 && AbsF(this.m_turnVel) < 3.0 {
      this.m_turnVel = 0.0;
      this.m_turning = false;
      return;
    }
    this.m_bodyYaw = CMPilotRig.Wrap(this.m_bodyYaw + this.m_turnVel * dt);
    this.Face(mech, this.m_bodyYaw);
  }

  private func Face(mech: ref<NPCPuppet>, yaw: Float) -> Void {
    let e: EulerAngles;
    e.Yaw = yaw;
    GameInstance.GetTeleportationFacility(this.m_game).Teleport(mech, mech.GetWorldPosition(), e);
  }
  // the fallback: the AI's own turn order toward the view, when the body is more than a
  // few degrees off (tighter with the trigger held), at most one order every 0.6 s
  private func TurnByOrder(s: ref<CMCSession>, mech: ref<NPCPuppet>, real: Float) -> Void {
    this.m_bodyYaw = real;
    let off = CMPilotRig.Wrap(s.rig.yaw - real);
    let firing = s.Key(CMCKey.Lmb());
    let now = s.Now();
    if AbsF(off) < (firing ? 6.0 : 12.0) || now - this.m_turnSent < 0.6 {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, mech.GetWorldPosition() + CMPilotRig.Dir(s.rig.yaw, 0.0) * 20.0);
    let spec: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(spec, world);
    let cmd = new AIRotateToCommand();
    cmd.target = spec;
    cmd.angleTolerance = 3.0;
    this.Send(mech, cmd, false);
    this.m_turnSent = now;
    this.m_turnOrders += 1;
    if this.m_turnOrders <= 10 {
      CMCSession.Log("chassis: turn order " + IntToString(this.m_turnOrders) + ", " + FloatToStringPrec(off, 1) + " deg to go");
    }
    GameObject.PlaySoundEvent(mech, AbsF(off) > 120.0 ? n"enm_mech_minotaur_loco_idle_to_idle_180_l" : n"enm_mech_minotaur_loco_idle_to_idle_90");
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

  // ---------------------------------------------------------------------------
  // The secondary: a missile strike at the reticle point (G)
  // A launch sound and a kick, then after the flight time an explosion attack at the
  // point with V as the instigator (the Dead Shot attack sequence), and the blast effect.
  // One delayed callback per shot; MISSILE_COOLDOWN between shots.
  // ---------------------------------------------------------------------------
  public func Secondary(s: ref<CMCSession>) -> Void {
    let mech = this.Mech();
    let now = s.Now();
    if !IsDefined(mech) {
      return;
    }
    if now < this.m_missileReady {
      GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"ui_hacking_press_fail");
      return;
    }
    this.m_missileReady = now + this.MISSILE_COOLDOWN;
    let at = s.aim;
    // the mech's own launchers when they are live weapon objects: left and right in turn,
    // a real projectile toward the reticle point, its hits credited to V like the MK.31s
    let launcher = this.NextLauncher();
    if IsDefined(launcher) {
      let trigger = gamedataTriggerMode.SemiAuto;
      let rec = launcher.GetWeaponRecord();
      if IsDefined(rec) && IsDefined(rec.PrimaryTriggerMode()) {
        trigger = rec.PrimaryTriggerMode().Type();
      }
      AIWeapon.Fire(mech, launcher, EngineTime.ToFloat(GameInstance.GetSimTime(this.m_game)), 1.0, trigger, at);
      GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_wpn_missile_fire_single");
      s.rig.Recoil(0.9);
      CMCSession.Log("missile: REAL LAUNCHER " + TDBID.ToStringDEBUG(ItemID.GetTDBID(launcher.GetItemID())) + " fired at " + CMCHits.V(at));
      return;
    }
    CMCSession.Log("missile: no live launcher object, using the stand-in strike");
    let flight = ClampF(Vector4.Distance(mech.GetWorldPosition(), at) / this.MISSILE_SPEED, 0.25, 2.5);
    GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_wpn_missile_fire_single");
    s.rig.Recoil(0.9);
    let cb = new CMUMinotaurMissileCb();
    cb.unit = this;
    cb.at = at;
    GameInstance.GetDelaySystem(this.m_game).DelayCallback(cb, flight, false);
    CMCSession.Log("missile: launched at " + CMCHits.V(at) + ", " + FloatToStringPrec(flight, 2) + " s flight");
  }

  // The launchers are in the mech's inventory (Items.Minotaur_Launcher_Right / _Left); they
  // can only fire if the game has them out as weapon objects in a slot. Looked up once on
  // entering.
  private func FindLaunchers(mech: ref<NPCPuppet>) -> Void {
    let ts = GameInstance.GetTransactionSystem(this.m_game);
    let items: array<wref<gameItemData>>;
    ts.GetItemList(mech, items);
    this.m_launchL = null;
    this.m_launchR = null;
    for item in items {
      let id = item.GetID();
      let tdb = ItemID.GetTDBID(id);
      if tdb == t"Items.Minotaur_Launcher_Left" {
        this.m_launchL = ts.GetItemInSlotByItemID(mech, id) as WeaponObject;
      }
      if tdb == t"Items.Minotaur_Launcher_Right" {
        this.m_launchR = ts.GetItemInSlotByItemID(mech, id) as WeaponObject;
      }
    }
    CMCSession.Log("launchers: left " + (IsDefined(this.m_launchL) ? "live" : "not in a slot") + ", right " + (IsDefined(this.m_launchR) ? "live" : "not in a slot"));
  }

  private func NextLauncher() -> ref<WeaponObject> {
    this.m_launchLeft = !this.m_launchLeft;
    let first: ref<WeaponObject> = this.m_launchLeft ? this.m_launchL : this.m_launchR;
    let second: ref<WeaponObject> = this.m_launchLeft ? this.m_launchR : this.m_launchL;
    return IsDefined(first) ? first : second;
  }

  public func Detonate(at: Vector4) -> Void {
    let player = GetPlayer(this.m_game);
    if !IsDefined(player) {
      return;
    }
    // the blast, seen and heard
    GameInstance.GetFxSystem(this.m_game).SpawnEffect(CMUMinotaur.Fx(r"base\\fx\\vehicles\\minotaur\\v_minotaur_explosion.effect"), CMUMinotaur.At(at, new Vector4(0.0, 0.0, 1.0, 0.0)), true);
    // the damage: our record (TweakXL), else the game's frag grenade attack
    let used = "Attacks.CM_Missile";
    let record = TweakDBInterface.GetAttackRecord(t"Attacks.CM_Missile") as Attack_GameEffect_Record;
    if !IsDefined(record) {
      used = "Attacks.FragGrenade";
      record = TweakDBInterface.GetAttackRecord(t"Attacks.FragGrenade") as Attack_GameEffect_Record;
    }
    if !IsDefined(record) {
      CMCSession.Log("missile: no attack record found (Attacks.CM_Missile, Attacks.FragGrenade); the blast is visual only");
      return;
    }
    let ctx: AttackInitContext;
    ctx.record = record;
    ctx.instigator = player;
    ctx.source = player;
    let attack = IAttack.Create(ctx) as Attack_GameEffect;
    if !IsDefined(attack) {
      CMCSession.Log("missile: IAttack.Create returned nothing for " + used);
      return;
    }
    attack.AddStatModifier(RPGManager.CreateStatModifier(gamedataStatType.PhysicalDamage, gameStatModifierType.Additive, this.MISSILE_DAMAGE));
    let statMods: array<ref<gameStatModifierData>>;
    attack.GetStatModList(statMods);
    let flags: array<SHitFlag>;
    let effect = attack.PrepareAttack(player);
    EffectData.SetFloat(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.radius, this.MISSILE_RADIUS);
    EffectData.SetVector(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.position, at);
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.attack, ToVariant(attack));
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.attackStatModList, ToVariant(statMods));
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.flags, ToVariant(flags));
    // the blast is V's attack (V's kill, XP and heat), but those it hits turn on the mech
    let mech = this.Mech();
    if IsDefined(mech) {
      CMCHits.Blame(mech, 0.6);
    }
    attack.StartAttack();
    CMCSession.Log("missile: detonated at " + CMCHits.V(at) + " with " + used + ", radius " + FloatToStringPrec(this.MISSILE_RADIUS, 1) + " m, damage " + FloatToStringPrec(this.MISSILE_DAMAGE, 0));
  }

  // what the mech really carries, once per session (is there a launcher to use later?)
  private func LogInventory(mech: ref<NPCPuppet>) -> Void {
    let items: array<wref<gameItemData>>;
    GameInstance.GetTransactionSystem(this.m_game).GetItemList(mech, items);
    let names = "";
    for item in items {
      names += (StrLen(names) > 0 ? ", " : "") + TDBID.ToStringDEBUG(ItemID.GetTDBID(item.GetID()));
    }
    CMCSession.Log("Minotaur inventory (" + IntToString(ArraySize(items)) + "): " + names);
  }

  // ---- audio: the game's own Militech HMG sounds layered on the mech, and cues for V.
  // Only on state changes: trigger pull and release, the fire loop starting and ending,
  // heat crossing the warning line, a gun locking or unlocking.
  private func GunAudio(mech: ref<NPCPuppet>, trigger: Bool, fired: Bool) -> Void {
    if trigger && !this.m_audioTrigger {
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_init");   // spin-up
    }
    if !trigger && this.m_audioTrigger && this.m_spin > this.SPIN_FIRE {
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_shutdown");   // wind-down
    }
    this.m_audioTrigger = trigger;
    if fired && !this.m_fireLoop {
      this.m_fireLoop = true;
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_fire_auto");
    }
    let locked = this.m_guns.left.locked && this.m_guns.right.locked;
    if this.m_fireLoop && (!trigger || locked) {
      this.StopFireLoop(mech);
    }
    let heat = MaxF(this.m_guns.left.heat, this.m_guns.right.heat);
    if heat > 0.8 && !this.m_heatWarned {
      this.m_heatWarned = true;
      GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"ui_hacking_press_fail");
    }
    if heat < 0.6 {
      this.m_heatWarned = false;
    }
    let anyLocked = this.m_guns.left.locked || this.m_guns.right.locked;
    if anyLocked && !this.m_audioLocked {
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_overheat_open");
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_overheat_steam");
    }
    if !anyLocked && this.m_audioLocked {
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_overheat_close");
    }
    this.m_audioLocked = anyLocked;
  }

  private func StopFireLoop(mech: ref<NPCPuppet>) -> Void {
    if !this.m_fireLoop {
      return;
    }
    this.m_fireLoop = false;
    if IsDefined(mech) {
      GameObject.StopSoundEvent(mech, n"w_gun_hmg_militech_fire_auto");
      GameObject.PlaySoundEvent(mech, n"w_gun_hmg_militech_fire_auto_stop");
    }
  }

  // ---- hull: the mech's Health pool in points against its maximum (read ten times a
  // second, logged whenever it moves by a percent), tougher while piloted, and a beep that
  // quickens as it drops below 30%
  private func ReadHull(mech: ref<NPCPuppet>) -> Float {
    let pools = GameInstance.GetStatPoolsSystem(this.m_game);
    let id = Cast<StatsObjectID>(mech.GetEntityID());
    let points = pools.GetStatPoolValue(id, gamedataStatPoolType.Health, false);
    let max = pools.GetStatPoolMaxPointValue(id, gamedataStatPoolType.Health);
    let frac = max > 0.0 ? ClampF(points / max, 0.0, 1.0) : 0.0;
    if AbsF(frac - this.m_hull) >= 0.01 {
      CMCSession.Log("hull " + FloatToStringPrec(points, 0) + " / " + FloatToStringPrec(max, 0) + " (" + IntToString(RoundF(frac * 100.0)) + "%), pool percent " + FloatToStringPrec(pools.GetStatPoolValue(id, gamedataStatPoolType.Health, true), 1));
    }
    // a hit that took hull: the display jolts and tears, harder for a bigger loss
    if this.m_hull >= 0.0 && frac < this.m_hull - 0.002 {
      let hud = CMCSession.Get(this.m_game).Hud();
      if IsDefined(hud) {
        hud.Damage(this.m_hull - frac);
      }
    }
    this.m_hull = frac;
    return frac;
  }

  // x the mech's Health stat while piloted; the pool keeps its percentage, so current
  // health scales with the maximum both when it goes on and when it comes off
  private func Armour(mech: ref<NPCPuppet>, mult: Float) -> Void {
    let stats = GameInstance.GetStatsSystem(this.m_game);
    let pools = GameInstance.GetStatPoolsSystem(this.m_game);
    let id = Cast<StatsObjectID>(mech.GetEntityID());
    let before = pools.GetStatPoolMaxPointValue(id, gamedataStatPoolType.Health);
    if IsDefined(this.m_armour) {
      stats.RemoveModifier(id, this.m_armour);
      this.m_armour = null;
    }
    if mult > 1.01 {
      this.m_armour = RPGManager.CreateStatModifier(gamedataStatType.Health, gameStatModifierType.Multiplier, mult);
      stats.AddModifier(id, this.m_armour);
    }
    CMCSession.Log("hull x" + FloatToStringPrec(mult, 1) + ": max health " + FloatToStringPrec(before, 0) + " -> " + FloatToStringPrec(pools.GetStatPoolMaxPointValue(id, gamedataStatPoolType.Health), 0)
      + ", now " + FloatToStringPrec(pools.GetStatPoolValue(id, gamedataStatPoolType.Health, false), 0));
  }

  // ten times a second: below 30% a beep repeats, from every 1.2 s at 30% to every 0.25 s
  // near zero; one alarm as it first crosses the line
  private func IntegrityAlarm(now: Float) -> Void {
    let hp = this.m_hull;
    if hp < 0.3 {
      if !this.m_lowAlarm {
        this.m_lowAlarm = true;
        GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"dev_alarm_02");
        CMCSession.Log("hull below 30%: alarm");
      }
      if now >= this.m_beepNext {
        this.m_beepNext = now + 0.25 + 0.95 * (hp / 0.3);
        GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"dev_drone_griffin_default_sgn_idle_beep");
      }
    }
    if hp > 0.4 {
      this.m_lowAlarm = false;
    }
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

  // The flags the damage pipeline hook reads (CMCHits): `piloted` marks the MK.31s and
  // the launchers as ours while the session runs, `credit` makes their hits V's.
  private func SetFlags(piloted: Bool, credit: Bool) -> Void {
    let weapons: array<wref<WeaponObject>> = [this.m_guns.left.weapon, this.m_guns.right.weapon, this.m_launchL, this.m_launchR];
    for w in weapons {
      if IsDefined(w) {
        w.m_cmPiloted = piloted;
        w.m_cmCreditV = piloted && credit;
      }
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
    this.KeepCalm(s, mech, now);
    this.WatchLookAts(s, mech, now);
    this.ReadHull(mech);
    this.IntegrityAlarm(now);
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

  // Diagnostics only: ten times a second, if both guns have been well off a distant
  // reticle point for a second and a half while the body faces it, say so (at most once
  // every 5 s). The look-ats themselves are sent once per session and left alone: taking
  // them off and sending them again left the guns stuck 60-80 deg off for good, where
  // left alone they came back on target by themselves within seconds.
  private func WatchLookAts(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Void {
    if ArraySize(this.m_lookAts) == 0 || !this.m_guns.left.Ready() || !this.m_guns.right.Ready() {
      return;
    }
    let body = AbsF(CMPilotRig.Wrap(s.rig.yaw - CMPilotRig.YawOf(mech.GetWorldForward())));
    let errL = CMCSession.AimError(this.m_guns.left.weapon, s.aim);
    let errR = CMCSession.AimError(this.m_guns.right.weapon, s.aim);
    if body < 35.0 && errL > 12.0 && errR > 12.0 && s.aimDist > 15.0 {
      this.m_lookMiss += 1;
    } else {
      this.m_lookMiss = 0;
    }
    if this.m_lookMiss >= 15 && now - this.m_lookSent > 5.0 {
      this.m_lookSent = now;
      CMCSession.Log("guns off the reticle: " + FloatToStringPrec(errR, 1) + " (R) and " + FloatToStringPrec(errL, 1) + " (L) deg with the body " + FloatToStringPrec(body, 1) + " deg off, reticle " + FloatToStringPrec(s.aimDist, 0) + " m, state " + CMUMinotaur.StateName(mech));
    }
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
      return;   // standing: TurnChassis turns the body and holds its heading, every frame
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

  private func Send(mech: ref<NPCPuppet>, cmd: ref<AICommand>, move: Bool) -> Void {
    let ai = mech.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    this.CancelCmd(mech, this.m_moveCmd);
    this.CancelCmd(mech, this.m_turnCmd);
    this.m_moveCmd = null;
    this.m_turnCmd = null;
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
      st.title = StrUpper(name);
    }
    st.integrity = this.m_hull;
    st.signal = link.SignalFraction();
    st.distance = link.Distance();
    st.heatL = this.m_guns.left.heat;
    st.heatR = this.m_guns.right.heat;
    st.lockedL = this.m_guns.left.locked;
    st.lockedR = this.m_guns.right.locked;
    st.hasL = this.m_guns.left.Ready();
    st.hasR = this.m_guns.right.Ready();
    let wait = this.m_missileReady - s.Now();
    st.hints = st.hints + "   [G] MISSILE";
    st.missile = wait > 0.0 ? "MSL RELOAD " + IntToString(CeilF(wait)) + "S" : "MSL READY";
    if !st.hasL && !st.hasR {
      st.warning = "NO WEAPONS - MK.31 OFFLINE";
    } else if st.integrity < 0.3 {
      st.warning = "HULL INTEGRITY LOW";
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

public class CMUMinotaurMissileCb extends DelayCallback {
  public let unit: wref<CMUMinotaur>;
  public let at: Vector4;
  public func Call() -> Void {
    if IsDefined(this.unit) {
      this.unit.Detonate(this.at);
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
