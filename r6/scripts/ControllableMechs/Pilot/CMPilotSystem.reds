// =============================================================================
// CONTROLLABLE MECHS - PILOT MODE (direct control of the linked mech)
//
// Enter: spawns the game's own free camera entity at the mech's sensor mount,
// switches the view to it, locks V in place with gameplay restrictions, fades the
// vanilla HUD and puts up the Militech overlay (CMPilotHud).
// While piloting:
//   - every frame: the weighted rig (CMPilotRig) moves the camera, the guns
//     (CMPilotGuns) fire while the triggers are held, barrel markers flash
//   - ten times a second: walk orders from WASD, body turns toward the aim,
//     HUD values, and the exit checks
// Exit (the Pilot key, or forced): mech lost or destroyed, out of signal range,
// V hit (optional), link closed, session end. Every exit path runs the same
// teardown: input callbacks, camera, HUD, restrictions and the save lock.
//
// Cost: nothing at all runs while not piloting. The raw input callbacks are
// registered on enter and removed on exit.
// =============================================================================
module ControllableMechs

import TerminalKit.*

public abstract class CMPilotKey {
  public static func W() -> Int32 = 0
  public static func A() -> Int32 = 1
  public static func S() -> Int32 = 2
  public static func D() -> Int32 = 3
  public static func Run() -> Int32 = 4
  public static func Lmb() -> Int32 = 5
  public static func Rmb() -> Int32 = 6
  public static func Mmb() -> Int32 = 7
  public static func Count() -> Int32 = 8
}

public class CMPilotSystem extends ScriptableSystem {
  // 0 off, 1 camera spawning, 2 piloting
  private let m_state: Int32;
  private let m_gen: Int32;

  private let m_mechID: EntityID;
  private let m_camID: EntityID;
  private let m_cam: ref<CameraComponent>;
  private let m_camEntity: wref<Entity>;
  private let m_attachPending: Bool;

  private let m_rig: ref<CMPilotRig>;
  private let m_guns: ref<CMPilotGuns>;
  private let m_hud: ref<CMPilotHud>;
  private let m_hudState: ref<CMPilotHudState>;

  private let m_keys: array<Bool>;
  private let m_zoom: Bool;
  private let m_sensX: Float;
  private let m_sensY: Float;

  private let m_lastTime: Float;
  private let m_slow: Float;
  private let m_lastFov: Float;
  private let m_aim: Vector4;
  private let m_aimDist: Float;

  private let m_moveCmd: ref<AICommand>;
  private let m_moving: Bool;
  private let m_moveDir: Vector4;
  private let m_moveTarget: Vector4;
  private let m_moveSent: Float;
  private let m_moveRun: Bool;
  private let m_moveYaw: Float;
  private let m_aligned: Bool;      // the body (and its guns) faces the reticle closely enough to fire
  private let m_unalignedHeld: Float;
  private let m_turnCmd: ref<AICommand>;
  private let m_turnSent: Float;

  // diagnostics: what actually arrives while piloting (HUD line + TerminalKit log)
  private let m_dbgFrames: Int32;
  private let m_dbgKeys: Int32;
  private let m_dbgAxis: Int32;
  private let m_dbgActions: Int32;
  private let m_dbgLast: String;
  private let m_dbgDt: Float;
  private let m_watchFrames: Int32;
  private let m_timerLoop: Bool;

  private let m_vHealth: Float;
  private let m_restricted: Bool;
  private let m_saveLocked: Bool;
  private let m_lastExit: Float;

  // settings, kept in the save
  private persistent let m_fireMode: Int32;
  private persistent let m_stayWhenHit: Bool;
  private persistent let m_themeIdx: Int32;   // 0 = militech (default), else 1 + index into TKTheme.Ids()
  // camera tuning from the terminal, stored +1 so 0 means "default"
  private persistent let m_camUpCm: Int32;
  private persistent let m_camFwdCm: Int32;
  private persistent let m_sensPct: Int32;
  private persistent let m_showDebug: Bool;
  private persistent let m_aimMode: Int32;      // 0 = along the barrels (default), 1 = to the reticle point
  private persistent let m_traverse: Int32;     // torso traverse deg/s, stored +1 (0 = default)
  private persistent let m_camMode: Int32;      // 0 = sensor view (default), 1 = third-person chase view
  private persistent let m_chaseDistCm: Int32;  // chase view: how far behind the mech's centre, stored +1
  private persistent let m_chaseUpCm: Int32;    // chase view: how high above its feet, stored +1

  // clipping: how far out from the mech's centre the camera may sit this frame
  private let m_clip: Float;

  // sound state: the servo loop plays while the view traverses
  private let m_servoOn: Bool;
  private let m_servoHit: Float;
  private let m_triggerWas: Bool;

  // where the sensor sits on the mech (forward, up; metres)
  // defaults for where the sensor sits on the mech (tunable in SETTINGS)
  private let MOUNT_UP_CM: Int32 = 230;
  private let MOUNT_FWD_CM: Int32 = 260;
  private let SPREAD_DEG: Float = 0.6;
  private let ALIGN_DEG: Float = 15.0;   // how far the reticle may be off the body's facing and still fire
  private let SIGNAL_RANGE: Float = 250.0;

