// =============================================================================
// MECHS OF NIGHT CITY - THE MNC PHYSICS PLUGIN, IF IT IS THERE
//
// MNC Physics (plugin/MNCPhysics, red4ext/plugins/MNCPhysics) flies the drones: its scripts
// are compiled only while it is loaded, so everything MNC asks of it goes through here,
// in two versions: the real one when its module exists, a harmless one when it doesn't.
// Plugin version 2 and up: a body's velocity and spin, set through the engine's own
// physics proxy (the route mapped by the Wind Framework session, checked against the
// game's own SetLinearVelocity code). The per-step calls are CMPhysStep's.
// =============================================================================
module ControllableMechs.Control

@if(ModuleExists("MNCPhysics.V2"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = MNCPhysics_Version() > 0
  public static func Version() -> Int32 = MNCPhysics_Version()
  public static func HasVelocity() -> Bool = MNCPhysics_Version() >= 2
  public static func SetVelocity(body: ref<PhysicalBodyInterface>, v: Vector4) -> Bool = MNCPhysics_SetLinearVelocity(body, v)
  public static func SetSpin(body: ref<PhysicalBodyInterface>, w: Vector4) -> Bool = MNCPhysics_SetAngularVelocity(body, w)
}

// not loaded, or a version-1 build (inspect only)
@if(!ModuleExists("MNCPhysics.V2"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = false
  public static func Version() -> Int32 = 0
  public static func HasVelocity() -> Bool = false
  public static func SetVelocity(body: ref<PhysicalBodyInterface>, v: Vector4) -> Bool = false
  public static func SetSpin(body: ref<PhysicalBodyInterface>, w: Vector4) -> Bool = false
}
