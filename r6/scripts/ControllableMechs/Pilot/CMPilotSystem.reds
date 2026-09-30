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
  private let m_turnCmd: ref<AICommand>;
  private let m_turnSent: Float;

  // diagnostics: what actually arrives while piloting (HUD line + TerminalKit log)
  private let m_dbgFrames: Int32;
  private let m_dbgKeys: Int32;
  private let m_dbgAxis: Int32;
  private let m_dbgActions: Int32;
  private let m_dbgLast: String;

  private let m_vHealth: Float;
  private let m_restricted: Bool;
  private let m_saveLocked: Bool;
  private let m_lastExit: Float;

  // settings, kept in the save
  private persistent let m_fireMode: Int32;
  private persistent let m_stayWhenHit: Bool;
  private persistent let m_themeIdx: Int32;   // 0 = militech (default), else 1 + index into TKTheme.Ids()

  // where the sensor sits on the mech (forward, up; metres)
  private let MOUNT_FORWARD: Float = 1.7;
  private let MOUNT_UP: Float = 3.0;
  private let SPREAD_DEG: Float = 0.6;
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
    this.m_rig.Init(this.Mount(mech), CMPilotRig.YawOf(mech.GetWorldForward()));
    this.m_guns = new CMPilotGuns();
    this.m_guns.Init(mech);
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
    this.ScheduleFrame();
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
    }
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
  private func ScheduleFrame() -> Void {
    let cb = new CMPilotFrameCb();
    cb.system = this;
    cb.generation = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallbackNextFrame(cb);
  }

  public func OnFrame(generation: Int32) -> Void {
    if generation != this.m_gen || this.m_state != 2 {
      return;
    }
    this.m_dbgFrames += 1;
    let game = this.GetGameInstance();
    let now = this.Now();
    let dt = ClampF(now - this.m_lastTime, 0.0, 0.1);
    this.m_lastTime = now;
    if dt <= 0.0 {
      this.ScheduleFrame();   // paused: nothing moves
      return;
    }
    let mech = GameInstance.FindEntityByID(game, this.m_mechID) as NPCPuppet;
    if !IsDefined(mech) {
      this.Exit("!ROBOT LINK LOST", false);
      return;
    }

    let rmbZoom = this.m_fireMode == CMFireMode.Split() ? this.Key(CMPilotKey.Mmb()) : this.Key(CMPilotKey.Rmb());
    this.m_zoom = rmbZoom;
    this.m_rig.Update(dt, this.Mount(mech), this.m_zoom);
    this.ApplyCamera();

    // triggers
    let lmb = this.Key(CMPilotKey.Lmb());
    let rmb = this.m_fireMode == CMFireMode.Split() && this.Key(CMPilotKey.Rmb());
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

    this.m_slow += dt;
    if this.m_slow >= 0.1 {
      this.m_slow = 0.0;
      if !this.SlowTick(mech, now) {
        return;   // exited
      }
    }
    this.ScheduleFrame();
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
    let from = this.m_rig.pos + fwd * 4.5;   // clear of the mech's own body
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
    let run = this.Key(CMPilotKey.Run());
    let turned = !this.m_moving || Vector4.Dot(dir, this.m_moveDir) < 0.94;
    let close = Vector4.Distance(pos, this.m_moveTarget) < 4.0;
    let stale = now - this.m_moveSent > 1.5;
    if turned || close || stale || NotEquals(run, this.m_moveRun) {
      let target = pos + dir * 9.0;
      let world: WorldPosition;
      WorldPosition.SetVector4(world, target);
      let spec: AIPositionSpec;
      AIPositionSpec.SetWorldPosition(spec, world);
      let cmd = new AIMoveToCommand();
      cmd.movementTarget = spec;
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

  // standing still: the body swings round when the torso is far off its facing
  private func TurnToward(mech: ref<NPCPuppet>, now: Float) -> Void {
    let body = CMPilotRig.YawOf(mech.GetWorldForward());
    if AbsF(CMPilotRig.Wrap(this.m_rig.yaw - body)) < 55.0 || now - this.m_turnSent < 1.5 {
      return;
    }
    let target = mech.GetWorldPosition() + CMPilotRig.Dir(this.m_rig.yaw, 0.0) * 20.0;
    let world: WorldPosition;
    WorldPosition.SetVector4(world, target);
    let spec: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(spec, world);
    let cmd = new AIRotateToCommand();
    cmd.target = spec;
    cmd.angleTolerance = 10.0;
    this.Send(mech, cmd, false);
    this.m_turnSent = now;
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
    s.title = (StrLen(name) > 0 ? StrUpper(name) : "MILITECH MINOTAUR") + "  //  NEURAL LINK";
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
      }
    }
    if this.m_fireMode == CMFireMode.Split() {
      s.hints = "[WASD] WALK   [SHIFT] RUN   [LMB] LEFT GUN   [RMB] RIGHT GUN   [MMB] OPTICS   [B] FIRE MODE   [L] DISCONNECT";
    } else {
      s.hints = "[WASD] WALK   [SHIFT] RUN   [LMB] FIRE   [RMB] OPTICS   [B] FIRE MODE   [L] DISCONNECT";
    }
    s.debug = this.DebugLine();
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
  private func Mount(mech: ref<NPCPuppet>) -> Vector4 {
    let p = mech.GetWorldPosition();
    let f = mech.GetWorldForward();
    return new Vector4(p.X + f.X * this.MOUNT_FORWARD, p.Y + f.Y * this.MOUNT_FORWARD, p.Z + this.MOUNT_UP, 1.0);
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
    return "DBG  FRAMES " + IntToString(this.m_dbgFrames) + "  KEYS " + IntToString(this.m_dbgKeys) + "  MOUSE " + IntToString(this.m_dbgAxis) + "  ACTIONS " + IntToString(this.m_dbgActions) + "  PAUSED " + (GameInstance.GetTimeSystem(this.GetGameInstance()).IsPausedState() ? "Y" : "N") + "  " + this.RestrictState();
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
