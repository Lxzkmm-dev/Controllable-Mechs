// =============================================================================
// CONTROLLABLE MECHS - HIT TRACE (dev)
// Every hit the mech's MK.31 rounds make, as the game's damage pipeline sees it:
// what was hit and where, who the instigator was, the damage computed, and
// whether the hit was cancelled (DealNoDamage / FriendlyFireIgnored). Tells rounds
// that miss (no lines at all) from hits that land but get cancelled.
// Cost: a weapon is watched only after it has fired from Pilot Mode or the
// framework (a bool on the weapon); every other hit in the game does one field
// check. At most 25 lines per 5 s.
// =============================================================================
module ControllableMechs

@addField(WeaponObject)
public let m_cmWatched: Bool;

// M1 credit to V (on while the framework pilots, CMUMinotaur sets it per weapon): the
// hit's instigator becomes V before the pipeline runs, so its friendly-fire check,
// damage, kill, XP and NCPD heat all count as V's (the pipeline's PreProcess, Process
// and DealDamages all run inside ProcessPipeline)
@addField(WeaponObject)
public let m_cmCreditV: Bool;

@wrapMethod(DamageSystem)
private final func ProcessPipeline(hitEvent: ref<gameHitEvent>, cache: ref<CacheData>) -> Void {
  let w = hitEvent.attackData.GetWeapon();
  if IsDefined(w) && w.m_cmCreditV {
    let player = GetPlayer(w.GetGame());
    if IsDefined(player) {
      hitEvent.attackData.SetInstigator(player);
    }
  }
  wrappedMethod(hitEvent, cache);
  if IsDefined(w) && w.m_cmWatched {
    CMHitLog.Note(hitEvent);
  }
}

public class CMHitLog extends ScriptableSystem {
  private let m_window: Float;
  private let m_lines: Int32;

  public static func Get(game: GameInstance) -> ref<CMHitLog> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.CMHitLog") as CMHitLog;
  }

  public static func Note(hit: ref<gameHitEvent>) -> Void {
    let w = hit.attackData.GetWeapon();
    let sys = CMHitLog.Get(w.GetGame());
    if !IsDefined(sys) || !sys.Allow(EngineTime.ToFloat(GameInstance.GetEngineTime(w.GetGame()))) {
      return;
    }
    let data = hit.attackData;
    let cancelled = "";
    if data.HasFlag(hitFlag.DealNoDamage) {
      cancelled += " DealNoDamage";
    }
    if data.HasFlag(hitFlag.FriendlyFireIgnored) {
      cancelled += " FriendlyFireIgnored";
    }
    if data.HasFlag(hitFlag.FriendlyFire) {
      cancelled += " FriendlyFire";
    }
    let target = hit.target as GameObject;
    let instigator = data.GetInstigator();
    let line = "hit " + CMSpike2System.Describe(target)
      + " at " + CMHitLog.V(hit.hitPosition)
      + (IsDefined(target) ? " (" + FloatToStringPrec(Vector4.Distance(hit.hitPosition, target.GetWorldPosition()), 1) + " m from its origin)" : "")
      + ", instigator " + (IsDefined(instigator) ? NameToString(instigator.GetClassName()) : "none")
      + ", weapon " + TDBID.ToStringDEBUG(ItemID.GetTDBID(w.GetItemID()))
      + ", damage " + FloatToStringPrec(hit.attackComputed.GetTotalAttackValue(gamedataStatPoolType.Health), 1)
      + (data.HasFlag(hitFlag.WasKillingBlow) ? ", KILLING BLOW" : "")
      + (StrLen(cancelled) > 0 ? ", CANCELLED:" + cancelled : "");
    CMSpikeSystem.Log(line);
  }

  private func Allow(now: Float) -> Bool {
    if now - this.m_window > 5.0 {
      this.m_window = now;
      this.m_lines = 0;
    }
    this.m_lines += 1;
    return this.m_lines <= 25;
  }

  public static func V(v: Vector4) -> String {
    return "(" + FloatToStringPrec(v.X, 1) + ", " + FloatToStringPrec(v.Y, 1) + ", " + FloatToStringPrec(v.Z, 1) + ")";
  }

  // where a weapon item is and points, against the mech and the reticle ray (for the log)
  public static func Muzzle(name: String, w: ref<WeaponObject>, mech: ref<GameObject>, camPos: Vector4, aim: Vector4) -> String {
    if !IsDefined(w) {
      return name + " none";
    }
    let p = w.GetWorldPosition();
    let f = w.GetWorldForward();
    let local = p - mech.GetWorldPosition();
    let ray = Vector4.Normalize(aim - camPos);
    return name + " item at " + CMHitLog.V(p) + " (" + FloatToStringPrec(local.Z, 1) + " m up, " + FloatToStringPrec(SqrtF(local.X * local.X + local.Y * local.Y), 1) + " m out from the mech), barrel yaw "
      + FloatToStringPrec(Rad2Deg(AtanF(-f.X, f.Y)), 1) + " pitch " + FloatToStringPrec(Rad2Deg(AsinF(ClampF(f.Z, -1.0, 1.0))), 1)
      + " vs reticle ray yaw " + FloatToStringPrec(Rad2Deg(AtanF(-ray.X, ray.Y)), 1) + " pitch " + FloatToStringPrec(Rad2Deg(AsinF(ClampF(ray.Z, -1.0, 1.0))), 1);
  }
}
