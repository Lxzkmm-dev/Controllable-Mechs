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
    CMCCalm.Note(ownerPuppet, evt.attackData.GetInstigator(), "a hit");
    return;
  }
  wrappedMethod(ownerPuppet, evt);
}

// threats handed over by the squad, by stimuli and by quest or AI scripts
@wrapMethod(TargetTrackingExtension)
public final static func InjectThreat(puppet: wref<ScriptedPuppet>, threat: wref<Entity>, accuracy: Float, opt cooldown: Float) -> Void {
  if IsDefined(puppet) && puppet.m_cmPiloted {
    CMCCalm.Note(puppet, threat as GameObject, "a shared threat");
    return;
  }
  wrappedMethod(puppet, threat, accuracy, cooldown);
}

@wrapMethod(TargetTrackingExtension)
public final static func InjectThreat(puppet: wref<ScriptedPuppet>, const threat: script_ref<TrackedLocation>) -> Void {
  if IsDefined(puppet) && puppet.m_cmPiloted {
    return;
  }
  wrappedMethod(puppet, threat);
}

@wrapMethod(TargetTrackingExtension)
public final static func InjectThreat(puppet: wref<ScriptedPuppet>, pos: Vector4, timeToLive: Float) -> Void {
  if IsDefined(puppet) && puppet.m_cmPiloted {
    return;
  }
  wrappedMethod(puppet, pos, timeToLive);
}

// the squad pushing an enemy to every member
@wrapMethod(TargetTrackingExtension)
protected cb func OnEnemyPushedToSquad(evt: ref<EnemyPushedToSquad>) -> Bool {
  let owner = this.GetEntity() as ScriptedPuppet;
  if IsDefined(owner) && owner.m_cmPiloted {
    return false;
  }
  return wrappedMethod(evt);
}

public abstract class CMCCalm {
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
