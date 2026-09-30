// =============================================================================
// CONTROLLABLE MECHS - ROBOT LINK (the native side)
//
// Owns the one robotic NPC V is linked to and everything it does in the world:
//   - Link(): take over the robot V is looking at (a mech, android, drone or
//     spiderbot NPC), turn it friendly and clear its AI role so our commands stick
//   - orders: follow V, hold, move to a point; one live AI command at a time,
//     cancelled before the next is sent
//   - telemetry for the terminal (health, distance, order), read on demand
//
// Quest NPCs are refused, so a link can't break a story scene.
//
// Test spawn: SpawnTestMech() puts a Militech Minotaur in front of V through
// the DynamicEntitySystem (not saved) and links it as soon as it has spawned.
//
// Timers: nothing runs while no robot is linked. While linked, one 1s check
// (unit still there, alive, in range). Nothing runs per frame. The unit is held
// by EntityID and looked up when needed, never kept alive by a strong ref.
// =============================================================================
module ControllableMechs

public abstract class CMOrder {
  public static func None() -> Int32 = 0
  public static func Follow() -> Int32 = 1
  public static func Hold() -> Int32 = 2
  public static func MoveTo() -> Int32 = 3
  public static func Pilot() -> Int32 = 4
}

public class CMLinkSystem extends ScriptableSystem {
  private let m_unitID: EntityID;
  private let m_linked: Bool;
  private let m_order: Int32;
  private let m_cmd: ref<AICommand>;
  private let m_generation: Int32;   // bumps on every link / unlink / session: stale ticks drop out
  private let m_testID: EntityID;    // the test Minotaur, if one is out
  private let m_listening: Bool;

  private let LINK_RANGE: Float = 60.0;    // how far V can be from a robot to link it
  private let SIGNAL_RANGE: Float = 250.0; // past this the link drops
  private let CHECK_TICK: Float = 1.0;

