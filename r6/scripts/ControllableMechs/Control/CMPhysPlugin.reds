// =============================================================================
// MECHS OF NIGHT CITY - THE MNC PHYSICS PLUGIN, IF IT IS THERE
//
// MNC Physics (plugin/MNCPhysics, red4ext/plugins/MNCPhysics) is optional: its scripts
// are compiled only while it is loaded, so everything MNC asks of it goes through here,
// in two versions: the real one when its module exists, a harmless one when it doesn't.
// v0 only inspects (what the engine's physics body really offers natively).
// =============================================================================
module ControllableMechs.Control

@if(ModuleExists("MNCPhysics.Plugin"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = MNCPhysics_Version() > 0
  public static func Version() -> Int32 = MNCPhysics_Version()
  public static func Inspect() -> String = MNCPhysics_Inspect()
  public static func BodyBits(body: ref<PhysicalBodyInterface>) -> String = MNCPhysics_BodyBits(body)
}

@if(!ModuleExists("MNCPhysics.Plugin"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = false
  public static func Version() -> Int32 = 0
  public static func Inspect() -> String = "!MNC PHYSICS PLUGIN NOT LOADED"
  public static func BodyBits(body: ref<PhysicalBodyInterface>) -> String = ""
}
