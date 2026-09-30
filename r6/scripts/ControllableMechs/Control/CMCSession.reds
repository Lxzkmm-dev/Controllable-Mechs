// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: THE SESSION (M1)
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
// Until M1 passes this runs beside the alpha's Pilot Mode: the Pilot key starts it
// only while the M1 PREVIEW switch (SPIKES tab) is on.
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
  public static func Count() -> Int32 = 7
}

public class CMCSession extends ScriptableSystem {
  // 0 idle, 1 camera spawning, 2 controlling, 3 in a vanilla turret takeover (M2)
  private let m_state: Int32;
  // M2: the turret V has taken over; the game owns the camera, HUD and fire meanwhile
  private let m_takeoverID: EntityID;
  private let m_takeoverSeen: Bool;
  private let m_takeoverAt: Float;
  private let m_tkCamOn: Bool;   // our chase camera is up over the takeover
  private let m_gen: Int32;
  private let m_unit: ref<CMCUnit>;

  // what units read
  public let rig: ref<CMPilotRig>;
  public let aim: Vector4;
  public let aimDist: Float;
  public let aimEntity: wref<Entity>;   // what the reticle's dynamic ray hit (none on world geometry)
  public let zoom: Bool;

  private let m_keys: array<Bool>;
  private let m_sensX: Float;
  private let m_sensY: Float;
  private let m_axisSeen: Int32;

  private let m_camID: EntityID;
  private let m_cam: ref<CameraComponent>;
  private let m_camEntity: wref<Entity>;
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
  private let m_saveLocked: Bool;
  private let m_vHealth: Float;
  private let m_lastExit: Float;

  // settings, kept in the save
  private persistent let m_armed: Bool;       // M1 preview: the Pilot key starts the framework
  private persistent let m_fireCall: Int32;   // CMFireCall
  private persistent let m_fireMode: Int32;   // CMFireMode
  private persistent let m_chase: Bool;
  private persistent let m_creditVOff: Bool;  // false = kills and aggro credit V (the default)

