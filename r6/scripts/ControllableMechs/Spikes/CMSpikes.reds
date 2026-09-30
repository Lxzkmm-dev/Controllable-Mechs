// =============================================================================
// CONTROLLABLE MECHS - FRAMEWORK SPIKES, FIRST BATCH (dev only)
//
// Small in-game tests that settle the unknowns in docs/TECHNICAL_DESIGN.md
// before any framework code is written. Each one logs to TOOLS > LOG
// (tag CM-SPIKE) and asks one question on the SPIKES tab.
//   S0  a spawned vanilla security turret: befriend it, then take control of it
//       the way the Take Control quickhack does
//   S1  movable single parts: the whole MaxTac turret entity, and a lone HMG
//       mesh added to a host entity at assemble time, spun every frame
//   S2  firing: the linked mech's gun fired with V as the owner, and fired from
//       a chosen origin point (the fire call's position provider)
//   S4  a mesh component bound to another component, rotated in place
//   S5  the Minotaur's MK.31 meshes hidden/shown, and a Minotaur spawned with a
//       test HMG bound to its right weapon bone at assemble time
// Cost: nothing runs unless a test is active. The assemble hook is registered
// only while one of our spawns is waiting to assemble; the frame tick only
// while a spin/rotate/burst test runs.
// =============================================================================
module ControllableMechs

import TerminalKit.*

public abstract class CMSpikeKind {
  public static func S1Host() -> Int32 = 1
  public static func S4Host() -> Int32 = 2
  public static func S5Mech() -> Int32 = 3
}

public class CMSpikeSystem extends ScriptableSystem {
  // S0
  private let m_turretID: EntityID;
  private let m_takeMode: Int32;
  // S1
  private let m_maxtacID: EntityID;
  private let m_s1HostID: EntityID;
  private let m_s1Pos: Vector4;
  private let m_s1HostPos: Vector4;
  private let m_spin: Bool;
  private let m_spinYaw: Float;
  // S4
  private let m_s4ID: EntityID;
  private let m_s4Rotate: Bool;
  private let m_s4Yaw: Float;
  // S5
  private let m_s5ID: EntityID;
  private let m_gunsHidden: Bool;
  // S2
  private let m_burst: Int32;
  private let m_burstFrom: Int32;   // 0 = mech gun (owner V), 1 = from the marker origin
  private let m_burstNext: Float;
  // assemble hook
  private let m_pendingIDs: array<EntityID>;
  private let m_pendingKinds: array<Int32>;
  private let m_hookOn: Bool;
  private let m_listening: Bool;
  // frame tick
  private let m_gen: Int32;
  private let m_ticking: Bool;
  private let m_last: Float;

