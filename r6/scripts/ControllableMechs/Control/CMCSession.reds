// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: THE SESSION
//
// One controller for any unit (docs/TECHNICAL_DESIGN.md, sections 2-4):
//   Begin: the unit starts, V is locked (restrictions, save lock), the game's own
//          free camera entity is spawned and activated once it attaches, the HUD
//          goes up and the frame loop starts
//   each frame: the weighted rig moves the camera (sight or chase view, clipped),
//          the aim ray finds what the reticle is on, the unit ticks
//   ten times a second: exits, the unit's slow tick, the HUD
//   End: one teardown for every exit path (key, unit lost, V hit, V dead or in a
//          vehicle, session end). `hard` = no blends.
// Input: raw keys and mouse (Codeware Input/Key, Input/Axis, registered once and
// returning at once when idle) plus the game's own actions through V's OnAction
// (CMInput.reds), which are swallowed while controlling.
// Cost: nothing runs per frame unless a unit is controlled.
// This is the mod's pilot mode (it replaced the alpha's Pilot Mode, milestone M5).
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*
import TerminalKit.*

public abstract class CMCKey {
  public static func W() -> Int32 = 0
  public static func A() -> Int32 = 1
  public static func S() -> Int32 = 2
  public static func D() -> Int32 = 3
  public static func Lmb() -> Int32 = 4
  public static func Rmb() -> Int32 = 5
  public static func Mmb() -> Int32 = 6
  public static func Up() -> Int32 = 7      // Space: a drone climbs
  public static func Down() -> Int32 = 8    // Ctrl: a drone descends
  public static func Count() -> Int32 = 9
  public static func Name(i: Int32) -> String {
    switch i {
      case 0: return "W";
      case 1: return "A";
      case 2: return "S";
      case 3: return "D";
    }
    return "?";
  }
}

public class CMCSession extends ScriptableSystem {
  // 0 idle, 1 camera spawning, 2 controlling
  private let m_state: Int32;
  private let m_gen: Int32;
  private let m_unit: ref<CMCUnit>;

  // what units read
  public let rig: ref<CMPilotRig>;
  public let aim: Vector4;
  public let aimDist: Float;
  public let aimEntity: wref<Entity>;
  private let m_sigLost: ref<CMSignalLost>;   // a destroyed drone's SIGNAL LOST screen (a47)
  private let m_sigLostAt: Float;   // what the reticle's dynamic ray hit (none on world geometry)
  public let zoom: Bool;

  private let m_keys: array<Bool>;
  private let m_sensX: Float;
  private let m_sensY: Float;
  private let m_axisSeen: Int32;
  private let m_rawSeen: array<Bool>;   // per key: the raw channel has reported it

  private let m_camID: EntityID;
  private let m_cam: ref<CameraComponent>;
  private let m_camEntity: wref<Entity>;
  private let m_camBase: Vector4;       // where the camera entity is (the component moves inside it)
  private let m_camBased: Bool;
  private let m_camLocal0: Vector4;     // the component's own offset in the entity
  private let m_attachPending: Bool;
  private let m_clip: Float;
  private let m_lastFov: Float;

  private let m_hud: ref<CMPilotHud>;
  private let m_hudState: ref<CMPilotHudState>;

  private let m_lastTime: Float;
  private let m_slow: Float;
  private let m_frames: Int32;
  private let m_watchFrames: Int32;
  private let m_timerLoop: Bool;

  private let m_restricted: Bool;
  private let m_hidV: Bool;
  private let m_saveLocked: Bool;
  private let m_vHealth: Float;
  private let m_lastExit: Float;

  // Settings. They live in the settings file (CMPilotSystem), not the save; these fields
  // are the session's copy, filled by Sync() once per game session.
  private let m_fireMode: Int32;   // CMFireMode
  private let m_chase: Bool;
  private let m_creditVOff: Bool;  // false = kills and aggro credit V (the default)
  private let m_hullX: Int32;      // hull multiplier while piloted, stored +1
  private let m_synced: Bool;
  // the chase camera, read once per pilot session (CONFIG can't change while piloting)
  private let m_chaseUp: Float;
  private let m_dtSmooth: Float;   // the frame step (see OnFrame)
  private let m_thermal: Int32;    // the sensor's thermal mode (CMThermal), 0 = off
  private let m_clockReal: Float;
  private let m_clockUsed: Float;
  private let m_chaseDist: Float;
  private let m_chaseSide: Float;
  private let m_opticsHeld: Bool;   // the optics key as last seen (with the sensor out, it no longer follows zoom)

  // the view's weight: moving a hulking piece of equipment (both views)
  private let LOOK_STIFFNESS: Float = 7.0;    // spring toward where the mouse points
  private let LOOK_DAMPING: Float = 5.0;      // just under critical (2*sqrt(7) = 5.3): a slow settle
  private let LOOK_YAW_RATE: Float = 24.0;    // deg/s top traverse
  private let LOOK_PITCH_RATE: Float = 16.0;  // deg/s top elevation
  private let LOOK_LEAD: Float = 25.0;        // how far the aim may run ahead of the view, degrees
  private let OPTICS_FOV: Float = 27.0;       // field of view through the optics (the view is 68)
  private let OPTICS_RATE: Float = 0.5;       // traverse rates and lead while zoomed, x
  private let STOMP: Float = 1.8;             // footfall thump, dip, roll and bob, x the rig's base

