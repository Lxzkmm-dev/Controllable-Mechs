// =============================================================================
// MECHS OF NIGHT CITY - MNC PHYSICS VERSION 3, IF IT IS THERE
//
// Per-physics-step control of a body (the plugin applies it right before every PhysX
// step): its gravity on or off, a continuous force and torque (world, N and N m), and
// what the body really did in the last step. Wishes are held until changed and dropped
// 0.3 s after the last call (then the body gets its gravity back). The real version when
// the plugin's version-3 scripts are installed, a harmless one otherwise.
// =============================================================================
module ControllableMechs.Control

@if(ModuleExists("MNCPhysics.V3"))
public abstract class CMPhysStep {
  public static func Present() -> Bool = true
  public static func SetForce(body: ref<PhysicalBodyInterface>, force: Vector4, torque: Vector4) -> Bool = MNCPhysics_SetForce(body, force, torque)
  public static func Release(body: ref<PhysicalBodyInterface>) -> Bool = MNCPhysics_Release(body)
  public static func Velocity(body: ref<PhysicalBodyInterface>) -> Vector4 = MNCPhysics_StepVelocity(body)
  public static func Spin(body: ref<PhysicalBodyInterface>) -> Vector4 = MNCPhysics_StepSpin(body)
  public static func Info(body: ref<PhysicalBodyInterface>) -> String = MNCPhysics_StepInfo(body)
}

@if(!ModuleExists("MNCPhysics.V3"))
public abstract class CMPhysStep {
  public static func Present() -> Bool = false
  public static func SetForce(body: ref<PhysicalBodyInterface>, force: Vector4, torque: Vector4) -> Bool = false
  public static func Release(body: ref<PhysicalBodyInterface>) -> Bool = false
  public static func Velocity(body: ref<PhysicalBodyInterface>) -> Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0)
  public static func Spin(body: ref<PhysicalBodyInterface>) -> Vector4 = new Vector4(0.0, 0.0, 0.0, 0.0)
  public static func Info(body: ref<PhysicalBodyInterface>) -> String = "MNC Physics version 3 not installed"
}
