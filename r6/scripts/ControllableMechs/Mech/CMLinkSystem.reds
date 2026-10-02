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

import ControllableMechs.Control.*

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
  private let m_stationed: Bool;     // posted somewhere (Night City Empires' HQ): no range limit

  private let LINK_RANGE: Float = 60.0;    // how far V can be from a robot to link it
  // past this the link drops (the pilot session uses the same range)
  public static func SignalRange() -> Float = 250.0
  // the linked unit's own range: drones carry a longer uplink (Omar: 500 m)
  public func Range() -> Float {
    let unit = this.Unit();
    return IsDefined(unit) && Equals(unit.GetNPCType(), gamedataNPCType.Drone) ? 500.0 : CMLinkSystem.SignalRange();
  }
  private let CHECK_TICK: Float = 1.0;

  // a terminal message for the HUD: the "!" / "*" colour marks are for the terminal only
  public static func Plain(msg: String) -> String = StrReplaceAll(StrReplaceAll(msg, "!", ""), "*", "")

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
    this.m_stationed = false;
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

  // A stationed unit (Night City Empires posts the linked mech at V's HQ) keeps its link at
  // any distance while its order is Hold and V isn't piloting it: the 1 s check skips the
  // range test, keeps the alive test, and keeps the link while the unit is streamed out
  // with distance. Any other order, a new link or an unlink ends it.
  public func SetStationed(on: Bool) -> Void { this.m_stationed = on && this.m_linked; }
  public func IsStationed() -> Bool = this.m_stationed
  private func StationedNow() -> Bool {
    if !this.m_stationed || this.m_order != CMOrder.Hold() {
      return false;
    }
    let session = CMCSession.Get(this.GetGameInstance());
    return !(IsDefined(session) && session.IsActive());
  }
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
    // a mech with broken parts shows them again (their attached effects were dropped when
    // it last left the link)
    if Equals(npc.GetNPCType(), gamedataNPCType.Mech) {
      CMCParts.Get(this.GetGameInstance()).Effects(npc);
    }
    this.Schedule();
    return "*" + CMLinkSystem.KindName(npc) + " LINKED";
  }

  public func Unlink() -> Void {
    let session = CMCSession.Get(this.GetGameInstance());
    if IsDefined(session) && session.IsActive() {
      session.End("NEURAL LINK CLOSED", false);
    }
    let unit = this.Unit();
    if IsDefined(unit) {
      this.CancelCmd(unit);
      CMCParts.Get(this.GetGameInstance()).DropFx(unit);
    }
    CMCParts.Get(this.GetGameInstance()).SetTest(null, false);
    this.Clear();
  }

  // ---------------------------------------------------------------------------
  // Test spawn: a Minotaur in front of V, linked once it's in the world
  // ---------------------------------------------------------------------------
  public func HasTestMech() -> Bool = EntityID.IsDefined(this.m_testID)

  // `appearance`: one of the Minotaur's liveries (mch_003__minotaur_militech_01, _arasaka_01,
  // _police_01, _kurt), or none for the record's own. Optional: Night City Empires calls this
  // with no argument.
  public func SpawnTestMech(opt appearance: CName) -> String {
    return this.SpawnTest([t"Character.q003_militech_mech", t"Character.q114_arasaka_netnest_mech_friendly_quest", t"Character.Mech_NPC_Base"], appearance, 0.0, "*MINOTAUR INBOUND", "!NO MINOTAUR RECORD IN THIS GAME VERSION");
  }

  // a test drone: "bombus", "griffin", "wyvern" or "octant", 2.5 m above the ground point.
  // (Every drone flies as a PhysX body now; `physics` is kept so callers that passed it,
  // from the V3 test days, still compile. Night City Empires passes only the kind.)
  public func SpawnTestDrone(kind: String, opt physics: Bool) -> String {
    let records: array<TweakDBID>;
    switch kind {
      case "bombus":
        records = [t"Character.aldecaldos_drone_bombus_easy", t"Character.aldecaldos_base_drone_bombus", t"Character.con_kurtz_base_drone_bombus"];
        break;
      case "griffin":
        records = [t"Character.bls_se_militech_drone_griffin_medium", t"Character.bls_se_militech_drone_griffin_hard", t"Character.arr_militech_drone_griffin_hard"];
        break;
      case "wyvern":
        records = [t"Character.bls_se_militech_drone_wyvern_medium", t"Character.arasaka_drone_wyvern_medium4", t"Character.bou_kurtz_base_drone_wyvern"];
        break;
      default:
        records = [t"Character.bls_se_militech_drone_octant_medium", t"Character.border_patrol_octant", t"Character.arasaka_drone_octant_easy4"];
    }
    return this.SpawnTest(records, n"", 2.5, "*" + StrUpper(kind) + " INBOUND", "!NO " + StrUpper(kind) + " RECORD IN THIS GAME VERSION");
  }

  // the first of `records` this game has, spawned in front of V (`lift` metres up) and
  // linked once it is in the world
  private func SpawnTest(records: array<TweakDBID>, appearance: CName, lift: Float, ok: String, missing: String) -> String {
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return "";
    }
    if this.HasTestMech() {
      return "!A TEST UNIT IS ALREADY OUT";
    }
    let record: TweakDBID;
    let found = false;
    for id in records {
      if !found && IsDefined(TweakDBInterface.GetCharacterRecord(id)) {
        record = id;
        found = true;
      }
    }
    if !found {
      return missing;
    }
    if !this.m_listening {
      GameInstance.GetDynamicEntitySystem().RegisterListener(n"ControllableMechsTest", this, n"OnTestMechEvent");
      this.m_listening = true;
    }
    let fwd = player.GetWorldForward();
    fwd.Z = 0.0;
    fwd = Vector4.Normalize(fwd);
    let at: Vector4;
    if !this.SpawnPoint(player.GetWorldPosition(), fwd, at) {
      GameObject.PlaySoundEvent(player, n"ui_hacking_press_fail");
      return "!NO CLEAR LZ: STAND ON OPEN, LEVEL GROUND";
    }
    let spec = new DynamicEntitySpec();
    spec.recordID = record;
    spec.position = at + new Vector4(0.0, 0.0, lift, 0.0);
    let face: EulerAngles;
    face.Yaw = CMPilotRig.YawOf(fwd) + 180.0;   // facing V
    spec.orientation = EulerAngles.ToQuat(face);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    if NotEquals(appearance, n"") {
      spec.appearanceName = appearance;
    }
    spec.tags = [n"ControllableMechsTest"];
    this.m_testID = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    return ok;
  }

  // Where the test mech goes: on the ground, up to 46 ft from V. The point straight ahead
  // at V's own height can be in the air (V on a ledge, a slope, above a lower road) or
  // inside a wall, and a mech spawned there falls or gets teleported about by the game.
  // So candidates are tried in turn (46, 33 and 20 ft ahead, then 33 ft off to each side);
  // each stops short of a wall, drops a ray for the ground, and is refused if that ground
  // is more than 16 ft above or below V. The first one on the navigation mesh wins; with
  // none on the mesh, the first with ground at all. False when nothing is usable.
  private func SpawnPoint(from: Vector4, fwd: Vector4, out at: Vector4) -> Bool {
    let yaw = CMPilotRig.YawOf(fwd);
    let dists: array<Float> = [14.0, 10.0, 6.0, 10.0, 10.0];
    let turns: array<Float> = [0.0, 0.0, 0.0, 40.0, -40.0];
    let fallback: Vector4;
    let haveFallback = false;
    let i = 0;
    while i < ArraySize(dists) {
      let p: Vector4;
      let onMesh = false;
      if this.GroundAt(from, CMPilotRig.Dir(yaw + turns[i], 0.0), dists[i], p, onMesh) {
        if onMesh {
          at = p;
          CMCSession.Log("test mech: spawn point " + IntToString(i + 1) + " of 5, on the navigation mesh, " + FloatToStringPrec(Vector4.Distance2D(from, p), 1) + " m from V, ground " + FloatToStringPrec(p.Z - from.Z, 1) + " m from V's level");
          return true;
        }
        if !haveFallback {
          fallback = p;
          haveFallback = true;
        }
      }
      i += 1;
    }
    if haveFallback {
      at = fallback;
      CMCSession.Log("test mech: no spawn point on the navigation mesh, using plain ground " + FloatToStringPrec(Vector4.Distance2D(from, at), 1) + " m from V");
      return true;
    }
    CMCSession.Log("test mech: no ground near V's level at any of the 5 spawn points");
    return false;
  }

  private func GroundAt(from: Vector4, dir: Vector4, dist: Float, out p: Vector4, out onMesh: Bool) -> Bool {
    let game = this.GetGameInstance();
    let sq = GameInstance.GetSpatialQueriesSystem(game);
    let hit: TraceResult;
    let reach = dist;
    let chest = new Vector4(from.X, from.Y, from.Z + 1.2, 1.0);
    if sq.SyncRaycastByCollisionGroup(chest, chest + dir * (reach + 3.0), n"Static", hit, true, false) {
      reach = Vector4.Distance(chest, Cast<Vector4>(hit.position)) - 3.0;   // room for its bulk
    }
    if reach < 5.0 {
      return false;
    }
    let over = from + dir * reach;
    // from a little above V's level first (so a roof or bridge overhead isn't taken for the
    // ground), then from higher up for ground that rises ahead
    let found = false;
    for lift in [3.0, 8.0] {
      if !found && CMGround.Down(game, new Vector4(over.X, over.Y, over.Z + lift, 1.0), new Vector4(over.X, over.Y, over.Z - 8.0, 1.0), hit) {
        found = true;
      }
    }
    if !found {
      return false;
    }
    p = Cast<Vector4>(hit.position);
    p.W = 1.0;
    if AbsF(p.Z - from.Z) > 5.0 {
      return false;
    }
    // the walkable point under it, when the navigation mesh has one close by
    let nav = GameInstance.GetNavigationSystem(game).GetNearestNavmeshPointBelowOnlyHumanNavmesh(new Vector4(p.X, p.Y, p.Z + 1.5, 1.0), 1.5, 4);
    onMesh = !Vector4.IsZero(nav) && AbsF(nav.Z - p.Z) < 2.5;
    if onMesh {
      p = nav;
      p.W = 1.0;
    }
    return true;
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
        player.SetWarningMessage(CMLinkSystem.Plain(msg));
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
    this.m_stationed = false;   // sent somewhere: no longer posted
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
    return d < 0.0 ? 0.0 : ClampF(1.0 - d / this.Range(), 0.0, 1.0);
  }

  public func UnitName() -> String {
    let unit = this.Unit();
    return IsDefined(unit) ? unit.GetDisplayName() : "";
  }

  public func UnitKind() -> String = CMLinkSystem.KindName(this.Unit())

  // A linked drone's parts (the Octant's, CMUDrone), kept between flights while it stays
  // the linked unit; whole (1.0) for any other unit or a fresh link.
  private let m_droneParts: array<Float>;
  private let m_dronePartsOf: EntityID;

  public func DroneParts(id: EntityID, n: Int32) -> array<Float> {
    let out: array<Float>;
    let keep = id == this.m_dronePartsOf && ArraySize(this.m_droneParts) == n;
    let i = 0;
    while i < n {
      ArrayPush(out, keep ? this.m_droneParts[i] : 1.0);
      i += 1;
    }
    return out;
  }

  public func SetDroneParts(id: EntityID, parts: array<Float>) -> Void {
    this.m_dronePartsOf = id;
    ArrayClear(this.m_droneParts);
    for p in parts {
      ArrayPush(this.m_droneParts, p);
    }
  }

  // DIAGNOSTICS: one of the linked drone's parts destroyed (-1: all whole again); applies
  // when it is next flown
  public func DevDronePart(part: Int32, n: Int32) -> Void {
    let unit = this.Unit();
    if !IsDefined(unit) {
      return;
    }
    let parts = this.DroneParts(unit.GetEntityID(), n);
    let i = 0;
    while i < n {
      if part < 0 {
        parts[i] = 1.0;
      } else {
        if i == part {
          parts[i] = 0.0;
        }
      }
      i += 1;
    }
    this.SetDroneParts(unit.GetEntityID(), parts);
  }

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
    let stationed = this.StationedNow();
    if stationed && !IsDefined(unit) {
      // streamed out with the distance: still posted, checked again when it is back
      this.Schedule();
      return;
    }
    if !IsDefined(unit) || !ScriptedPuppet.IsAlive(unit) {
      // a destroyed drone's feed shows SIGNAL LOST until the pilot key closes it (a59,
      // Omar): while that session is open the link waits, and drops on the next check
      let session = CMCSession.Get(this.GetGameInstance());
      if IsDefined(session) && session.IsActive() {
        this.Schedule();
        return;
      }
      this.Drop(player, "ROBOT LINK LOST");
      return;
    }
    if !stationed && this.Distance() > this.Range() {
      this.Drop(player, CMLinkSystem.KindName(unit) + " OUT OF SIGNAL RANGE");
      return;
    }
    let session = CMCSession.Get(this.GetGameInstance());
    if Equals(unit.GetNPCType(), gamedataNPCType.Mech) && !(IsDefined(session) && session.IsActive()) {
      this.KeepGrounded(unit);
    }
    this.Schedule();
  }

  // The Minotaur has no fall of its own: lifted or knocked high enough it hangs in the air.
  // A linked mech that isn't being piloted (the pilot session has its own check) is looked
  // at once a second: with more than 2 m of air under it for two checks running, it is set
  // down on the ground below. One ray a second, only while a mech is linked.
  private let m_airChecks: Int32;

  private func KeepGrounded(mech: ref<NPCPuppet>) -> Void {
    let pos = mech.GetWorldPosition();
    let hit: TraceResult;
    let gap = 0.0;   // no ground found at all: left alone
    if CMGround.Down(this.GetGameInstance(), new Vector4(pos.X, pos.Y, pos.Z + 0.5, 1.0), new Vector4(pos.X, pos.Y, pos.Z - 60.0, 1.0), hit) {
      gap = pos.Z - Cast<Vector4>(hit.position).Z;
    }
    if gap < 2.0 {
      this.m_airChecks = 0;
      return;
    }
    this.m_airChecks += 1;
    // three checks (3 s) first, so the game's own settling from a small height isn't cut
    // short, then one try every 5 s while it stays up
    if this.m_airChecks < 3 {
      return;
    }
    this.m_airChecks = -2;
    CMGround.SetDown(mech, Cast<Vector4>(hit.position));
    CMCSession.Log("AIRBORNE (linked, not piloted): hanging " + FloatToStringPrec(gap, 1) + " m up for 3 s, teleport order to the ground below");
  }

  private func Drop(player: ref<PlayerPuppet>, why: String) -> Void {
    this.Unlink();
    if IsDefined(player) {
      player.SetWarningMessage(why);
    }
  }

  // The damage test: neutral both ways, so V's rounds count against it; friendly again after.
  public func TestAttitude(npc: ref<NPCPuppet>, on: Bool) -> Void {
    let player = GetPlayer(this.GetGameInstance());
    if !IsDefined(player) || !IsDefined(npc) {
      return;
    }
    let playerAgent = player.GetAttitudeAgent();
    let npcAgent = npc.GetAttitudeAgent();
    if !IsDefined(playerAgent) || !IsDefined(npcAgent) {
      return;
    }
    if on {
      npcAgent.SetAttitudeTowards(playerAgent, EAIAttitude.AIA_Neutral);
      playerAgent.SetAttitudeTowards(npcAgent, EAIAttitude.AIA_Neutral);
    } else {
      playerAgent.SetAttitudeTowards(npcAgent, EAIAttitude.AIA_Friendly);
      this.MakeFriendly(npc);
    }
  }

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

