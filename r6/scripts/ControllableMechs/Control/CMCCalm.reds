// =============================================================================
// CONTROLLABLE MECHS - CONTROL FRAMEWORK: KEEPING THE PILOTED UNIT'S AI OUT OF IT
//
// Why a piloted mech kept acting on its own in a fight: every hit it took went
// through the game's TargetTrackingExtension.OnHit, which alerts the puppet and
// adds whoever shot it to its threat list. A threat is a combat target: the mech
// turned to face it, walked at it, and swung at it when it was close, and while
// its arms were busy the guns could not reach the reticle. Its squad shares
// threats the same way. Switching its senses and reactions off did not touch
// this path.
//
// So the unit is flagged while piloted (ScriptedPuppet.m_cmPiloted, set on
// entering and cleared on leaving), and the script functions that hand a puppet
// a threat do nothing for a flagged puppet. Every other puppet in the game pays
// one field check on those calls; nothing here runs on its own.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

@addField(ScriptedPuppet)
public let m_cmPiloted: Bool;

// being hit: no alert, no threat
@wrapMethod(TargetTrackingExtension)
public final static func OnHit(ownerPuppet: wref<ScriptedPuppet>, evt: ref<gameHitEvent>) -> Void {
  if IsDefined(ownerPuppet) && ownerPuppet.m_cmPiloted {
    let shooter = evt.attackData.GetInstigator();
    CMCCalm.Note(ownerPuppet, shooter, "a hit");
    CMCSession.Get(ownerPuppet.GetGame()).UnitHit(evt);   // part damage
    // where it came from, for the pilot's HUD (not the mech's own rounds, credited to V)
    if IsDefined(shooter) && !shooter.IsPlayer() {
      CMCSession.Get(ownerPuppet.GetGame()).HitFrom(shooter.GetWorldPosition());
    }
    return;
  }
  // the linked mech under the damage test: V's hits wear its parts, and nothing else
  if IsDefined(ownerPuppet) && ownerPuppet.m_cmTestTarget {
    CMCParts.Get(ownerPuppet.GetGame()).TestHit(ownerPuppet as NPCPuppet, evt);
    return;
  }
  // Someone hit by the piloted unit: the hit is credited to V (the kill, XP and heat are
  // V's), but the one to turn on is the unit that fired. The game's own function runs with
  // the unit standing in as the instigator, then V is put back.
  if IsDefined(ownerPuppet) && IsDefined(evt) && IsDefined(evt.attackData) {
    let credited = evt.attackData.GetInstigator();
    let unit = CMCCalm.FiredBy(evt, credited);
    if IsDefined(unit) && IsDefined(credited) && unit != credited {
      evt.attackData.SetInstigator(unit);
      wrappedMethod(ownerPuppet, evt);
      evt.attackData.SetInstigator(credited);
      // and V, named as the attacker by the credit, comes off its threat list
      if credited.IsPlayer() && !evt.attackData.HasFlag(hitFlag.WasKillingBlow) {
        TargetTrackingExtension.RemoveThreat(ownerPuppet, credited);
      }
      CMCCalm.Drew(ownerPuppet, unit);
      return;
    }
  }
  wrappedMethod(ownerPuppet, evt);
}

// threats handed over by the squad, by stimuli and by quest or AI scripts
@wrapMethod(TargetTrackingExtension)
public final static func InjectThreat(puppet: wref<ScriptedPuppet>, threat: wref<Entity>, accuracy: Float, opt cooldown: Float) -> Void {
  if IsDefined(puppet) && puppet.m_cmPiloted {
    CMCCalm.Note(puppet, threat as GameObject, "a shared threat");
    // the game has just named one of V's enemies to the unit: that enemy gets the unit
    // as its enemy in return, so it fights the mech and not only V
    CMCCalm.DrawFire(puppet, threat as ScriptedPuppet);
    return;
  }
  if IsDefined(puppet) && puppet.m_cmTestTarget {
    return;
  }
  wrappedMethod(puppet, threat, accuracy, cooldown);
}

