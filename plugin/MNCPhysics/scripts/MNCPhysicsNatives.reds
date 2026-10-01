// MNC Physics (the optional plugin): its natives (src/Main.cpp registers them by these names)
public static native func MNCPhysics_Version() -> Int32
public static native func MNCPhysics_Inspect() -> String
public static native func MNCPhysics_BodyBits(body: ref<PhysicalBodyInterface>) -> String
// v1 (plugin version 2): a body's velocity and spin (world, m/s and rad/s), and its sleep;
// false / zero when the body isn't a live physics body
public static native func MNCPhysics_SetLinearVelocity(body: ref<PhysicalBodyInterface>, velocity: Vector4) -> Bool
public static native func MNCPhysics_SetAngularVelocity(body: ref<PhysicalBodyInterface>, spin: Vector4) -> Bool
public static native func MNCPhysics_GetLinearVelocity(body: ref<PhysicalBodyInterface>) -> Vector4
public static native func MNCPhysics_GetAngularVelocity(body: ref<PhysicalBodyInterface>) -> Vector4
public static native func MNCPhysics_SetSleeping(body: ref<PhysicalBodyInterface>, sleeping: Bool) -> Bool
// v3 (plugin version 3): wishes applied before every physics step, held until changed and
// dropped 0.3 s after the last call (then the body's gravity is given back)
public static native func MNCPhysics_SetGravity(body: ref<PhysicalBodyInterface>, on: Bool) -> Bool
public static native func MNCPhysics_SetForce(body: ref<PhysicalBodyInterface>, force: Vector4, torque: Vector4) -> Bool
public static native func MNCPhysics_Release(body: ref<PhysicalBodyInterface>) -> Bool
public static native func MNCPhysics_StepVelocity(body: ref<PhysicalBodyInterface>) -> Vector4
public static native func MNCPhysics_StepSpin(body: ref<PhysicalBodyInterface>) -> Vector4
public static native func MNCPhysics_StepInfo(body: ref<PhysicalBodyInterface>) -> String