// Finding the ground under a point. The "Static" collision group misses some ground (the
// dirt lots under the overpasses, for one: a mech there was taken for standing on nothing,
// and one really in the air there went unnoticed), so the ray is tried with the "World
// Static" preset first, the one the pilot's rangefinder uses, and with the group after.
public abstract class CMGround {
  public static func Down(game: GameInstance, from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    let sq = GameInstance.GetSpatialQueriesSystem(game);
    if sq.SyncRaycastByCollisionPreset(from, to, n"World Static", hit, true) {
      return true;
    }
    if sq.SyncRaycastByCollisionGroup(from, to, n"Static", hit, true, false) {
      return true;
    }
    return sq.SyncRaycastByCollisionGroup(from, to, n"Terrain", hit, true, false);
  }

  // The world (static and terrain) along a line, nearest first. Preset queries returned
  // nothing in some sessions (2026-09-30: the drones found no ground at all, with or
  // without a physics mod), while the collision groups still answered; the preset is tried
  // first, the groups after.
  public static func World(game: GameInstance, from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    let sq = GameInstance.GetSpatialQueriesSystem(game);
    if sq.SyncRaycastByCollisionPreset(from, to, n"World Static", hit, true) {
      return true;
    }
    let a: TraceResult;
    let b: TraceResult;
    let gotA = sq.SyncRaycastByCollisionGroup(from, to, n"Static", a, true, false);
    let gotB = sq.SyncRaycastByCollisionGroup(from, to, n"Terrain", b, true, false);
    if gotA && (!gotB || Vector4.Distance(from, Cast<Vector4>(a.position)) <= Vector4.Distance(from, Cast<Vector4>(b.position))) {
      hit = a;
      return true;
    }
    if gotB {
      hit = b;
      return true;
    }
    return false;
  }

