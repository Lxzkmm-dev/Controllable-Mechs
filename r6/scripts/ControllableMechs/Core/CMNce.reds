// =============================================================================
// MECHS OF NIGHT CITY - NIGHT CITY EMPIRES BRIDGE
//
// Night City Empires (NCE) is optional. What MNC calls in it compiles only when its module
// is installed (@if(ModuleExists("NightCityEmpires"))); without it the same names compile
// as stubs that say so, and MNC builds and runs the same either way.
//
//   AV DROP: NCE's airlift (NCEAirliftCallIn, NCE 0.8.0) flies an AV in to the first
//   open-sky spot 20 to 60 m from V, sets the linked unit down 12 m from it facing V and
//   links it; V pays NCE's AV DROP price. NCEAirliftReady says whether an AV can fly now.
//   MNC doesn't build its own AV drop (Omar: deployment uses NCE's AV system).
// =============================================================================
module ControllableMechs

@if(ModuleExists("NightCityEmpires"))
import NightCityEmpires.*

public abstract class CMNce {
  @if(ModuleExists("NightCityEmpires"))
  public static func Installed() -> Bool = true

  @if(!ModuleExists("NightCityEmpires"))
  public static func Installed() -> Bool = false

  // "" when an AV can fly now, otherwise the reason ("!...")
  @if(ModuleExists("NightCityEmpires"))
  public static func AirliftReady() -> String = NCEAirliftReady()

  @if(!ModuleExists("NightCityEmpires"))
  public static func AirliftReady() -> String = "!NEEDS NIGHT CITY EMPIRES"

  // "" when the AV is on its way, otherwise the reason ("!...")
  @if(ModuleExists("NightCityEmpires"))
  public static func AirliftCallIn(unit: ref<NPCPuppet>, near: Vector4, yaw: Float) -> String = NCEAirliftCallIn(unit, near, yaw)

  @if(!ModuleExists("NightCityEmpires"))
  public static func AirliftCallIn(unit: ref<NPCPuppet>, near: Vector4, yaw: Float) -> String = "!NEEDS NIGHT CITY EMPIRES"
}
