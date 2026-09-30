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
    // the damage test: whether V's rounds on the test mech went through (diagnostics)
    let test = hitEvent.target as ScriptedPuppet;
    if IsDefined(test) && test.m_cmTestTarget {
      CMCHits.Landed(test.GetGame(), hitEvent);
    }
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

  // The unit answerable for V's weaponless hits for a short while: the missile's blast is
  // an attack of V's with no weapon, so the unit that launched it says so here, and those
  // it hits turn on the unit (CMCCalm).
  private let m_blamed: wref<GameObject>;
  private let m_blameUntil: Float;

  public static func Blame(unit: wref<GameObject>, seconds: Float) -> Void {
    let sys = CMCHits.Get(unit.GetGame());
    if IsDefined(sys) {
      sys.m_blamed = unit;
      sys.m_blameUntil = EngineTime.ToFloat(GameInstance.GetEngineTime(unit.GetGame())) + seconds;
    }
  }

  public static func Blamed(game: GameInstance) -> wref<GameObject> {
    let sys = CMCHits.Get(game);
    if IsDefined(sys) && IsDefined(sys.m_blamed) && EngineTime.ToFloat(GameInstance.GetEngineTime(game)) < sys.m_blameUntil {
      return sys.m_blamed;
    }
    return null;
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
