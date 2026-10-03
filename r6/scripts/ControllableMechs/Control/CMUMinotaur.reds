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
  private let m_stoodAt: Float;       // the last slow tick it was walking: the turn waits for it to settle
  private let m_triggerWas: Bool;     // for the FIRE tag, on each pull
  // part damage (CMCParts): this mech's seven parts, and a message about one that just broke
  private let m_parts: ref<CMPartState>;
  private let m_partsOn: Bool;
  private let m_partNote: String;
  private let m_partNoteUntil: Float;
  private let m_limpHalt: Bool;
  private let m_limpNext: Float;
  private let m_gait: Float;          // the walk's animation speed (a damaged leg slows it)
  private let m_critFx: Bool;         // the all-vents smoke while the hull is critical
  private let m_mech: wref<NPCPuppet>;
  private let m_sensorUp: Float;      // the sensor mount, read once per session
  private let m_sensorFwd: Float;

  // the weighted chassis turn while standing: the body turns toward the view at a capped
  // rate, easing in and out (the look-ats cover the last TURN_START_DEG on their own)
  private let m_bodyYaw: Float;
  private let m_turnVel: Float;
  private let m_air: Bool;           // nothing under the mech's feet (Airborne)
  private let m_combatWatch: Int32;   // seconds left to report whether it is still in combat
  private let m_lookAtsFrom: Float;   // not before this time (after an AI restart)
  private let m_combatWatchAt: Float;
  private let m_airTime: Float;
  private let m_airLogs: Int32;
  private let m_sentOpen: Bool;       // a rotation request is out and has not landed yet
  private let m_sentYaw: Float;
  private let m_sentAt: Float;
  private let m_lookMiss: Int32;     // slow ticks the guns have been off with the body on
  private let m_lookSent: Float;
  private let m_turning: Bool;
  private let m_body: ref<CMMechBody>;   // the physics body (0.9.0-a2, CONFIG > MECH PHYSICS)
  private let m_bodyLed: Bool;        // the body led last frame
  private let m_edgeT: Float;         // seconds walked against a drop (steps off at 0.5)
  private let m_dropAhead: Bool;      // SafeReach stopped at a drop, not a wall
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

  // the livery names it: the Minotaur's four appearances share one body
  public func Name() -> String {
    let mech = this.Mech();
    if !IsDefined(mech) {
      return "MINOTAUR";
    }
    let look = NameToString(mech.GetCurrentAppearanceName());
    if StrContains(look, "arasaka") {
      return "ARASAKA MINOTAUR";
    }
    if StrContains(look, "police") {
      return "NCPD MINOTAUR";
    }
    if StrContains(look, "kurt") {
      return "KURT'S MINOTAUR";
    }
    return "MILITECH MINOTAUR";
  }
  public func LostReason() -> String = "!MECH DESTROYED"

  // the mech, looked up by its id only when the kept reference has gone (it is asked for
  // several times a frame)
  private func Mech() -> ref<NPCPuppet> {
    if !IsDefined(this.m_mech) {
      this.m_mech = GameInstance.FindEntityByID(this.m_game, this.m_mechID) as NPCPuppet;
    }
    return this.m_mech;
  }

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
    this.m_mech = mech;
    let cfg = CMPilotSystem.Get(this.m_game);
    this.m_sensorUp = Cast<Float>(cfg.CamUpCm()) / 100.0;
    this.m_sensorFwd = Cast<Float>(cfg.CamFwdCm()) / 100.0;
    link.Hold();
    link.SetOrder(CMOrder.Pilot());
    this.m_guns = new CMPilotGuns();
    this.m_guns.Init(mech);
    this.m_moving = false;
    this.m_triggerWas = false;
    this.m_bodyYaw = CMPilotRig.YawOf(mech.GetWorldForward());
    this.m_turnVel = 0.0;
    this.m_turning = false;
    this.m_sentOpen = false;
    let turn = Cast<Float>(cfg.TurnPct()) / 100.0;
    this.m_turnRate = this.TURN_RATE * turn;
    this.m_turnAccel = this.TURN_ACCEL * turn;
    this.m_gate = cfg.FireGate();
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
    // taken over mid-fight: its combat behaviour would run on (searching for the enemies
    // it no longer has) for many seconds; its AI is switched off and on again to drop it
    let fighting = NPCPuppet.IsInCombat(mech) || Equals(mech.GetHighLevelStateFromBlackboard(), gamedataNPCHighLevelState.Combat);
    this.Pacify(mech, true);
    if fighting {
      this.Reboot(mech);
      // the gun look-ats sent in the same moment as the restart were lost with it (the
      // guns stayed 20-30 deg off for the whole session): they go out a second later
      this.m_lookAtsFrom = s.Now() + 1.0;
    }
    this.m_combatWatch = fighting ? 10 : 0;
    GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"ui_q110_personal_link_01");   // link established
    CMCSession.Log("Minotaur: guns " + this.m_guns.Describe());
    this.LogInventory(mech);
    this.SetFlags(true, s.CreditV());
    this.m_missileReady = 0.0;
    this.m_hull = -1.0;
    this.Armour(mech, s.HullMult());
    this.ReadHull(mech);
    this.m_partsOn = cfg.PartDamage();
    this.m_parts = CMCParts.Get(this.m_game).State(mech.GetEntityID());
    this.m_partNote = "";
    this.m_gait = 1.0;
    this.m_critFx = false;
    this.ApplyParts(s, mech);
    CMCSession.Log("rounds: " + this.m_guns.SpeedUp(this.m_game, this.ROUND_SPEED));
    this.m_body = null;
    this.m_bodyLed = false;
    this.m_edgeT = 0.0;
    if cfg.MechPhysics() {
      if CMPhysStep.Present() {
        this.m_body = CMMechBody.Make(this.m_game);
        this.m_body.Start(mech, s.Now());
      } else {
        CMCSession.Log("mech body: MECH PHYSICS is on but MNC Physics (version 3 or up) isn't loaded; the mech walks without a body");
      }
    }
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
    CMCSession.Log("AI " + (on ? "suppressed (stimulus reactions" + (IsDefined(reactions) ? "" : " [no component]") + ", senses and target tracking off, relaxed)" : "restored") + ", state now " + CMUMinotaur.StateName(mech));
  }

  private static func StateName(mech: ref<NPCPuppet>) -> String {
    return EnumValueToString("gamedataNPCHighLevelState", Cast<Int64>(EnumInt(mech.GetHighLevelStateFromBlackboard())));
  }

  // Its AI controller off and on again: the behaviour tree starts over, with its state
  // already relaxed and nothing on its threat list, so the fight it was in is gone.
  private func Reboot(mech: ref<NPCPuppet>) -> Void {
    let ai = mech.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    ai.Toggle(false);
    ai.Toggle(true);
    CMCSession.Log("AI: taken over mid-fight, its AI restarted to drop the fight (in combat now: " + (NPCPuppet.IsInCombat(mech) ? "yes" : "no") + ")");
  }

  // ten times a second: one blackboard read and two flag reads unless something is wrong
  private func KeepCalm(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Void {
    // after a mid-fight takeover, once a second for ten seconds: still fighting?
    if this.m_combatWatch > 0 && now - this.m_combatWatchAt >= 1.0 {
      this.m_combatWatchAt = now;
      this.m_combatWatch -= 1;
      let still = NPCPuppet.IsInCombat(mech);
      CMCSession.Log("AI: " + IntToString(10 - this.m_combatWatch) + " s after the takeover, in combat: " + (still ? "yes" : "no") + ", state " + CMUMinotaur.StateName(mech));
      if !still {
        this.m_combatWatch = 0;
      }
    }
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
    if this.m_moving {
      this.m_stoodAt = now;
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
    // (a gun shot off is gone for good, not lost: nothing to look for)
    let ready = (this.m_guns.left.Ready() || this.m_guns.left.destroyed ? 1 : 0) + (this.m_guns.right.Ready() || this.m_guns.right.destroyed ? 1 : 0);
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
      this.SetFlags(true, s.CreditV());
      CMCSession.Log("weapons found again: " + this.m_guns.Describe());
      CMCSession.Log("rounds: " + this.m_guns.SpeedUp(this.m_game, this.ROUND_SPEED));
    }
  }

  public func End(s: ref<CMCSession>, hard: Bool) -> Void {
    let mech = this.Mech();
    if IsDefined(this.m_body) {
      this.m_body.Stop(mech);
      this.m_body = null;
    }
    this.StopServo(mech);
    this.StopFireLoop(mech);
    if IsDefined(mech) {
      this.Armour(mech, 1.0);   // its own health again (the percentage carries over)
    }
    GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"q110_sc_08c_personal_link_disconnected");
    if IsDefined(mech) && this.m_critFx {
      GameObjectEffectHelper.StopEffectEvent(mech, n"hacks_overheat_lvl2");
    }
    this.m_critFx = false;
    // destroyed under the pilot: the Minotaur's own explosion, and no attached effect left
    // on the wreck
    if IsDefined(mech) && !ScriptedPuppet.IsAlive(mech) {
      CMCParts.Get(this.m_game).DropFx(mech);
      CMCSession.Log("fx: start explode_death");
      GameObjectEffectHelper.StartEffectEvent(mech, n"explode_death");
    }
    if IsDefined(mech) && this.m_gait != 1.0 {
      mech.UnsetIndividualTimeDilation();
    }
    this.m_gait = 1.0;
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
    // the mech's own hits are its own again
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
  public func SensorUp() -> Float = this.m_sensorUp
  public func SensorFwd() -> Float = this.m_sensorFwd
  public func AimSkip() -> Float = 4.5

  // ---------------------------------------------------------------------------
  // Every frame: the marker onto the aim point, the gate, the guns
  // ---------------------------------------------------------------------------
  public func Tick(s: ref<CMCSession>, dt: Float, now: Float) -> Void {
    let mech = this.Mech();
    this.MoveMarker(s.aim);
    this.BodyTick(s, mech, dt, now);
    this.TurnChassis(s, mech, dt);
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
    // By default the guns fire while they are still swinging onto the reticle, and a gun
    // that is not on it yet fires where its own barrel points (its gun reticle on the
    // HUD), so flash, tracer and hit agree. Once within GATE_DEG it fires at the reticle
    // point. With CONFIG > HOLD FIRE UNTIL ON TARGET a gun waits instead.
    this.m_guns.left.offAim = this.m_gate && offL;
    this.m_guns.right.offAim = this.m_gate && offR;
    this.OwnTarget(this.m_guns.left, !this.m_gate && offL && trigger, now, dt);
    this.OwnTarget(this.m_guns.right, !this.m_gate && offR && trigger, now, dt);
    let flashL = this.m_guns.left.flash;
    let flashR = this.m_guns.right.flash;
    let shots = this.m_guns.Update(mech, now, dt, lmb, rmb, s.FireMode(), s.aim, this.SPREAD_DEG, s.rig.pos);
    if shots > 0 {
      s.rig.Recoil(this.KICK * Cast<Float>(shots));
      // which barrel just fired: its flash timer was reset this frame
      if this.m_guns.left.flash > flashL {
        this.RoundFx(this.m_guns.left.weapon, this.m_guns.left.ownTarget ? this.m_guns.left.target : s.aim);
      }
      if this.m_guns.right.flash > flashR && this.m_guns.right.weapon != this.m_guns.left.weapon {
        this.RoundFx(this.m_guns.right.weapon, this.m_guns.right.ownTarget ? this.m_guns.right.target : s.aim);
      }
    }
    if trigger && !this.m_triggerWas {
      s.FlashTag(CMPilotHud.TagFire());
    }
    this.m_triggerWas = trigger;
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


  // Standing still, the chassis heading is ours. `m_bodyYaw` is the heading we want: it
  // swings toward the view with weight (a rate cap, spin-up and braking), by time alone.
  // The body is steered onto it with the AI's own turn order, one at a time: the next goes
  // out only when the last has landed (the body's real heading reached it) or after
  // 0.45 s. Sent every frame, rotation requests never landed; one at a time, turn orders
  // land about 98% of the time within a frame or two (teleports, tried first, almost never
  // did and were dropped). Walking hands the facing back to the walk orders.
  private func TurnChassis(s: ref<CMCSession>, mech: ref<NPCPuppet>, dt: Float) -> Void {
    let real = CMPilotRig.YawOf(mech.GetWorldForward());
    let now = s.Now();
    if this.m_moving || this.m_air || now - this.m_stoodAt < 0.8 {
      // walking, in the air, or settling out of a walk: no rotation from us
      this.m_bodyYaw = real;
      this.m_turnVel = 0.0;
      this.m_turning = false;
      this.m_sentOpen = false;
      return;
    }
    // has the last order landed?
    if this.m_sentOpen && AbsF(CMPilotRig.Wrap(real - this.m_sentYaw)) < 3.5 {
      this.m_sentOpen = false;
    }
    // the heading we want, swinging toward the view
    let off = CMPilotRig.Wrap(s.rig.yaw - this.m_bodyYaw);
    if !this.m_turning {
      // the chassis leads a sweep: it starts sooner while the view is moving
      let start = AbsF(s.rig.YawRate()) > 15.0 ? this.TURN_START_SWEEP_DEG : this.TURN_START_DEG;
      if AbsF(off) >= start {
        this.m_turning = true;
        GameObject.PlaySoundEvent(mech, AbsF(off) > 120.0 ? n"enm_mech_minotaur_loco_idle_to_idle_180_l" : n"enm_mech_minotaur_loco_idle_to_idle_90");
      }
    }
    if this.m_turning {
      let want = ClampF(off * this.TURN_K, -this.m_turnRate, this.m_turnRate);
      let step = this.m_turnAccel * dt;
      this.m_turnVel += ClampF(want - this.m_turnVel, -step, step);
      if AbsF(off) < 1.0 && AbsF(this.m_turnVel) < 3.0 {
        this.m_turnVel = 0.0;
        this.m_turning = false;
      } else {
        this.m_bodyYaw = CMPilotRig.Wrap(this.m_bodyYaw + this.m_turnVel * dt);
      }
    }
    // steer the body onto it, one order at a time
    if AbsF(CMPilotRig.Wrap(real - this.m_bodyYaw)) > 0.7 && (!this.m_sentOpen || now - this.m_sentAt > 0.45) {
      let world: WorldPosition;
      WorldPosition.SetVector4(world, mech.GetWorldPosition() + CMPilotRig.Dir(this.m_bodyYaw, 0.0) * 20.0);
      let spec: AIPositionSpec;
      AIPositionSpec.SetWorldPosition(spec, world);
      let cmd = new AIRotateToCommand();
      cmd.target = spec;
      cmd.angleTolerance = 1.0;
      this.Send(mech, cmd, false);
      this.m_sentYaw = this.m_bodyYaw;
      this.m_sentAt = now;
      this.m_sentOpen = true;
    }
  }
  // What a barrel that is off the reticle points at: the nearest hit of a ray along it
  // (world geometry, then characters and vehicles), or a point 150 m out when it points at
  // nothing. Two raycasts, and only in the frame that gun is about to fire.
  private func OwnTarget(g: ref<CMGun>, off: Bool, now: Float, dt: Float) -> Void {
    g.ownTarget = false;
    if !off || !g.Ready() || now < g.nextShot - dt {
      return;
    }
    let fwd = g.weapon.GetWorldForward();
    let from = g.weapon.GetWorldPosition() + fwd * 2.0;
    let to = from + fwd * 300.0;
    let sq = GameInstance.GetSpatialQueriesSystem(this.m_game);
    let at = from + fwd * 150.0;
    let best = 9999.0;
    let hit: TraceResult;
    if CMGround.World(this.m_game, from, to, hit) {
      at = Cast<Vector4>(hit.position);
      best = Vector4.Distance(from, at);
    }
    let dyn: TraceResult;
    if CMGround.Movers(this.m_game, from, to, dyn) {
      let p = Cast<Vector4>(dyn.position);
      if Vector4.Distance(from, p) < best {
        at = p;
      }
    }
    at.W = 1.0;
    g.target = at;
    g.ownTarget = true;
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

  public static func Fx(path: ResRef) -> FxResource {
    let ref: ResourceAsyncRef;
    ResourceAsyncRef.SetPath(ref, path);
    let fx: FxResource;
    fx.effect = ref;
    return fx;
  }

  public static func At(p: Vector4, dir: Vector4) -> WorldTransform {
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
  // point with V as the instigator, and the blast effect.
  // One delayed callback per shot; MISSILE_COOLDOWN between shots.
  // ---------------------------------------------------------------------------
  public func Secondary(s: ref<CMCSession>) -> Void {
    let mech = this.Mech();
    let now = s.Now();
    if !IsDefined(mech) {
      return;
    }
    if now < this.m_missileReady || this.PartHp(CMPart.Pods()) <= 0.0 {
      GameObject.PlaySoundEvent(GetPlayer(this.m_game), n"ui_hacking_press_fail");
      return;
    }
    // damaged pods reload half as fast again
    this.m_missileReady = now + this.MISSILE_COOLDOWN * (this.PartHp(CMPart.Pods()) < 0.5 ? 1.5 : 1.0);
    let at = s.aim;
    // (the Minotaur's own launchers are in its inventory but never out as weapon objects,
    // so there is nothing to fire them with: the strike is ours)
    let flight = ClampF(Vector4.Distance(mech.GetWorldPosition(), at) / this.MISSILE_SPEED, 0.25, 2.5);
    GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_wpn_missile_fire_single");
    s.rig.Recoil(0.9);
    let cb = new CMUMinotaurMissileCb();
    cb.unit = this;
    cb.at = at;
    GameInstance.GetDelaySystem(this.m_game).DelayCallback(cb, flight, false);
    CMCSession.Log("missile: launched at " + CMCHits.V(at) + ", " + FloatToStringPrec(flight, 2) + " s flight");
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
      + ", now " + FloatToStringPrec(pools.GetStatPoolValue(id, gamedataStatPoolType.Health, false), 0)
      + " (Health stat " + FloatToStringPrec(stats.GetStatValue(id, gamedataStatType.Health), 0) + (IsDefined(this.m_armour) ? ", our modifier on" : ", no modifier of ours") + ")");
  }

  // ten times a second: below 30% a beep repeats, from every 1.2 s at 30% to every 0.25 s
  // near zero; one alarm as it first crosses the line. Played on the mech, where the camera
  // is: world sounds played on V were too far from the camera to be heard.
  private func IntegrityAlarm(mech: ref<NPCPuppet>, now: Float) -> Void {
    let hp = this.m_hull;
    if hp < 0.3 {
      if !this.m_lowAlarm {
        this.m_lowAlarm = true;
        // louder: the alarm with a Militech drone's final warning over it
        GameObject.PlaySoundEvent(mech, n"dev_alarm_02");
        GameObject.PlaySoundEvent(mech, n"dev_drone_octant_default_sgn_reprimand_final_warning");
        CMCSession.Log("hull below 30%: alarm");
      }
      if now >= this.m_beepNext {
        this.m_beepNext = now + 0.25 + 0.95 * (hp / 0.3);
        // two drone beeps layered, so it cuts through gunfire
        GameObject.PlaySoundEvent(mech, n"dev_drone_griffin_default_sgn_idle_beep");
        GameObject.PlaySoundEvent(mech, n"dev_drone_octant_default_sgn_idle_beep");
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
    let weapons: array<wref<WeaponObject>> = [this.m_guns.left.weapon, this.m_guns.right.weapon];
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
    if link.Distance() > CMLinkSystem.SignalRange() {
      return "!SIGNAL LOST";
    }
    this.SendLookAts(mech);
    this.KeepCalm(s, mech, now);
    this.WatchLookAts(s, mech, now);
    this.ReadHull(mech);
    this.IntegrityAlarm(mech, now);
    if IsDefined(this.m_body) && this.m_body.Live() {
      this.m_air = this.m_body.led || this.BodyFall(mech, now);
    } else {
      this.m_air = this.Airborne(s, mech);
    }
    if !this.m_air {
      this.Drive(s, mech, now);
      this.Gait(mech);
    }
    return "";
  }

  // once the marker has attached: the four gun-part look-ats, pointed at it
  private func SendLookAts(mech: ref<NPCPuppet>) -> Void {
    if ArraySize(this.m_lookAts) > 0 || !EntityID.IsDefined(this.m_markerID) || EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_game)) < this.m_lookAtsFrom {
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
  // How far the mech can walk along `dir` before a real drop: the ground is sampled every
  // 1.5 m from 3 m out (a short ray down each time), and the walk stops 1 m before the
  // first point more than 2.5 m below its feet (or 2 m above, a wall-like step). Slopes,
  // kerbs and banks pass (the first version, at 1.5 m either way, stopped walks that went
  // nowhere near an edge). Only when a walk order is about to go out.
  private func SafeReach(pos: Vector4, dir: Vector4, reach: Float) -> Float {
    this.m_dropAhead = false;
    let d = 3.0;
    while d <= reach {
      let p = pos + dir * d;
      let hit: TraceResult;
      let ground = CMGround.Down(this.m_game, new Vector4(p.X, p.Y, pos.Z + 3.0, 1.0), new Vector4(p.X, p.Y, pos.Z - 6.0, 1.0), hit);
      let dz = ground ? Cast<Vector4>(hit.position).Z - pos.Z : -10.0;
      if dz < -2.5 || dz > 2.0 {
        this.m_dropAhead = dz < -2.5;
        return d - 1.0;
      }
      d += 1.5;
    }
    return reach;
  }

  // Ten times a second: is the mech standing on anything? One ray down from its feet. In
  // the air (walked or blown off a ledge) it gets no orders at all, so the game's own fall
  // has the best chance to run; if it is still in the air after half a second (the game
  // left it hanging), it is set down on the ground below, with a heavy landing.
  private func Airborne(s: ref<CMCSession>, mech: ref<NPCPuppet>) -> Bool {
    let pos = mech.GetWorldPosition();
    let hit: TraceResult;
    let gap = 0.0;
    // no hit at all is not taken as air: some ground isn't in the static group the ray
    // looks for (a mech standing in such a spot lost all walking, as if it hung 60 m up)
    if CMGround.Down(this.m_game, new Vector4(pos.X, pos.Y, pos.Z + 0.5, 1.0), new Vector4(pos.X, pos.Y, pos.Z - 60.0, 1.0), hit) {
      gap = pos.Z - Cast<Vector4>(hit.position).Z;
    }
    if gap < 1.0 {
      this.m_airTime = 0.0;
      return false;
    }
    if this.m_airTime == 0.0 {
      CMCSession.Log("AIRBORNE: " + FloatToStringPrec(gap, 1) + " m above the ground, orders held");
      this.CancelCmd(mech, this.m_moveCmd);
      this.CancelCmd(mech, this.m_turnCmd);
      this.m_moveCmd = null;
      this.m_turnCmd = null;
      this.m_moving = false;
    }
    this.m_airTime += 0.1;
    // wait a second and a half first: from a small height the game settles it by itself,
    // and acting sooner (every half second) stopped even that; then one try every 3 s
    if this.m_airTime >= 1.5 && gap < 60.0 {
      CMGround.SetDown(mech, Cast<Vector4>(hit.position));
      this.m_airLogs += 1;
      if this.m_airLogs <= 6 {
        CMCSession.Log("AIRBORNE: still hanging after " + FloatToStringPrec(this.m_airTime, 1) + " s, teleport order to the ground " + FloatToStringPrec(gap, 1) + " m below");
      }
      s.rig.Nudge(12.0, -1.2);   // the landing, felt
      this.m_airTime = -1.5;   // the next try 3 s from now if it is still up
    }
    return true;
  }

  // ---- the physics body (CMMechBody): every frame it follows the walk or leads it; when it
  // takes the lead the walk and turn orders are dropped, and its landings and knocks are felt
  private func BodyTick(s: ref<CMCSession>, mech: ref<NPCPuppet>, dt: Float, now: Float) -> Void {
    if !IsDefined(this.m_body) {
      return;
    }
    this.m_body.Tick(mech, dt, now);
    if this.m_body.failed {
      this.m_body = null;
      return;
    }
    let led = this.m_body.led;
    if led && !this.m_bodyLed {
      this.CancelCmd(mech, this.m_moveCmd);
      this.CancelCmd(mech, this.m_turnCmd);
      this.m_moveCmd = null;
      this.m_turnCmd = null;
      this.m_moving = false;
      this.m_air = true;
    }
    if !led && this.m_bodyLed {
      // back on its legs: the turn starts from where it faces now
      this.m_bodyYaw = CMPilotRig.YawOf(mech.GetWorldForward());
      this.m_turnVel = 0.0;
      this.m_turning = false;
      this.m_sentOpen = false;
      this.m_stoodAt = now;
      this.m_air = false;
    }
    this.m_bodyLed = led;
    if this.m_body.knock > 0.0 {
      s.rig.Nudge(MinF(30.0, this.m_body.knock * 4.0), -MinF(2.0, this.m_body.knock * 0.3));
    }
    if this.m_body.landing > 0.0 {
      this.Land(s, mech, this.m_body.landing);
    }
  }

  // ten times a second, with a body: nothing under its feet, it falls (the game has no fall
  // for the Minotaur; the body has)
  private func BodyFall(mech: ref<NPCPuppet>, now: Float) -> Bool {
    let pos = mech.GetWorldPosition();
    let hit: TraceResult;
    if !CMGround.Down(this.m_game, new Vector4(pos.X, pos.Y, pos.Z + 0.5, 1.0), new Vector4(pos.X, pos.Y, pos.Z - 60.0, 1.0), hit) {
      return false;   // no hit is not air (see Airborne)
    }
    let gap = pos.Z - Cast<Vector4>(hit.position).Z;
    if gap < 1.2 {
      return false;
    }
    this.m_body.Fall(mech, gap, now);
    return this.m_body.led;
  }

  // A landing, felt: a heavy one shakes the view and costs hull, a hard one the legs too
  private func Land(s: ref<CMCSession>, mech: ref<NPCPuppet>, speed: Float) -> Void {
    s.rig.Nudge(MinF(40.0, 4.0 + speed * 2.5), -MinF(3.0, 0.4 + speed * 0.2));
    GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_lcm_servo_short");
    if speed < 7.0 {
      return;
    }
    let over = speed - 7.0;
    let pct = MinF(60.0, over * over * 1.5);
    GameInstance.GetStatPoolsSystem(this.m_game).RequestChangingStatPoolValue(Cast<StatsObjectID>(mech.GetEntityID()), gamedataStatPoolType.Health, -pct, null, false, true);
    GameObject.PlaySoundEvent(mech, n"dev_generic_impact_metal");
    this.m_partNote = speed >= 12.0 ? "HARD LANDING - LEG ACTUATORS DAMAGED" : "HARD LANDING";
    this.m_partNoteUntil = s.Now() + 3.0;
    if speed >= 12.0 && this.m_partsOn && IsDefined(this.m_parts) {
      let wear = MinF(0.6, (speed - 12.0) * 0.06 + 0.15);
      for leg in [CMPart.LegL(), CMPart.LegR()] {
        if this.m_parts.hp[leg] > 0.0 {
          this.m_parts.hp[leg] = MaxF(0.0, this.m_parts.hp[leg] - wear);
          if this.m_parts.hp[leg] <= 0.0 {
            this.BreakPart(s, mech, leg);
          }
        }
      }
    }
    CMCSession.Log("landing: " + FloatToStringPrec(speed, 1) + " m/s, " + FloatToStringPrec(pct, 0) + "% of its health" + (speed >= 12.0 ? ", legs worn" : ""));
  }

  // WASD relative to where the view looks; the mech walks there on its own legs
  private func Drive(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Void {
    let f = (s.Key(CMCKey.W()) ? 1.0 : 0.0) - (s.Key(CMCKey.S()) ? 1.0 : 0.0);
    let side = (s.Key(CMCKey.D()) ? 1.0 : 0.0) - (s.Key(CMCKey.A()) ? 1.0 : 0.0);
    let dir = CMPilotRig.Dir(s.rig.yaw, 0.0) * f + CMPilotRig.Dir(s.rig.yaw - 90.0, 0.0) * side;
    let pos = mech.GetWorldPosition();
    if Vector4.Length(dir) < 0.1 {
      this.m_edgeT = 0.0;
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
    if this.Limp(s, mech, now) {
      return;
    }
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
    // nor off a ledge: the game walks NPCs on its navigation mesh and has no fall for the
    // Minotaur, so one walked off an edge hangs in the air (see Airborne)
    let wall = reach;
    reach = this.SafeReach(pos, dir, reach);
    if reach < 1.5 && this.m_dropAhead && IsDefined(this.m_body) && this.m_body.Live() {
      // with a body it can go over: held against the drop for half a second, it steps off
      this.m_edgeT += 0.1;
      if this.m_edgeT >= 0.5 {
        this.m_edgeT = 0.0;
        this.CancelCmd(mech, this.m_moveCmd);
        this.m_moveCmd = null;
        this.m_moving = false;
        this.m_body.StepOff(mech, dir, now);
        return;
      }
    } else {
      this.m_edgeT = 0.0;
    }
    if reach < 1.5 {
      if this.m_moving {
        this.CancelCmd(mech, this.m_moveCmd);
        this.m_moveCmd = null;
        this.m_moving = false;
        CMCSession.Log(reach < wall ? "walk: stop (drop ahead)" : "walk: stop (wall ahead)");
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
  // ---------------------------------------------------------------------------
  // Part damage (docs/DAMAGE_DESIGN.md; the state lives in CMCParts)
  // ---------------------------------------------------------------------------
  private func PartHp(i: Int32) -> Float = this.m_partsOn && IsDefined(this.m_parts) ? this.m_parts.hp[i] : 1.0

  public func OpticsOnline() -> Bool = this.PartHp(CMPart.Sensor()) > 0.0

  // What is already broken on this mech (from an earlier session, or the dev tools), put
  // on the model and the guns. Also called with no hit when parts were restored or broken
  // from the terminal.
  private func ApplyParts(s: ref<CMCSession>, mech: ref<NPCPuppet>) -> Void {
    let armL = this.PartHp(CMPart.ArmL()) <= 0.0;
    let armR = this.PartHp(CMPart.ArmR()) <= 0.0;
    this.m_guns.left.destroyed = armL;
    this.m_guns.right.destroyed = armR;
    if this.m_partsOn {
      CMCParts.Get(this.m_game).Effects(mech);
    }
    CMCParts.ShowGun(mech, true, !armL);
    CMCParts.ShowGun(mech, false, !armR);
    if !this.OpticsOnline() {
      s.OpticsLost();
    }
  }

  // A hit the mech took: CMCParts works out the part and wears it down.
  public func TakeHit(s: ref<CMCSession>, hit: ref<gameHitEvent>) -> Void {
    let mech = this.Mech();
    if !IsDefined(mech) || !IsDefined(this.m_parts) {
      return;
    }
    if !IsDefined(hit) {
      this.ApplyParts(s, mech);   // restored or broken from the terminal
      return;
    }
    this.Blast(s, mech, hit);
    if !this.m_partsOn {
      return;
    }
    let r = CMCParts.Get(this.m_game).Hit(mech, hit);
    if !IsDefined(r) {
      return;
    }
    let hud = s.Hud();
    if IsDefined(hud) {
      hud.PartHit(r.part);
    }
    if r.broke {
      this.BreakPart(s, mech, r.part);
    }
  }

  // A damaged leg slows the walk: the mech's animation runs slower while it walks (one leg
  // broken 60%, both 40%, a leg under half 85%), so it covers less ground. The Minotaur has
  // no limping walk of its own. Set only when the speed changes.
  private func Gait(mech: ref<NPCPuppet>) -> Void {
    let want = 1.0;
    if this.m_moving {
      let l = this.PartHp(CMPart.LegL());
      let r = this.PartHp(CMPart.LegR());
      let broken = (l <= 0.0 ? 1 : 0) + (r <= 0.0 ? 1 : 0);
      want = broken == 2 ? 0.4 : (broken == 1 ? 0.6 : (l < 0.5 || r < 0.5 ? 0.85 : 1.0));
    }
    if want == this.m_gait {
      return;
    }
    this.m_gait = want;
    if want < 1.0 {
      mech.SetIndividualTimeDilation(n"CMDamagedLeg", want);
    } else {
      mech.UnsetIndividualTimeDilation();
    }
  }

  // A damaged leg: the walk comes in halting strides, the body dipping as it plants on the
  // bad leg. One leg broken: short strides and halts; both: shorter, longer halts; a leg
  // under half: a slight hitch. True while halted (no walk order goes out).
  private func Limp(s: ref<CMCSession>, mech: ref<NPCPuppet>, now: Float) -> Bool {
    let l = this.PartHp(CMPart.LegL());
    let r = this.PartHp(CMPart.LegR());
    let broken = (l <= 0.0 ? 1 : 0) + (r <= 0.0 ? 1 : 0);
    let stride = 0.0;
    let halt = 0.0;
    if broken == 2 {
      stride = 0.7;
      halt = 1.1;
    } else if broken == 1 {
      stride = 1.0;
      halt = 0.7;
    } else if l < 0.5 || r < 0.5 {
      stride = 1.8;
      halt = 0.35;
    } else {
      return false;
    }
    if now >= this.m_limpNext {
      this.m_limpHalt = !this.m_limpHalt;
      this.m_limpNext = now + (this.m_limpHalt ? halt : stride);
      if this.m_limpHalt {
        s.rig.Nudge(this.STOP_ROCK * 1.6, -0.45);   // it sags onto the bad leg
      }
    }
    if this.m_limpHalt && this.m_moving {
      this.CancelCmd(mech, this.m_moveCmd);
      this.m_moveCmd = null;
      this.m_moving = false;
    }
    return this.m_limpHalt;
  }
  // A blast near it shoves the body (away from the blast, a little up): the nearer, the
  // harder; past KNOCK it staggers
  private func Blast(s: ref<CMCSession>, mech: ref<NPCPuppet>, hit: ref<gameHitEvent>) -> Void {
    if !IsDefined(this.m_body) || !this.m_body.Live() || !IsDefined(hit.attackData) {
      return;
    }
    if NotEquals(hit.attackData.GetAttackType(), gamedataAttackType.Explosion) {
      return;
    }
    let from = hit.attackData.GetAttackPosition();
    let away = mech.GetWorldPosition() - from;
    away.Z = 0.0;
    away.W = 0.0;
    let dist = Vector4.Length(away);
    if dist > 12.0 {
      return;
    }
    let dir = dist > 0.2 ? away * (1.0 / dist) : mech.GetWorldForward() * -1.0;
    let k = ClampF(1.0 - dist / 12.0, 0.25, 1.0);
    let dv = dir * (4.5 * k) + new Vector4(0.0, 0.0, 1.2 * k, 0.0);
    this.m_body.Push(mech, dv, s.Now(), "a blast " + FloatToStringPrec(dist, 1) + " m away");
    s.rig.Nudge(MinF(30.0, 18.0 * k), -1.5 * k);
    CMCSession.Log("blast: " + FloatToStringPrec(dist, 1) + " m away, the body shoved at " + FloatToStringPrec(Vector4.Length(dv), 1) + " m/s");
  }

  // A part has just broken: on the model, in how the mech works, and on the HUD.
  private func BreakPart(s: ref<CMCSession>, mech: ref<NPCPuppet>, part: Int32) -> Void {
    if (part == CMPart.ArmL() || part == CMPart.ArmR()) && !this.m_parts.killed[part] {
      this.m_parts.killed[part] = true;
      CMCParts.BlowGun(mech, part == CMPart.ArmL());
    }
    this.ApplyParts(s, mech);
    this.m_partNote = CMPart.Name(part) + (part == CMPart.Sensor() ? " DESTROYED - OPTICS OFFLINE" : (part == CMPart.LegL() || part == CMPart.LegR() ? " CRIPPLED" : " DESTROYED"));
    this.m_partNoteUntil = s.Now() + 3.0;
    GameObject.PlaySoundEvent(mech, n"dev_alarm_02");
    CMCSession.Log("parts: " + CMPart.Name(part) + " broken");
  }

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
    st.missile = this.PartHp(CMPart.Pods()) <= 0.0 ? "MSL OFFLINE" : (wait > 0.0 ? "MSL RELOAD " + IntToString(CeilF(wait)) + "S" : "MSL READY");
    // part damage: the schematic, the sensor's rangefinder, and a part that just broke
    if ArraySize(st.parts) != CMPart.Count() {
      ArrayResize(st.parts, CMPart.Count());
    }
    let i = 0;
    while i < CMPart.Count() {
      st.parts[i] = i == CMPart.Torso() ? this.m_hull : this.PartHp(i);
      i += 1;
    }
    st.lostL = this.m_guns.left.destroyed;
    st.lostR = this.m_guns.right.destroyed;
    // hull critical (under 30%): smoke from every vent (the Minotaur's overheat effect)
    let crit = this.m_hull >= 0.0 && this.m_hull < 0.3;
    if NotEquals(crit, this.m_critFx) {
      this.m_critFx = crit;
      let mech = this.Mech();
      if IsDefined(mech) {
        if crit {
          GameObjectEffectHelper.StartEffectEvent(mech, n"hacks_overheat_lvl2");
        } else {
          GameObjectEffectHelper.StopEffectEvent(mech, n"hacks_overheat_lvl2");
        }
      }
    }
    let sensor = this.PartHp(CMPart.Sensor());
    if sensor <= 0.0 || (sensor < 0.5 && RandF() < (0.5 - sensor) * 1.4) {
      st.range = -1.0;   // the rangefinder drops out, always once the sensor is gone
    }
    if StrLen(this.m_partNote) > 0 && s.Now() < this.m_partNoteUntil {
      st.warning = this.m_partNote;
    } else if IsDefined(this.m_body) && this.m_body.led {
      st.warning = this.m_body.Gap() > 1.0 ? "AIRBORNE - BRACE" : "STAGGERED - STABILIZING";
    } else if !st.hasL && !st.hasR {
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