  public static func Get(game: GameInstance) -> ref<CMLinkSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMLinkSystem") as CMLinkSystem;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    // New session or load: whatever we linked (or spawned) before is gone
    this.Clear();
    let empty: EntityID;
    this.m_testID = empty;
  }

  private func Clear() -> Void {
    this.m_generation += 1;
    this.m_linked = false;
    this.m_order = CMOrder.None();
    this.m_cmd = null;
  }

  // ---------------------------------------------------------------------------
  // Which NPCs count as robots
  // ---------------------------------------------------------------------------
  public static func IsRobot(npc: ref<NPCPuppet>) -> Bool {
    if !IsDefined(npc) {
      return false;
    }
    switch npc.GetNPCType() {
      case gamedataNPCType.Mech:
      case gamedataNPCType.Android:
      case gamedataNPCType.Drone:
      case gamedataNPCType.Spiderbot:
        return true;
    }
    return false;
  }

  public static func KindName(npc: ref<NPCPuppet>) -> String {
    if !IsDefined(npc) {
      return "";
    }
    switch npc.GetNPCType() {
      case gamedataNPCType.Mech:
        return "MECH";
      case gamedataNPCType.Android:
        return "ANDROID";
      case gamedataNPCType.Drone:
        return "DRONE";
      case gamedataNPCType.Spiderbot:
        return "SPIDERBOT";
    }
    return "UNIT";
  }

  // ---------------------------------------------------------------------------
  // Link
  // ---------------------------------------------------------------------------
  public func IsLinked() -> Bool = this.m_linked && IsDefined(this.Unit())
  public func Order() -> Int32 = this.m_order
  public func SetOrder(order: Int32) -> Void { this.m_order = order; }

  public func Unit() -> ref<NPCPuppet> {
    if !this.m_linked {
      return null;
    }
    return GameInstance.FindEntityByID(this.GetGameInstance(), this.m_unitID) as NPCPuppet;
  }

  // Links the robot V is looking at; returns a message for the HUD / terminal
  public func LinkLookAt() -> String {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return "";
    }
    let npc = GameInstance.GetTargetingSystem(this.GetGameInstance()).GetLookAtObject(player) as NPCPuppet;
    if !CMLinkSystem.IsRobot(npc) {
      return "!NO ROBOT IN SIGHT";
    }
    if !ScriptedPuppet.IsAlive(npc) {
      return "!" + CMLinkSystem.KindName(npc) + " IS DESTROYED";
    }
    if npc.IsQuest() {
      return "!" + CMLinkSystem.KindName(npc) + " IS SHIELDED FROM THE LINK";
    }
    if Vector4.Distance(player.GetWorldPosition(), npc.GetWorldPosition()) > this.LINK_RANGE {
      return "!OUT OF LINK RANGE";
    }
    return this.Link(npc);
  }

  public func Link(npc: ref<NPCPuppet>) -> String {
    if this.m_linked {
      this.Unlink();
    }
    this.m_unitID = npc.GetEntityID();
    this.m_linked = true;
    this.m_generation += 1;
    this.MakeFriendly(npc);
    this.SetNoRole(npc);
    this.Hold();
    this.Schedule();
    return "*" + CMLinkSystem.KindName(npc) + " LINKED";
  }

  public func Unlink() -> Void {
    let pilot = CMPilotSystem.Get(this.GetGameInstance());
    if IsDefined(pilot) && pilot.IsPiloting() {
      pilot.Exit("NEURAL LINK CLOSED", false);
    }
    let unit = this.Unit();
    if IsDefined(unit) {
      this.CancelCmd(unit);
    }
    this.Clear();
  }

  // ---------------------------------------------------------------------------
  // Test spawn: a Minotaur in front of V, linked once it's in the world
  // ---------------------------------------------------------------------------
  public func HasTestMech() -> Bool = EntityID.IsDefined(this.m_testID)

  public func SpawnTestMech() -> String {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return "";
    }
    if this.HasTestMech() {
      return "!A TEST MECH IS ALREADY OUT";
    }
    let record: TweakDBID;
    let found = false;
    for id in [t"Character.q003_militech_mech", t"Character.q114_arasaka_netnest_mech_friendly_quest", t"Character.Mech_NPC_Base"] {
      if !found && IsDefined(TweakDBInterface.GetCharacterRecord(id)) {
        record = id;
        found = true;
      }
    }
    if !found {
      return "!NO MINOTAUR RECORD IN THIS GAME VERSION";
    }
    if !this.m_listening {
      GameInstance.GetDynamicEntitySystem().RegisterListener(n"ControllableMechsTest", this, n"OnTestMechEvent");
      this.m_listening = true;
    }
    let fwd = player.GetWorldForward();
    let spec = new DynamicEntitySpec();
    spec.recordID = record;
    spec.position = player.GetWorldPosition() + fwd * 14.0;
    let face: EulerAngles;
    face.Yaw = CMPilotRig.YawOf(fwd) + 180.0;   // facing V
    spec.orientation = EulerAngles.ToQuat(face);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"ControllableMechsTest"];
    this.m_testID = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    return "*MINOTAUR INBOUND";
  }

  public func DespawnTestMech() -> Void {
    if !this.HasTestMech() {
      return;
    }
    if this.m_linked && this.m_unitID == this.m_testID {
      this.Unlink();
    }
    GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_testID);
    let empty: EntityID;
    this.m_testID = empty;
  }

  protected cb func OnTestMechEvent(event: ref<DynamicEntityEvent>) -> Void {
    if !Equals(event.GetEventType(), DynamicEntityEventType.Spawned) || event.GetEntityID() != this.m_testID {
      return;
    }
    let npc = GameInstance.GetDynamicEntitySystem().GetEntity(this.m_testID) as NPCPuppet;
    if IsDefined(npc) {
      let msg = this.Link(npc);
      let player = GetPlayer(this.GetGameInstance());
      if IsDefined(player) {
        player.SetWarningMessage(StrReplaceAll(StrReplaceAll(msg, "!", ""), "*", ""));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Orders: one live command, the old one cancelled first
  // ---------------------------------------------------------------------------
  public func Follow() -> Void {
    let unit = this.Unit();
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(unit) || !IsDefined(player) {
      return;
    }
    let cmd = new AIFollowTargetCommand();
    cmd.target = player;
    cmd.lookAtTarget = player;
    cmd.desiredDistance = 6.0;
    cmd.tolerance = 2.0;
    cmd.stopWhenDestinationReached = false;
    cmd.movementType = moveMovementType.Run;
    this.Send(unit, cmd, CMOrder.Follow());
  }

  public func Hold() -> Void {
    let unit = this.Unit();
    if !IsDefined(unit) {
      return;
    }
    this.CancelCmd(unit);
    this.m_order = CMOrder.Hold();
  }

  // Moves to what V is looking at, or a point ahead of V when nothing is in sight
  public func MoveToLookAt() -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return;
    }
    let target = GameInstance.GetTargetingSystem(this.GetGameInstance()).GetLookAtObject(player);
    let pos: Vector4;
    if IsDefined(target) && NotEquals(target.GetEntityID(), this.m_unitID) {
      pos = target.GetWorldPosition();
    } else {
      pos = player.GetWorldPosition() + player.GetWorldForward() * 15.0;
    }
    this.MoveTo(pos);
  }

  public func MoveTo(pos: Vector4) -> Void {
    let unit = this.Unit();
    if !IsDefined(unit) {
      return;
    }
    let world: WorldPosition;
    WorldPosition.SetVector4(world, pos);
    let spec: AIPositionSpec;
    AIPositionSpec.SetWorldPosition(spec, world);
    let cmd = new AIMoveToCommand();
    cmd.movementTarget = spec;
    cmd.ignoreNavigation = false;
    cmd.finishWhenDestinationReached = true;
    this.Send(unit, cmd, CMOrder.MoveTo());
  }

  private func Send(unit: ref<NPCPuppet>, cmd: ref<AICommand>, order: Int32) -> Void {
    let ai = unit.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    this.CancelCmd(unit);
    ai.SendCommand(cmd);
    this.m_cmd = cmd;
    this.m_order = order;
  }

  private func CancelCmd(unit: ref<NPCPuppet>) -> Void {
    if IsDefined(this.m_cmd) {
      let ai = unit.GetAIControllerComponent();
      if IsDefined(ai) {
        ai.CancelCommand(this.m_cmd);
      }
      this.m_cmd = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Telemetry (read when the terminal draws, not polled)
  // ---------------------------------------------------------------------------
  public func HealthFraction() -> Float {
    let unit = this.Unit();
    if !IsDefined(unit) {
      return 0.0;
    }
    let id = Cast<StatsObjectID>(unit.GetEntityID());
    return GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(id, gamedataStatPoolType.Health, true) / 100.0;
  }

  public func Distance() -> Float {
    let unit = this.Unit();
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(unit) || !IsDefined(player) {
      return -1.0;
    }
    return Vector4.Distance(player.GetWorldPosition(), unit.GetWorldPosition());
  }

  public func SignalFraction() -> Float {
    let d = this.Distance();
    return d < 0.0 ? 0.0 : ClampF(1.0 - d / this.SIGNAL_RANGE, 0.0, 1.0);
  }

  public func UnitName() -> String {
    let unit = this.Unit();
    return IsDefined(unit) ? unit.GetDisplayName() : "";
  }

  public func UnitKind() -> String = CMLinkSystem.KindName(this.Unit())

  // ---------------------------------------------------------------------------
  // The 1s link check: only scheduled while a robot is linked
  // ---------------------------------------------------------------------------
  private func Schedule() -> Void {
    let cb = new CMLinkTick();
    cb.system = this;
    cb.generation = this.m_generation;
    GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, this.CHECK_TICK, false);
  }

  public func OnTick(generation: Int32) -> Void {
    if generation != this.m_generation || !this.m_linked {
      return;
    }
    let unit = this.Unit();
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(unit) || !ScriptedPuppet.IsAlive(unit) {
      this.Drop(player, "ROBOT LINK LOST");
      return;
    }
    if this.Distance() > this.SIGNAL_RANGE {
      this.Drop(player, CMLinkSystem.KindName(unit) + " OUT OF SIGNAL RANGE");
      return;
    }
    this.Schedule();
  }

  private func Drop(player: ref<PlayerPuppet>, why: String) -> Void {
    this.Unlink();
    if IsDefined(player) {
      player.SetWarningMessage(why);
    }
  }

  // ---------------------------------------------------------------------------
  // Taking the robot over: friendly to V, no AI role of its own
  // ---------------------------------------------------------------------------
  private func MakeFriendly(npc: ref<NPCPuppet>) -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) {
      return;
    }
    let playerAgent = player.GetAttitudeAgent();
    let npcAgent = npc.GetAttitudeAgent();
    if IsDefined(playerAgent) && IsDefined(npcAgent) {
      npcAgent.SetAttitudeGroup(playerAgent.GetAttitudeGroup());
      npcAgent.SetAttitudeTowards(playerAgent, EAIAttitude.AIA_Friendly);
    }
  }

  private func SetNoRole(npc: ref<NPCPuppet>) -> Void {
    let ai = npc.GetAIControllerComponent();
    if IsDefined(ai) {
      ai.SetAIRole(new AINoRole());
      ai.OnAttach();   // the role only takes effect after this
    }
  }
}

public class CMLinkTick extends DelayCallback {
  public let system: wref<CMLinkSystem>;
  public let generation: Int32;

  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnTick(this.generation);
    }
  }
}
