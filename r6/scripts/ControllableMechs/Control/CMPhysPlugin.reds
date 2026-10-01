// =============================================================================
// MECHS OF NIGHT CITY - THE MNC PHYSICS PLUGIN, IF IT IS THERE
//
// MNC Physics (plugin/MNCPhysics, red4ext/plugins/MNCPhysics) is optional: its scripts
// are compiled only while it is loaded, so everything MNC asks of it goes through here,
// in two versions: the real one when its module exists, a harmless one when it doesn't.
// Plugin version 2: a body's velocity and spin, set and read through the engine's own
// physics proxy (the route mapped by the Wind Framework session, checked against the
// game's own SetLinearVelocity code).
// =============================================================================
module ControllableMechs.Control

// version 1 installed (inspect only): no velocity calls
@if(ModuleExists("MNCPhysics.Plugin") && !ModuleExists("MNCPhysics.V2"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = MNCPhysics_Version() > 0
  public static func Version() -> Int32 = MNCPhysics_Version()
  public static func Inspect() -> String = MNCPhysics_Inspect()
  public static func BodyBits(body: ref<PhysicalBodyInterface>) -> String = MNCPhysics_BodyBits(body)
  public static func HasVelocity() -> Bool = false
  public static func SetVelocity(body: ref<PhysicalBodyInterface>, v: Vector4) -> Bool = false
  public static func SetSpin(body: ref<PhysicalBodyInterface>, w: Vector4) -> Bool = false
  public static func Velocity(body: ref<PhysicalBodyInterface>) -> Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0)
  public static func Spin(body: ref<PhysicalBodyInterface>) -> Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0)
  public static func SetSleeping(body: ref<PhysicalBodyInterface>, sleeping: Bool) -> Bool = false
}

// version 2 installed: the body's velocity and spin
@if(ModuleExists("MNCPhysics.V2"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = MNCPhysics_Version() > 0
  public static func Version() -> Int32 = MNCPhysics_Version()
  public static func Inspect() -> String = MNCPhysics_Inspect()
  public static func BodyBits(body: ref<PhysicalBodyInterface>) -> String = MNCPhysics_BodyBits(body)
  public static func HasVelocity() -> Bool = MNCPhysics_Version() >= 2
  public static func SetVelocity(body: ref<PhysicalBodyInterface>, v: Vector4) -> Bool = MNCPhysics_SetLinearVelocity(body, v)
  public static func SetSpin(body: ref<PhysicalBodyInterface>, w: Vector4) -> Bool = MNCPhysics_SetAngularVelocity(body, w)
  public static func Velocity(body: ref<PhysicalBodyInterface>) -> Vector4 = MNCPhysics_GetLinearVelocity(body)
  public static func Spin(body: ref<PhysicalBodyInterface>) -> Vector4 = MNCPhysics_GetAngularVelocity(body)
  public static func SetSleeping(body: ref<PhysicalBodyInterface>, sleeping: Bool) -> Bool = MNCPhysics_SetSleeping(body, sleeping)
}

@if(!ModuleExists("MNCPhysics.Plugin"))
public abstract class CMPhysPlugin {
  public static func Present() -> Bool = false
  public static func Version() -> Int32 = 0
  public static func Inspect() -> String = "!MNC PHYSICS PLUGIN NOT LOADED"
  public static func BodyBits(body: ref<PhysicalBodyInterface>) -> String = ""
  public static func HasVelocity() -> Bool = false
  public static func SetVelocity(body: ref<PhysicalBodyInterface>, v: Vector4) -> Bool = false
  public static func SetSpin(body: ref<PhysicalBodyInterface>, w: Vector4) -> Bool = false
  public static func Velocity(body: ref<PhysicalBodyInterface>) -> Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0)
  public static func Spin(body: ref<PhysicalBodyInterface>) -> Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0)
  public static func SetSleeping(body: ref<PhysicalBodyInterface>, sleeping: Bool) -> Bool = false
}