// The piloted unit's state stays relaxed: a request to alert it or put it in combat is
// refused here, where it is made. (Letting it happen and resetting it afterwards made the
// mech put its guns away and draw them again, and knocked the gun look-ats off.)
@wrapMethod(NPCPuppet)
public final static func ChangeHighLevelState(obj: ref<GameObject>, newState: gamedataNPCHighLevelState) -> Void {
  let puppet = obj as ScriptedPuppet;
  if IsDefined(puppet) && (puppet.m_cmPiloted || puppet.m_cmTestTarget)
    && (Equals(newState, gamedataNPCHighLevelState.Alerted) || Equals(newState, gamedataNPCHighLevelState.Combat)
      || Equals(newState, gamedataNPCHighLevelState.Stealth) || Equals(newState, gamedataNPCHighLevelState.Fear)) {
    if CMPilotSystem.Get(puppet.GetGame()).ShowDebug() {
      CMCHits.Trace(puppet.GetGame(), "AI kept out: a change of state to " + EnumValueToString("gamedataNPCHighLevelState", Cast<Int64>(EnumInt(newState))) + " was refused");
    }
    return;
  }
  wrappedMethod(obj, newState);
}

@wrapMethod(NPCStatesComponent)
public final static func AlertPuppet(ownerPuppet: wref<ScriptedPuppet>) -> Void {
  if IsDefined(ownerPuppet) && (ownerPuppet.m_cmPiloted || ownerPuppet.m_cmTestTarget) {
    return;
  }
  wrappedMethod(ownerPuppet);
}

@wrapMethod(TargetTrackingExtension)
public final static func InjectThreat(puppet: wref<ScriptedPuppet>, const threat: script_ref<TrackedLocation>) -> Void {
  if IsDefined(puppet) && (puppet.m_cmPiloted || puppet.m_cmTestTarget) {
    return;
  }
  wrappedMethod(puppet, threat);
}

@wrapMethod(TargetTrackingExtension)
public final static func InjectThreat(puppet: wref<ScriptedPuppet>, pos: Vector4, timeToLive: Float) -> Void {
  if IsDefined(puppet) && (puppet.m_cmPiloted || puppet.m_cmTestTarget) {
    return;
  }
  wrappedMethod(puppet, pos, timeToLive);
}

// the squad pushing an enemy to every member
@wrapMethod(TargetTrackingExtension)
protected cb func OnEnemyPushedToSquad(evt: ref<EnemyPushedToSquad>) -> Bool {
  let owner = this.GetEntity() as ScriptedPuppet;
  if IsDefined(owner) && (owner.m_cmPiloted || owner.m_cmTestTarget) {
    return false;
  }
  return wrappedMethod(evt);
}

public abstract class CMCCalm {
  // The piloted unit behind a hit, if there is one: the owner of a flagged weapon, or,
  // for a hit of V's with no weapon (the missile's blast), the unit that launched a
  // missile in the last moments (CMCHits.Blame). Null for every other hit in the game,
  // after one field check (two for V's weaponless hits).
  public static func FiredBy(evt: ref<gameHitEvent>, credited: wref<GameObject>) -> wref<GameObject> {
    let w = evt.attackData.GetWeapon();
    if IsDefined(w) {
      if w.m_cmPiloted {
        return w.GetOwner();
      }
      return null;
    }
    if IsDefined(credited) && credited.IsPlayer() {
      return CMCHits.Blamed(credited.GetGame());
    }
    return null;
  }