  public static func Get(game: GameInstance) -> ref<CMCSession> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMCSession") as CMCSession;
  }

  public static func Log(text: String) -> Void {
    TKLog.Add("CM-M1", text);
    let line = "CM-M1 " + text;
    ModLog(n"ControllableMechs", line);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  private func OnAttach() -> Void {
    let cbs = GameInstance.GetCallbackSystem();
    cbs.RegisterCallback(n"Session/BeforeEnd", this, n"OnSessionEnd").SetLifetime(CallbackLifetime.Forever);
    cbs.RegisterCallback(n"Input/Key", this, n"OnKey").SetLifetime(CallbackLifetime.Forever);
    cbs.RegisterCallback(n"Input/Axis", this, n"OnAxis")
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseX))
      .AddTarget(InputTarget.Axis(EInputKey.IK_MouseY))
      .SetLifetime(CallbackLifetime.Forever);
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

  public func IsActive() -> Bool = this.m_state != 0
  public func Armed() -> Bool = this.m_armed
  public func SetArmed(on: Bool) -> Void {
    this.m_armed = on;
    CMCSession.Log("M1 preview " + (on ? "ON: the Pilot key starts the framework" : "off: the Pilot key starts the alpha's Pilot Mode"));
  }
  public func FireCall() -> Int32 = this.m_fireCall
  public func SetFireCall(call: Int32) -> Void {
    this.m_fireCall = Clamp(call, 0, 2);
    CMCSession.Log("fire call " + CMFireCall.Name(this.m_fireCall));
  }
  public func FireMode() -> Int32 = this.m_fireMode
  public func CreditV() -> Bool = !this.m_creditVOff
  public func SetCreditV(on: Bool) -> Void {
    this.m_creditVOff = !on;
    CMCSession.Log("credit to V " + (on ? "ON" : "off"));
  }
  public func IsChase() -> Bool = this.m_chase

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
    this.Warn(this.Begin(new CMUMinotaur(), false));
  }

  // from the terminal: let the popup close first
  public func RequestBegin(delay: Float) -> Void {
    let cb = new CMCBeginCb();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  public func BeginFromCallback() -> Void {
    if this.m_state == 0 {
      this.Warn(this.Begin(new CMUMinotaur(), true));
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
    if CMPilotSystem.Get(game).IsPiloting() {
      return "!THE ALPHA PILOT MODE IS ACTIVE";
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

    this.rig.Init(unit.Ground(), this.CamUp(), this.CamFwd(), unit.Facing());
    this.rig.SetChase(this.m_chase);
    this.rig.SetTraverse(Cast<Float>(CMPilotSystem.Get(game).Traverse()));
    this.m_clip = 999.0;
    this.m_lastFov = 0.0;
    this.aim = this.rig.pos + this.rig.Forward() * 100.0;
    this.aimDist = 0.0;
    this.zoom = false;
    ArrayClear(this.m_keys);
    ArrayResize(this.m_keys, CMCKey.Count());
    this.m_axisSeen = 0;
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
    let timeout = new CMCTimeoutCb();
    timeout.system = this;
    timeout.generation = this.m_gen;
    GameInstance.GetDelaySystem(game).DelayCallback(timeout, 3.0, false);
    CMCSession.Log("begin: " + unit.Name() + ", fire call " + CMFireCall.Name(this.m_fireCall) + ", " + (this.m_chase ? "chase" : "sight") + " view");
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
    if this.m_state != 1 && this.m_state != 3 {
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
    if this.m_state == 3 {
      // the chase camera over an emplacement takeover
      if !IsDefined(cam) {
        CMCSession.Log("emplacement chase view: no camera component, staying in the turret's view");
        return;
      }
      this.m_camEntity = entity;
      this.m_cam = cam;
      this.m_tkCamOn = true;
      this.TakeoverCamPlace();
      cam.Activate(0.35, true);
      let owner = GetPlayer(this.GetGameInstance());
      if IsDefined(owner) {
        owner.m_cmcSession = this;   // the frame event reaches us (game actions still pass: state 3)
      }
      this.m_frames = 0;
      this.m_timerLoop = false;
      this.ScheduleFrame();
      CMCSession.Log("emplacement chase view on");
      return;
    }
    if !IsDefined(cam) {
      this.End("!CAMERA LINK FAILED", false);
      return;
    }
    this.m_camEntity = entity;
    this.m_cam = cam;
    this.ApplyCamera();
    cam.Activate(0.35, true);
    this.m_hud = new CMPilotHud();
    this.m_hud.Build();
    this.m_state = 2;
    let player = GetPlayer(this.GetGameInstance());
    if IsDefined(player) {
      player.m_cmcSession = this;   // the game's own actions now come to us
    }
    this.m_lastTime = this.Now();
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
    if this.m_state == 3 {
      this.EndTakeover(reason);
      return;
    }
    let game = this.GetGameInstance();
    this.m_gen += 1;   // stops the frame loop, the watchdog and any pending timeout
    this.m_state = 0;
    this.m_lastExit = this.Now();
    let player = GetPlayer(game);
    if IsDefined(player) {
      player.m_cmcSession = null;
    }
    CMCSession.Log("end (" + reason + ") after " + IntToString(this.m_frames) + " frames");
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
  // M2: the emplacement, through the game's own turret takeover
  // The game runs the view (the turret's own camera: no chase view there), the turret
  // HUD, aiming and firing (V-credited, per S0b), and its own Esc exit. The session
  // starts the takeover, watches it at 10 Hz for the exit, adds \ as a second exit,
  // and releases it on every teardown path (turret gone, V dead, load, session end).
  // ---------------------------------------------------------------------------
  public func BeginTakeover() -> Void {
    this.Warn(this.StartTakeover());
  }

  public func RequestTakeover(delay: Float) -> Void {
    let cb = new CMCTakeoverCb();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delay, false);
  }

  private func StartTakeover() -> String {
    if this.m_state != 0 {
      return "";
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) || player.IsDead() {
      return "!NO OPERATOR";
    }
    if CMPilotSystem.Get(game).IsPiloting() {
      return "!THE ALPHA PILOT MODE IS ACTIVE";
    }
    let veh: wref<VehicleObject>;
    VehicleComponent.GetVehicle(game, player.GetEntityID(), veh);
    if IsDefined(veh) {
      return "!LEAVE THE VEHICLE FIRST";
    }
    let turret = CMCEmplacements.Get(game).Turret();
    if !IsDefined(turret) {
      return "!NO EMPLACEMENT OUT";
    }
    let action = turret.GetDevicePS().ActionToggleTakeOverControl();
    action.SetExecutor(player);
    TakeOverControlSystem.RequestTakeControl(turret, action);
    this.m_gen += 1;
    this.m_state = 3;
    this.m_takeoverID = turret.GetEntityID();
    this.m_takeoverSeen = false;
    this.m_takeoverAt = this.Now();
    this.ScheduleTakeoverWatch();
    CMCSession.Log("takeover requested: " + CMCEmplacements.ModelName(CMCEmplacements.Get(game).Model()) + " (sight view only: the takeover uses the turret's own camera)");
    return "";
  }

  private func ScheduleTakeoverWatch() -> Void {
    let cb = new CMCTakeoverWatchCb();
    cb.system = this;
    cb.generation = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.1, false);
  }

  private func TakeoverSystem() -> ref<TakeOverControlSystem> {
    return GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"TakeOverControlSystem") as TakeOverControlSystem;
  }

  private func InOurTurret() -> Bool {
    let tocs = this.TakeoverSystem();
    if !IsDefined(tocs) {
      return false;
    }
    let obj = tocs.GetControlledObject();
    return IsDefined(obj) && obj.GetEntityID() == this.m_takeoverID;
  }

  public func OnTakeoverWatch(generation: Int32) -> Void {
    if generation != this.m_gen || this.m_state != 3 {
      return;
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) || player.IsDead() {
      this.End("", false);
      return;
    }
    let turret = GameInstance.FindEntityByID(game, this.m_takeoverID) as SecurityTurret;
    if !IsDefined(turret) {
      this.End("!EMPLACEMENT LOST", false);
      return;
    }
    if this.InOurTurret() {
      if !this.m_takeoverSeen {
        this.m_takeoverSeen = true;
        CMCSession.Log("takeover active");
        if this.m_chase {
          this.StartTakeoverCam();
        }
      }
    } else {
      if this.m_takeoverSeen {
        this.End("", false);   // the game's own exit (Esc) already put V back
        return;
      }
      if this.Now() - this.m_takeoverAt > 3.0 {
        this.End("!TAKEOVER FAILED", false);
        return;
      }
    }
    this.ScheduleTakeoverWatch();
  }

  private func EndTakeover(reason: String) -> Void {
    this.StopTakeoverCam(false);
    this.m_gen += 1;
    this.m_state = 0;
    this.m_lastExit = this.Now();
    if this.InOurTurret() {
      TakeOverControlSystem.ReleaseControl(this.GetGameInstance());
      CMCSession.Log("takeover released by the framework (" + reason + ")");
    } else {
      CMCSession.Log("takeover ended (" + reason + ")");
    }
    let empty: EntityID;
    this.m_takeoverID = empty;
    this.Warn(reason);
  }

  // ---- the emplacement's chase view: our camera behind and above the turret, looking
  // along its gun at what the gun is on. The takeover keeps the turret's own aiming and
  // fire (so damage stays V's); the camera follows the gun, and the vanilla crosshair at
  // the screen centre sits on the gun's aim point. V switches it on and off.
  private func StartTakeoverCam() -> Void {
    if this.m_tkCamOn || this.m_attachPending {
      return;
    }
    let turret = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_takeoverID);
    if !IsDefined(turret) {
      return;
    }
    let spec = new StaticEntitySpec();
    spec.templatePath = r"base\\entities\\cameras\\simple_free_camera.ent";
    spec.position = turret.GetWorldPosition() + new Vector4(0.0, 0.0, 2.2, 0.0);
    spec.orientation = CMCSession.Identity();
    spec.attached = true;
    this.m_camID = GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
    if !EntityID.IsDefined(this.m_camID) {
      CMCSession.Log("emplacement chase view: the camera didn't spawn");
      return;
    }
    this.m_attachPending = true;
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Attached", this, n"OnCamAttached");
  }

  // `backToTurret`: give the view back to the turret's own camera (the view switch);
  // on leaving, the game's release puts V's camera back
  private func StopTakeoverCam(backToTurret: Bool) -> Void {
    let game = this.GetGameInstance();
    if this.m_attachPending {
      this.m_attachPending = false;
      GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Attached", this, n"OnCamAttached");
    }
    let wasOn = this.m_tkCamOn;
    this.m_tkCamOn = false;
    let owner = GetPlayer(game);
    if IsDefined(owner) && wasOn {
      owner.m_cmcSession = null;
    }
    if IsDefined(this.m_cam) {
      this.m_cam.Deactivate(0.25, true);
    }
    this.m_cam = null;
    this.m_camEntity = null;
    if EntityID.IsDefined(this.m_camID) {
      let cb = new CMCDespawnCb();
      cb.id = this.m_camID;
      GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.4, false);
    }
    let empty: EntityID;
    this.m_camID = empty;
    if wasOn && backToTurret {
      let turret = GameInstance.FindEntityByID(game, this.m_takeoverID);
      let found = false;
      if IsDefined(turret) {
        for c in turret.GetComponents() {
          let tc = c as CameraComponent;
          if !found && IsDefined(tc) {
            tc.Activate(0.25, true);
            found = true;
            CMCSession.Log("emplacement sight view: turret camera " + NameToString(c.GetName()) + " reactivated");
          }
        }
      }
      if !found {
        CMCSession.Log("emplacement sight view: no camera component on the turret to hand back to");
      }
    }
  }

  private func TakeoverCamPlace() -> Void {
    let game = this.GetGameInstance();
    let turret = GameInstance.FindEntityByID(game, this.m_takeoverID) as SecurityTurret;
    if !IsDefined(turret) || !IsDefined(this.m_camEntity) || !IsDefined(this.m_cam) {
      return;
    }
    let weapon = GameInstance.GetTransactionSystem(game).GetItemInSlot(turret, t"AttachmentSlots.WeaponRight") as WeaponObject;
    let gunPos = IsDefined(weapon) ? weapon.GetWorldPosition() : turret.GetWorldPosition() + new Vector4(0.0, 0.0, 1.2, 0.0);
    let fwd = Vector4.Normalize(IsDefined(weapon) ? weapon.GetWorldForward() : turret.GetWorldForward());
    let sq = GameInstance.GetSpatialQueriesSystem(game);
    // what the gun is on
    let aimAt = gunPos + fwd * 80.0;
    let hit: TraceResult;
    if sq.SyncRaycastByCollisionPreset(gunPos + fwd * 1.0, aimAt, n"World Static", hit, true) {
      aimAt = Cast<Vector4>(hit.position);
    }
    // behind and above the gun along its heading, pulled in short of walls
    let yaw = CMPilotRig.YawOf(fwd);
    let pivot = gunPos + new Vector4(0.0, 0.0, 1.0, 0.0);
    let want = pivot - CMPilotRig.Dir(yaw, 0.0) * 4.5 + new Vector4(0.0, 0.0, 1.2, 0.0);
    let off = want - pivot;
    let full = Vector4.Length(off);
    let pos = want;
    let wall: TraceResult;
    if full > 0.3 && sq.SyncRaycastByCollisionGroup(pivot, want, n"Static", wall, true, false) {
      pos = pivot + off * (MaxF(0.2, Vector4.Distance(pivot, Cast<Vector4>(wall.position)) - 0.35) / full);
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, pos);
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, CMCSession.Identity());
    this.m_camEntity.SetWorldTransform(wt);
    let look = Vector4.Normalize(aimAt - pos);
    let e: EulerAngles;
    e.Yaw = CMPilotRig.YawOf(look);
    e.Pitch = Rad2Deg(AsinF(ClampF(look.Z, -1.0, 1.0)));
    this.m_cam.SetLocalOrientation(EulerAngles.ToQuat(e));
  }

  // the emplacement is being removed: leave it first
  public func EndIfTakeover(id: EntityID) -> Void {
    if this.m_state == 3 && this.m_takeoverID == id {
      this.End("EMPLACEMENT REMOVED", false);
    }
  }

  public func InTakeover() -> Bool = this.m_state == 3

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
    if generation != this.m_gen {
      return;
    }
    if this.m_state == 3 {
      // the emplacement's chase camera: only while it's up
      if this.m_tkCamOn {
        this.m_frames += 1;
        this.TakeoverCamPlace();
        this.ScheduleFrame();
      }
      return;
    }
    if this.m_state != 2 {
      return;
    }
    this.m_frames += 1;
    let now = this.Now();
    let dt = ClampF(now - this.m_lastTime, 0.0, 0.1);
    this.m_lastTime = now;
    if dt <= 0.0 {
      dt = 0.016;
    }
    if !this.m_unit.IsAlive() {
      this.End("!UNIT LOST", false);
      return;
    }
    let optics = this.m_fireMode == CMFireMode.Split() ? this.Key(CMCKey.Mmb()) : this.Key(CMCKey.Rmb());
    this.zoom = optics;
    this.rig.Update(dt, this.m_unit.Ground(), this.CamUp(), this.CamFwd(), this.zoom);
    this.ClipCamera(dt);
    this.ApplyCamera();
    this.UpdateAim();
    this.m_unit.Tick(this, dt, now);

    this.m_slow += dt;
    if this.m_slow >= 0.1 {
      this.m_slow = 0.0;
      if !this.SlowTick(now) {
        return;
      }
    }
    this.ScheduleFrame();
  }

  private func SlowTick(now: Float) -> Bool {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) || player.IsDead() {
      this.End("", false);
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
    s.title = this.m_unit.Name() + (this.m_chase ? "  //  CHASE CAM" : "  //  NEURAL LINK") + "  //  FRAMEWORK M1";
    let h = RoundF(CMPilotRig.Wrap(-this.rig.yaw));
    s.heading = h < 0 ? h + 360 : h;
    s.range = this.aimDist;
    s.zoomed = this.zoom;
    s.speed = this.rig.speed;
    s.fireMode = this.m_fireMode;
    s.warning = "";
    s.hints = this.m_fireMode == CMFireMode.Split()
      ? "[WASD] WALK   [LMB] LEFT GUN   [RMB] RIGHT GUN   [MMB] OPTICS   [B] FIRE MODE   [V] VIEW   [\\] DISCONNECT"
      : "[WASD] WALK   [LMB] FIRE   [RMB] OPTICS   [B] FIRE MODE   [V] VIEW   [\\] DISCONNECT";
    this.m_unit.Hud(this, s);
    this.m_hud.Refresh(s);
  }

  // the unit's barrel markers and muzzle flashes, drawn every frame
  public func Hud() -> ref<CMPilotHud> = this.m_hud

  // ---------------------------------------------------------------------------
  // Camera and aim
  // ---------------------------------------------------------------------------
  private func CamUp() -> Float = this.m_chase ? Cast<Float>(CMPilotSystem.Get(this.GetGameInstance()).ChaseUpCm()) / 100.0 : this.m_unit.SensorUp()
  private func CamFwd() -> Float = this.m_chase ? -Cast<Float>(CMPilotSystem.Get(this.GetGameInstance()).ChaseDistCm()) / 100.0 : this.m_unit.SensorFwd()

  private func SetChase(on: Bool) -> Void {
    this.m_chase = on;
    this.m_clip = 999.0;
    if IsDefined(this.rig) {
      this.rig.SetChase(on);
    }
  }

  private func ApplyCamera() -> Void {
    if !IsDefined(this.m_camEntity) || !IsDefined(this.m_cam) {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, this.rig.pos);
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, CMCSession.Identity());
    this.m_camEntity.SetWorldTransform(wt);   // the entity stays unrotated,
    let e: EulerAngles;                       // the component carries the view
    e.Yaw = this.rig.yaw;
    e.Pitch = this.rig.pitch;
    e.Roll = this.rig.roll;
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
    if sq.SyncRaycastByCollisionPreset(this.rig.pos + fwd * 0.3, to, n"World Static", hit, true) {
      this.aim = Cast<Vector4>(hit.position);
      best = Vector4.Distance(this.rig.pos, this.aim);
    }
    let dyn: TraceResult;
    if sq.SyncRaycastByCollisionPreset(this.rig.pos + fwd * skip, to, n"World Dynamic", dyn, true) {
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

  private func SetKey(i: Int32, down: Bool) -> Void {
    if i >= 0 && i < ArraySize(this.m_keys) {
      this.m_keys[i] = down;
    }
  }

  public func OnGameAction(name: CName, type: gameinputActionType, value: Float) -> Bool {
    if this.m_state != 2 {
      return false;
    }
    let down = !Equals(type, gameinputActionType.BUTTON_RELEASED);
    switch name {
      case n"Forward": this.SetKey(CMCKey.W(), down); break;
      case n"Back": this.SetKey(CMCKey.S(), down); break;
      case n"Left": this.SetKey(CMCKey.A(), down); break;
      case n"Right": this.SetKey(CMCKey.D(), down); break;
      case n"RangedAttack":
      case n"ShootPrimary":
        this.SetKey(CMCKey.Lmb(), down);
        break;
      case n"CameraAim":
        this.SetKey(CMCKey.Rmb(), down);
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
    if this.m_state == 3 {
      // in the emplacement: \ leaves it too (not in the first half second, which is
      // the press that started it arriving through the raw channel)
      if Equals(event.GetKey(), EInputKey.IK_Backslash) && Equals(event.GetAction(), EInputAction.IACT_Press) && this.Now() - this.m_takeoverAt > 0.5 {
        this.End("EMPLACEMENT RELEASED", false);
      }
      // V: chase view <-> the turret's own sight view
      if Equals(event.GetKey(), EInputKey.IK_V) && Equals(event.GetAction(), EInputAction.IACT_Press) && this.m_takeoverSeen {
        this.m_chase = !this.m_chase;
        if this.m_chase {
          this.StartTakeoverCam();
        } else {
          this.StopTakeoverCam(true);
        }
      }
      return;
    }
    if this.m_state != 2 {
      return;
    }
    let action = event.GetAction();
    if Equals(action, EInputAction.IACT_Axis) {
      return;
    }
    let down = !Equals(action, EInputAction.IACT_Release);
    let press = Equals(action, EInputAction.IACT_Press);
    switch event.GetKey() {
      case EInputKey.IK_W: this.SetKey(CMCKey.W(), down); break;
      case EInputKey.IK_A: this.SetKey(CMCKey.A(), down); break;
      case EInputKey.IK_S: this.SetKey(CMCKey.S(), down); break;
      case EInputKey.IK_D: this.SetKey(CMCKey.D(), down); break;
      case EInputKey.IK_LeftMouse: this.SetKey(CMCKey.Lmb(), down); break;
      case EInputKey.IK_RightMouse: this.SetKey(CMCKey.Rmb(), down); break;
      case EInputKey.IK_MiddleMouse: this.SetKey(CMCKey.Mmb(), down); break;
      case EInputKey.IK_V:
        if press {
          this.SetChase(!this.m_chase);
          this.m_slow = 1.0;
        }
        break;
      case EInputKey.IK_B:
        if press {
          this.m_fireMode = CMFireMode.Next(this.m_fireMode);
          this.m_slow = 1.0;
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
      player.SetWarningMessage(StrReplaceAll(StrReplaceAll(msg, "!", ""), "*", ""));
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

public class CMCTakeoverCb extends DelayCallback {
  public let system: wref<CMCSession>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.BeginTakeover();
    }
  }
}

public class CMCTakeoverWatchCb extends DelayCallback {
  public let system: wref<CMCSession>;
  public let generation: Int32;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnTakeoverWatch(this.generation);
    }
  }
}

public class CMCDespawnCb extends DelayCallback {
  public let id: EntityID;
  public func Call() -> Void {
    GameInstance.GetStaticEntitySystem().DespawnEntity(this.id);
  }
}
