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