  // An enemy of V's that the game has named to the piloted unit: make it the unit's enemy
  // too (hostile to the unit, with the unit on its threat list), so it goes for the mech.
  // With CONFIG > HIDE V WHILE LINKED, V is also taken off its threat list, so it stops
  // searching for V. Only enemies already hostile to V are touched; the threat call does
  // nothing when the unit is on the list already.
  public static func DrawFire(unit: wref<ScriptedPuppet>, enemy: wref<ScriptedPuppet>) -> Void {
    if !IsDefined(enemy) || enemy.m_cmPiloted || enemy.IsPlayer() || !ScriptedPuppet.IsAlive(enemy) {
      return;
    }
    let player = GetPlayer(unit.GetGame());
    if !IsDefined(player) || NotEquals(GameObject.GetAttitudeBetween(enemy, player), EAIAttitude.AIA_Hostile) {
      return;
    }
    let turned = false;
    if NotEquals(GameObject.GetAttitudeBetween(enemy, unit), EAIAttitude.AIA_Hostile) {
      GameObject.ChangeAttitudeToHostile(enemy, unit);
      turned = true;
    }
    TargetTrackingExtension.InjectThreat(enemy, unit);
    let cfg = CMPilotSystem.Get(unit.GetGame());
    if cfg.HideOperator() {
      TargetTrackingExtension.RemoveThreat(enemy, player);
    }
    if turned && cfg.ShowDebug() {
      CMCHits.Trace(unit.GetGame(), "aggro: " + CMCHits.Describe(enemy) + ", " + FloatToStringPrec(Vector4.Distance(enemy.GetWorldPosition(), unit.GetWorldPosition()), 1) + " m from the mech, was made hostile to the mech and given it as a threat");
    }
  }

  // with diagnostics on: who was made to turn on the unit
  public static func Drew(victim: wref<ScriptedPuppet>, unit: wref<GameObject>) -> Void {
    if !CMPilotSystem.Get(victim.GetGame()).ShowDebug() {
      return;
    }
    CMCHits.Trace(victim.GetGame(), "aggro: " + CMCHits.Describe(victim) + " was hit and handed the mech as its attacker, " + FloatToStringPrec(Vector4.Distance(victim.GetWorldPosition(), unit.GetWorldPosition()), 1) + " m away; it is now " + (Equals(GameObject.GetAttitudeBetween(victim, unit), EAIAttitude.AIA_Hostile) ? "hostile" : "NOT hostile") + " to the mech");
  }

  // with diagnostics on: what was kept away from the piloted unit, and how close it was
  public static func Note(owner: wref<ScriptedPuppet>, from: wref<GameObject>, what: String) -> Void {
    if !IsDefined(owner) || !CMPilotSystem.Get(owner.GetGame()).ShowDebug() {
      return;
    }
    let who = "something";
    let dist = "?";
    if IsDefined(from) {
      who = CMCHits.Describe(from);
      dist = FloatToStringPrec(Vector4.Distance(owner.GetWorldPosition(), from.GetWorldPosition()), 1);
    }
    CMCHits.Trace(owner.GetGame(), "AI kept out: " + what + " from " + who + " at " + dist + " m raised no alert and no threat");
  }
}

// V while piloting: no jumping or crouching. Space and Ctrl climb and descend a drone, and
// NoJump alone did not stop V hopping and ducking at the operator's spot.
@wrapMethod(JumpDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a jump was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}

@wrapMethod(CrouchDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a crouch was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}
// the cyberware jumps (Reinforced Tendons, Lynx Paws) too: the plain jump's block alone
// left V jumping
@wrapMethod(ChargeJumpDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a ChargeJumpDecisions jump was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}
// the cyberware jumps (Reinforced Tendons, Lynx Paws) too: the plain jump's block alone
// left V jumping
@wrapMethod(DoubleJumpDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a DoubleJumpDecisions jump was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}
// the cyberware jumps (Reinforced Tendons, Lynx Paws) too: the plain jump's block alone
// left V jumping
@wrapMethod(HoverJumpDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a HoverJumpDecisions jump was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}
// Space at a ledge or low wall is a climb or a vault, not a jump: refused as well
@wrapMethod(ClimbDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a ClimbDecisions move was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}
// Space at a ledge or low wall is a climb or a vault, not a jump: refused as well
@wrapMethod(VaultDecisions)
protected const func EnterCondition(const stateContext: ref<StateContext>, const scriptInterface: ref<StateGameScriptInterface>) -> Bool {
  let player = scriptInterface.executionOwner as PlayerPuppet;
  if IsDefined(player) && IsDefined(player.m_cmcSession) {
    if wrappedMethod(stateContext, scriptInterface) && CMPilotSystem.Get(player.GetGame()).ShowDebug() {
      CMCHits.Trace(player.GetGame(), "operator: a VaultDecisions move was refused");
    }
    return false;
  }
  return wrappedMethod(stateContext, scriptInterface);
}