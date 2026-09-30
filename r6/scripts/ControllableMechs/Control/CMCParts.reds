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

// set on the linked mech while the damage test is on: V can shoot it, and it neither
// turns on V nor dies (CMCCalm skips its threat and alert functions, as for a piloted one)
@addField(ScriptedPuppet)
public let m_cmTestTarget: Bool;

// what one hit did: the part it landed on, and whether that broke it
public class CMPartHit {
  public let part: Int32;
  public let broke: Bool;
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
    // and the hull full again
    GameInstance.GetStatPoolsSystem(mech.GetGame()).RequestSettingStatPoolMaxValue(Cast<StatsObjectID>(mech.GetEntityID()), gamedataStatPoolType.Health, null);
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

    CMCSession.Log("parts: " + CMPart.Name(part) + " broken (dev tool)");
  }

  // One hit on a mech: which part it landed on, and how much of that part it took. The
  // body zone the game reports decides when it names a limb or the head; otherwise where
  // the hit landed on the body does. A part breaks once the hits on it add up to its share
  // of the mech's hull. None when the hit did no damage.
  public func Hit(mech: ref<NPCPuppet>, hit: ref<gameHitEvent>) -> ref<CMPartHit> {
    if !IsDefined(mech) || !IsDefined(hit) || !IsDefined(hit.attackData) || hit.attackData.HasFlag(hitFlag.DealNoDamage) {
      return null;
    }
    let dmg = hit.attackComputed.GetTotalAttackValue(gamedataStatPoolType.Health);
    if dmg <= 0.0 {
      return null;
    }
    // where on the body, in the mech's own frame
    let d = hit.hitPosition - mech.GetWorldPosition();
    let fwd = mech.GetWorldForward();
    let right = CMPilotRig.Dir(CMPilotRig.YawOf(fwd) - 90.0, 0.0);
    let up = d.Z;
    let side = Vector4.Dot(d, right);
    let back = -(d.X * fwd.X + d.Y * fwd.Y);
    let zone = EHitReactionZone.Special;
    if ArraySize(hit.hitRepresentationResult.hitShapes) > 0 {
      zone = HitShapeUserDataBase.GetHitReactionZone(hit.hitRepresentationResult.hitShapes[0].userData as HitShapeUserDataBase);
    }
    let r = new CMPartHit();
    r.part = CMCParts.PartAt(zone, up, side, back);
    let game = mech.GetGame();
    if CMPilotSystem.Get(game).ShowDebug() {
      CMCHits.Trace(game, "part hit: zone " + EnumValueToString("EHitReactionZone", Cast<Int64>(EnumInt(zone))) + ", " + FloatToStringPrec(up, 1) + " m up, " + FloatToStringPrec(side, 1) + " m right, " + FloatToStringPrec(back, 1) + " m back -> " + CMPart.Name(r.part) + ", " + FloatToStringPrec(dmg, 0) + " damage");
    }
    if r.part == CMPart.Torso() {
      return r;   // the torso is the hull
    }
    let st = this.State(mech.GetEntityID());
    let before = st.hp[r.part];
    if before <= 0.0 {
      return r;
    }
    let hull = GameInstance.GetStatPoolsSystem(game).GetStatPoolMaxPointValue(Cast<StatsObjectID>(mech.GetEntityID()), gamedataStatPoolType.Health);
    st.hp[r.part] = MaxF(0.0, before - dmg / MaxF(1.0, hull * CMPart.Share(r.part)));
    r.broke = st.hp[r.part] <= 0.0;
    return r;
  }

  // The Minotaur's body, from the zone the game names or where the hit landed.
  // Heights are metres above its feet; its arms and guns stand out about 1.3 m either side.
  public static func PartAt(zone: EHitReactionZone, up: Float, side: Float, back: Float) -> Int32 {
    switch zone {
      case EHitReactionZone.Head: return CMPart.Sensor();
      case EHitReactionZone.ArmLeft: return CMPart.ArmL();
      case EHitReactionZone.HandLeft: return CMPart.ArmL();
      case EHitReactionZone.ArmRight: return CMPart.ArmR();
      case EHitReactionZone.HandRight: return CMPart.ArmR();
      case EHitReactionZone.LegLeft: return CMPart.LegL();
      case EHitReactionZone.LegRight: return CMPart.LegR();
    }
    if up < 2.0 {
      return side < 0.0 ? CMPart.LegL() : CMPart.LegR();
    }
    if AbsF(side) > 1.3 {
      return side < 0.0 ? CMPart.ArmL() : CMPart.ArmR();
    }
    if back > 0.8 && up > 2.6 {
      return CMPart.Pods();
    }
    if up > 3.4 && back < 0.3 {
      return CMPart.Sensor();
    }
    return CMPart.Torso();
  }

  // ---- the damage test (a dev tool): V shoots the linked mech to try part damage ----
  private let m_test: wref<NPCPuppet>;

  public func Testing() -> Bool = IsDefined(this.m_test) && this.m_test.m_cmTestTarget

  // On: the mech can't be killed (it stops at 1 HP) and doesn't turn on V; V's hits on it
  // wear its parts as they would while piloted, each named on screen. Off, or on unlink:
  // back to normal.
  public func SetTest(mech: ref<NPCPuppet>, on: Bool) -> Void {
    if IsDefined(this.m_test) && (!on || this.m_test != mech) {
      this.m_test.m_cmTestTarget = false;
      GameInstance.GetGodModeSystem(this.m_test.GetGame()).RemoveGodMode(this.m_test.GetEntityID(), gameGodModeType.Immortal, n"CMDamageTest");
      this.m_test = null;
    }
    if !on || !IsDefined(mech) {
      return;
    }
    mech.m_cmTestTarget = true;
    GameInstance.GetGodModeSystem(mech.GetGame()).AddGodMode(mech.GetEntityID(), gameGodModeType.Immortal, n"CMDamageTest");
    this.m_test = mech;
    CMCSession.Log("parts: damage test on");
  }

  // a hit on the mech under test (from CMCCalm)
  public func TestHit(mech: ref<NPCPuppet>, hit: ref<gameHitEvent>) -> Void {
    if !IsDefined(mech) {
      return;
    }
    // friendly again, whatever the hit did to how it sees V
    CMLinkSystem.Get(mech.GetGame()).Befriend(mech);
    let r = this.Hit(mech, hit);
    if !IsDefined(r) {
      return;
    }
    if r.broke {
      this.Break(mech, r.part);
    }
    let text = CMPart.Name(r.part);
    if r.part == CMPart.Torso() {
      let hull = GameInstance.GetStatPoolsSystem(mech.GetGame()).GetStatPoolValue(Cast<StatsObjectID>(mech.GetEntityID()), gamedataStatPoolType.Health, true);
      text += " (HULL " + IntToString(RoundF(hull)) + "%)";
    } else {
      let hp = this.State(mech.GetEntityID()).hp[r.part];
      text += hp <= 0.0 ? " BROKEN" : " " + IntToString(RoundF(hp * 100.0)) + "%";
    }
    CMCParts.Screen(mech.GetGame(), "DAMAGE TEST: " + text);
  }

  // a line in the game's on-screen message slot
  public static func Screen(game: GameInstance, text: String) -> Void {
    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = 2.5;
    msg.message = text;
    let bb = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_Notifications);
    bb.SetVariant(GetAllBlackboardDefs().UI_Notifications.OnscreenMessage, ToVariant(msg), true);
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
}
