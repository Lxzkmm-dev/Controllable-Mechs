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

// one mech's parts, 0..1 each, and which parts' damage effects are running on it
public class CMPartState {
  public let id: EntityID;
  public let hp: array<Float>;
  public let fx: array<Bool>;
  public let stage: array<Int32>;              // each arm's weak spot damage stage shown (0-2)
  public let fxInst: array<ref<FxInstance>>;   // the effects attached to it, and their parts
  public let fxPart: array<Int32>;
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
      ArrayPush(st.fx, false);
      ArrayPush(st.stage, 0);
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
    this.Effects(mech);
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
      CMCParts.BlowGun(mech, part == CMPart.ArmL());
      CMCParts.ShowGun(mech, part == CMPart.ArmL(), false);
    }

    this.Effects(mech);
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

  // The Minotaur's body, from the zone the game names or where the hit landed. Measured on
  // its meshes (metres above its feet): legs up to 1.1 (thighs to 1.9, inside the torso's
  // width), torso 1.05-2.3, the arms and MK.31s 1.8-2.5 and 0.55-1.2 m out, the sensor dome
  // above 2.3 in the middle, the pods 0.6-1.05 m behind at 1.55-2.1.
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
    if up < 1.15 {
      return side < 0.0 ? CMPart.LegL() : CMPart.LegR();
    }
    if AbsF(side) > 0.62 && up > 1.6 {
      return side < 0.0 ? CMPart.ArmL() : CMPart.ArmR();
    }
    if back > 0.55 && up > 1.45 && up < 2.25 {
      return CMPart.Pods();
    }
    if up > 2.3 && AbsF(side) < 0.4 {
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
      CMLinkSystem.Get(this.m_test.GetGame()).TestAttitude(this.m_test, false);
      GameInstance.GetGodModeSystem(this.m_test.GetGame()).RemoveGodMode(this.m_test.GetEntityID(), gameGodModeType.Immortal, n"CMDamageTest");
      CMCParts.ShieldSpots(this.m_test, false);
      this.m_test = null;
    }
    if !on || !IsDefined(mech) {
      return;
    }
    mech.m_cmTestTarget = true;
    // a linked mech is friendly to V, and the game drops V's hits on friendlies: it is made
    // neutral for the test (and friendly again after)
    CMLinkSystem.Get(mech.GetGame()).TestAttitude(mech, true);
    GameInstance.GetGodModeSystem(mech.GetGame()).AddGodMode(mech.GetEntityID(), gameGodModeType.Immortal, n"CMDamageTest");
    // the vanilla weak spots only die when part damage breaks that gun (BlowGun), not to\n    // the game's own weak spot damage
    CMCParts.ShieldSpots(mech, true);
    this.m_test = mech;
    CMCSession.Log("parts: damage test on");
  }

  // a hit on the mech under test (from CMCCalm)
  public func TestHit(mech: ref<NPCPuppet>, hit: ref<gameHitEvent>) -> Void {
    if !IsDefined(mech) {
      return;
    }
    // neutral again, whatever the hit did to how it sees V
    CMLinkSystem.Get(mech.GetGame()).TestAttitude(mech, true);
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

  // the weak spots made (or no longer) invulnerable for the damage test
  public static func ShieldSpots(mech: ref<NPCPuppet>, on: Bool) -> Void {
    let comp = mech.GetWeakspotComponent();
    if !IsDefined(comp) {
      return;
    }
    let spots: array<wref<WeakspotObject>>;
    comp.GetWeakspots(spots);
    let gods = GameInstance.GetGodModeSystem(mech.GetGame());
    for spot in spots {
      if IsDefined(spot) {
        if on {
          gods.AddGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"CMDamageTest");
        } else {
          gods.RemoveGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"CMDamageTest");
        }
      }
    }
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

  // The damage effects, one set per broken part, started once when it breaks (or on a
  // mech found broken) and stopped when it is restored; nothing runs per frame.
  //   - named effects the Minotaur's own entity carries (EffectsOf): its arm smoke at each
  //     gun port (l/r_arm_04), the locomotion-malfunction sparks and generator smoke at the
  //     legs, the optics malfunction on the sensor
  //   - effect files it doesn't name, spawned and attached to its slots (Attach): the
  //     Centaur boss's weak spot sparks at a gun port (slots WeakspotLeft/Right, on the arm),
  //     Minotaur smoke and the q003 boss's fuel leak on the pods (slot Chest, on the upper
  //     body)
  // And warnings before a gun goes: its weak spot's own damage stages at 70% and 35%.
  public func Effects(mech: ref<NPCPuppet>) -> Void {
    if !IsDefined(mech) {
      return;
    }
    let st = this.State(mech.GetEntityID());
    let i = 0;
    while i < CMPart.Count() {
      let on = st.hp[i] <= 0.0 && i != CMPart.Torso();
      if NotEquals(on, st.fx[i]) {
        st.fx[i] = on;
        for name in CMCParts.EffectsOf(i) {
          if on {
            GameObjectEffectHelper.StartEffectEvent(mech, name);
          } else {
            GameObjectEffectHelper.StopEffectEvent(mech, name);
          }
        }
        if on {
          this.Attach(mech, st, i);
        } else {
          this.Detach(st, i);
        }
      }
      i += 1;
    }
    this.GunStage(mech, st, true);
    this.GunStage(mech, st, false);
  }

  public static func EffectsOf(part: Int32) -> array<CName> {
    switch part {
      case 0: return [n"hacks_optics_malfunction"];
      case 2: return [n"left_arm_destroyed"];
      case 3: return [n"right_arm_destroyed"];
      case 4: return [n"hacks_locomotion_malfunction", n"se_locomotion_malfunction_left"];
      case 5: return [n"hacks_locomotion_malfunction", n"se_locomotion_malfunction_right"];
    }
    return [];
  }

  private func Attach(mech: ref<NPCPuppet>, st: ref<CMPartState>, part: Int32) -> Void {
    switch part {
      case 2:
        this.AttachFx(mech, st, part, r"base\\fx\\quest\\q003\\boss_centaur\\weakspot_compensating\\weakspot_takedown_sparks.effect", n"WeakspotLeft", 0.0);
        break;
      case 3:
        this.AttachFx(mech, st, part, r"base\\fx\\quest\\q003\\boss_centaur\\weakspot_compensating\\weakspot_takedown_sparks.effect", n"WeakspotRight", 0.0);
        break;
      case 6:
        this.AttachFx(mech, st, part, r"base\\fx\\vehicles\\minotaur\\v_minotaur_smoke.effect", n"Chest", 0.35);
        this.AttachFx(mech, st, part, r"base\\fx\\vehicles\\minotaur\\v_minotaur_smoke.effect", n"Chest", -0.35);
        this.AttachFx(mech, st, part, r"base\\fx\\quest\\q003\\boss\\weakspot\\weakspot_fuel.effect", n"Chest", 0.0);
        break;
    }
  }

  // one effect file spawned at the mech and attached to one of its slots, `side` metres
  // across from it
  private func AttachFx(mech: ref<NPCPuppet>, st: ref<CMPartState>, part: Int32, path: ResRef, slot: CName, side: Float) -> Void {
    let fx: FxResource;
    ResourceAsyncRef.SetPath(fx.effect, path);
    let at: WorldTransform;
    WorldTransform.SetPosition(at, mech.GetWorldPosition());
    let inst = GameInstance.GetFxSystem(mech.GetGame()).SpawnEffect(fx, at);
    if !IsDefined(inst) {
      CMCSession.Log("parts: an effect did not spawn on " + NameToString(slot));
      return;
    }
    let rel: WorldTransform;
    WorldTransform.SetPosition(rel, new Vector4(side, 0.0, 0.0, 1.0));
    inst.AttachToSlot(mech, entAttachmentTarget.Transform, slot, rel);
    ArrayPush(st.fxInst, inst);
    ArrayPush(st.fxPart, part);
  }

  private func Detach(st: ref<CMPartState>, part: Int32) -> Void {
    let i = ArraySize(st.fxInst) - 1;
    while i >= 0 {
      if st.fxPart[i] == part {
        if IsDefined(st.fxInst[i]) {
          st.fxInst[i].BreakLoop();
          st.fxInst[i].Kill();
        }
        ArrayErase(st.fxInst, i);
        ArrayErase(st.fxPart, i);
      }
      i -= 1;
    }
  }

  // a gun's weak spot shows the damage it has taken: stage 1 below 70%, stage 2 below 35%
  private func GunStage(mech: ref<NPCPuppet>, st: ref<CMPartState>, left: Bool) -> Void {
    let part = left ? CMPart.ArmL() : CMPart.ArmR();
    let hp = st.hp[part];
    let stage = hp < 0.35 ? 2 : (hp < 0.7 ? 1 : 0);
    if stage == st.stage[part] {
      return;
    }
    let spot = CMCParts.Spot(mech, left);
    if IsDefined(spot) {
      if stage >= 1 && st.stage[part] < 1 {
        GameObjectEffectHelper.StartEffectEvent(spot, n"weakspot_damage_stage_01");
      }
      if stage >= 2 && st.stage[part] < 2 {
        GameObjectEffectHelper.StartEffectEvent(spot, n"weakspot_damage_stage_02");
      }
      if stage < st.stage[part] {
        GameObjectEffectHelper.StopEffectEvent(spot, n"weakspot_damage_stage_01");
        GameObjectEffectHelper.StopEffectEvent(spot, n"weakspot_damage_stage_02");
      }
    }
    st.stage[part] = stage;
  }

  // the weak spot on one arm, told apart by its side
  public static func Spot(mech: ref<NPCPuppet>, left: Bool) -> ref<WeakspotObject> {
    let comp = mech.GetWeakspotComponent();
    if !IsDefined(comp) {
      return null;
    }
    let spots: array<wref<WeakspotObject>>;
    comp.GetWeakspots(spots);
    let right = CMPilotRig.Dir(CMPilotRig.YawOf(mech.GetWorldForward()) - 90.0, 0.0);
    let pos = mech.GetWorldPosition();
    for spot in spots {
      if IsDefined(spot) {
        let side = Vector4.Dot(spot.GetWorldPosition() - pos, right);
        if (left && side < 0.0) || (!left && side > 0.0) {
          return spot;
        }
      }
    }
    return null;
  }

  // the MK.31 on one arm shown or shot off (its mesh component on the Minotaur)
  public static func ShowGun(mech: ref<NPCPuppet>, left: Bool, on: Bool) -> Void {
    let c = mech.FindComponentByName(left ? n"mch_003__minotaur_weapons_l_01" : n"mch_003__minotaur_weapons_r_01");
    if IsDefined(c) {
      c.Toggle(on);
    }
  }

  // A gun shot off the vanilla way: the weak spot on that arm destroyed as the game does
  // it (its smoke, sparks and "destroyed" look; Omar's pick after trying both). Killing one
  // takes only that gun (Omar's clip of 8298d66). The two are told apart by their side.
  public static func BlowGun(mech: ref<NPCPuppet>, left: Bool) -> Void {
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
          // it has to be able to take the kill: the pilot session and the damage test shield it
          let gods = GameInstance.GetGodModeSystem(mech.GetGame());
          gods.RemoveGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"ControllableMechs");
          gods.RemoveGodMode(spot.GetEntityID(), gameGodModeType.Invulnerable, n"CMDamageTest");
          ScriptedWeakspotObject.Kill(spot);
          CMCSession.Log("parts: weak spot on the " + (left ? "left" : "right") + " (" + FloatToStringPrec(side, 1) + " m to the side) destroyed");
        }
      }
    }
  }
}
