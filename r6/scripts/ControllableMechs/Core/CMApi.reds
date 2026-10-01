// =============================================================================
// MECHS OF NIGHT CITY - PUBLIC API FOR OTHER MODS
//
// Stable calls for mods that build on MNC (Night City Empires' Mech Bay first). Names and
// signatures here are kept; new arguments come as optional ones.
//
//   CMApi.Wireframe(npc, out atlas, out part) -> Bool
//     A whole-unit wireframe of a robot MNC supports, for a UI image: white lines on
//     transparent with premultiplied alpha (tint it), a three-quarter front view, 512 x 512
//     in a 2048 x 1024 atlas. Atlas: mnc\ui\unit_wireframes.inkatlas. Parts: minotaur,
//     bombus, griffin, wyvern, octant (built by tools/units/wireframes.py from the meshes).
//     False when MNC has no wireframe of that unit.
//   CMApi.WireframeAtlas() -> ResRef, CMApi.WireframePart(npc) -> CName: the same, as the
//     types an inkImage takes.
//   CMApi.SetStationed(on) / IsStationed(): see CMLinkSystem.SetStationed.
// =============================================================================
module ControllableMechs

import ControllableMechs.Control.*

public abstract class CMApi {
  public static func WireframeAtlasPath() -> String = "mnc\\ui\\unit_wireframes.inkatlas"
  public static func WireframeAtlas() -> ResRef = r"mnc\\ui\\unit_wireframes.inkatlas"

  // the atlas part for this unit, or n"" when there is none
  public static func WireframePart(npc: ref<NPCPuppet>) -> CName {
    if !IsDefined(npc) {
      return n"";
    }
    switch npc.GetNPCType() {
      case gamedataNPCType.Mech:
        return n"minotaur";
      case gamedataNPCType.Drone:
        switch CMUDrone.Kind(npc) {
          case "bombus": return n"bombus";
          case "griffin": return n"griffin";
          case "octant": return n"octant";
        }
        return n"wyvern";
    }
    return n"";
  }

  public static func Wireframe(npc: ref<NPCPuppet>, out atlas: String, out part: String) -> Bool {
    let p = CMApi.WireframePart(npc);
    if !IsNameValid(p) {
      atlas = "";
      part = "";
      return false;
    }
    atlas = CMApi.WireframeAtlasPath();
    part = NameToString(p);
    return true;
  }

  public static func SetStationed(game: GameInstance, on: Bool) -> Void {
    CMLinkSystem.Get(game).SetStationed(on);
  }

  public static func IsStationed(game: GameInstance) -> Bool = CMLinkSystem.Get(game).IsStationed()
}