  // Anything that moves along a line (characters, props, vehicles), nearest first: the
  // "World Dynamic" preset, or the AI, Dynamic and Vehicle groups when that answers nothing.
  // The group queries ask for dynamic objects too (staticOnly false): a20-a26 passed true,
  // static objects only, so they never found a person, a prop or a car (every drone log:
  // "dynamic 0, vehicle 0"; the Octant's LMG: 0 targets struck). The AI group takes in the
  // NPCs' hitboxes (the "NPC Hitbox" preset is queried as AI).
  public static func Movers(game: GameInstance, from: Vector4, to: Vector4, out hit: TraceResult) -> Bool {
    let sq = GameInstance.GetSpatialQueriesSystem(game);
    if sq.SyncRaycastByCollisionPreset(from, to, n"World Dynamic", hit, true) {
      return true;
    }
    let best = 1000000.0;
    let found = false;
    for g in [n"AI", n"Dynamic", n"Vehicle"] {
      let h: TraceResult;
      if sq.SyncRaycastByCollisionGroup(from, to, g, h, false, false) {
        let d = Vector4.Distance(from, Cast<Vector4>(h.position));
        if d < best {
          best = d;
          hit = h;
          found = true;
        }
      }
    }
    return found;
  }

  // A mech hanging in the air (the Minotaur has no fall) set down on `ground`, with a heavy
  // clunk. The AI's own teleport order: the teleport facility's moves don't land on this
  // mech. 0.3 m above the hit point, or its legs sink into the ground.
  public static func SetDown(mech: ref<NPCPuppet>, ground: Vector4) -> Void {
    let ai = mech.GetAIControllerComponent();
    if !IsDefined(ai) {
      return;
    }
    let cmd = new AITeleportCommand();
    cmd.position = new Vector4(ground.X, ground.Y, ground.Z + 0.3, 1.0);
    cmd.rotation = CMPilotRig.YawOf(mech.GetWorldForward());
    cmd.doNavTest = false;
    ai.SendCommand(cmd);
    GameObject.PlaySoundEvent(mech, n"nme_boss_smasher_lcm_servo_short");
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
