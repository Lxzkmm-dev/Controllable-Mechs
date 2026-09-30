// =============================================================================
// CONTROLLABLE MECHS - FRAMEWORK SPIKES, SECOND BATCH (dev only)
//
// Follow-ups to the first batch (Omar's report in the design doc):
//   S2b  damage credited to V. Batch 1's rounds (mech gun, V as owner) hit the
//        crosshair but did no damage. Four routes side by side, each logging the
//        target's health before and after the burst.
//   S5b  a gun that follows the Minotaur's arm. Batch 1's bound HMG never showed.
//        Three bone bindings added at Entity/Assemble (when the appearance's
//        components exist), plus a fallback placed every frame at the MK.31
//        weapon item's transform. The MK.31 meshes are hidden automatically.
//   S6   look-at requests on the Minotaur's gun parts (LeftWeapon, RightWeapon,
//        Weapon, Chassis) and the arm IK inputs, toward V's crosshair, with the
//        guns' aim error logged before and after.
// Everything logs to TOOLS > LOG (tag CM-SPIKE) and to the redscript log.
// Cost: nothing runs unless a test is active. The assemble hook is registered
// only while our Minotaur is waiting to assemble (and filtered to its record);
// the frame tick only while a burst or the follow test runs.
// =============================================================================
module ControllableMechs

import TerminalKit.*

public class CMSpike2System extends ScriptableSystem {
  // S2b
  private let m_burst: Int32;
  private let m_mode: Int32;          // 0 owner mech, 1 V + player attack, 2 V + NPC attack, 3 V tracers + V hit
  private let m_fromMarker: Bool;
  private let m_next: Float;
  private let m_target: wref<GameObject>;
  private let m_targetHP: Float;
  private let m_recordWarned: Bool;
  // S5b
  private let m_mechID: EntityID;
  private let m_bind: Int32;          // 0 anim root, 1 gun mesh, 2 arm mesh, 3 follow each frame
  private let m_hostID: EntityID;     // the follow test's gun host
  private let m_follow: Bool;
  private let m_assembleOn: Bool;
  private let m_initOn: Bool;
  private let m_listening: Bool;
  // S6
  private let m_lookAts: array<ref<LookAtAddEvent>>;
  private let m_iks: array<ref<IKTargetAddEvent>>;
  private let m_s6Aim: Vector4;
  // frame tick
  private let m_gen: Int32;
  private let m_ticking: Bool;