  public static func Get(game: GameInstance) -> ref<CMPilotSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMPilotSystem") as CMPilotSystem;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  private func OnAttach() -> Void {
    let cbs = GameInstance.GetCallbackSystem();
    cbs.RegisterCallback(n"Session/BeforeEnd", this, n"OnSessionEnd").SetLifetime(CallbackLifetime.Forever);
    // raw input, registered once like XUtils does; both handlers return at once unless piloting
    cbs.RegisterCallback(n"Input/Key", this, n"OnKey").SetLifetime(CallbackLifetime.Forever);
    cbs.RegisterCallback(n"Input/Axis", this, n"OnAxis")
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseX))
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseY))
      .SetLifetime(CallbackLifetime.Forever);
  }

  private func OnDetach() -> Void {
    this.Exit("", true);
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    this.Exit("", true);
  }

  protected cb func OnSessionEnd(event: ref<GameSessionEvent>) -> Void {
    this.Exit("", true);
  }

  public func IsPiloting() -> Bool = this.m_state != 0
  public func FireMode() -> Int32 = this.m_fireMode
  public func StayWhenHit() -> Bool = this.m_stayWhenHit

  public func CycleFireMode() -> Void {
    this.m_fireMode = CMFireMode.Next(this.m_fireMode);
  }

  public func SetFireMode(mode: Int32) -> Void {
    this.m_fireMode = mode;
  }

  public func SetStayWhenHit(stay: Bool) -> Void {
    this.m_stayWhenHit = stay;
  }

  // the terminal's palette (a TerminalKit theme id), kept in the save
  public func Theme() -> String {
    let ids = TKTheme.Ids();
    let i = this.m_themeIdx - 1;
    if i >= 0 && i < ArraySize(ids) {
      return ids[i];
    }
    return "militech";
  }

  public func SetTheme(id: String) -> Void {
    let ids = TKTheme.Ids();
    let i = 0;
    while i < ArraySize(ids) {
      if Equals(ids[i], id) {
        this.m_themeIdx = i + 1;
        return;
      }
      i += 1;
    }
  }

  // The Pilot key: in if out, out if in
  public func Toggle() -> Void {
    if this.m_state != 0 {
      this.Exit("NEURAL LINK CLOSED", false);
      return;
    }
    // the raw key and the Input Loader action can both fire for one press
    if this.Now() - this.m_lastExit < 0.5 {
      return;
    }
    let msg = this.Enter();
    if StrLen(msg) > 0 {
      this.Warn(msg);
    }
  }

  // From the terminal: let the popup close first
  public func RequestEnter(delay: Float) -> Void {
    let cb = new CMPilotEnterCb();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  public func EnterFromCallback() -> Void {
    if this.m_state == 0 {
      let msg = this.Enter();
      if StrLen(msg) > 0 {
        this.Warn(msg);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Enter
  // ---------------------------------------------------------------------------
  // `fromTerminal`: the terminal itself is up (it closes before entering), so skip the menu check
  public func CanPilot(opt fromTerminal: Bool) -> String {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return "!NO OPERATOR";
    }
    let link = CMLinkSystem.Get(game);
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
    let veh: wref<VehicleObject>;
    VehicleComponent.GetVehicle(game, player.GetEntityID(), veh);
    if IsDefined(veh) {
      return "!LEAVE THE VEHICLE FIRST";
    }
    if !fromTerminal && !TKPopup.CanOpen(player) {
      return "!NOT NOW";
    }
    return "";
  }

  private func Enter() -> String {
    if this.m_state != 0 {
      return "";
    }
    let why = this.CanPilot();
    if StrLen(why) > 0 {
      return why;
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let link = CMLinkSystem.Get(game);
    let mech = link.Unit();

    this.m_gen += 1;
    this.m_mechID = mech.GetEntityID();
    link.Hold();
    link.SetOrder(CMOrder.Pilot());

    this.m_rig = new CMPilotRig();
    this.m_rig.Init(mech.GetWorldPosition(), this.CamUp(), this.CamFwd(), CMPilotRig.YawOf(mech.GetWorldForward()));
    this.m_clip = 999.0;
    this.m_guns = new CMPilotGuns();
    this.m_guns.Init(mech);
    this.m_guns.SetBarrelMode(this.m_aimMode == 0);
    this.m_rig.SetTraverse(Cast<Float>(this.Traverse()));
    this.m_servoOn = false;
    this.m_servoHit = 0.0;
    this.m_triggerWas = false;
    this.m_hudState = new CMPilotHudState();
    ArrayClear(this.m_keys);
    ArrayResize(this.m_keys, CMPilotKey.Count());
    this.m_dbgFrames = 0;
    this.m_dbgKeys = 0;
    this.m_dbgAxis = 0;
    this.m_dbgActions = 0;
    this.m_dbgLast = "";
    this.m_zoom = false;
    this.m_moving = false;
    this.m_moveCmd = null;
    this.m_turnCmd = null;
    this.m_lastFov = 0.0;
    this.m_aim = this.m_rig.pos + this.m_rig.Forward() * 100.0;
    this.m_aimDist = 0.0;
    this.CacheSensitivity();

    this.Restrict(player, true);
    SaveLocksManager.RequestSaveLockAdd(game, n"ControllableMechs_Pilot");
    this.m_saveLocked = true;
    this.m_vHealth = this.PlayerHealth(player);

    // the game's own free camera entity; activated once it has attached
    let spec = new StaticEntitySpec();
    spec.templatePath = r"base\\entities\\cameras\\simple_free_camera.ent";
    spec.position = this.m_rig.pos;
    spec.orientation = CMPilotSystem.Identity();
    spec.attached = true;
    this.m_camID = GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
    if !EntityID.IsDefined(this.m_camID) {
      this.Exit("!CAMERA LINK FAILED", false);
      return "";
    }
    this.m_attachPending = true;
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Attached", this, n"OnCamAttached");
    this.m_state = 1;

    // if the camera never attaches, back out cleanly
    let timeout = new CMPilotTimeoutCb();
    timeout.system = this;
    timeout.generation = this.m_gen;
    GameInstance.GetDelaySystem(game).DelayCallback(timeout, 3.0, false);
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
      let parts = entity.GetComponents();
      let i = 0;
      while i < ArraySize(parts) && !IsDefined(cam) {
        cam = parts[i] as CameraComponent;
        i += 1;
      }
    }
    if !IsDefined(cam) {
      this.Exit("!CAMERA LINK FAILED", false);
      return;
    }
    this.m_camEntity = entity;
    this.m_cam = cam;
    this.ApplyCamera();
    cam.Activate(0.35, true);

    this.m_hud = new CMPilotHud();
    this.m_hud.Build();

    this.m_state = 2;
    let owner = GetPlayer(this.GetGameInstance());
    if IsDefined(owner) {
      owner.m_cmPilot = this;   // the game's own actions now come to us
    }
    TKLog.Add("ControllableMechs", "pilot: camera active, guns " + this.m_guns.Describe() + ", paused " + (GameInstance.GetTimeSystem(this.GetGameInstance()).IsPausedState() ? "yes" : "no"));
    this.m_lastTime = this.Now();
    this.m_slow = 1.0;   // refresh the HUD on the first frame
    this.m_timerLoop = false;
    this.m_watchFrames = 0;
    this.m_hud.ShowDebug(this.m_showDebug);
    this.m_hud.SetDebug("DBG  LOOP SCHEDULED, WAITING FOR FIRST FRAME");
    this.ScheduleFrame();
    this.ScheduleWatchdog();
  }

  public func OnTimeout(generation: Int32) -> Void {
    if generation == this.m_gen && this.m_state == 1 {
      this.Exit("!CAMERA LINK TIMED OUT", false);
    }
  }

  // ---------------------------------------------------------------------------
  // Exit: one teardown for every path. `hard` = session ending, no blends.
  // ---------------------------------------------------------------------------
  public func Exit(reason: String, hard: Bool) -> Void {
    if this.m_state == 0 {
      return;
    }
    let game = this.GetGameInstance();
    this.m_gen += 1;   // stops the frame loop and any pending timeout
    this.m_state = 0;
    let owner = GetPlayer(game);
    if IsDefined(owner) {
      owner.m_cmPilot = null;
    }
    this.m_lastExit = this.Now();

    TKLog.Add("ControllableMechs", "pilot: exit (" + reason + ") frames " + IntToString(this.m_dbgFrames) + ", keys " + IntToString(this.m_dbgKeys) + ", mouse " + IntToString(this.m_dbgAxis) + ", actions " + IntToString(this.m_dbgActions));
    if this.m_attachPending {
      this.m_attachPending = false;
      GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Attached", this, n"OnCamAttached");
    }

    // the mech stops where it is and goes back under the link's orders
    let mech = GameInstance.FindEntityByID(game, this.m_mechID) as NPCPuppet;
    if IsDefined(mech) {
      this.CancelCmd(mech, this.m_moveCmd);
      this.CancelCmd(mech, this.m_turnCmd);
      this.StopServo(mech);
    }
    this.m_servoOn = false;
    this.m_moveCmd = null;
    this.m_turnCmd = null;
    this.m_moving = false;
    let link = CMLinkSystem.Get(game);
    if IsDefined(link) && link.IsLinked() {
      link.Hold();
    }

    // camera back to V
    let player = GetPlayer(game);
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
    if EntityID.IsDefined(this.m_camID) {
      if hard {
        GameInstance.GetStaticEntitySystem().DespawnEntity(this.m_camID);
      } else {
        // after the blend back, or the blend is cut short
        let cb = new CMPilotDespawnCb();
        cb.system = this;
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

    if IsDefined(player) && this.m_restricted {
      this.Restrict(player, false);
    }
    this.m_restricted = false;
    if this.m_saveLocked {
      SaveLocksManager.RequestSaveLockRemove(game, n"ControllableMechs_Pilot");
      this.m_saveLocked = false;
    }
    this.m_rig = null;
    this.m_guns = null;
    ArrayClear(this.m_keys);

    if StrLen(reason) > 0 {
      this.Warn(reason);
    }
  }

  public func Despawn(id: EntityID) -> Void {
    GameInstance.GetStaticEntitySystem().DespawnEntity(id);
  }

  // ---------------------------------------------------------------------------
  // The frame loop (only while piloting)
  // ---------------------------------------------------------------------------
  // Primary: an event queued on V for the next frame, handled by PlayerPuppet.OnCMPilotTick
  // (the pattern Anti-Theft Measures' tick uses). Fallback, if the watchdog sees no frames:
  // a short DelayCallback timer.
  private func ScheduleFrame() -> Void {
    let game = this.GetGameInstance();
    if this.m_timerLoop {
      let cb = new CMPilotFrameCb();
      cb.system = this;
      cb.generation = this.m_gen;
      GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.016, false);
      return;
    }
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return;
    }
    let evt = new CMPilotTickEvent();
    evt.generation = this.m_gen;
    GameInstance.GetDelaySystem(game).DelayEventNextFrame(player, evt);
  }

  // twice a second while piloting: the frame loop must be advancing, or it's restarted on the timer
  private func ScheduleWatchdog() -> Void {
    let cb = new CMPilotWatchCb();
    cb.system = this;
    cb.generation = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.5, false);
  }

  public func OnWatchdog(generation: Int32) -> Void {
    if generation != this.m_gen || this.m_state != 2 {
      return;
    }
    if this.m_dbgFrames == this.m_watchFrames && !this.m_timerLoop {
      this.m_timerLoop = true;
      TKLog.Add("ControllableMechs", "pilot: no frames after 0.5 s, switching the loop to a timer");
      this.ScheduleFrame();
    }
    this.m_watchFrames = this.m_dbgFrames;
    if IsDefined(this.m_hud) {
      this.m_hud.SetDebug(this.DebugLine());
    }
    this.ScheduleWatchdog();
  }

  public func OnFrame(generation: Int32) -> Void {
    if generation != this.m_gen || this.m_state != 2 {
      return;
    }
    this.m_dbgFrames += 1;
    if this.m_showDebug && this.m_dbgFrames % 10 == 1 && IsDefined(this.m_hud) {
      this.m_hud.SetDebug(this.DebugLine());
    }
    let game = this.GetGameInstance();
    let now = this.Now();
    let dt = ClampF(now - this.m_lastTime, 0.0, 0.1);
    this.m_lastTime = now;
    this.m_dbgDt = dt;
    if dt <= 0.0 {
      dt = 0.016;   // a frame did pass, even if the clock didn't show it
    }
    let mech = GameInstance.FindEntityByID(game, this.m_mechID) as NPCPuppet;
    if !IsDefined(mech) {
      this.Exit("!ROBOT LINK LOST", false);
      return;
    }

    let rmbZoom = this.m_fireMode == CMFireMode.Split() ? this.Key(CMPilotKey.Mmb()) : this.Key(CMPilotKey.Rmb());
    this.m_zoom = rmbZoom;
    this.m_rig.Update(dt, mech.GetWorldPosition(), this.CamUp(), this.CamFwd(), this.m_zoom);
    this.ClipCamera(mech, dt);
    if this.m_rig.jumped > 0.0 {
      TKLog.Add("ControllableMechs", "pilot: the mech jumped " + FloatToStringPrec(this.m_rig.jumped, 1) + " m in one frame (moving " + (this.m_moving ? "yes" : "no") + ")");
    }
    this.ApplyCamera();

    // triggers: the MK.31s are fixed to the body, so they only fire once it faces the reticle
    // (otherwise the flash leaves the barrels one way and the rounds go another)
    this.m_aligned = AbsF(CMPilotRig.Wrap(this.m_rig.yaw - CMPilotRig.YawOf(mech.GetWorldForward()))) < this.ALIGN_DEG;
    if this.m_aimMode == 1 && !this.m_aligned && (this.Key(CMPilotKey.Lmb()) || this.Key(CMPilotKey.Rmb())) {
      this.m_unalignedHeld += dt;
      if this.m_unalignedHeld > 2.0 && this.m_unalignedHeld - dt <= 2.0 {
        TKLog.Add("ControllableMechs", "pilot: trigger held 2 s but the chassis is still " + FloatToStringPrec(AbsF(CMPilotRig.Wrap(this.m_rig.yaw - CMPilotRig.YawOf(mech.GetWorldForward()))), 0) + " deg off the reticle");
      }
    } else {
      this.m_unalignedHeld = 0.0;
    }
    // along the barrels, the rounds always follow the muzzles, so there's nothing to wait for
    let gate = this.m_aimMode == 0 || this.m_aligned;
    let lmb = gate && this.Key(CMPilotKey.Lmb());
    let rmb = gate && this.m_fireMode == CMFireMode.Split() && this.Key(CMPilotKey.Rmb());
    let trigger = this.Key(CMPilotKey.Lmb()) || (this.m_fireMode == CMFireMode.Split() && this.Key(CMPilotKey.Rmb()));
    if trigger && !this.m_triggerWas {
      // where the barrels really point, once per trigger pull (TOOLS > LOG)
      TKLog.Add("ControllableMechs", "pilot: barrels vs view  L " + this.m_guns.BarrelOffset(this.m_guns.left, this.m_rig.yaw, this.m_rig.pitch) + "  R " + this.m_guns.BarrelOffset(this.m_guns.right, this.m_rig.yaw, this.m_rig.pitch) + "  chassis " + FloatToStringPrec(CMPilotRig.Wrap(CMPilotRig.YawOf(mech.GetWorldForward()) - this.m_rig.yaw), 1));
    }
    this.m_triggerWas = trigger;
    if lmb || rmb {
      this.UpdateAim();
      let shots = this.m_guns.Update(mech, now, dt, lmb, rmb, this.m_fireMode, this.m_aim, this.SPREAD_DEG, this.m_rig.pos);
      if shots > 0 {
        this.m_rig.Recoil(0.45 * Cast<Float>(shots));
      }
    } else {
      this.m_guns.Update(mech, now, dt, false, false, this.m_fireMode, this.m_aim, this.SPREAD_DEG, this.m_rig.pos);
    }
    this.m_hud.Flash(this.m_guns.left.flash > 0.0, this.m_guns.right.flash > 0.0);
    this.PlacePips();
    this.Servo(mech, now);

    this.m_slow += dt;
    if this.m_slow >= 0.1 {
      this.m_slow = 0.0;
      if !this.SlowTick(mech, now) {
        return;   // exited
      }
    }
    this.ScheduleFrame();
  }

  // The barrel pips: where each MK.31 points, at the reticle's range, drawn on the HUD.
  // Screen offset from the view's angles: tan(angle) / tan(fov / 2) x half the 4K height
  // (the camera's FOV is taken as vertical; unverified, the pips may need a scale fix).
  private func PlacePips() -> Void {
    let range = this.m_aimDist > 1.0 ? this.m_aimDist : 150.0;
    let scale = 1080.0 / TanF(Deg2Rad(this.m_rig.fov * 0.5));
    let l = this.PipOffset(this.m_guns.BarrelPoint(this.m_guns.left, range), scale);
    let r = this.PipOffset(this.m_guns.BarrelPoint(this.m_guns.right, range), scale);
    let lOn = this.m_guns.left.Ready() && AbsF(l.X) < 1900.0 && AbsF(l.Y) < 1050.0;
    let rOn = this.m_guns.right.Ready() && AbsF(r.X) < 1900.0 && AbsF(r.Y) < 1050.0;
    this.m_hud.SetPips(l.X, l.Y, lOn, r.X, r.Y, rOn);
  }

  private func PipOffset(p: Vector4, scale: Float) -> Vector2 {
    let d = p - this.m_rig.pos;
    let flat = SqrtF(d.X * d.X + d.Y * d.Y);
    let yawOff = CMPilotRig.Wrap(CMPilotRig.YawOf(d) - this.m_rig.yaw);
    let pitchOff = Rad2Deg(AtanF(d.Z, flat)) - this.m_rig.pitch;
    if AbsF(yawOff) > 80.0 {
      return Vector2(9999.0, 9999.0);   // behind or far off: hidden
    }
    // positive yaw is to the left, positive pitch is up
    return Vector2(-TanF(Deg2Rad(yawOff)) * scale, -TanF(Deg2Rad(pitchOff)) * scale);
  }

  // Weight you can hear: the game's own sensor-camera servo loops while the view traverses,
  // a heavy servo thunk marks each start. Only state changes make sound calls.
  private func Servo(mech: ref<NPCPuppet>, now: Float) -> Void {
    let rate = AbsF(this.m_rig.YawRate());
    if !this.m_servoOn && rate > 10.0 {
      this.m_servoOn = true;
      GameObject.PlaySoundEvent(mech, n"dev_surveillance_camera_rotating");
      if now - this.m_servoHit > 0.6 {
        this.m_servoHit = now;
        GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_lcm_servo_short");
      }
    } else {
      if this.m_servoOn && rate < 4.0 {
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

  private func ApplyCamera() -> Void {
    if !IsDefined(this.m_camEntity) || !IsDefined(this.m_cam) {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, this.m_rig.pos);
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, CMPilotSystem.Identity());
    this.m_camEntity.SetWorldTransform(wt);   // the entity stays unrotated,
    let e: EulerAngles;                       // the component carries the view
    e.Yaw = this.m_rig.yaw;
    e.Pitch = this.m_rig.pitch;
    e.Roll = this.m_rig.roll;
    this.m_cam.SetLocalOrientation(EulerAngles.ToQuat(e));
    if AbsF(this.m_rig.fov - this.m_lastFov) > 0.05 {
      this.m_lastFov = this.m_rig.fov;
      this.m_cam.SetFOV(this.m_rig.fov);
    }
  }

  // what the reticle is on: first static hit along the view, else far away
  private func UpdateAim() -> Void {
    let fwd = this.m_rig.Forward();
    let from = this.m_rig.pos + fwd * (4.5 + (this.IsChase() ? this.ChaseDist() : 0.0));   // clear of the mech's own body
    let to = this.m_rig.pos + fwd * 600.0;
    let hit: TraceResult;
    if GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(from, to, n"Static", hit, true, false) {
      this.m_aim = Cast<Vector4>(hit.position);
      this.m_aimDist = Vector4.Distance(this.m_rig.pos, this.m_aim);
    } else {
      this.m_aim = to;
      this.m_aimDist = 0.0;
    }
  }

  // ---------------------------------------------------------------------------
  // Ten times a second: exits, orders, HUD
  // ---------------------------------------------------------------------------
  private func SlowTick(mech: ref<NPCPuppet>, now: Float) -> Bool {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let link = CMLinkSystem.Get(game);
    if !IsDefined(player) {
      this.Exit("", false);
      return false;
    }
    if !link.IsLinked() {
      this.Exit("!ROBOT LINK LOST", false);
      return false;
    }
    if !ScriptedPuppet.IsAlive(mech) {
      this.Exit("!MECH DESTROYED", false);
      return false;
    }
    let dist = Vector4.Distance(player.GetWorldPosition(), mech.GetWorldPosition());
    if dist > this.SIGNAL_RANGE {
      this.Exit("!SIGNAL LOST", false);
      return false;
    }
    let hp = this.PlayerHealth(player);
    if hp < this.m_vHealth - 0.01 && !this.m_stayWhenHit {
      this.Exit("!OPERATOR UNDER ATTACK - LINK DROPPED", false);
      return false;
    }
    this.m_vHealth = hp;

    this.Drive(mech, now);

    if !this.Key(CMPilotKey.Lmb()) && !this.Key(CMPilotKey.Rmb()) {
      this.UpdateAim();   // keeps the range readout live
    }
    this.RefreshHud(mech, link, dist);
    return true;
  }

  // WASD relative to where the torso looks; the mech walks there on its own legs
  private func Drive(mech: ref<NPCPuppet>, now: Float) -> Void {
    let f = (this.Key(CMPilotKey.W()) ? 1.0 : 0.0) - (this.Key(CMPilotKey.S()) ? 1.0 : 0.0);
    let s = (this.Key(CMPilotKey.D()) ? 1.0 : 0.0) - (this.Key(CMPilotKey.A()) ? 1.0 : 0.0);
    let fwd = CMPilotRig.Dir(this.m_rig.yaw, 0.0);
    let right = CMPilotRig.Dir(this.m_rig.yaw - 90.0, 0.0);
    let dir = fwd * f + right * s;
    let pos = mech.GetWorldPosition();
    if Vector4.Length(dir) < 0.1 {
      if this.m_moving {
        this.CancelCmd(mech, this.m_moveCmd);
        this.m_moveCmd = null;
        this.m_moving = false;
      }
      this.TurnToward(mech, now);
      return;
    }
    dir = Vector4.Normalize(dir);
    // no run: the Minotaur's "run" came out slower than its walk
    let run = false;
    let turned = !this.m_moving || Vector4.Dot(dir, this.m_moveDir) < 0.94;
    let close = Vector4.Distance(pos, this.m_moveTarget) < 4.0;
    let stale = now - this.m_moveSent > 1.5;
    let swung = AbsF(CMPilotRig.Wrap(this.m_rig.yaw - this.m_moveYaw)) > 25.0;
    if turned || close || stale || swung || NotEquals(run, this.m_moveRun) {
      // never order it into a wall: an unreachable target is when the game teleports it.
      // Stop 2.5 m short of the first static hit along the way, or don't move at all.
      let reach = 9.0;
      let from = new Vector4(pos.X, pos.Y, pos.Z + 1.2, 1.0);
      let hit: TraceResult;
      if GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(from + dir * 2.0, from + dir * (reach + 2.5), n"Static", hit, true, false) {
        reach = Vector4.Distance(from, Cast<Vector4>(hit.position)) - 2.5;
      }
      if reach < 1.5 {
        if this.m_moving {
          this.CancelCmd(mech, this.m_moveCmd);
          this.m_moveCmd = null;
          this.m_moving = false;
        }
        return;
      }
      let target = pos + dir * reach;
      let world: WorldPosition;
      WorldPosition.SetVector4(world, target);
      let spec: AIPositionSpec;
      AIPositionSpec.SetWorldPosition(spec, world);
      // keep the body (and the guns fixed to it) facing where the torso aims while walking
      let face: WorldPosition;
      WorldPosition.SetVector4(face, pos + CMPilotRig.Dir(this.m_rig.yaw, 0.0) * 30.0);
      let faceSpec: AIPositionSpec;
      AIPositionSpec.SetWorldPosition(faceSpec, face);
      let cmd = new AIMoveToCommand();
      cmd.movementTarget = spec;
      cmd.facingTarget = faceSpec;
      cmd.rotateEntityTowardsFacingTarget = true;
      this.m_moveYaw = this.m_rig.yaw;
      cmd.movementType = run ? moveMovementType.Run : moveMovementType.Walk;
      cmd.ignoreNavigation = false;
      cmd.useStart = !this.m_moving;
      cmd.useStop = true;
      cmd.finishWhenDestinationReached = true;
      cmd.desiredDistanceFromTarget = 0.5;
      this.Send(mech, cmd, true);
      this.m_moving = true;
      this.m_moveDir = dir;
      this.m_moveTarget = target;
      this.m_moveSent = now;
      this.m_moveRun = run;
    }
  }

  // standing still: the body follows where the torso aims, lazily, at its own heavy pace
  // (the MK.31s are fixed to the body, so this is what points the barrels). Orders go out
  // sparingly: each one restarts the turn animation. With a trigger held it lines up tighter
  // so the guns can fire.
  private func TurnToward(mech: ref<NPCPuppet>, now: Float) -> Void {
    let body = CMPilotRig.YawOf(mech.GetWorldForward());
    let firing = this.Key(CMPilotKey.Lmb()) || this.Key(CMPilotKey.Rmb());
    let slack = firing ? 6.0 : 20.0;
    let wait = firing ? 0.5 : 0.8;
    if AbsF(CMPilotRig.Wrap(this.m_rig.yaw - body)) < slack || now - this.m_turnSent < wait {
      return;
    }
    let target = mech.GetWorldPosition() + CMPilotRig.Dir(this.m_rig.yaw, 0.0) * 20.0;
    let world: WorldPosition;
    WorldPosition.SetVector4(world, target);
    let spec: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(spec, world);
    let cmd = new AIRotateToCommand();
    cmd.target = spec;
    cmd.angleTolerance = 3.0;
    this.Send(mech, cmd, false);
    this.m_turnSent = now;
    // the chassis swinging round: the Minotaur's own turn-in-place sound
    GameObject.PlaySoundEvent(mech, AbsF(CMPilotRig.Wrap(this.m_rig.yaw - body)) > 120.0 ? n"enm_mech_minotaur_loco_idle_to_idle_180_l" : n"enm_mech_minotaur_loco_idle_to_idle_90");
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

  private func RefreshHud(mech: ref<NPCPuppet>, link: ref<CMLinkSystem>, dist: Float) -> Void {
    let s = this.m_hudState;
    let name = link.UnitName();
    s.title = (StrLen(name) > 0 ? StrUpper(name) : "MILITECH MINOTAUR") + (this.IsChase() ? "  //  CHASE CAM" : "  //  NEURAL LINK");
    let h = RoundF(CMPilotRig.Wrap(-this.m_rig.yaw));
    s.heading = h < 0 ? h + 360 : h;
    s.range = this.m_aimDist;
    s.zoomed = this.m_zoom;
    s.integrity = link.HealthFraction();
    s.signal = link.SignalFraction();
    s.distance = dist;
    s.speed = this.m_rig.speed;
    s.fireMode = this.m_fireMode;
    s.heatL = this.m_guns.left.heat;
    s.heatR = this.m_guns.right.heat;
    s.lockedL = this.m_guns.left.locked;
    s.lockedR = this.m_guns.right.locked;
    s.hasL = this.m_guns.left.Ready();
    s.hasR = this.m_guns.right.Ready();
    s.warning = "";
    if s.integrity < 0.3 {
      s.warning = "INTEGRITY CRITICAL";
    } else {
      if s.signal < 0.2 {
        s.warning = "SIGNAL DEGRADED - RETURN TO OPERATOR";
      } else {
        if this.m_aimMode == 1 && !this.m_aligned {
          s.warning = "ALIGNING CHASSIS";
        }
      }
    }
    if this.m_fireMode == CMFireMode.Split() {
      s.hints = "[WASD] WALK   [LMB] LEFT GUN   [RMB] RIGHT GUN   [MMB] OPTICS   [B] FIRE MODE   [V] VIEW   [L] DISCONNECT";
    } else {
      s.hints = "[WASD] WALK   [LMB] FIRE   [RMB] OPTICS   [B] FIRE MODE   [V] VIEW   [L] DISCONNECT";
    }
    if this.m_showDebug {
      s.debug = this.DebugLine();
    }
    this.m_hud.Refresh(s);
  }

  // ---------------------------------------------------------------------------
  // Input, two channels:
  //   - raw keys and mouse (Codeware Input/Key, Input/Axis), registered once
  //     in OnAttach; both handlers return at once unless piloting
  //   - the game's own actions (Forward, Back, Left, Right, sprint, attack,
  //     aim, camera mouse) through the player's OnAction (CMInput.reds);
  //     rebind-aware, and the path XUtils and AMM rely on
  // Setting a held key from both channels is harmless. The camera mouse
  // actions are only used while no raw mouse events have arrived, so the view
  // never turns twice.
  // ---------------------------------------------------------------------------
  public func OnGameAction(name: CName, type: gameinputActionType, value: Float) -> Bool {
    if this.m_state != 2 {
      return false;
    }
    let down = !Equals(type, gameinputActionType.BUTTON_RELEASED);
    let used = true;
    switch name {
      case n"Forward": this.SetKey(CMPilotKey.W(), down); break;
      case n"Back": this.SetKey(CMPilotKey.S(), down); break;
      case n"Left": this.SetKey(CMPilotKey.A(), down); break;
      case n"Right": this.SetKey(CMPilotKey.D(), down); break;
      case n"ToggleSprint":
      case n"Sprint":
        this.SetKey(CMPilotKey.Run(), down);
        break;
      case n"RangedAttack":
      case n"ShootPrimary":
        this.SetKey(CMPilotKey.Lmb(), down);
        break;
      case n"CameraAim":
        this.SetKey(CMPilotKey.Rmb(), down);
        break;
      case n"CameraMouseX":
        if this.m_dbgAxis == 0 && IsDefined(this.m_rig) {
          this.m_rig.Look(-value / 45.0 * (this.m_zoom ? 0.5 : 1.0), 0.0);
        }
        break;
      case n"CameraMouseY":
        if this.m_dbgAxis == 0 && IsDefined(this.m_rig) {
          this.m_rig.Look(0.0, value / 45.0 * (this.m_zoom ? 0.5 : 1.0));
        }
        break;
      // V's own actions: swallowed while piloting, even if a restriction didn't take
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
        used = false;
        break;
    }
    if used {
      this.m_dbgActions += 1;
      this.Trace("action " + NameToString(name));
    }
    return used;
  }

  protected cb func OnKey(event: ref<KeyInputEvent>) -> Void {
    if this.m_state != 2 {
      return;
    }
    let action = event.GetAction();
    if Equals(action, EInputAction.IACT_Axis) {
      return;
    }
    this.m_dbgKeys += 1;
    this.Trace("key " + EnumValueToString("EInputKey", Cast<Int64>(EnumInt(event.GetKey()))));
    let down = !Equals(action, EInputAction.IACT_Release);
    switch event.GetKey() {
      case EInputKey.IK_W: this.SetKey(CMPilotKey.W(), down); break;
      case EInputKey.IK_A: this.SetKey(CMPilotKey.A(), down); break;
      case EInputKey.IK_S: this.SetKey(CMPilotKey.S(), down); break;
      case EInputKey.IK_D: this.SetKey(CMPilotKey.D(), down); break;
      case EInputKey.IK_LShift: this.SetKey(CMPilotKey.Run(), down); break;
      case EInputKey.IK_LeftMouse: this.SetKey(CMPilotKey.Lmb(), down); break;
      case EInputKey.IK_RightMouse: this.SetKey(CMPilotKey.Rmb(), down); break;
      case EInputKey.IK_MiddleMouse: this.SetKey(CMPilotKey.Mmb(), down); break;
      case EInputKey.IK_V:
        if Equals(action, EInputAction.IACT_Press) {
          this.SetCamMode(this.IsChase() ? 0 : 1);
          this.m_slow = 1.0;
        }
        break;
      case EInputKey.IK_B:
        if Equals(action, EInputAction.IACT_Press) {
          this.CycleFireMode();
          this.m_slow = 1.0;
        }
        break;
      case EInputKey.IK_L:
        // failsafe: L always disconnects, even if the Input Loader action is blocked
        if Equals(action, EInputAction.IACT_Press) {
          this.Exit("NEURAL LINK CLOSED", false);
        }
        break;
      default:
        break;
    }
  }

  protected cb func OnAxis(event: ref<AxisInputEvent>) -> Void {
    if this.m_state != 2 || !IsDefined(this.m_rig) {
      return;
    }
    this.m_dbgAxis += 1;
    let v = event.GetValue();
    // finer control through the optics
    let zoomScale = this.m_zoom ? 0.5 : 1.0;
    if Equals(event.GetKey(), EInputKey.IK_MouseX) {
      this.m_rig.Look(-v * this.m_sensX * zoomScale, 0.0);
    } else {
      this.m_rig.Look(0.0, -v * this.m_sensY * zoomScale);
    }
  }

  private func SetKey(i: Int32, down: Bool) -> Void {
    if i >= 0 && i < ArraySize(this.m_keys) {
      this.m_keys[i] = down;
    }
  }

  private func Key(i: Int32) -> Bool {
    return i >= 0 && i < ArraySize(this.m_keys) && this.m_keys[i];
  }

  // the game's own mouse sensitivity (as XUtils reads it), so the rig feels native
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
    let k = Cast<Float>(this.SensPct()) / 100.0;
    this.m_sensX *= k;
    this.m_sensY *= k;
  }

  // ---------------------------------------------------------------------------
  // V while piloting: locked in place, no weapons, no menus that fight the camera
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
    let missing = "";
    for id in list {
      if on {
        if !IsDefined(TweakDBInterface.GetStatusEffectRecord(id)) {
          missing += " " + TDBID.ToStringDEBUG(id);
        }
        ss.ApplyStatusEffect(pid, id, rid, pid);
      } else {
        ss.RemoveStatusEffect(pid, id);
      }
    }
    if on {
      TKLog.Add("ControllableMechs", "pilot: restrictions applied" + (StrLen(missing) > 0 ? ", records missing:" + missing : ", all records found"));
    }
    this.m_restricted = on;
  }

  // live check for the DBG line: do V's movement and jump locks hold?
  private func RestrictState() -> String {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return "?";
    }
    let ss = GameInstance.GetStatusEffectSystem(this.GetGameInstance());
    let pid = player.GetEntityID();
    let move = ss.HasStatusEffect(pid, t"GameplayRestriction.NoMovement");
    let jump = ss.HasStatusEffect(pid, t"GameplayRestriction.NoJump");
    return "MOVE-LOCK " + (move ? "Y" : "N") + "  JUMP-LOCK " + (jump ? "Y" : "N");
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  // the rig's height and reach: the sensor mount, or behind and above for the chase view
  private func CamUp() -> Float = this.IsChase() ? this.ChaseUp() : Cast<Float>(this.CamUpCm()) / 100.0
  private func CamFwd() -> Float = this.IsChase() ? -this.ChaseDist() : Cast<Float>(this.CamFwdCm()) / 100.0

  // ---- camera view: sensor (first person) or chase (third person) ----
  public func IsChase() -> Bool = this.m_camMode == 1
  public func CamMode() -> Int32 = this.m_camMode
  public func SetCamMode(mode: Int32) -> Void {
    this.m_camMode = Clamp(mode, 0, 1);
    this.m_clip = 999.0;   // re-measure from the full distance
  }
  public func ChaseDistCm() -> Int32 = this.m_chaseDistCm > 0 ? this.m_chaseDistCm - 1 : 850
  public func ChaseUpCm() -> Int32 = this.m_chaseUpCm > 0 ? this.m_chaseUpCm - 1 : 420
  public func SetChaseDistCm(v: Int32) -> Void { this.m_chaseDistCm = Clamp(v, 400, 1600) + 1; }
  public func SetChaseUpCm(v: Int32) -> Void { this.m_chaseUpCm = Clamp(v, 200, 900) + 1; }
  private func ChaseDist() -> Float = Cast<Float>(this.ChaseDistCm()) / 100.0
  private func ChaseUp() -> Float = Cast<Float>(this.ChaseUpCm()) / 100.0

  // Keeps the camera out of walls, poles and containers: one static raycast per frame
  // (piloting only) from the mech's centre at camera height out to where the rig put the
  // camera. On a hit the camera snaps in to 0.35 m short of it, and eases back out at
  // 6 m/s once the way is clear, so it doesn't pop.
  private func ClipCamera(mech: ref<NPCPuppet>, dt: Float) -> Void {
    let g = mech.GetWorldPosition();
    let pivot = new Vector4(g.X, g.Y, g.Z + this.CamUp(), 1.0);
    let want = this.m_rig.pos;
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
      this.m_rig.pos = pivot + dir * this.m_clip;
    }
  }

  // ---- camera tuning (SETTINGS sliders; applied live) ----
  public func CamUpCm() -> Int32 = this.m_camUpCm > 0 ? this.m_camUpCm - 1 : this.MOUNT_UP_CM
  public func CamFwdCm() -> Int32 = this.m_camFwdCm > 0 ? this.m_camFwdCm - 1 : this.MOUNT_FWD_CM
  public func SensPct() -> Int32 = this.m_sensPct > 0 ? this.m_sensPct - 1 : 100
  public func ShowDebug() -> Bool = this.m_showDebug

  public func AimMode() -> Int32 = this.m_aimMode
  public func SetAimMode(mode: Int32) -> Void {
    this.m_aimMode = Clamp(mode, 0, 1);
    if IsDefined(this.m_guns) {
      this.m_guns.SetBarrelMode(this.m_aimMode == 0);
    }
  }
  public func Traverse() -> Int32 = this.m_traverse > 0 ? this.m_traverse - 1 : 40
  public func SetTraverse(v: Int32) -> Void {
    this.m_traverse = Clamp(v, 15, 120) + 1;
    if IsDefined(this.m_rig) {
      this.m_rig.SetTraverse(Cast<Float>(this.Traverse()));
    }
  }

  public func SetCamUpCm(v: Int32) -> Void { this.m_camUpCm = Clamp(v, 100, 450) + 1; }
  public func SetCamFwdCm(v: Int32) -> Void { this.m_camFwdCm = Clamp(v, 0, 500) + 1; }
  public func SetSensPct(v: Int32) -> Void {
    this.m_sensPct = Clamp(v, 25, 300) + 1;
    if this.m_state == 2 {
      this.CacheSensitivity();
    }
  }
  public func SetShowDebug(on: Bool) -> Void {
    this.m_showDebug = on;
    if IsDefined(this.m_hud) {
      this.m_hud.ShowDebug(on);
    }
  }

  public func ResetCamera() -> Void {
    this.m_camUpCm = 0;
    this.m_camFwdCm = 0;
    this.m_sensPct = 0;
    this.m_traverse = 0;
    if IsDefined(this.m_rig) {
      this.m_rig.SetTraverse(Cast<Float>(this.Traverse()));
    }
    if this.m_state == 2 {
      this.CacheSensitivity();
    }
  }

  private func PlayerHealth(player: ref<PlayerPuppet>) -> Float {
    return GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, false);
  }

  // engine time: it always advances (the frame loop itself stops while a menu pauses the game)
  private func Now() -> Float = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()))

  // the first input events of each kind go to TerminalKit's log (TOOLS > LOG)
  private func Trace(what: String) -> Void {
    if Equals(what, this.m_dbgLast) || this.m_dbgKeys + this.m_dbgAxis + this.m_dbgActions > 40 {
      return;
    }
    this.m_dbgLast = what;
    TKLog.Add("ControllableMechs", "pilot input: " + what);
  }

  public func DebugLine() -> String {
    return "DBG  " + (this.m_timerLoop ? "TIMER" : "EVENT") + " FRAMES " + IntToString(this.m_dbgFrames) + "  DT " + FloatToStringPrec(this.m_dbgDt, 3) + "  KEYS " + IntToString(this.m_dbgKeys) + "  MOUSE " + IntToString(this.m_dbgAxis) + "  ACTIONS " + IntToString(this.m_dbgActions) + "  PAUSED " + (GameInstance.GetTimeSystem(this.GetGameInstance()).IsPausedState() ? "Y" : "N") + "  " + this.RestrictState();
  }

  // a default Quaternion is all zeros, not identity
  public static func Identity() -> Quaternion {
    let e: EulerAngles;
    return EulerAngles.ToQuat(e);
  }

  private func Warn(msg: String) -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if IsDefined(player) && StrLen(msg) > 0 {
      player.SetWarningMessage(StrReplaceAll(StrReplaceAll(msg, "!", ""), "*", ""));
    }
  }
}

// ---- the per-frame tick: an event V receives next frame (only queued while piloting) ----
public class CMPilotTickEvent extends Event {
  public let generation: Int32;
}

@addMethod(PlayerPuppet)
protected cb func OnCMPilotTick(evt: ref<CMPilotTickEvent>) -> Bool {
  if IsDefined(this.m_cmPilot) {
    this.m_cmPilot.OnFrame(evt.generation);
  }
  return true;
}

public class CMPilotWatchCb extends DelayCallback {
  public let system: wref<CMPilotSystem>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnWatchdog(this.generation);
    }
  }
}

// ---- callbacks (weak back-references; a stale generation does nothing) ----
public class CMPilotFrameCb extends DelayCallback {
  public let system: wref<CMPilotSystem>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnFrame(this.generation);
    }
  }
}

public class CMPilotTimeoutCb extends DelayCallback {
  public let system: wref<CMPilotSystem>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnTimeout(this.generation);
    }
  }
}

public class CMPilotEnterCb extends DelayCallback {
  public let system: wref<CMPilotSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.EnterFromCallback();
    }
  }
}

public class CMPilotDespawnCb extends DelayCallback {
  public let system: wref<CMPilotSystem>;
  public let id: EntityID;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.Despawn(this.id);
    }
  }
}