  public static func Get(game: GameInstance) -> ref<CMSpikeSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMSpikeSystem") as CMSpikeSystem;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    // a new session: nothing we spawned survives (none of it is saved)
    this.m_gen += 1;
    this.m_ticking = false;
    this.m_spin = false;
    this.m_s4Rotate = false;
    this.m_burst = 0;
    let empty: EntityID;
    this.m_turretID = empty;
    this.m_maxtacID = empty;
    this.m_s1HostID = empty;
    this.m_s4ID = empty;
    this.m_s5ID = empty;
    this.m_gunsHidden = false;
    ArrayClear(this.m_pendingIDs);
    ArrayClear(this.m_pendingKinds);
    this.HookOff();
  }

  public static func Log(text: String) -> Void {
    TKLog.Add("CM-SPIKE", text);
  }

  // ---------------------------------------------------------------------------
  // Placement helpers
  // ---------------------------------------------------------------------------
  // a point on the ground `ahead` metres in front of V and `side` metres to the right
  private func Ground(ahead: Float, side: Float) -> Vector4 {
    let player = GetPlayer(this.GetGameInstance());
    let f = player.GetWorldForward();
    let r = new Vector4(f.Y, -f.X, 0.0, 0.0);
    let p = player.GetWorldPosition() + f * ahead + r * side;
    let hit: TraceResult;
    let top = new Vector4(p.X, p.Y, p.Z + 3.0, 1.0);
    let bottom = new Vector4(p.X, p.Y, p.Z - 6.0, 1.0);
    if GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(top, bottom, n"Static", hit, true, false) {
      return Cast<Vector4>(hit.position);
    }
    return p;
  }

  private func FacingV() -> Quaternion {
    let player = GetPlayer(this.GetGameInstance());
    let e: EulerAngles;
    e.Yaw = CMPilotRig.YawOf(player.GetWorldForward());
    return EulerAngles.ToQuat(e);
  }

  private func SpawnStatic(path: ResRef, pos: Vector4, rot: Quaternion) -> EntityID {
    let spec = new StaticEntitySpec();
    spec.templatePath = path;
    spec.position = pos;
    spec.orientation = rot;
    spec.attached = true;
    return GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
  }

  private func Place(id: EntityID, pos: Vector4, yaw: Float) -> Void {
    let ent = GameInstance.FindEntityByID(this.GetGameInstance(), id);
    if !IsDefined(ent) {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, pos);
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, world);
    let e: EulerAngles;
    e.Yaw = yaw;
    WorldTransform.SetOrientation(wt, EulerAngles.ToQuat(e));
    ent.SetWorldTransform(wt);
  }

  // ---------------------------------------------------------------------------
  // Assemble hook: add our mesh components while an entity is being built
  // ---------------------------------------------------------------------------
  private func Expect(id: EntityID, kind: Int32) -> Void {
    ArrayPush(this.m_pendingIDs, id);
    ArrayPush(this.m_pendingKinds, kind);
    if !this.m_hookOn {
      GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Initialize", this, n"OnEntityInit");
      this.m_hookOn = true;
    }
    let cb = new CMSpikeHookTimeout();
    cb.system = this;
    cb.id = id;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 10.0, false);
  }

  private func HookOff() -> Void {
    if this.m_hookOn {
      GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Initialize", this, n"OnEntityInit");
      this.m_hookOn = false;
    }
  }

  public func HookTimeout(id: EntityID) -> Void {
    let i = 0;
    while i < ArraySize(this.m_pendingIDs) {
      if this.m_pendingIDs[i] == id {
        CMSpikeSystem.Log("assemble hook never fired for a spawned entity (kind " + IntToString(this.m_pendingKinds[i]) + "): Entity/Initialize may not cover this spawn route");
        ArrayErase(this.m_pendingIDs, i);
        ArrayErase(this.m_pendingKinds, i);
        break;
      }
      i += 1;
    }
    if ArraySize(this.m_pendingIDs) == 0 {
      this.HookOff();
    }
  }

  protected cb func OnEntityInit(event: ref<EntityLifecycleEvent>) -> Void {
    let ent = event.GetEntity();
    if !IsDefined(ent) {
      return;
    }
    let id = ent.GetEntityID();
    let i = 0;
    while i < ArraySize(this.m_pendingIDs) {
      if this.m_pendingIDs[i] == id {
        let kind = this.m_pendingKinds[i];
        ArrayErase(this.m_pendingIDs, i);
        ArrayErase(this.m_pendingKinds, i);
        this.Dress(ent, kind);
        break;
      }
      i += 1;
    }
    if ArraySize(this.m_pendingIDs) == 0 {
      this.HookOff();
    }
  }

  public static func Mesh(name: CName, path: ResRef) -> ref<MeshComponent> {
    let m = new MeshComponent();
    m.name = name;
    m.mesh *= path;
    m.meshAppearance = n"default";
    m.visualScale = new Vector3(1.0, 1.0, 1.0);
    m.isEnabled = true;
    return m;
  }

  private func Dress(ent: ref<Entity>, kind: Int32) -> Void {
    if kind == CMSpikeKind.S1Host() {
      ent.AddComponent(CMSpikeSystem.Mesh(n"cm_s1_gun", r"base\\environment\\decoration\\weapons\\hmg\\hmg_a.mesh"));
      CMSpikeSystem.Log("S1: lone HMG mesh added to its host at assemble time");
      return;
    }
    if kind == CMSpikeKind.S4Host() {
      let base = CMSpikeSystem.Mesh(n"cm_s4_base", r"base\\environment\\decoration\\weapons\\hmg\\hmg_a.mesh");
      ent.AddComponent(base);
      let gun = CMSpikeSystem.Mesh(n"cm_s4_gun", r"base\\environment\\decoration\\weapons\\hmg\\hmg_a.mesh");
      let b = new entHardTransformBinding();
      b.bindName = n"cm_s4_base";
      gun.parentTransform = b;
      let lt: WorldTransform;
      let wp: WorldPosition;
      WorldPosition.SetVector4(wp, new Vector4(0.0, 0.0, 0.6, 1.0));
      WorldTransform.SetWorldPosition(lt, wp);
      WorldTransform.SetOrientation(lt, CMPilotSystem.Identity());
      gun.localTransform = lt;
      ent.AddComponent(gun);
      CMSpikeSystem.Log("S4: two HMG meshes added, the upper one bound to the lower (cm_s4_base), 0.6 m above it");
      return;
    }
    if kind == CMSpikeKind.S5Mech() {
      let gun = CMSpikeSystem.Mesh(n"cm_s5_gun", r"base\\environment\\decoration\\weapons\\hmg\\hmg_a.mesh");
      let b = new entHardTransformBinding();
      b.bindName = n"root";
      b.slotName = n"r_weapon_jnt";
      gun.parentTransform = b;
      ent.AddComponent(gun);
      CMSpikeSystem.Log("S5: test HMG added to the Minotaur at assemble time, bound to root / r_weapon_jnt");
    }
  }

  // ---------------------------------------------------------------------------
  // S0: vanilla turret takeover
  // ---------------------------------------------------------------------------
  public func S0Spawn() -> String {
    if EntityID.IsDefined(this.m_turretID) {
      return "!A TEST TURRET IS ALREADY OUT";
    }
    this.Listen();
    let spec = new DynamicEntitySpec();
    spec.templatePath = r"base\\gameplay\\devices\\security_systems\\security_turret\\security_turret_1.ent";
    spec.position = this.Ground(4.0, 0.0);
    spec.orientation = this.FacingV();
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"CMSpikeTurret"];
    this.m_turretID = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    CMSpikeSystem.Log("S0: security_turret_1.ent spawned 4 m ahead");
    return "*TURRET INBOUND";
  }

  private func Listen() -> Void {
    if this.m_listening {
      return;
    }
    let des = GameInstance.GetDynamicEntitySystem();
    des.RegisterListener(n"CMSpikeTurret", this, n"OnSpikeEntity");
    des.RegisterListener(n"CMSpikeMech", this, n"OnSpikeEntity");
    this.m_listening = true;
  }

  protected cb func OnSpikeEntity(event: ref<DynamicEntityEvent>) -> Void {
    if NotEquals(event.GetEventType(), DynamicEntityEventType.Spawned) {
      return;
    }
    let game = this.GetGameInstance();
    let ent = GameInstance.GetDynamicEntitySystem().GetEntity(event.GetEntityID());
    if event.GetEntityID() == this.m_turretID {
      let turret = ent as SecurityTurret;
      if !IsDefined(turret) {
        CMSpikeSystem.Log("S0: the spawned entity is not a SecurityTurret");
        return;
      }
      // the Friendly Mode quickhack's path (as Night City Empires does it)
      let action = turret.GetDevicePS().ActionSetDeviceAttitude();
      action.SetExecutor(GetPlayer(game));
      turret.QueueEvent(action);
      CMSpikeSystem.Log("S0: turret spawned and set friendly");
      return;
    }
    if event.GetEntityID() == this.m_s5ID {
      let npc = ent as NPCPuppet;
      if IsDefined(npc) {
        CMSpikeSystem.Log("S5: test Minotaur spawned; linking it");
        CMLinkSystem.Get(game).Link(npc);
      }
    }
  }

  // mode 0: queue the Take Control quickhack action on the turret; 1: ask the TakeOverControlSystem
  public func S0TakeControl(mode: Int32) -> String {
    let turret = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_turretID) as SecurityTurret;
    if !IsDefined(turret) {
      return "!SPAWN THE TEST TURRET FIRST";
    }
    this.m_takeMode = mode;
    CMTerminal.CloseOpen(this.GetGameInstance());
    let cb = new CMSpikeTakeCb();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.4, false);
    return "";
  }

  public func DoTakeControl() -> Void {
    let game = this.GetGameInstance();
    let turret = GameInstance.FindEntityByID(game, this.m_turretID) as SecurityTurret;
    let player = GetPlayer(game);
    if !IsDefined(turret) || !IsDefined(player) {
      return;
    }
    let action = turret.GetDevicePS().ActionToggleTakeOverControl();
    action.SetExecutor(player);
    if this.m_takeMode == 0 {
      turret.QueueEvent(action);
      CMSpikeSystem.Log("S0: Take Control action queued on the turret (quickhack route)");
    } else {
      TakeOverControlSystem.RequestTakeControl(turret, action);
      CMSpikeSystem.Log("S0: TakeOverControlSystem.RequestTakeControl called (system route)");
    }
  }

  // ---------------------------------------------------------------------------
  // S1: movable single parts
  // ---------------------------------------------------------------------------
  public func S1Spawn() -> String {
    if EntityID.IsDefined(this.m_maxtacID) || EntityID.IsDefined(this.m_s1HostID) {
      return "!S1 PARTS ARE ALREADY OUT";
    }
    this.m_s1Pos = this.Ground(5.0, 2.5);
    this.m_s1HostPos = this.Ground(5.0, -2.5) + new Vector4(0.0, 0.0, 1.0, 0.0);
    this.m_maxtacID = this.SpawnStatic(r"base\\weapons\\turrets\\maxtac_turret\\w_turret__maxtac_turret__base1.ent", this.m_s1Pos, this.FacingV());
    this.m_s1HostID = this.SpawnStatic(r"base\\entities\\cameras\\simple_free_camera.ent", this.m_s1HostPos, CMPilotSystem.Identity());
    this.Expect(this.m_s1HostID, CMSpikeKind.S1Host());
    CMSpikeSystem.Log("S1: MaxTac turret entity spawned 2.5 m right; host for the lone HMG mesh spawned 2.5 m left, 1 m up");
    return "*S1 PARTS SPAWNED";
  }

  public func S1ToggleSpin() -> String {
    this.m_spin = !this.m_spin;
    this.m_spinYaw = 0.0;
    this.EnsureTick();
    CMSpikeSystem.Log("S1: spin " + (this.m_spin ? "on" : "off"));
    return this.m_spin ? "*SPINNING (45 DEG/S)" : "SPIN STOPPED";
  }

  // ---------------------------------------------------------------------------
  // S4: a component bound to another, rotated in place
  // ---------------------------------------------------------------------------
  public func S4Spawn() -> String {
    if EntityID.IsDefined(this.m_s4ID) {
      return "!S4 IS ALREADY OUT";
    }
    this.m_s4ID = this.SpawnStatic(r"base\\entities\\cameras\\simple_free_camera.ent", this.Ground(3.0, 0.0) + new Vector4(0.0, 0.0, 0.8, 0.0), CMPilotSystem.Identity());
    this.Expect(this.m_s4ID, CMSpikeKind.S4Host());
    CMSpikeSystem.Log("S4: host spawned 3 m ahead; two HMG meshes go on at assemble");
    return "*S4 SPAWNED";
  }

  public func S4ToggleRotate() -> String {
    this.m_s4Rotate = !this.m_s4Rotate;
    this.EnsureTick();
    let ent = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_s4ID);
    let gun = IsDefined(ent) ? ent.FindComponentByName(n"cm_s4_gun") as IPlacedComponent : null;
    CMSpikeSystem.Log("S4: rotate " + (this.m_s4Rotate ? "on" : "off") + ", upper gun component " + (IsDefined(gun) ? "found" : "NOT found"));
    return this.m_s4Rotate ? "*ROTATING THE UPPER GUN" : "ROTATION STOPPED";
  }

  // ---------------------------------------------------------------------------
  // S5: the Minotaur's own guns, and a gun bound to its arm bone
  // ---------------------------------------------------------------------------
  public func S5ToggleGuns() -> String {
    let mech = CMLinkSystem.Get(this.GetGameInstance()).Unit();
    if !IsDefined(mech) {
      return "!LINK A MINOTAUR FIRST";
    }
    this.m_gunsHidden = !this.m_gunsHidden;
    let found = 0;
    for name in [n"mch_003__minotaur_weapons_l_01", n"mch_003__minotaur_weapons_r_01"] {
      let c = mech.FindComponentByName(name);
      if IsDefined(c) {
        c.Toggle(!this.m_gunsHidden);
        found += 1;
      }
    }
    CMSpikeSystem.Log("S5: MK.31 mesh components found " + IntToString(found) + "/2, now " + (this.m_gunsHidden ? "hidden" : "shown"));
    if found == 0 {
      return "!NO MK.31 MESH COMPONENTS FOUND (SEE LOG)";
    }
    return this.m_gunsHidden ? "*MK.31 MESHES HIDDEN" : "*MK.31 MESHES SHOWN";
  }

  public func S5SpawnMech() -> String {
    if EntityID.IsDefined(this.m_s5ID) {
      return "!THE S5 MINOTAUR IS ALREADY OUT";
    }
    this.Listen();
    let spec = new DynamicEntitySpec();
    spec.recordID = t"Character.q003_militech_mech";
    spec.position = this.Ground(14.0, 0.0);
    let face: EulerAngles;
    face.Yaw = CMPilotRig.YawOf(GetPlayer(this.GetGameInstance()).GetWorldForward()) + 180.0;
    spec.orientation = EulerAngles.ToQuat(face);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"CMSpikeMech"];
    this.m_s5ID = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    this.Expect(this.m_s5ID, CMSpikeKind.S5Mech());
    CMSpikeSystem.Log("S5: Minotaur spawned 14 m ahead; the test gun goes on at assemble");
    return "*MINOTAUR WITH TEST GUN INBOUND";
  }

  // ---------------------------------------------------------------------------
  // S2: firing
  // ---------------------------------------------------------------------------
  // from: 0 = the mech's right gun with V as the owner; 1 = the same, from a marker point
  public func S2Burst(from: Int32) -> String {
    let mech = CMLinkSystem.Get(this.GetGameInstance()).Unit();
    if !IsDefined(mech) || !IsDefined(ScriptedPuppet.GetWeaponRight(mech)) {
      return "!LINK A MECH WITH A WEAPON FIRST";
    }
    this.m_burst = 10;
    this.m_burstFrom = from;
    this.m_burstNext = 0.0;
    this.EnsureTick();
    CMSpikeSystem.Log("S2" + (from == 0 ? "a" : "b") + ": 10-round burst at V's crosshair, owner V" + (from == 1 ? ", origin 1.5 m right of and 2 m above V" : ""));
    return "*FIRING";
  }

  private func FireOnce() -> Void {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let mech = CMLinkSystem.Get(game).Unit();
    if !IsDefined(player) || !IsDefined(mech) {
      this.m_burst = 0;
      return;
    }
    let weapon = ScriptedPuppet.GetWeaponRight(mech);
    if !IsDefined(weapon) {
      this.m_burst = 0;
      return;
    }
    // aim: what V's crosshair is on
    let cam = player.GetFPPCameraComponent().GetLocalToWorld().GetTranslation();
    let fwd = GameInstance.GetCameraSystem(game).GetActiveCameraForward();
    let to = cam + fwd * 150.0;
    let hit: TraceResult;
    if GameInstance.GetSpatialQueriesSystem(game).SyncRaycastByCollisionPreset(cam + fwd * 1.0, to, n"World Static", hit, true) {
      to = Cast<Vector4>(hit.position);
    }
    let now = EngineTime.ToFloat(GameInstance.GetSimTime(game));
    let noTarget: ref<GameObject>;
    let noAttack: TweakDBID;
    let zero = new Vector4(0.0, 0.0, 0.0, 0.0);
    let provider: ref<IPositionProvider>;
    if this.m_burstFrom == 1 {
      let f = player.GetWorldForward();
      let origin = player.GetWorldPosition() + new Vector4(f.Y, -f.X, 0.0, 0.0) * 1.5 + new Vector4(0.0, 0.0, 2.0, 0.0);
      let wp: WorldPosition;
      WorldPosition.SetVector4(wp, origin);
      provider = IPositionProvider.CreateStaticPositionProvider(wp);
    }
    AIWeapon.Fire(player, weapon, now, 0.0, gamedataTriggerMode.FullAuto, to, noTarget, noAttack, 0.0, 0.0, zero, false, 0.0, provider, zero, n"");
  }

  // ---------------------------------------------------------------------------
  // Frame tick: only while spin / rotate / burst is active
  // ---------------------------------------------------------------------------
  private func EnsureTick() -> Void {
    if this.m_ticking {
      return;
    }
    if !this.m_spin && !this.m_s4Rotate && this.m_burst <= 0 {
      return;
    }
    this.m_ticking = true;
    this.m_gen += 1;
    this.m_last = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()));
    this.Queue();
  }

  private func Queue() -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      this.m_ticking = false;
      return;
    }
    player.m_cmSpikes = this;
    let evt = new CMSpikeTickEvent();
    evt.generation = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayEventNextFrame(player, evt);
  }

  public func OnFrame(generation: Int32) -> Void {
    if generation != this.m_gen || !this.m_ticking {
      return;
    }
    if !this.m_spin && !this.m_s4Rotate && this.m_burst <= 0 {
      this.m_ticking = false;
      return;
    }
    let now = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()));
    let dt = ClampF(now - this.m_last, 0.0, 0.1);
    this.m_last = now;
    if dt <= 0.0 {
      dt = 0.016;
    }
    if this.m_spin {
      this.m_spinYaw = CMPilotRig.Wrap(this.m_spinYaw + 45.0 * dt);
      this.Place(this.m_maxtacID, this.m_s1Pos, this.m_spinYaw);
      this.Place(this.m_s1HostID, this.m_s1HostPos, this.m_spinYaw);
    }
    if this.m_s4Rotate {
      this.m_s4Yaw = CMPilotRig.Wrap(this.m_s4Yaw + 60.0 * dt);
      let ent = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_s4ID);
      let gun = IsDefined(ent) ? ent.FindComponentByName(n"cm_s4_gun") as IPlacedComponent : null;
      if IsDefined(gun) {
        let e: EulerAngles;
        e.Yaw = this.m_s4Yaw;
        gun.SetLocalOrientation(EulerAngles.ToQuat(e));
      }
    }
    if this.m_burst > 0 && now >= this.m_burstNext {
      this.FireOnce();
      this.m_burst -= 1;
      this.m_burstNext = now + 0.12;
    }
    this.Queue();
  }

  // ---------------------------------------------------------------------------
  // Clean-up
  // ---------------------------------------------------------------------------
  public func DespawnAll() -> String {
    let game = this.GetGameInstance();
    this.m_spin = false;
    this.m_s4Rotate = false;
    this.m_burst = 0;
    this.m_ticking = false;
    this.m_gen += 1;
    if EntityID.IsDefined(this.m_turretID) {
      GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_turretID);
    }
    if EntityID.IsDefined(this.m_s5ID) {
      let link = CMLinkSystem.Get(game);
      if link.IsLinked() && link.Unit().GetEntityID() == this.m_s5ID {
        link.Unlink();
      }
      GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_s5ID);
    }
    for id in [this.m_maxtacID, this.m_s1HostID, this.m_s4ID] {
      if EntityID.IsDefined(id) {
        GameInstance.GetStaticEntitySystem().DespawnEntity(id);
      }
    }
    let empty: EntityID;
    this.m_turretID = empty;
    this.m_maxtacID = empty;
    this.m_s1HostID = empty;
    this.m_s4ID = empty;
    this.m_s5ID = empty;
    CMSpikeSystem.Log("all spike objects removed");
    return "SPIKE OBJECTS REMOVED";
  }

  public func Has(which: Int32) -> Bool {
    switch which {
      case 0: return EntityID.IsDefined(this.m_turretID);
      case 1: return EntityID.IsDefined(this.m_maxtacID) || EntityID.IsDefined(this.m_s1HostID);
      case 4: return EntityID.IsDefined(this.m_s4ID);
      case 5: return EntityID.IsDefined(this.m_s5ID);
    }
    return false;
  }

  public func Spinning() -> Bool = this.m_spin
  public func Rotating() -> Bool = this.m_s4Rotate
  public func GunsHidden() -> Bool = this.m_gunsHidden

  // ---------------------------------------------------------------------------
  // The SPIKES page (dev only)
  // ---------------------------------------------------------------------------
  public func Page(p: ref<TKPage>) -> Void {
    p.SetTitle("SPIKES", "Framework tests, first batch. Results go to TOOLS > LOG (tag CM-SPIKE).");
    p.SetSection("spikes");

    p.Heading("S0  VANILLA TURRET TAKEOVER");
    p.Item("SPAWN A SECURITY TURRET", "4 m ahead of you, set friendly.", "", this.Has(0) ? "!SPAWNED" : "SPAWN", "sp_s0", "", !this.Has(0));
    p.Buttons("Take control of it", "", "", "QUICKHACK ROUTE|SYSTEM ROUTE", "sp_s0take|sp_s0take", "0|1");
    p.ItemNote("Question: does the view switch into the turret, can you aim and fire it, do its barrel, flash and rounds line up, and how do you get out?");

    p.Heading("S1  MOVABLE SINGLE PARTS");
    p.Item("SPAWN THE PARTS", "Right: the whole MaxTac turret entity. Left: a lone HMG mesh on a host entity.", "", this.Has(1) ? "!SPAWNED" : "SPAWN", "sp_s1", "", !this.Has(1));
    p.Item("SPIN THEM", "Both turn at 45 deg/s, placed every frame.", "", this.Spinning() ? "STOP" : "SPIN", "sp_s1spin", "", true);
    p.ItemNote("Question: do both appear, and do they spin smoothly on the spot?");

    p.Heading("S2  FIRING (LINK A MECH FIRST)");
    p.Buttons("10-round burst at your crosshair, V as the owner", "", "", "FROM THE MECH GUN|FROM A MARKER POINT", "sp_s2|sp_s2", "0|1");
    p.ItemNote("Question: where do the tracers start (the mech's gun, or a point 1.5 m right of and 2 m above V), do the rounds hit your crosshair and deal damage, and does a kill count as V's (XP, enemies turning on V)?");

    p.Heading("S4  A PART BOUND TO ANOTHER, ROTATED IN PLACE");
    p.Item("SPAWN", "Two HMG meshes on one host, the upper bound to the lower.", "", this.Has(4) ? "!SPAWNED" : "SPAWN", "sp_s4", "", !this.Has(4));
    p.Item("ROTATE THE UPPER GUN", "Turns only the upper component, 60 deg/s.", "", this.Rotating() ? "STOP" : "ROTATE", "sp_s4rot", "", true);
    p.ItemNote("Question: do you see two guns, 0.6 m apart, and does only the upper one turn?");

    p.Heading("S5  MINOTAUR GUNS");
    p.Item("HIDE / SHOW THE MK.31s", "On the linked Minotaur.", "", this.GunsHidden() ? "SHOW" : "HIDE", "sp_s5guns", "", true);
    p.Item("SPAWN A MINOTAUR WITH A TEST GUN", "An HMG mesh bound to its right weapon bone, then linked.", "", this.Has(5) ? "!SPAWNED" : "SPAWN", "sp_s5mech", "", !this.Has(5));
    p.ItemNote("Question: do the MK.31s vanish and come back, and does the test HMG sit on the right arm and move with it when the mech walks (pilot it), without trailing?");

    p.Gap();
    p.Button("REMOVE ALL SPIKE OBJECTS", "sp_clear", "", true);
  }

  public func Act(p: ref<TKPage>, action: String, arg: String) -> Bool {
    let msg = "";
    switch action {
      case "sp_s0": msg = this.S0Spawn(); break;
      case "sp_s0take": msg = this.S0TakeControl(StringToInt(arg, 0)); break;
      case "sp_s1": msg = this.S1Spawn(); break;
      case "sp_s1spin": msg = this.S1ToggleSpin(); break;
      case "sp_s2": msg = this.S2Burst(StringToInt(arg, 0)); break;
      case "sp_s4": msg = this.S4Spawn(); break;
      case "sp_s4rot": msg = this.S4ToggleRotate(); break;
      case "sp_s5guns": msg = this.S5ToggleGuns(); break;
      case "sp_s5mech": msg = this.S5SpawnMech(); break;
      case "sp_clear": msg = this.DespawnAll(); break;
      default: return false;
    }
    if StrLen(msg) > 0 {
      p.SetMessage(msg);
    }
    return true;
  }
}

// ---- the spike frame tick: an event V receives next frame (only while a test runs) ----
public class CMSpikeTickEvent extends Event {
  public let generation: Int32;
}

@addField(PlayerPuppet)
public let m_cmSpikes: wref<CMSpikeSystem>;

@addMethod(PlayerPuppet)
protected cb func OnCMSpikeTick(evt: ref<CMSpikeTickEvent>) -> Bool {
  if IsDefined(this.m_cmSpikes) {
    this.m_cmSpikes.OnFrame(evt.generation);
  }
  return true;
}

public class CMSpikeTakeCb extends DelayCallback {
  public let system: wref<CMSpikeSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.DoTakeControl();
    }
  }
}

public class CMSpikeHookTimeout extends DelayCallback {
  public let system: wref<CMSpikeSystem>;
  public let id: EntityID;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.HookTimeout(this.id);
    }
  }
}