  public static func Get(game: GameInstance) -> ref<CMCSession> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMCSession") as CMCSession;
  }

  // TOOLS > LOG in the terminal always; the game log on disk only with diagnostics on
  public static func Log(text: String) -> Void {
    TKLog.Add("ControllableMechs", text);
    if CMPilotSystem.Get(GetGameInstance()).ShowDebug() {
      let line = "CM " + text;
      ModLog(n"ControllableMechs", line);
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  private func OnAttach() -> Void {
    let cbs = GameInstance.GetCallbackSystem();
    cbs.RegisterCallback(n"Session/BeforeEnd", this, n"OnSessionEnd").SetLifetime(CallbackLifetime.Forever);
  }

  // The raw keyboard and mouse callbacks exist only while piloting: registered on entering,
  // removed on leaving, so outside a session no key press or mouse move reaches this mod.
  private let m_inputOn: Bool;

  private func ListenInput(on: Bool) -> Void {
    if Equals(on, this.m_inputOn) {
      return;
    }
    this.m_inputOn = on;
    let cbs = GameInstance.GetCallbackSystem();
    if on {
      cbs.RegisterCallback(n"Input/Key", this, n"OnKey");
      cbs.RegisterCallback(n"Input/Axis", this, n"OnAxis")
        .AddTarget(InputTarget.Axis(EInputKey.IK_MouseX))
        .AddTarget(InputTarget.Axis(EInputKey.IK_MouseY));
    } else {
      cbs.UnregisterCallback(n"Input/Key", this, n"OnKey");
      cbs.UnregisterCallback(n"Input/Axis", this, n"OnAxis");
    }
  }

  private func OnDetach() -> Void {
    this.End("", true);
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.End("", true);
  }

  protected cb func OnSessionEnd(event: ref<GameSessionEvent>) -> Void {
    this.End("", true);
  }

  private func Sync() -> Void {
    if this.m_synced {
      return;
    }
    this.m_synced = true;
    let cfg = CMPilotSystem.Get(this.GetGameInstance());
    this.m_fireMode = Clamp(cfg.Int("fireMode", CMFireMode.Stagger()), 0, 2);
    this.m_chase = cfg.Flag("chaseView", false);
    this.m_creditVOff = !cfg.Flag("creditV", true);
    this.m_hullX = Clamp(cfg.Int("hullMult", 10), 1, 50) + 1;
  }

  public func IsActive() -> Bool = this.m_state != 0
  public func FireMode() -> Int32 {
    this.Sync();
    return this.m_fireMode;
  }
  public func SetFireMode(mode: Int32) -> Void {
    this.Sync();
    this.m_fireMode = Clamp(mode, 0, 2);
    CMPilotSystem.Get(this.GetGameInstance()).PutInt("fireMode", this.m_fireMode);
  }
  // from the terminal (V does the same while piloting)
  public func SetChaseView(on: Bool) -> Void {
    this.SetChase(on);
  }

  // before the terminal closes to start piloting: "" = ready, else why not
  public func CanPilot() -> String {
    let link = CMLinkSystem.Get(this.GetGameInstance());
    let mech = link.Unit();
    if !link.IsLinked() || !IsDefined(mech) {
      return "!NO UNIT LINKED";
    }
    if NotEquals(mech.GetNPCType(), gamedataNPCType.Mech) && NotEquals(mech.GetNPCType(), gamedataNPCType.Drone) {
      return "!PILOTING NEEDS A MECH OR A DRONE";
    }
    if !ScriptedPuppet.IsAlive(mech) {
      return "!" + CMLinkSystem.KindName(mech) + " IS DESTROYED";
    }
    return "";
  }

  // the unit type for what is linked: a drone flies (CMUDrone), a mech walks (CMUMinotaur)
  private func NewUnit() -> ref<CMCUnit> {
    let unit = CMLinkSystem.Get(this.GetGameInstance()).Unit();
    if IsDefined(unit) && Equals(unit.GetNPCType(), gamedataNPCType.Drone) {
      return new CMUDrone();
    }
    return new CMUMinotaur();
  }
  // how much tougher the mech is while piloted: x its health, 10 by default (stored +1)
  public func HullMult() -> Float {
    this.Sync();
    return this.m_hullX > 0 ? Cast<Float>(this.m_hullX - 1) : 10.0;
  }
  public func SetHullMult(x: Int32) -> Void {
    this.Sync();
    this.m_hullX = Clamp(x, 1, 50) + 1;
    CMPilotSystem.Get(this.GetGameInstance()).PutInt("hullMult", this.m_hullX - 1);
    CMCSession.Log("hull multiplier x" + IntToString(x) + " (applies on the next link)");
  }
  public func CreditV() -> Bool {
    this.Sync();
    return !this.m_creditVOff;
  }
  public func SetCreditV(on: Bool) -> Void {
    this.Sync();
    this.m_creditVOff = !on;
    CMPilotSystem.Get(this.GetGameInstance()).PutFlag("creditV", on);
    CMCSession.Log("credit to V " + (on ? "ON" : "off"));
  }
  public func IsChase() -> Bool {
    this.Sync();
    return this.m_chase;
  }

  // ---------------------------------------------------------------------------
  // The Pilot key
  // ---------------------------------------------------------------------------
  public func Toggle() -> Void {
    if this.m_state != 0 {
      this.End("NEURAL LINK CLOSED", false);
      return;
    }
    // the raw key and the Input Loader action can both fire for one press
    if this.Now() - this.m_lastExit < 0.5 {
      return;
    }
    this.Warn(this.Begin(this.NewUnit(), false));
  }

  // from the terminal: let the popup close first
  public func RequestBegin(delay: Float) -> Void {
    let cb = new CMCBeginCb();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  public func BeginFromCallback() -> Void {
    if this.m_state == 0 {
      this.Warn(this.Begin(this.NewUnit(), true));
    }
  }

  // ---------------------------------------------------------------------------
  // Begin
  // ---------------------------------------------------------------------------
  public func Begin(unit: ref<CMCUnit>, fromTerminal: Bool) -> String {
    if this.m_state != 0 {
      return "";
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return "!NO OPERATOR";
    }
    let veh: wref<VehicleObject>;
    VehicleComponent.GetVehicle(game, player.GetEntityID(), veh);
    if IsDefined(veh) {
      return "!LEAVE THE VEHICLE FIRST";
    }
    if !fromTerminal && !TKPopup.CanOpen(player) {
      return "!NOT NOW";
    }
    this.m_gen += 1;
    this.rig = new CMPilotRig();
    this.m_unit = unit;
    let why = unit.Begin(this);
    if StrLen(why) > 0 {
      this.m_unit = null;
      this.rig = null;
      return why;
    }

    this.LoadChase();
    CMCSession.Log("chase camera (" + unit.CamProfile() + "): " + FloatToStringPrec(this.m_chaseDist, 2) + " m behind, " + FloatToStringPrec(this.m_chaseUp, 2) + " m up, " + FloatToStringPrec(this.m_chaseSide, 2) + " m to the side");
    this.rig.Init(unit.Ground(), this.CamUp(), this.CamFwd(), unit.Facing());
    this.Sync();
    this.rig.SetChase(this.m_chase);
    this.ApplyWeight();
    this.m_clip = 999.0;
    this.m_lastFov = 0.0;
    this.aim = this.rig.pos + this.rig.Forward() * 100.0;
    this.aimDist = 0.0;
    this.zoom = false;
    this.m_opticsHeld = false;
    ArrayClear(this.m_keys);
    ArrayResize(this.m_keys, CMCKey.Count());
    this.m_axisSeen = 0;
    ArrayClear(this.m_rawSeen);
    ArrayResize(this.m_rawSeen, CMCKey.Count());
    this.m_frames = 0;
    this.m_hudState = new CMPilotHudState();
    this.CacheSensitivity();

    this.Restrict(player, true);
    SaveLocksManager.RequestSaveLockAdd(game, n"ControllableMechs_Control");
    this.m_saveLocked = true;
    this.m_vHealth = this.PlayerHealth(player);

    // the game's own free camera entity; activated once it has attached
    let spec = new StaticEntitySpec();
    spec.templatePath = r"base\\entities\\cameras\\simple_free_camera.ent";
    spec.position = this.rig.pos;
    spec.orientation = CMCSession.Identity();
    spec.attached = true;
    this.m_camID = GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
    this.m_state = 1;
    if !EntityID.IsDefined(this.m_camID) {
      this.End("!CAMERA LINK FAILED", false);
      return "";
    }
    this.m_attachPending = true;
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Attached", this, n"OnCamAttached");
    this.ListenInput(true);
    let timeout = new CMCTimeoutCb();
    timeout.system = this;
    timeout.generation = this.m_gen;
    GameInstance.GetDelaySystem(game).DelayCallback(timeout, 3.0, false);
    CMCSession.Log("begin: " + unit.Name() + ", " + (this.m_chase ? "chase" : "sight") + " view, build " + CMVersion.Build());
    return "";
  }

  protected cb func OnCamAttached(event: ref<EntityLifecycleEvent>) -> Void {
    if !this.m_attachPending {
      return;
    }
    let entity = event.GetEntity();
    if !IsDefined(entity) || entity.GetEntityID() != this.m_camID {
      return;
    }
    this.m_attachPending = false;
    GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Attached", this, n"OnCamAttached");
    if this.m_state != 1 {
      return;
    }
    let cam = entity.FindComponentByName(n"camera") as CameraComponent;
    if !IsDefined(cam) {
      for c in entity.GetComponents() {
        if !IsDefined(cam) {
          cam = c as CameraComponent;
        }
      }
    }
    if !IsDefined(cam) {
      this.End("!CAMERA LINK FAILED", false);
      return;
    }
    this.m_camEntity = entity;
    this.m_cam = cam;
    // spawned at the rig's place: that is the base the component moves from
    this.m_camLocal0 = cam.GetLocalPosition();
    this.m_camLocal0.W = 0.0;
    this.m_camBase = entity.GetWorldPosition();
    this.m_camBased = true;
    this.ApplyCamera();
    cam.Activate(0.35, true);
    this.m_hud = this.m_unit.NewHud();
    this.m_hud.Build();
    this.m_hud.StartBoot();
    this.m_state = 2;
    let player = GetPlayer(this.GetGameInstance());
    if IsDefined(player) {
      player.m_cmcSession = this;   // the game's own actions now come to us
    }
    this.m_lastTime = this.Now();
    this.m_dtSmooth = 0.016;
    this.m_thermal = 0;
    this.m_clockReal = 0.0;
    this.m_clockUsed = 0.0;
    this.m_slow = 1.0;
    this.m_timerLoop = false;
    this.m_watchFrames = 0;
    this.ScheduleFrame();
    this.ScheduleWatchdog();
  }

  public func OnTimeout(generation: Int32) -> Void {
    if generation == this.m_gen && this.m_state == 1 {
      this.End("!CAMERA LINK TIMED OUT", false);
    }
  }

  // ---------------------------------------------------------------------------
  // End: the one teardown
  // ---------------------------------------------------------------------------
  public func End(reason: String, hard: Bool) -> Void {
    if this.m_state == 0 {
      return;
    }
    let game = this.GetGameInstance();
    this.m_gen += 1;   // stops the frame loop, the watchdog and any pending timeout
    this.m_state = 0;
    if this.m_thermal != 0 {
      CMThermal.Set(game, 0);   // the sensor's thermal mode goes with the link
      this.m_thermal = 0;
    }
    this.m_lastExit = this.Now();
    let player = GetPlayer(game);
    if IsDefined(player) {
      player.m_cmcSession = null;
    }
    CMCSession.Log("end (" + reason + ") after " + IntToString(this.m_frames) + " frames");
    this.ListenInput(false);
    if this.m_attachPending {
      this.m_attachPending = false;
      GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Attached", this, n"OnCamAttached");
    }
    if IsDefined(this.m_unit) {
      this.m_unit.End(this, hard);
    }
    this.m_unit = null;

    // the camera back to V
    let blend = hard ? 0.0 : 0.3;
    if IsDefined(this.m_cam) {
      this.m_cam.Deactivate(blend, true);
    }
    if IsDefined(player) {
      let fpp = player.GetFPPCameraComponent();
      if IsDefined(fpp) {
        fpp.Activate(blend, true);
        fpp.ResetPitch();
      }
    }
    this.m_cam = null;
    this.m_camEntity = null;
    this.m_camBased = false;
    if EntityID.IsDefined(this.m_camID) {
      if hard {
        GameInstance.GetStaticEntitySystem().DespawnEntity(this.m_camID);
      } else {
        let cb = new CMCDespawnCb();
        cb.id = this.m_camID;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, blend + 0.15, false);
      }
    }
    let empty: EntityID;
    this.m_camID = empty;

    if IsDefined(this.m_hud) {
      this.m_hud.Remove();
    }
    this.m_hud = null;
    if IsDefined(this.m_sigLost) {
      this.m_sigLost.Remove();
    }
    this.m_sigLost = null;
    if IsDefined(player) && this.m_restricted {
      this.Restrict(player, false);
    }
    this.m_restricted = false;
    if this.m_saveLocked {
      SaveLocksManager.RequestSaveLockRemove(game, n"ControllableMechs_Control");
      this.m_saveLocked = false;
    }
    this.rig = null;
    ArrayClear(this.m_keys);
    this.Warn(reason);
  }

  // ---------------------------------------------------------------------------
  // The frame loop (only while controlling)
  // ---------------------------------------------------------------------------
  private func ScheduleFrame() -> Void {
    let game = this.GetGameInstance();
    if this.m_timerLoop {
      let cb = new CMCFrameCb();
      cb.system = this;
      cb.generation = this.m_gen;
      GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.016, false);
      return;
    }
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return;
    }
    let evt = new CMCTickEvent();
    evt.generation = this.m_gen;
    GameInstance.GetDelaySystem(game).DelayEventNextFrame(player, evt);
  }

  private func ScheduleWatchdog() -> Void {
    let cb = new CMCWatchCb();
    cb.system = this;
    cb.generation = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.5, false);
  }

  public func OnWatchdog(generation: Int32) -> Void {
    if generation != this.m_gen || this.m_state != 2 {
      return;
    }
    if this.m_frames == this.m_watchFrames && !this.m_timerLoop {
      this.m_timerLoop = true;
      CMCSession.Log("no frames after 0.5 s, the loop moves to a timer");
      this.ScheduleFrame();
    }
    this.m_watchFrames = this.m_frames;
    this.ScheduleWatchdog();
  }

  public func OnFrame(generation: Int32) -> Void {
    if generation != this.m_gen || this.m_state != 2 {
      return;
    }
    this.m_frames += 1;
    let now = this.Now();
    let raw = ClampF(now - this.m_lastTime, 0.0, 0.1);
    this.m_lastTime = now;
    if raw <= 0.0 {
      raw = 0.016;
    }
    // The engine clock ticks in 1/128 s, so even frames read as 15.6 or 23.4 ms (a41 frame
    // log): stepped by those, everything moved unevenly from frame to frame. The step is the
    // frame time smoothed, plus a share of whatever the smoothed clock has fallen behind or
    // run ahead of the real one, so no time is lost or gained over a flight.
    this.m_dtSmooth += (raw - this.m_dtSmooth) * 0.15;
    this.m_clockReal += raw;
    let dt = ClampF(this.m_dtSmooth + (this.m_clockReal - this.m_clockUsed) * 0.1, 0.002, 0.1);
    this.m_clockUsed += dt;
    if !this.m_unit.IsAlive() {
      // a drone's feed dies on screen first (Omar): SIGNAL LOST for a moment, the view held
      // where it was, then back to V
      if this.m_unit.SignalLost() {
        if !IsDefined(this.m_sigLost) {
          this.m_sigLostAt = now;
          if IsDefined(this.m_hud) {
            this.m_hud.Remove();
          }
          this.m_hud = null;
          this.m_sigLost = CMSignalLost.Show(this.m_unit.Name());
          let pl = GetPlayer(this.GetGameInstance());
          if IsDefined(pl) {
            GameObject.PlaySoundEvent(pl, n"ui_hacking_access_denied");
          }
          CMCSession.Log("signal lost: " + this.m_unit.Name());
        }
        this.m_sigLost.Tick(dt);
        if now - this.m_sigLostAt < CMSignalLost.SignalLostTime() {
          this.ScheduleFrame();
          return;
        }
      }
      this.End(this.m_unit.LostReason(), false);
      return;
    }
    let optics = this.m_fireMode == CMFireMode.Split() ? this.Key(CMCKey.Mmb()) : this.Key(CMCKey.Rmb());
    if NotEquals(optics, this.m_opticsHeld) {
      this.m_opticsHeld = optics;
      this.SetOptics(optics);
    }
    // A drone moves first and the camera frames where it now is. With the camera first, it
    // had to guess where the drone would be (a frame of its velocity at the last frame's
    // length); the frame lengths differ, so at speed the drawn drone landed a few
    // centimetres off the guess every frame: the third-person jitter.
    let first = this.m_unit.TickFirst();
    if first {
      this.m_unit.Tick(this, dt, now);
      if this.m_state != 2 || !IsDefined(this.m_unit) {
        return;
      }
    }
    this.rig.Update(dt, this.m_unit.Ground(), this.CamUp(), this.CamFwd(), this.zoom);
    if this.ChaseNow() {
      // over one shoulder, so the hull never covers the reticle (CONFIG > CHASE CAMERA)
      this.rig.pos += CMPilotRig.Dir(this.rig.yaw - 90.0, 0.0) * this.m_chaseSide;
    }
    this.ClipCamera(dt);
    this.ApplyCamera();
    this.m_unit.FrameLog(this, dt);
    if IsDefined(this.m_hud) {
      this.m_hud.SetAttitude(CMPilotRig.Wrap(-this.rig.yaw), this.rig.pitch);
      this.m_hud.Boot(dt);
      this.m_hud.Tags(dt);
    }
    this.UpdateAim();
    if !first {
      this.m_unit.Tick(this, dt, now);
    }

    this.m_slow += dt;
    if this.m_slow >= 0.1 {
      this.m_slow = 0.0;
      if !this.SlowTick(now) {
        return;
      }
    }
    this.ScheduleFrame();
  }

  // The chase camera of this unit's profile (the mech's, or its drone type's), read again
  // ten times a second: it was read once at link-in, so CONFIG changes made while flying
  // (or from the terminal) never showed (Omar: the Wyvern and Griffin camera settings
  // didn't apply)
  private func LoadChase() -> Void {
    if !IsDefined(this.m_unit) {
      return;
    }
    let cfg = CMPilotSystem.Get(this.GetGameInstance());
    let prof = this.m_unit.CamProfile();
    this.m_chaseUp = Cast<Float>(cfg.ChaseUpCm(prof)) / 100.0;
    this.m_chaseDist = Cast<Float>(cfg.ChaseDistCm(prof)) / 100.0;
    this.m_chaseSide = Equals(prof, "mech") ? cfg.ChaseSide() : Cast<Float>(cfg.ChaseSideCm(prof)) / 100.0 * (cfg.ShoulderLeft(prof) ? -1.0 : 1.0);
  }

  private func SlowTick(now: Float) -> Bool {
    this.LoadChase();
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      this.End("", false);
      return false;
    }
    if player.IsDead() {
      this.End("!OPERATOR DOWN", false);
      return false;
    }
    let hp = this.PlayerHealth(player);
    if hp < this.m_vHealth - 0.01 && !CMPilotSystem.Get(game).StayWhenHit() {
      this.End("!OPERATOR UNDER ATTACK - LINK DROPPED", false);
      return false;
    }
    this.m_vHealth = hp;
    let why = this.m_unit.SlowTick(this, now);
    if StrLen(why) > 0 {
      this.End(why, false);
      return false;
    }
    this.RefreshHud();
    return true;
  }

  private func RefreshHud() -> Void {
    if !IsDefined(this.m_hud) {
      return;
    }
    let s = this.m_hudState;
    s.title = this.m_unit.Name();
    let h = RoundF(CMPilotRig.Wrap(-this.rig.yaw));
    s.heading = h < 0 ? h + 360 : h;
    s.range = this.aimDist;
    s.zoomed = this.zoom;
    s.speed = this.rig.speed;
    s.fireMode = this.m_fireMode;
    s.warning = "";
    s.sensor = CMThermal.Name(this.m_thermal);
    this.m_unit.Hud(this, s);
    this.m_hud.Refresh(s);
  }

  // the unit's sensor was shot out: out of the optics if it was in them
  public func OpticsLost() -> Void {
    if this.zoom {
      this.SetOptics(false);
    }
  }

  // a hit the unit took (the hit-to-threat hook, after the damage pipeline): its parts
  public func UnitHit(hit: ref<gameHitEvent>) -> Void {
    if this.m_state == 2 && IsDefined(this.m_unit) {
      this.m_unit.TakeHit(this, hit);
    }
  }

  // CONFIG > DIAGNOSTICS > RESTORE PARTS: the unit takes its parts' state again
  public func PartsRestored() -> Void {
    if this.m_state == 2 && IsDefined(this.m_unit) {
      this.m_unit.TakeHit(this, null);
    }
  }

  // a hit on the unit from a shooter at `from`: the HUD's direction marker, placed by where
  // the shooter stands relative to the view
  public func HitFrom(from: Vector4) -> Void {
    if this.m_state != 2 || !IsDefined(this.m_hud) || !IsDefined(this.rig) || !IsDefined(this.m_unit) {
      return;
    }
    this.m_hud.HitFrom(CMPilotRig.Wrap(CMPilotRig.YawOf(from - this.m_unit.Ground()) - this.rig.yaw));
  }

  // the unit's barrel markers and muzzle flashes, drawn every frame
  public func Hud() -> ref<CMPilotHud> = this.m_hud

  // a key was used: its tag on the HUD lights for a moment
  public func FlashTag(tag: Int32) -> Void {
    if IsDefined(this.m_hud) {
      this.m_hud.TagFlash(tag);
    }
  }

  // a round of ours connected (the damage pipeline hook): the hit marker, and a small
  // jolt through the frame, bigger on a kill
  public func RoundHit(kill: Bool) -> Void {
    if this.m_state != 2 {
      return;
    }
    if IsDefined(this.m_hud) {
      this.m_hud.Hit(kill);
    }
    if kill && IsDefined(this.rig) {
      this.rig.Recoil(0.3);
    }
  }

  // ---------------------------------------------------------------------------
  // Camera and aim
  // ---------------------------------------------------------------------------
  private func CamUp() -> Float = this.ChaseNow() ? this.m_chaseUp : this.m_unit.SensorUp()
  private func CamFwd() -> Float = this.ChaseNow() ? -this.m_chaseDist : this.m_unit.SensorFwd()

  // the optics always look from the sensor: the chase view steps in while they're held
  private func ChaseNow() -> Bool = this.m_chase && !this.zoom
  // the sight view (first person) is on: not the chase view, or the optics zoomed in
  public func SightView() -> Bool = !this.ChaseNow()

  // optics on or off (held RMB, or MMB in split fire mode): tight field of view, slower
  // traverse, the sight view even from the chase view, and the optics frame on the HUD
  private func SetOptics(on: Bool) -> Void {
    if on && IsDefined(this.m_unit) && !this.m_unit.OpticsOnline() {
      GameObject.PlaySoundEvent(GetPlayer(this.GetGameInstance()), n"ui_hacking_press_fail");   // the sensor is shot out
      return;
    }
    this.zoom = on;
    this.m_clip = 999.0;
    this.rig.SetChase(this.ChaseNow());
    this.ApplyWeight();
    if IsDefined(this.m_hud) {
      this.m_hud.SetOptics(on);
      if on {
        this.m_hud.TagFlash(CMPilotHud.TagZoom());
      }
    }
  }

  private func SetChase(on: Bool) -> Void {
    this.Sync();
    this.m_chase = on;
    CMPilotSystem.Get(this.GetGameInstance()).PutFlag("chaseView", on);
    this.m_clip = 999.0;
    if IsDefined(this.rig) {
      this.rig.SetChase(this.ChaseNow());
      this.ApplyWeight();   // SetChase resets the damping
    }
  }

  private func ApplyWeight() -> Void {
    let k = this.zoom ? this.OPTICS_RATE : 1.0;
    // CONFIG > CHASSIS > TURN SPEED scales the traverse (and the unit scales its chassis turn)
    let t = Cast<Float>(CMPilotSystem.Get(this.GetGameInstance()).TurnPct()) / 100.0;
    if IsDefined(this.m_unit) && this.m_unit.LightLook() {
      // a drone's sensor gimbal: a stiff, critically damped spring (settled in about 0.1 s)
      // and no lead limit, so the view stays on the mouse. The turret's 42 deg/s cap had the
      // first-person view trailing the mouse (Omar, Phase 4: "camera lagging behind").
      this.rig.SetWeight(900.0, 60.0, 720.0 * k, 720.0 * k, 0.0);
    } else {
      this.rig.SetWeight(this.LOOK_STIFFNESS * t, this.LOOK_DAMPING * SqrtF(t), this.LOOK_YAW_RATE * k * t, this.LOOK_PITCH_RATE * k * t, this.LOOK_LEAD * k);
    }
    this.rig.SetZoomFov(this.OPTICS_FOV);
    this.rig.SetStepWeight(this.STOMP * (IsDefined(this.m_unit) ? this.m_unit.StepWeight() : 1.0));
    this.rig.SetStride(!IsDefined(this.m_unit) || this.m_unit.StepWeight() > 0.0);
    this.rig.SetRecoilScale(Cast<Float>(CMPilotSystem.Get(this.GetGameInstance()).RecoilPct()) / 100.0);
  }

  private func ApplyCamera() -> Void {
    if !IsDefined(this.m_camEntity) || !IsDefined(this.m_cam) {
      return;
    }
    // The camera entity stays where it was spawned and the camera component moves inside
    // it. Moved by its entity's transform each frame, the engine drew the camera two frames
    // after it was set, while a drone (an NPC) is drawn one frame after: a21's frame log had
    // the engine's camera 0.47-0.71 m behind where it was put at 19 m/s, so the first-person
    // view trailed the drone by a frame (Omar, Phase 4). The entity is only moved again
    // if the camera gets 2 km from it (the uplink reaches 500 m).
    let off = this.rig.pos - this.m_camBase;
    if !this.m_camBased || Vector4.Length(off) > 2000.0 {
      let world: WorldPosition;
      WorldPosition.SetVector4(world, this.rig.pos);
      let wt: WorldTransform;
      WorldTransform.SetWorldPosition(wt, world);
      WorldTransform.SetOrientation(wt, CMCSession.Identity());
      this.m_camEntity.SetWorldTransform(wt);   // the entity stays unrotated,
      this.m_camBase = this.rig.pos;
      this.m_camBased = true;
      off = new Vector4(0.0, 0.0, 0.0, 0.0);
    }
    off.W = 0.0;
    this.m_cam.SetLocalPosition(this.m_camLocal0 + off);
    let e: EulerAngles;                       // the component carries the view
    e.Yaw = this.rig.yaw + this.rig.kickYaw;       // recoil shakes the picture,
    e.Pitch = this.rig.pitch + this.rig.kickPitch;   // not the aim
    e.Roll = this.rig.roll;
    // a drone's tilt, which the game won't show on its body: all of it through its own
    // sensor, a third of it from the chase camera
    if IsDefined(this.m_unit) {
      let tilt = this.m_unit.CamTilt();
      let k = this.ChaseNow() ? 0.35 : 1.0;
      e.Pitch += tilt.X * k;
      e.Roll += tilt.Y * k;
    }
    this.m_cam.SetLocalOrientation(EulerAngles.ToQuat(e));
    if AbsF(this.rig.fov - this.m_lastFov) > 0.05 {
      this.m_lastFov = this.rig.fov;
      this.m_cam.SetFOV(this.rig.fov);
    }
  }

  // one static ray from the unit's centre at camera height out to the camera: on a hit the
  // camera snaps in short of it, and eases back out at 6 m/s once the way is clear
  private func ClipCamera(dt: Float) -> Void {
    let g = this.m_unit.Ground();
    let pivot = new Vector4(g.X, g.Y, g.Z + this.CamUp(), 1.0);
    let want = this.rig.pos;
    let off = want - pivot;
    let full = Vector4.Length(off);
    if full < 0.3 {
      return;
    }
    let dir = off * (1.0 / full);
    let allowed = full;
    let hit: TraceResult;
    if GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(pivot, want + dir * 0.35, n"Static", hit, true, false) {
      allowed = MaxF(0.2, Vector4.Distance(pivot, Cast<Vector4>(hit.position)) - 0.35);
    }
    if allowed < this.m_clip {
      this.m_clip = allowed;
    } else {
      this.m_clip = MinF(allowed, this.m_clip + 6.0 * dt);
    }
    if this.m_clip < full {
      this.rig.pos = pivot + dir * this.m_clip;
    }
  }

  // what the reticle is on: the nearest hit on world geometry (from the camera) or on
  // anything dynamic (from past the unit, so it can't aim at itself), else far away
  private func UpdateAim() -> Void {
    let fwd = this.rig.Forward();
    let to = this.rig.pos + fwd * 600.0;
    let skip = MaxF(this.m_unit.AimSkip(), Vector4.Dot(this.m_unit.Ground() - this.rig.pos, fwd) + 3.0);
    let sq = GameInstance.GetSpatialQueriesSystem(this.GetGameInstance());
    let best = 0.0;
    this.aimEntity = null;
    let hit: TraceResult;
    if CMGround.World(this.GetGameInstance(), this.rig.pos + fwd * 0.3, to, hit) {
      this.aim = Cast<Vector4>(hit.position);
      best = Vector4.Distance(this.rig.pos, this.aim);
    }
    let dyn: TraceResult;
    if CMGround.Movers(this.GetGameInstance(), this.rig.pos + fwd * skip, to, dyn) {
      let p = Cast<Vector4>(dyn.position);
      let d = Vector4.Distance(this.rig.pos, p);
      if best <= 0.0 || d < best {
        this.aim = p;
        best = d;
        this.aimEntity = TraceResult.GetHitEntity(dyn);
      }
    }
    if best <= 0.0 {
      this.aim = to;
    }
    this.aimDist = best;
  }

  // a world point as a HUD offset from the screen centre (4K units): tan(angle) / tan(fov/2)
  public func PipOffset(p: Vector4) -> Vector2 {
    let scale = 1080.0 / TanF(Deg2Rad(this.rig.fov * 0.5));
    let d = p - this.rig.pos;
    let flat = SqrtF(d.X * d.X + d.Y * d.Y);
    let yawOff = CMPilotRig.Wrap(CMPilotRig.YawOf(d) - this.rig.yaw);
    let pitchOff = Rad2Deg(AtanF(d.Z, flat)) - this.rig.pitch;
    if AbsF(yawOff) > 80.0 {
      return Vector2(9999.0, 9999.0);
    }
    return Vector2(-TanF(Deg2Rad(yawOff)) * scale, -TanF(Deg2Rad(pitchOff)) * scale);
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------
  public func Key(i: Int32) -> Bool {
    return i >= 0 && i < ArraySize(this.m_keys) && this.m_keys[i];
  }

  // A key the raw channel has reported is its alone from then on: the game's attack
  // action sends release-like events mid-hold, which chopped the fire into bursts. Keys
  // the raw channel never reports still come from the game's actions.
  private func RawKey(i: Int32, down: Bool) -> Void {
    if i >= 0 && i < ArraySize(this.m_rawSeen) {
      this.m_rawSeen[i] = true;
    }
    this.SetKey(i, down);
  }

  private func ActionKey(i: Int32, down: Bool, from: String) -> Void {
    if i >= 0 && i < ArraySize(this.m_rawSeen) && this.m_rawSeen[i] {
      return;
    }
    this.SetKey(i, down, from);
  }

  // `from`: which channel set it, for the log (a key changing state is logged, so a
  // stuck key shows up)
  private func SetKey(i: Int32, down: Bool, opt from: String) -> Void {
    if i >= 0 && i < ArraySize(this.m_keys) {
      if NotEquals(this.m_keys[i], down) && i <= CMCKey.D() {
        CMCSession.Log("key " + CMCKey.Name(i) + (down ? " down" : " up") + " (" + (StrLen(from) > 0 ? from : "raw") + ")");
      }
      this.m_keys[i] = down;
    }
  }

  public func OnGameAction(name: CName, type: gameinputActionType, value: Float) -> Bool {
    if this.m_state != 2 {
      return false;
    }
    // held only while the value says so: an axis-type event that isn't a button release
    // (value 0) used to count as held, and left the mech walking on its own
    let down = !Equals(type, gameinputActionType.BUTTON_RELEASED) && AbsF(value) > 0.1;
    // once raw keys arrive they're the truth: the attack action sends release-like events
    // mid-hold, which chopped the fire into bursts; its events are then only swallowed
    switch name {
      case n"Forward": this.ActionKey(CMCKey.W(), down, "Forward"); break;
      case n"Back": this.ActionKey(CMCKey.S(), down, "Back"); break;
      case n"Left": this.ActionKey(CMCKey.A(), down, "Left"); break;
      case n"Right": this.ActionKey(CMCKey.D(), down, "Right"); break;
      case n"RangedAttack":
      case n"ShootPrimary":
        this.ActionKey(CMCKey.Lmb(), down, "attack");
        break;
      case n"CameraAim":
        this.ActionKey(CMCKey.Rmb(), down, "aim");
        break;
      case n"CameraMouseX":
        if this.m_axisSeen == 0 && IsDefined(this.rig) {
          this.rig.Look(-value / 45.0 * (this.zoom ? 0.5 : 1.0), 0.0);
        }
        break;
      case n"CameraMouseY":
        if this.m_axisSeen == 0 && IsDefined(this.rig) {
          this.rig.Look(0.0, value / 45.0 * (this.zoom ? 0.5 : 1.0));
        }
        break;
      // V's own actions: swallowed while controlling
      case n"ToggleSprint":
      case n"Sprint":
      case n"Jump":
      case n"ToggleCrouch":
      case n"Crouch":
      case n"Dodge":
      case n"DodgeForward":
      case n"DodgeBackward":
      case n"DodgeLeft":
      case n"DodgeRight":
      case n"Reload":
      case n"SwitchItem":
      case n"SelectWeapon":
      case n"NextWeapon":
      case n"PreviousWeapon":
      case n"QuickMelee":
      case n"UseConsumable":
      case n"UseCombatGadget":
      case n"MeleeAttack":
      case n"Choice1":
        break;
      default:
        return false;
    }
    return true;
  }

  protected cb func OnKey(event: ref<KeyInputEvent>) -> Void {
    if this.m_state != 2 {
      return;
    }
    let action = event.GetAction();
    if Equals(action, EInputAction.IACT_Axis) {
      return;
    }
    let down = !Equals(action, EInputAction.IACT_Release);
    let press = Equals(action, EInputAction.IACT_Press);
    // the unit's hold mode (a drone's gunship hold): H by default, rebindable in Mod
    // Settings (Omar: H is the game's quick-access menu key)
    if Equals(event.GetKey(), CMKeys.Gunship(GetPlayer(this.GetGameInstance()))) {
      if press && IsDefined(this.m_unit) {
        this.m_unit.Hold(this);
        this.m_slow = 1.0;
      }
      return;
    }
    switch event.GetKey() {
      case EInputKey.IK_W: this.RawKey(CMCKey.W(), down); break;
      case EInputKey.IK_A: this.RawKey(CMCKey.A(), down); break;
      case EInputKey.IK_S: this.RawKey(CMCKey.S(), down); break;
      case EInputKey.IK_D: this.RawKey(CMCKey.D(), down); break;
      case EInputKey.IK_LeftMouse: this.RawKey(CMCKey.Lmb(), down); break;
      case EInputKey.IK_RightMouse: this.RawKey(CMCKey.Rmb(), down); break;
      case EInputKey.IK_MiddleMouse: this.RawKey(CMCKey.Mmb(), down); break;
      case EInputKey.IK_Space: this.RawKey(CMCKey.Up(), down); break;
      case EInputKey.IK_LControl: this.RawKey(CMCKey.Down(), down); break;
      case EInputKey.IK_T:
        // the sensor's thermal modes (CMThermal): off, WHT, THERMAL, RED HOT
        if press {
          this.m_thermal = (this.m_thermal + 1) % CMThermal.Count();
          if !CMThermal.Set(this.GetGameInstance(), this.m_thermal) {
            this.m_thermal = 0;
          }
          CMCSession.Log("sensor: " + CMThermal.Name(this.m_thermal));
        }
        break;
      case EInputKey.IK_V:
        if press {
          this.SetChase(!this.m_chase);
          this.m_slow = 1.0;
          this.FlashTag(CMPilotHud.TagView());
        }
        break;
      case EInputKey.IK_G:
        // the grenade key: the unit's secondary weapon
        if press && IsDefined(this.m_unit) {
          this.m_unit.Secondary(this);
          this.m_slow = 1.0;
          this.FlashTag(CMPilotHud.TagMissile());
        }
        break;
      case EInputKey.IK_B:
        if press {
          if !IsDefined(this.m_unit) || !this.m_unit.Select(this) {
            this.SetFireMode(CMFireMode.Next(this.m_fireMode));
          }
          this.m_slow = 1.0;
          this.FlashTag(CMPilotHud.TagMode());
        }
        break;
      case EInputKey.IK_Backslash:
        // failsafe: \ always disconnects, even if the Input Loader action is blocked
        if press {
          this.End("NEURAL LINK CLOSED", false);
        }
        break;
      default:
        break;
    }
  }

  protected cb func OnAxis(event: ref<AxisInputEvent>) -> Void {
    if this.m_state != 2 || !IsDefined(this.rig) {
      return;
    }
    this.m_axisSeen += 1;
    let v = event.GetValue();
    let k = this.zoom ? 0.5 : 1.0;
    if Equals(event.GetKey(), EInputKey.IK_MouseX) {
      this.rig.Look(-v * this.m_sensX * k, 0.0);
    } else {
      this.rig.Look(0.0, -v * this.m_sensY * k);
    }
  }

  // the game's own mouse sensitivity, times ours (SETTINGS > MOUSE SENSITIVITY)
  private func CacheSensitivity() -> Void {
    this.m_sensX = 0.15;
    this.m_sensY = 0.15;
    let settings = GameInstance.GetSettingsSystem(this.GetGameInstance());
    let x = settings.GetVar(n"/controls/fppcameramouse", n"FPP_MouseX") as ConfigVarFloat;
    let y = settings.GetVar(n"/controls/fppcameramouse", n"FPP_MouseY") as ConfigVarFloat;
    if IsDefined(x) && x.GetValue() > 0.0 {
      this.m_sensX = x.GetValue() / 100.0;
    }
    if IsDefined(y) && y.GetValue() > 0.0 {
      this.m_sensY = y.GetValue() / 100.0;
    }
    let k = Cast<Float>(CMPilotSystem.Get(this.GetGameInstance()).SensPct()) / 100.0;
    this.m_sensX *= k;
    this.m_sensY *= k;
  }

  // ---------------------------------------------------------------------------
  // V while controlling: locked in place, no weapons, nothing that fights the camera
  // ---------------------------------------------------------------------------
  private func Restrict(player: ref<PlayerPuppet>, on: Bool) -> Void {
    let ss = GameInstance.GetStatusEffectSystem(this.GetGameInstance());
    let pid = player.GetEntityID();
    let rid = player.GetRecordID();
    let list: array<TweakDBID> = [
      t"GameplayRestriction.NoMovement",
      t"GameplayRestriction.NoCombat",
      t"GameplayRestriction.NoZooming",
      t"GameplayRestriction.NoPhone",
      t"GameplayRestriction.NoWorldInteractions",
      t"GameplayRestriction.NoQuickHacks",
      t"GameplayRestriction.NoScanning",
      t"GameplayRestriction.NoJump",
      t"GameplayRestriction.NoRadialMenus",
      t"GameplayRestriction.NoCameraControl",
      t"GameplayRestriction.NoCyberware",
      t"GameplayRestriction.NoPhotoMode",
      t"GameplayRestriction.VehicleNoSummoning"
    ];
    for id in list {
      if on {
        ss.ApplyStatusEffect(pid, id, rid, pid);
      } else {
        ss.RemoveStatusEffect(pid, id);
      }
    }
    this.m_restricted = on;
    // CONFIG > OPERATOR > HIDE V WHILE LINKED (off by default): the game's own switch
    // that takes V out of what enemy senses can pick up; put back on leaving
    if on {
      if CMPilotSystem.Get(this.GetGameInstance()).HideOperator() && !player.IsInvisible() {
        player.SetInvisible(true);
        this.m_hidV = true;
        CMCSession.Log("operator hidden from enemy senses while linked");
      }
    } else {
      if this.m_hidV {
        player.SetInvisible(false);
        this.m_hidV = false;
        CMCSession.Log("operator visible to enemy senses again");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  private func PlayerHealth(player: ref<PlayerPuppet>) -> Float {
    return GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, false);
  }

  public func Now() -> Float = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()))

  // a default Quaternion is all zeros, not identity
  public static func Identity() -> Quaternion {
    let e: EulerAngles;
    return EulerAngles.ToQuat(e);
  }

  // the angle between a gun's barrel and the direction from it to a point, degrees
  public static func AimError(weapon: ref<GameObject>, at: Vector4) -> Float {
    if !IsDefined(weapon) {
      return -1.0;
    }
    let to = Vector4.Normalize(at - weapon.GetWorldPosition());
    let fwd = Vector4.Normalize(weapon.GetWorldForward());
    return Rad2Deg(AcosF(ClampF(Vector4.Dot(to, fwd), -1.0, 1.0)));
  }

  private func Warn(msg: String) -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if IsDefined(player) && StrLen(msg) > 0 {
      player.SetWarningMessage(CMLinkSystem.Plain(msg));
    }
  }
}

