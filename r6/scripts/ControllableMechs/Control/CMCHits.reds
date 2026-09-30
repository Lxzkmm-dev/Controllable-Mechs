// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: HITS
//
// One hook on the game's damage pipeline, for the weapons a piloted unit fires
// (a flag on the weapon object, set while piloting and cleared on exit; every
// other hit in the game costs one field check):
//   - credit: the hit's instigator becomes V before the pipeline runs, so its
//     friendly-fire check, damage, the kill, XP and NCPD heat are V's (the
//     rounds themselves stay owned by the mech, the only call that does damage)
//   - the pilot HUD's hit marker when a round connects
//   - with diagnostics on (CONFIG > DIAGNOSTICS): a trace of each hit to the log,
//     at most 25 lines per 5 s
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

@addField(WeaponObject)
public let m_cmPiloted: Bool;    // fired by a piloted unit: its hits reach the HUD and the trace

@addField(WeaponObject)
public let m_cmCreditV: Bool;    // ... and are credited to V

@wrapMethod(DamageSystem)
private final func ProcessPipeline(hitEvent: ref<gameHitEvent>, cache: ref<CacheData>) -> Void {
  let w = hitEvent.attackData.GetWeapon();
  if !IsDefined(w) || !w.m_cmPiloted {
    wrappedMethod(hitEvent, cache);
    return;
  }
  if w.m_cmCreditV {
    let player = GetPlayer(w.GetGame());
    if IsDefined(player) {
      hitEvent.attackData.SetInstigator(player);
    }
  }
  wrappedMethod(hitEvent, cache);
  CMCHits.Landed(w.GetGame(), hitEvent);
}

public class CMCHits extends ScriptableSystem {
  private let m_window: Float;
  private let m_lines: Int32;

  public static func Get(game: GameInstance) -> ref<CMCHits> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMCHits") as CMCHits;
  }

  public static func Landed(game: GameInstance, hit: ref<gameHitEvent>) -> Void {
    let data = hit.attackData;
    if !data.HasFlag(hitFlag.DealNoDamage) {
      let session = CMCSession.Get(game);
      if IsDefined(session) {
        session.RoundHit(data.HasFlag(hitFlag.WasKillingBlow));
      }
    }
    if !CMPilotSystem.Get(game).ShowDebug() {
      return;
    }
    let sys = CMCHits.Get(game);
    if !IsDefined(sys) || !sys.Allow(EngineTime.ToFloat(GameInstance.GetEngineTime(game))) {
      return;
    }
    let cancelled = "";
    if data.HasFlag(hitFlag.DealNoDamage) {
      cancelled += " DealNoDamage";
    }
    if data.HasFlag(hitFlag.FriendlyFireIgnored) {
      cancelled += " FriendlyFireIgnored";
    }
    let target = hit.target as GameObject;
    let instigator = data.GetInstigator();
    CMCSession.Log("hit " + CMCHits.Describe(target)
      + " at " + CMCHits.V(hit.hitPosition)
      + ", instigator " + (IsDefined(instigator) ? NameToString(instigator.GetClassName()) : "none")
      + ", weapon " + TDBID.ToStringDEBUG(ItemID.GetTDBID(data.GetWeapon().GetItemID()))
      + ", damage " + FloatToStringPrec(hit.attackComputed.GetTotalAttackValue(gamedataStatPoolType.Health), 1)
      + (data.HasFlag(hitFlag.WasKillingBlow) ? ", KILLING BLOW" : "")
      + (StrLen(cancelled) > 0 ? ", CANCELLED:" + cancelled : ""));
  }

  // a diagnostics line under the same limit (at most 25 lines per 5 s)
  public static func Trace(game: GameInstance, text: String) -> Void {
    let sys = CMCHits.Get(game);
    if IsDefined(sys) && sys.Allow(EngineTime.ToFloat(GameInstance.GetEngineTime(game))) {
      CMCSession.Log(text);
    }
  }

  private func Allow(now: Float) -> Bool {
    if now - this.m_window > 5.0 {
      this.m_window = now;
      this.m_lines = 0;
    }
    this.m_lines += 1;
    return this.m_lines <= 25;
  }

  // ---- what something is, for the log ----
  public static func Health(obj: ref<GameObject>) -> Float {
    if !IsDefined(obj) {
      return -1.0;
    }
    return GameInstance.GetStatPoolsSystem(obj.GetGame()).GetStatPoolValue(Cast<StatsObjectID>(obj.GetEntityID()), gamedataStatPoolType.Health, false);
  }

  public static func Describe(obj: ref<GameObject>) -> String {
    if !IsDefined(obj) {
      return "nothing";
    }
    let s = NameToString(obj.GetClassName());
    let puppet = obj as ScriptedPuppet;
    if IsDefined(puppet) {
      s += " " + TDBID.ToStringDEBUG(puppet.GetRecordID());
    }
    let a = GameObject.GetAttitudeBetween(obj, GetPlayer(obj.GetGame()));
    s += Equals(a, EAIAttitude.AIA_Friendly) ? " (friendly to V)" : (Equals(a, EAIAttitude.AIA_Hostile) ? " (hostile to V)" : " (neutral to V)");
    return s;
  }

  public static func V(v: Vector4) -> String {
    return "(" + FloatToStringPrec(v.X, 1) + ", " + FloatToStringPrec(v.Y, 1) + ", " + FloatToStringPrec(v.Z, 1) + ")";
  }
}
