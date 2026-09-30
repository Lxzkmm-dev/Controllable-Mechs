// =============================================================================
// MECHS OF NIGHT CITY - CONTROL FRAMEWORK: PART DAMAGE (0.6.0 alpha)
//
// A piloted mech is seven parts on top of its hull (docs/DAMAGE_DESIGN.md):
//   the sensor head, the torso, the left and right MK.31 arms, the left and right
//   legs, and the missile pods.
// Each part has its own integrity from 0 to 1. Hits taken while piloted wear down
// the part they land on; at 0 the part is broken: a gun goes offline and is shot off
// the model, the sensor loses the optics and rangefinder, a leg cripples the walk, the
// pods stop firing. The torso is the hull itself and breaks nothing extra.
//
// Broken parts stay broken for the game session, piloted or not, until they are
// repaired (a planned mechanic; for now a dev button under CONFIG > DIAGNOSTICS
// restores them). The state is kept here by the mech's EntityID. Nothing here runs
// on its own: it only answers the pilot session and the terminal.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public abstract class CMPart {
  public static func Sensor() -> Int32 = 0
  public static func Torso() -> Int32 = 1
  public static func ArmL() -> Int32 = 2
  public static func ArmR() -> Int32 = 3
  public static func LegL() -> Int32 = 4
  public static func LegR() -> Int32 = 5
  public static func Pods() -> Int32 = 6
  public static func Count() -> Int32 = 7

  public static func Name(i: Int32) -> String {
    switch i {
      case 0: return "SENSOR";
      case 1: return "TORSO";
      case 2: return "MK.31 L";
      case 3: return "MK.31 R";
      case 4: return "LEG L";
      case 5: return "LEG R";
      case 6: return "MISSILE PODS";
    }
    return "PART";
  }

  // how tough a part is, as a share of the mech's whole hull: a part at 0.35 breaks once
  // hits on it add up to 35% of the hull (the torso is the hull and never breaks alone)
  public static func Share(i: Int32) -> Float {
    switch i {
      case 0: return 0.30;
      case 2: return 0.35;
      case 3: return 0.35;
      case 4: return 0.40;
      case 5: return 0.40;
      case 6: return 0.30;
    }
    return 1.0;
  }
}

// one mech's parts, 0..1 each
public class CMPartState {
  public let id: EntityID;
  public let hp: array<Float>;
}

public class CMCParts extends ScriptableSystem {
  private let m_states: array<ref<CMPartState>>;

  public static func Get(game: GameInstance) -> ref<CMCParts> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMCParts") as CMCParts;
  }

  // the state for a mech, made whole the first time it is asked for
  public func State(id: EntityID) -> ref<CMPartState> {
    for st in this.m_states {
      if st.id == id {
        return st;
      }
    }
    let st = new CMPartState();
    st.id = id;
    let i = 0;
    while i < CMPart.Count() {
      ArrayPush(st.hp, 1.0);
      i += 1;
    }
    ArrayPush(this.m_states, st);
    return st;
  }

  // the dev tool: every part whole again, the model and the walk put back
  public func Restore(mech: ref<NPCPuppet>) -> Void {
    if !IsDefined(mech) {
      return;
    }
    let st = this.State(mech.GetEntityID());
    let i = 0;
    while i < CMPart.Count() {
      st.hp[i] = 1.0;
      i += 1;
    }
    CMCParts.ShowGun(mech, true, true);
    CMCParts.ShowGun(mech, false, true);
    CMCParts.Cripple(mech, true, false);
    CMCParts.Cripple(mech, false, false);
    let session = CMCSession.Get(mech.GetGame());
    if IsDefined(session) {
      session.PartsRestored();
    }
    CMCSession.Log("parts: all restored (dev tool)");
  }

  // the dev tool: one part broken outright, as if shot off (the pilot HUD picks it up at
  // the next link-in)
  public func Break(mech: ref<NPCPuppet>, part: Int32) -> Void {
    if !IsDefined(mech) || part < 0 || part >= CMPart.Count() || part == CMPart.Torso() {
      return;
    }
    this.State(mech.GetEntityID()).hp[part] = 0.0;
    if part == CMPart.ArmL() || part == CMPart.ArmR() {
      CMCParts.BreakWeakspot(mech, part == CMPart.ArmL());
      CMCParts.ShowGun(mech, part == CMPart.ArmL(), false);
    }
    if part == CMPart.LegL() || part == CMPart.LegR() {
      CMCParts.Cripple(mech, part == CMPart.LegL(), true);
    }
    CMCSession.Log("parts: " + CMPart.Name(part) + " broken (dev tool)");
  }

  // ---- what a broken part does to the model and the body ----

  // the MK.31 on one arm shown or shot off (its mesh component on the Minotaur)
  public static func ShowGun(mech: ref<NPCPuppet>, left: Bool, on: Bool) -> Void {
    let c = mech.FindComponentByName(left ? n"mch_003__minotaur_weapons_l_01" : n"mch_003__minotaur_weapons_r_01");
    if IsDefined(c) {
      c.Toggle(on);
    }
  }

  // the weak spot on that arm destroyed as the game does it (its own smoke, sparks and
  // "destroyed" look). The mech's two weak spots are told apart by which side they sit.
  public static func BreakWeakspot(mech: ref<NPCPuppet>, left: Bool) -> Void {
    let comp = mech.GetWeakspotComponent();
    if !IsDefined(comp) {
      return;
    }
    let spots: array<wref<WeakspotObject>>;
    comp.GetWeakspots(spots);
    let right = CMPilotRig.Dir(CMPilotRig.YawOf(mech.GetWorldForward()) - 90.0, 0.0);
    let pos = mech.GetWorldPosition();
    for spot in spots {
      if IsDefined(spot) {
        let side = Vector4.Dot(spot.GetWorldPosition() - pos, right);
        if (left && side < 0.0) || (!left && side > 0.0) {
          // it has to be able to take the kill: the pilot session shields it
          GameInstance.GetGodModeSystem(mech.GetGame()).RemoveGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"ControllableMechs");
          ScriptedWeakspotObject.Kill(spot);
          CMCSession.Log("parts: weak spot on the " + (left ? "left" : "right") + " (" + FloatToStringPrec(side, 1) + " m to the side) destroyed");
        }
      }
    }
  }

  // a broken leg: the game's own crippled-leg effect, when this game has it
  public static func Cripple(mech: ref<NPCPuppet>, left: Bool, on: Bool) -> Void {
    let id = left ? t"BaseStatusEffect.CrippledLegLeft" : t"BaseStatusEffect.CrippledLegRight";
    if !IsDefined(TweakDBInterface.GetStatusEffectRecord(id)) {
      return;
    }
    if on {
      StatusEffectHelper.ApplyStatusEffect(mech, id);
    } else {
      StatusEffectHelper.RemoveStatusEffect(mech, id);
    }
  }
}