// ---- the per-frame tick: an event V receives next frame (only queued while controlling) ----
public class CMCTickEvent extends Event {
  public let generation: Int32;
}

@addField(PlayerPuppet)
public let m_cmcSession: wref<CMCSession>;

@addMethod(PlayerPuppet)
protected cb func OnCMCTick(evt: ref<CMCTickEvent>) -> Bool {
  if IsDefined(this.m_cmcSession) {
    this.m_cmcSession.OnFrame(evt.generation);
  }
  return true;
}

// ---- callbacks (weak back-references; a stale generation does nothing) ----
public class CMCFrameCb extends DelayCallback {
  public let system: wref<CMCSession>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnFrame(this.generation);
    }
  }
}

public class CMCWatchCb extends DelayCallback {
  public let system: wref<CMCSession>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnWatchdog(this.generation);
    }
  }
}

public class CMCTimeoutCb extends DelayCallback {
  public let system: wref<CMCSession>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnTimeout(this.generation);
    }
  }
}

public class CMCBeginCb extends DelayCallback {
  public let system: wref<CMCSession>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.BeginFromCallback();
    }
  }
}

public class CMCDespawnCb extends DelayCallback {
  public let id: EntityID;
  public func Call() -> Void {
    GameInstance.GetStaticEntitySystem().DespawnEntity(this.id);
  }
}