  public static func Get(game: GameInstance) -> ref<CMSpike2System> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMSpike2System") as CMSpike2System;
  }

  public static func Minotaur() -> TweakDBID = t"Character.q003_militech_mech"
  public static func Hmg() -> ResRef = r"base\\environment\\decoration\\weapons\\hmg\\hmg_a.mesh"

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    // a new session: nothing we spawned survives (none of it is saved)
    this.m_gen += 1;
    this.m_ticking = false;
    this.m_burst = 0;
    this.m_follow = false;
    let empty: EntityID;
    this.m_mechID = empty;
    this.m_hostID = empty;
    ArrayClear(this.m_lookAts);
    ArrayClear(this.m_iks);
    this.AssembleOff();
    this.InitOff();
  }

  private func Log(text: String) -> Void {
    CMSpikeSystem.Log(text);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  private func Mech() -> ref<NPCPuppet> = CMLinkSystem.Get(this.GetGameInstance()).Unit()

  // what V's crosshair is on: the nearest static or dynamic hit within 150 m
  private func AimPoint() -> Vector4 {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let cam = player.GetFPPCameraComponent().GetLocalToWorld().GetTranslation();
    let fwd = GameInstance.GetCameraSystem(game).GetActiveCameraForward();
    let to = cam + fwd * 150.0;
    let best = to;
    let bestD = 150.0;
    let sq = GameInstance.GetSpatialQueriesSystem(game);
    for preset in [n"World Static", n"World Dynamic"] {
      let hit: TraceResult;
      if sq.SyncRaycastByCollisionPreset(cam + fwd * 1.0, to, preset, hit, true) {
        let p = Cast<Vector4>(hit.position);
        let d = Vector4.Distance(cam, p);
        if d < bestD {
          bestD = d;
          best = p;
        }
      }
    }
    return best;
  }

  public static func Health(obj: ref<GameObject>) -> Float {
    if !IsDefined(obj) {
      return -1.0;
    }
    return GameInstance.GetStatPoolsSystem(obj.GetGame()).GetStatPoolValue(Cast<StatsObjectID>(obj.GetEntityID()), gamedataStatPoolType.Health, false);
  }

  public static func Describe(obj: ref<GameObject>) -> String {
    if !IsDefined(obj) {
      return "nothing (no object under the crosshair)";
    }
    let s = NameToString(obj.GetClassName());
    let puppet = obj as ScriptedPuppet;
    if IsDefined(puppet) {
      s += " " + TDBID.ToStringDEBUG(puppet.GetRecordID());
    }
    return s;
  }

  private static func V(v: Vector4) -> String {
    return "(" + FloatToStringPrec(v.X, 2) + ", " + FloatToStringPrec(v.Y, 2) + ", " + FloatToStringPrec(v.Z, 2) + ")";
  }

  // angle between a weapon's forward and the direction from it to a point
  public static func AimError(weapon: ref<GameObject>, at: Vector4) -> Float {
    if !IsDefined(weapon) {
      return -1.0;
    }
    let to = Vector4.Normalize(at - weapon.GetWorldPosition());
    let fwd = Vector4.Normalize(weapon.GetWorldForward());
    return Rad2Deg(AcosF(ClampF(Vector4.Dot(to, fwd), -1.0, 1.0)));
  }

  private func SetMk31(mech: ref<Entity>, show: Bool) -> Int32 {
    let found = 0;
    for name in [n"mch_003__minotaur_weapons_l_01", n"mch_003__minotaur_weapons_r_01"] {
      let c = mech.FindComponentByName(name);
      if IsDefined(c) {
        c.Toggle(show);
        found += 1;
      }
    }
    return found;
  }

  // ---------------------------------------------------------------------------
  // S2b: damage credited to V
  // ---------------------------------------------------------------------------
  public static func ModeName(mode: Int32) -> String {
    switch mode {
      case 0: return "OWNER MECH";
      case 1: return "OWNER V + PLAYER ATTACK";
      case 2: return "OWNER V + NPC ATTACK";
      case 4: return "S2c VANILLA TURRET CALL (V, ALONG THE BARREL)";
      case 5: return "S2c VANILLA CALL + TARGET POINT";
      case 6: return "S2c OWNER MECH, ALONG THE BARREL";
    }
    return "V TRACERS + V HIT";
  }

  public func ToggleOrigin() -> String {
    this.m_fromMarker = !this.m_fromMarker;
    return this.m_fromMarker ? "*ORIGIN: MARKER POINT" : "*ORIGIN: MECH GUN";
  }

  public func FromMarker() -> Bool = this.m_fromMarker

  public func S2bBurst(mode: Int32) -> String {
    let game = this.GetGameInstance();
    let mech = this.Mech();
    let weapon = IsDefined(mech) ? ScriptedPuppet.GetWeaponRight(mech) : null;
    if !IsDefined(weapon) {
      return "!LINK A MECH WITH A WEAPON FIRST";
    }
    if this.m_burst > 0 {
      return "!A BURST IS STILL FIRING";
    }
    let player = GetPlayer(game);
    this.m_target = GameInstance.GetTargetingSystem(game).GetLookAtObject(player);
    this.m_targetHP = CMSpike2System.Health(this.m_target);
    this.m_mode = mode;
    this.m_burst = 10;
    this.m_next = 0.0;
    let line = "S2b " + CMSpike2System.ModeName(mode) + (this.m_fromMarker ? ", from the marker point" : ", from the mech gun")
      + ": target " + CMSpike2System.Describe(this.m_target) + ", health " + FloatToStringPrec(this.m_targetHP, 1);
    if mode == 1 || mode == 2 {
      line += ", attack " + TDBID.ToStringDEBUG(CMSpike2System.AttackOf(weapon, mode == 1));
    }
    this.Log(line);
    this.EnsureTick();
    return "*FIRING: " + CMSpike2System.ModeName(mode);
  }

  // S2c: fire the way a V-controlled vanilla turret does (securityTurret.script,
  // ShootAttachedWeapon: AIWeapon.Fire(player, weapon, simTime, 1.0, triggerMode)).
  // The guns are first aimed at the crosshair with the S6 look-at (all four parts),
  // and the burst starts 1.5 s later, once they have turned.
  public func S2cBurst(mode: Int32) -> String {
    let msg = this.S6LookAt(4);
    if StrBeginsWith(msg, "!") {
      return msg;
    }
    msg = this.S2bBurst(mode);
    if StrBeginsWith(msg, "!") {
      return msg;
    }
    this.m_next = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance())) + 1.5;
    return "*GUNS TURNING, THEN " + msg;
  }

  private static func AttackOf(weapon: ref<WeaponObject>, player: Bool) -> TweakDBID {
    let none: TweakDBID;
    let rec = weapon.GetWeaponRecord();
    if !IsDefined(rec) || !IsDefined(rec.RangedAttacks()) || !IsDefined(rec.RangedAttacks().DefaultFire()) {
      return none;
    }
    let attack = player ? rec.RangedAttacks().DefaultFire().PlayerAttack() : rec.RangedAttacks().DefaultFire().NPCAttack();
    return IsDefined(attack) ? attack.GetID() : none;
  }

  private func FireOnce() -> Void {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    let mech = this.Mech();
    let weapon = IsDefined(mech) ? ScriptedPuppet.GetWeaponRight(mech) : null;
    if !IsDefined(player) || !IsDefined(weapon) {
      this.m_burst = 0;
      return;
    }
    let to = this.AimPoint();
    let now = EngineTime.ToFloat(GameInstance.GetSimTime(game));
    if this.m_mode >= 4 {
      let trigger = gamedataTriggerMode.FullAuto;
      let rec = weapon.GetWeaponRecord();
      if IsDefined(rec) && IsDefined(rec.PrimaryTriggerMode()) {
        trigger = rec.PrimaryTriggerMode().Type();
      }
      switch this.m_mode {
        case 4:
          AIWeapon.Fire(player, weapon, now, 1.0, trigger);
          break;
        case 5:
          AIWeapon.Fire(player, weapon, now, 1.0, trigger, to);
          break;
        default:
          AIWeapon.Fire(mech, weapon, now, 1.0, trigger);
          break;
      }
      return;
    }
    let noTarget: ref<GameObject>;
    let attack: TweakDBID;
    if this.m_mode == 1 || this.m_mode == 2 {
      attack = CMSpike2System.AttackOf(weapon, this.m_mode == 1);
    }
    let zero = new Vector4(0.0, 0.0, 0.0, 0.0);
    let provider: ref<IPositionProvider>;
    if this.m_fromMarker {
      let f = player.GetWorldForward();
      let origin = player.GetWorldPosition() + new Vector4(f.Y, -f.X, 0.0, 0.0) * 1.5 + new Vector4(0.0, 0.0, 2.0, 0.0);
      let wp: WorldPosition;
      WorldPosition.SetVector4(wp, origin);
      provider = IPositionProvider.CreateStaticPositionProvider(wp);
    }
    let owner: ref<GameObject> = player;
    if this.m_mode == 0 {
      owner = mech;
    }
    AIWeapon.Fire(owner, weapon, now, 0.0, gamedataTriggerMode.FullAuto, to, noTarget, attack, 0.0, 0.0, zero, false, 0.0, provider, zero, n"");
    if this.m_mode == 3 {
      // the hit itself, with V as the instigator: on the target's body when there is one
      let at = to;
      if IsDefined(this.m_target) {
        at = this.m_target.GetWorldPosition() + new Vector4(0.0, 0.0, 1.0, 0.0);
      }
      this.HitAt(player, at);
    }
  }

  // one round's hit: a small area attack at the point, V as instigator and source
  // (the Dead Shot sequence: create, add damage, prepare, fill shared data, start)
  private func HitAt(player: ref<PlayerPuppet>, at: Vector4) -> Void {
    let record = TweakDBInterface.GetAttackRecord(t"Attacks.CM_SpikeHMGRound") as Attack_GameEffect_Record;
    if !IsDefined(record) {
      if !this.m_recordWarned {
        this.Log("S2b: Attacks.CM_SpikeHMGRound missing (TweakXL did not load r6/tweaks/ControllableMechs/spikes.yaml); using Attacks.BaseProjectileAoEAttack");
        this.m_recordWarned = true;
      }
      record = TweakDBInterface.GetAttackRecord(t"Attacks.BaseProjectileAoEAttack") as Attack_GameEffect_Record;
    }
    if !IsDefined(record) {
      this.Log("S2b: no attack record to hit with");
      return;
    }
    let ctx: AttackInitContext;
    ctx.record = record;
    ctx.instigator = player;
    ctx.source = player;
    let attack = IAttack.Create(ctx) as Attack_GameEffect;
    if !IsDefined(attack) {
      this.Log("S2b: IAttack.Create returned nothing");
      return;
    }
    attack.AddStatModifier(RPGManager.CreateStatModifier(gamedataStatType.PhysicalDamage, gameStatModifierType.Additive, 45.0));
    let statMods: array<ref<gameStatModifierData>>;
    attack.GetStatModList(statMods);
    let flags: array<SHitFlag>;
    let effect = attack.PrepareAttack(player);
    EffectData.SetFloat(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.radius, 1.0);
    EffectData.SetVector(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.position, at);
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.attack, ToVariant(attack));
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.attackStatModList, ToVariant(statMods));
    EffectData.SetVariant(effect.GetSharedData(), GetAllBlackboardDefs().EffectSharedData.flags, ToVariant(flags));
    attack.StartAttack();
  }

  public func S2bReport() -> Void {
    let hp = CMSpike2System.Health(this.m_target);
    let line = "S2b " + CMSpike2System.ModeName(this.m_mode) + " result: target " + CMSpike2System.Describe(this.m_target);
    if IsDefined(this.m_target) {
      line += ", health " + FloatToStringPrec(this.m_targetHP, 1) + " -> " + FloatToStringPrec(hp, 1) + " (" + FloatToStringPrec(this.m_targetHP - hp, 1) + " damage)";
      let puppet = this.m_target as ScriptedPuppet;
      if IsDefined(puppet) {
        line += puppet.IsDead() ? ", DEAD" : ", alive";
      }
    }
    this.Log(line);
    if this.m_mode >= 4 {
      this.S6Clear();
    }
  }

  // ---------------------------------------------------------------------------
  // S5b: a gun that follows the Minotaur's arm
  // ---------------------------------------------------------------------------
  public static func BindName(bind: Int32) -> String {
    switch bind {
      case 0: return "BIND TO THE ANIM ROOT";
      case 1: return "BIND TO THE MK.31 MESH";
      case 2: return "BIND TO THE ARM MESH";
    }
    return "FOLLOW EACH FRAME";
  }

  private static func BindParent(bind: Int32) -> CName {
    switch bind {
      case 0: return n"root";
      case 1: return n"mch_003__minotaur_weapons_r_01";
    }
    return n"mch_003__minotaur_arm_r_01";
  }

  public func HasMech() -> Bool = EntityID.IsDefined(this.m_mechID)

  public func S5bSpawn(bind: Int32) -> String {
    if EntityID.IsDefined(this.m_mechID) {
      return "!REMOVE THE S5B MINOTAUR FIRST";
    }
    let game = this.GetGameInstance();
    this.m_bind = bind;
    this.Listen();
    if bind < 3 {
      this.AssembleOn();
    }
    let player = GetPlayer(game);
    let f = player.GetWorldForward();
    let spec = new DynamicEntitySpec();
    spec.recordID = CMSpike2System.Minotaur();
    spec.position = player.GetWorldPosition() + f * 14.0;
    let face: EulerAngles;
    face.Yaw = CMPilotRig.YawOf(f) + 180.0;
    spec.orientation = EulerAngles.ToQuat(face);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"CMSpike2Mech"];
    this.m_mechID = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    this.Log("S5b " + CMSpike2System.BindName(bind) + ": Minotaur spawning 14 m ahead");
    return "*MINOTAUR INBOUND: " + CMSpike2System.BindName(bind);
  }

  private func Listen() -> Void {
    if this.m_listening {
      return;
    }
    GameInstance.GetDynamicEntitySystem().RegisterListener(n"CMSpike2Mech", this, n"OnSpike2Entity");
    this.m_listening = true;
  }

  private func AssembleOn() -> Void {
    if this.m_assembleOn {
      return;
    }
    // no record filter: with one, the hook never fired for the spawned Minotaur (batch 2 log).
    // Registered only until our mech spawns, and the handler checks the ID first.
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Assemble", this, n"OnMechAssemble");
    this.m_assembleOn = true;
  }

  private func AssembleOff() -> Void {
    if this.m_assembleOn {
      GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Assemble", this, n"OnMechAssemble");
      this.m_assembleOn = false;
    }
  }

  private func InitOn() -> Void {
    if this.m_initOn {
      return;
    }
    GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/Initialize", this, n"OnHostInit");
    this.m_initOn = true;
  }

  private func InitOff() -> Void {
    if this.m_initOn {
      GameInstance.GetCallbackSystem().UnregisterCallback(n"Entity/Initialize", this, n"OnHostInit");
      this.m_initOn = false;
    }
  }

  // the appearance's components exist here, so the gun can be bound to them
  protected cb func OnMechAssemble(event: ref<EntityLifecycleEvent>) -> Void {
    let ent = event.GetEntity();
    if !IsDefined(ent) || ent.GetEntityID() != this.m_mechID {
      return;
    }
    this.AssembleOff();
    let comps = ent.GetComponents();
    let names = "";
    for c in comps {
      names += (StrLen(names) > 0 ? ", " : "") + NameToString(c.GetName());
    }
    this.Log("S5b: Entity/Assemble fired, " + IntToString(ArraySize(comps)) + " components: " + names);
    let parentName = CMSpike2System.BindParent(this.m_bind);
    let parent = ent.FindComponentByName(parentName);
    this.Log("S5b: bind parent " + NameToString(parentName) + (IsDefined(parent) ? " found (" + NameToString(parent.GetClassName()) + ")" : " NOT found"));
    let gun = CMSpikeSystem.Mesh(n"cm_s5b_gun", CMSpike2System.Hmg());
    let b = new entHardTransformBinding();
    b.bindName = parentName;
    b.slotName = n"r_weapon_jnt";
    gun.parentTransform = b;
    ent.AddComponent(gun);
    this.Log("S5b: test gun added, bound to " + NameToString(parentName) + " / r_weapon_jnt; component present after add: " + (IsDefined(ent.FindComponentByName(n"cm_s5b_gun")) ? "yes" : "NO"));
  }

  protected cb func OnSpike2Entity(event: ref<DynamicEntityEvent>) -> Void {
    if NotEquals(event.GetEventType(), DynamicEntityEventType.Spawned) || event.GetEntityID() != this.m_mechID {
      return;
    }
    let game = this.GetGameInstance();
    let npc = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_mechID) as NPCPuppet;
    if !IsDefined(npc) {
      this.Log("S5b: the spawned entity is not an NPCPuppet");
      return;
    }
    if this.m_assembleOn {
      this.Log("S5b: Entity/Assemble never fired for our Minotaur before it spawned");
      this.AssembleOff();
    }
    CMLinkSystem.Get(game).Link(npc);
    this.Log("S5b: Minotaur spawned and linked; MK.31 meshes hidden: " + IntToString(this.SetMk31(npc, false)) + "/2");
    if this.m_bind == 3 {
      this.InitOn();
      let spec = new StaticEntitySpec();
      spec.templatePath = r"base\\entities\\cameras\\simple_free_camera.ent";
      spec.position = npc.GetWorldPosition();
      spec.orientation = CMPilotSystem.Identity();
      spec.attached = true;
      this.m_hostID = GameInstance.GetStaticEntitySystem().SpawnEntity(spec);
      this.m_follow = true;
      this.EnsureTick();
    }
    let cb = new CMSpike2CheckCb();
    cb.system = this;
    GameInstance.GetDelaySystem(game).DelayCallback(cb, 2.0, false);
  }

  protected cb func OnHostInit(event: ref<EntityLifecycleEvent>) -> Void {
    let ent = event.GetEntity();
    if !IsDefined(ent) || ent.GetEntityID() != this.m_hostID {
      return;
    }
    this.InitOff();
    ent.AddComponent(CMSpikeSystem.Mesh(n"cm_s5b_gun", CMSpike2System.Hmg()));
    this.Log("S5b: follow host dressed with the test gun");
  }

  // where the test gun is against where the MK.31 weapon item is (it tracks the arm)
  public func S5bCheck() -> String {
    let game = this.GetGameInstance();
    let mech = GameInstance.FindEntityByID(game, this.m_mechID) as NPCPuppet;
    if !IsDefined(mech) {
      return "!SPAWN AN S5B MINOTAUR FIRST";
    }
    let weapon = ScriptedPuppet.GetWeaponRight(mech);
    let wpos = IsDefined(weapon) ? weapon.GetWorldPosition() : mech.GetWorldPosition();
    let holder: ref<Entity> = mech;
    if this.m_bind == 3 {
      holder = GameInstance.FindEntityByID(game, this.m_hostID);
    }
    let gun = IsDefined(holder) ? holder.FindComponentByName(n"cm_s5b_gun") as IPlacedComponent : null;
    let line = "S5b check (" + CMSpike2System.BindName(this.m_bind) + "): right weapon item at " + CMSpike2System.V(wpos);
    if IsDefined(gun) {
      let gpos = gun.GetLocalToWorld().GetTranslation();
      line += "; test gun " + (gun.IsEnabled() ? "enabled" : "DISABLED") + " at " + CMSpike2System.V(gpos) + ", " + FloatToStringPrec(Vector4.Distance(gpos, wpos), 2) + " m from the weapon item, "
        + FloatToStringPrec(Vector4.Distance(gpos, mech.GetWorldPosition()), 2) + " m from the mech's feet";
    } else {
      line += "; test gun component NOT found";
    }
    this.Log(line);
    // slot components that can report the arm bone (a second fallback source)
    for c in mech.GetComponents() {
      let slot = c as SlotComponent;
      if IsDefined(slot) {
        let wt: WorldTransform;
        let ok = slot.GetSlotTransform(n"r_weapon_jnt", wt);
        this.Log("S5b: slot component " + NameToString(c.GetName()) + " r_weapon_jnt " + (ok ? "resolves at " + CMSpike2System.V(WorldPosition.ToVector4(WorldTransform.GetWorldPosition(wt))) : "does not resolve"));
      }
    }
    return "*CHECKED (SEE LOG)";
  }

  private func FollowStep() -> Void {
    let game = this.GetGameInstance();
    let mech = GameInstance.FindEntityByID(game, this.m_mechID) as NPCPuppet;
    let host = GameInstance.FindEntityByID(game, this.m_hostID);
    let weapon = IsDefined(mech) ? ScriptedPuppet.GetWeaponRight(mech) : null;
    if !IsDefined(host) || !IsDefined(weapon) {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, weapon.GetWorldPosition());
    let wt: WorldTransform;
    WorldTransform.SetWorldPosition(wt, world);
    WorldTransform.SetOrientation(wt, weapon.GetWorldOrientation());
    host.SetWorldTransform(wt);
  }

  public func S5bToggleMk31() -> String {
    let mech = GameInstance.FindEntityByID(this.GetGameInstance(), this.m_mechID);
    if !IsDefined(mech) {
      return "!SPAWN AN S5B MINOTAUR FIRST";
    }
    let c = mech.FindComponentByName(n"mch_003__minotaur_weapons_r_01");
    let show = IsDefined(c) && !c.IsEnabled();
    this.SetMk31(mech, show);
    return show ? "*MK.31s SHOWN" : "*MK.31s HIDDEN";
  }

  public func S5bRemove() -> Void {
    this.m_follow = false;
    this.AssembleOff();
    this.InitOff();
    let game = this.GetGameInstance();
    if EntityID.IsDefined(this.m_mechID) {
      let link = CMLinkSystem.Get(game);
      if link.IsLinked() && link.Unit().GetEntityID() == this.m_mechID {
        link.Unlink();
      }
      GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_mechID);
    }
    if EntityID.IsDefined(this.m_hostID) {
      GameInstance.GetStaticEntitySystem().DespawnEntity(this.m_hostID);
    }
    let empty: EntityID;
    this.m_mechID = empty;
    this.m_hostID = empty;
  }

  // ---------------------------------------------------------------------------
  // S6: look-ats and arm IK toward V's crosshair
  // ---------------------------------------------------------------------------
  public static func PartName(which: Int32) -> CName {
    switch which {
      case 0: return n"RightWeapon";
      case 1: return n"LeftWeapon";
      case 2: return n"Weapon";
    }
    return n"Chassis";
  }

  public func S6LookAt(which: Int32) -> String {
    let mech = this.Mech();
    if !IsDefined(mech) {
      return "!LINK A MINOTAUR FIRST";
    }
    this.S6Clear();
    this.m_s6Aim = this.AimPoint();
    let parts: array<CName>;
    if which < 4 {
      ArrayPush(parts, CMSpike2System.PartName(which));
    } else {
      parts = [n"RightWeapon", n"LeftWeapon", n"Weapon", n"Chassis"];
    }
    let names = "";
    for part in parts {
      let ev = new LookAtAddEvent();
      ev.SetStaticTarget(this.m_s6Aim);
      ev.bodyPart = part;
      ev.SetStyle(animLookAtStyle.Normal);
      ev.SetLimits(animLookAtLimitDegreesType.Wide, animLookAtLimitDegreesType.Wide, animLookAtLimitDistanceType.None, animLookAtLimitDegreesType.Wide);
      mech.QueueEvent(ev);
      ArrayPush(this.m_lookAts, ev);
      names += (StrLen(names) > 0 ? ", " : "") + NameToString(part);
    }
    this.S6Before("look-at " + names);
    return "*LOOK-AT SENT: " + StrUpper(names);
  }

  public func S6IK() -> String {
    let mech = this.Mech();
    if !IsDefined(mech) {
      return "!LINK A MINOTAUR FIRST";
    }
    this.S6Clear();
    this.m_s6Aim = this.AimPoint();
    for part in [n"ikRightArm", n"ikLeftArm"] {
      let ev = new IKTargetAddEvent();
      ev.SetStaticTarget(this.m_s6Aim);
      ev.bodyPart = part;
      mech.QueueEvent(ev);
      ArrayPush(this.m_iks, ev);
    }
    this.S6Before("arm IK ikRightArm, ikLeftArm");
    return "*ARM IK SENT";
  }

  // logs the guns' aim error now, and again in 1.5 s
  private func S6Before(what: String) -> Void {
    let mech = this.Mech();
    this.Log("S6 " + what + " toward " + CMSpike2System.V(this.m_s6Aim) + "; aim error now: right " + FloatToStringPrec(CMSpike2System.AimError(ScriptedPuppet.GetWeaponRight(mech), this.m_s6Aim), 1)
      + " deg, left " + FloatToStringPrec(CMSpike2System.AimError(ScriptedPuppet.GetWeaponLeft(mech), this.m_s6Aim), 1) + " deg");
    let cb = new CMSpike2AfterCb();
    cb.system = this;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 1.5, false);
  }

  public func S6After() -> Void {
    let mech = this.Mech();
    if !IsDefined(mech) {
      return;
    }
    this.Log("S6 after 1.5 s: aim error right " + FloatToStringPrec(CMSpike2System.AimError(ScriptedPuppet.GetWeaponRight(mech), this.m_s6Aim), 1)
      + " deg, left " + FloatToStringPrec(CMSpike2System.AimError(ScriptedPuppet.GetWeaponLeft(mech), this.m_s6Aim), 1) + " deg");
  }

  public func S6Clear() -> Void {
    let mech = this.Mech();
    if IsDefined(mech) {
      for ev in this.m_lookAts {
        let r = new LookAtRemoveEvent();
        r.lookAtRef = ev.outLookAtRef;
        mech.QueueEvent(r);
      }
      for ik in this.m_iks {
        let r = new IKTargetRemoveEvent();
        r.ikTargetRef = ik.outIKTargetRef;
        mech.QueueEvent(r);
      }
    }
    ArrayClear(this.m_lookAts);
    ArrayClear(this.m_iks);
  }

  // ---------------------------------------------------------------------------
  // Frame tick: only while a burst or the follow test runs
  // ---------------------------------------------------------------------------
  private func EnsureTick() -> Void {
    if this.m_ticking || (this.m_burst <= 0 && !this.m_follow) {
      return;
    }
    this.m_ticking = true;
    this.m_gen += 1;
    this.Queue();
  }

  private func Queue() -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      this.m_ticking = false;
      return;
    }
    player.m_cmSpikes2 = this;
    let evt = new CMSpike2TickEvent();
    evt.generation = this.m_gen;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayEventNextFrame(player, evt);
  }

  public func OnFrame(generation: Int32) -> Void {
    if generation != this.m_gen || !this.m_ticking {
      return;
    }
    if this.m_burst <= 0 && !this.m_follow {
      this.m_ticking = false;
      return;
    }
    let now = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()));
    if this.m_burst > 0 && now >= this.m_next {
      this.FireOnce();
      this.m_burst -= 1;
      this.m_next = now + 0.12;
      if this.m_burst == 0 {
        let cb = new CMSpike2ReportCb();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 1.0, false);
      }
    }
    if this.m_follow {
      this.FollowStep();
    }
    this.Queue();
  }

  // ---------------------------------------------------------------------------
  // Clean-up
  // ---------------------------------------------------------------------------
  public func DespawnAll() -> Void {
    this.m_burst = 0;
    this.S6Clear();
    this.S5bRemove();
    this.m_ticking = false;
    this.m_gen += 1;
  }

  // ---------------------------------------------------------------------------
  // The page (above batch 1 on the SPIKES tab)
  // ---------------------------------------------------------------------------
  public func Page(p: ref<TKPage>) -> Void {
    let pilot = CMPilotSystem.Get(this.GetGameInstance());
    p.Heading("S7  PILOT WITH THE GUN LOOK-AT (BATCH 3)");
    p.Item("GUN LOOK-AT WHILE PILOTING", "RightWeapon, LeftWeapon, Weapon and Chassis follow the reticle; the MK.31s fire along their barrels", "", pilot.S7On() ? "ON" : "OFF", "sp_b3_s7", pilot.S7On() ? "0" : "1", true);
    p.Item("ROUNDS OWNED BY", "The mech (the alpha's way) or V (the call a V-controlled turret makes)", "", pilot.S7OwnerV() ? "V" : "MECH", "sp_b3_s7owner", pilot.S7OwnerV() ? "0" : "1", true);
    p.ItemNote("Question: pilot the mech with this ON and shoot enemies while walking and turning, once with each owner. Do the flash, tracers and hits land on the reticle? Does damage land, and do enemies turn on V or on the mech?");

    p.Heading("S2c  THE VANILLA TURRET'S FIRE CALL (LINK A MINOTAUR, SET IT TO HOLD)");
    p.Buttons("Guns turn to your crosshair, then 10 rounds", "", "", "VANILLA CALL|+ TARGET POINT|OWNER MECH", "sp_b3_s2c|sp_b3_s2c|sp_b3_s2c", "4|5|6");
    p.ItemNote("Question: aim at a standing enemy. Does each button deal damage, and who does the enemy turn on?");

    p.Heading("S2b  DAMAGE CREDITED TO V (LINK A MECH FIRST)");
    p.Item("ORIGIN OF THE TRACERS", "Mech gun, or a point 1.5 m right of and 2 m above V", "", this.m_fromMarker ? "MARKER POINT" : "MECH GUN", "sp_b2_origin", "", true);
    p.Buttons("10 rounds at your crosshair", "", "", "OWNER MECH|V + PLAYER ATTACK|V + NPC ATTACK", "sp_b2_fire|sp_b2_fire|sp_b2_fire", "0|1|2");
    p.Item("V TRACERS + V HIT", "Tracers as in batch 1, plus each round's hit applied at the target with V as the instigator", "", "FIRE", "sp_b2_fire", "3", true);
    p.ItemNote("Question: aim at an enemy (not a car). For each button: does it take damage, does it turn on V or on the mech, and does a kill give V XP? The log records its health before and after.");

    p.Heading("S5b  A GUN THAT FOLLOWS THE ARM");
    p.Buttons("Spawn a Minotaur (MK.31s hidden) with a test HMG", "", "", "ANIM ROOT|MK.31 MESH|ARM MESH", "sp_b2_s5|sp_b2_s5|sp_b2_s5", "0|1|2");
    p.Item("FOLLOW EACH FRAME", "The fallback: the test HMG placed on the MK.31 weapon item every frame", "", "SPAWN", "sp_b2_s5", "3", true);
    p.Item("CHECK", "Logs where the test gun is against the arm", "", "CHECK", "sp_b2_s5check", "", this.HasMech());
    p.Item("MK.31s", "Show or hide the real guns to compare", "", "TOGGLE", "sp_b2_s5mk", "", this.HasMech());
    p.Item("REMOVE THE S5B MINOTAUR", "Then spawn the next variant", "", "REMOVE", "sp_b2_s5rm", "", this.HasMech());
    p.ItemNote("Question: for each spawn, do you see the test HMG, where is it, and does it stay on the right arm when you pilot the mech and walk? Press CHECK once while it stands and once while walking.");

    p.Heading("S6  LOOK-AT AND ARM IK (LINK A MINOTAUR, SET IT TO HOLD)");
    p.Buttons("Point this part at your crosshair", "", "", "RIGHTWEAPON|LEFTWEAPON|WEAPON|CHASSIS", "sp_b2_s6|sp_b2_s6|sp_b2_s6|sp_b2_s6", "0|1|2|3");
    p.Item("ALL FOUR", "All four look-ats at once", "", "SEND", "sp_b2_s6", "4", true);
    p.Item("ARM IK", "ikRightArm and ikLeftArm targets at your crosshair", "", "SEND", "sp_b2_s6ik", "", true);
    p.Item("CLEAR", "Remove the look-ats and IK targets", "", "CLEAR", "sp_b2_s6clear", "", true);
    p.ItemNote("Question: stand beside the mech and aim well off its facing. Does any button turn its guns, arms or torso toward your crosshair? The log gives each gun's aim error before and after.");
  }

  public func Act(p: ref<TKPage>, action: String, arg: String) -> Bool {
    let msg = "";
    switch action {
      case "sp_b3_s7": CMPilotSystem.Get(this.GetGameInstance()).SetS7(Equals(arg, "1")); msg = Equals(arg, "1") ? "*S7 ON: PILOT THE MECH" : "S7 OFF"; break;
      case "sp_b3_s7owner": CMPilotSystem.Get(this.GetGameInstance()).SetS7OwnerV(Equals(arg, "1")); msg = Equals(arg, "1") ? "*ROUNDS OWNED BY V" : "*ROUNDS OWNED BY THE MECH"; break;
      case "sp_b3_s2c": msg = this.S2cBurst(StringToInt(arg, 4)); break;
      case "sp_b2_origin": msg = this.ToggleOrigin(); break;
      case "sp_b2_fire": msg = this.S2bBurst(StringToInt(arg, 0)); break;
      case "sp_b2_s5": msg = this.S5bSpawn(StringToInt(arg, 0)); break;
      case "sp_b2_s5check": msg = this.S5bCheck(); break;
      case "sp_b2_s5mk": msg = this.S5bToggleMk31(); break;
      case "sp_b2_s5rm": this.S5bRemove(); msg = "S5B MINOTAUR REMOVED"; break;
      case "sp_b2_s6": msg = this.S6LookAt(StringToInt(arg, 0)); break;
      case "sp_b2_s6ik": msg = this.S6IK(); break;
      case "sp_b2_s6clear": this.S6Clear(); msg = "LOOK-ATS AND IK CLEARED"; break;
      default: return false;
    }
    if StrLen(msg) > 0 {
      p.SetMessage(msg);
    }
    return true;
  }
}

// ---- the batch 2 frame tick: an event V receives next frame (only while a test runs) ----
public class CMSpike2TickEvent extends Event {
  public let generation: Int32;
}

@addField(PlayerPuppet)
public let m_cmSpikes2: wref<CMSpike2System>;

@addMethod(PlayerPuppet)
protected cb func OnCMSpike2Tick(evt: ref<CMSpike2TickEvent>) -> Bool {
  if IsDefined(this.m_cmSpikes2) {
    this.m_cmSpikes2.OnFrame(evt.generation);
  }
  return true;
}

public class CMSpike2ReportCb extends DelayCallback {
  public let system: wref<CMSpike2System>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.S2bReport();
    }
  }
}

public class CMSpike2CheckCb extends DelayCallback {
  public let system: wref<CMSpike2System>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.S5bCheck();
    }
  }
}

public class CMSpikeS7ReportCb extends DelayCallback {
  public let system: wref<CMPilotSystem>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.S7Report();
    }
  }
}

public class CMSpike2AfterCb extends DelayCallback {
  public let system: wref<CMSpike2System>;
  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.S6After();
    }
  }
}
