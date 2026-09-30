// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: THE EMPLACEMENT (M2)
//
// The emplacement is a spawned vanilla turret device taken over the game's own
// way (spikes S0 / S0b: barrel, flash, rounds and V-credited damage all work, and
// the exit restores V). This system owns the spawned turret: spawn in front of V,
// befriend it, find it again, despawn it. CMCSession.BeginTakeover drives the
// control session.
//   models: 0 = the Arasaka floor turret (the Minotaur's HMG look, the default),
//           1 = Security turret 1
// The spawn isn't saved (persistSpawn false): it's gone after a load.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMCEmplacements extends ScriptableSystem {
  private let m_id: EntityID;
  private let m_listening: Bool;
  private persistent let m_model: Int32;

  public static func Get(game: GameInstance) -> ref<CMCEmplacements> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMCEmplacements") as CMCEmplacements;
  }

  private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
    let empty: EntityID;
    this.m_id = empty;   // nothing we spawned survives a load
  }

  public static func ModelName(i: Int32) -> String = i == 1 ? "SECURITY TURRET" : "ARASAKA HMG"

  public static func ModelPath(i: Int32) -> ResRef {
    if i == 1 {
      return r"base\\gameplay\\devices\\security_systems\\security_turret\\security_turret_1.ent";
    }
    return r"base\\gameplay\\devices\\security_systems\\security_turret\\special\\arasaka_ceo_floor_turret.ent";
  }

  public func Model() -> Int32 = this.m_model
  public func SetModel(i: Int32) -> Void {
    this.m_model = Clamp(i, 0, 1);
  }

  public func Turret() -> ref<SecurityTurret> {
    if !EntityID.IsDefined(this.m_id) {
      return null;
    }
    return GameInstance.FindEntityByID(this.GetGameInstance(), this.m_id) as SecurityTurret;
  }

  public func Has() -> Bool = EntityID.IsDefined(this.m_id)

  // the Pilot key takes the emplacement when V looks at it or stands within 5 m of it
  public func IsNear(player: ref<PlayerPuppet>) -> Bool {
    let t = this.Turret();
    if !IsDefined(t) || !IsDefined(player) {
      return false;
    }
    let look = GameInstance.GetTargetingSystem(this.GetGameInstance()).GetLookAtObject(player);
    if IsDefined(look) && look.GetEntityID() == this.m_id {
      return true;
    }
    return Vector4.Distance(player.GetWorldPosition(), t.GetWorldPosition()) < 5.0;
  }

  public func Spawn() -> String {
    if this.Has() {
      return "!AN EMPLACEMENT IS ALREADY OUT";
    }
    let game = this.GetGameInstance();
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return "";
    }
    if !this.m_listening {
      GameInstance.GetDynamicEntitySystem().RegisterListener(n"CMEmplacement", this, n"OnEmplacementEntity");
      this.m_listening = true;
    }
    // on the ground 4 m ahead of V, facing where V faces
    let f = player.GetWorldForward();
    let p = player.GetWorldPosition() + f * 4.0;
    let hit: TraceResult;
    if GameInstance.GetSpatialQueriesSystem(game).SyncRaycastByCollisionGroup(new Vector4(p.X, p.Y, p.Z + 3.0, 1.0), new Vector4(p.X, p.Y, p.Z - 6.0, 1.0), n"Static", hit, true, false) {
      p = Cast<Vector4>(hit.position);
    }
    let face: EulerAngles;
    face.Yaw = CMPilotRig.YawOf(f);
    let spec = new DynamicEntitySpec();
    spec.templatePath = CMCEmplacements.ModelPath(this.m_model);
    spec.position = p;
    spec.orientation = EulerAngles.ToQuat(face);
    spec.persistState = false;
    spec.persistSpawn = false;
    spec.alwaysSpawned = true;
    spec.tags = [n"CMEmplacement"];
    this.m_id = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
    CMCSession.Log("emplacement: " + CMCEmplacements.ModelName(this.m_model) + " spawning 4 m ahead");
    return "*EMPLACEMENT INBOUND: " + CMCEmplacements.ModelName(this.m_model);
  }

  // friendly to V as soon as it exists (the Friendly Mode quickhack's device action)
  protected cb func OnEmplacementEntity(event: ref<DynamicEntityEvent>) -> Void {
    if NotEquals(event.GetEventType(), DynamicEntityEventType.Spawned) || event.GetEntityID() != this.m_id {
      return;
    }
    let turret = this.Turret();
    if !IsDefined(turret) {
      CMCSession.Log("emplacement: the spawned entity is not a SecurityTurret");
      return;
    }
    let action = turret.GetDevicePS().ActionSetDeviceAttitude();
    action.SetExecutor(GetPlayer(this.GetGameInstance()));
    turret.QueueEvent(action);
    CMCSession.Log("emplacement: spawned and set friendly");
  }

  public func Despawn() -> String {
    if !this.Has() {
      return "!NO EMPLACEMENT OUT";
    }
    CMCSession.Get(this.GetGameInstance()).EndIfTakeover(this.m_id);
    GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_id);
    let empty: EntityID;
    this.m_id = empty;
    CMCSession.Log("emplacement: removed");
    return "EMPLACEMENT REMOVED";
  }
}
