// =============================================================================
// MECHS OF NIGHT CITY - MNC PHYSICS VERSION 3.1 / 3.2, IF IT IS THERE
//
// A body's shapes off as simulation shapes (they push nothing and nothing pushes them;
// bullets and rays still hit them), held while asked for every frame and put back when not.
// A V3 Octant's own thruster pods (kinematic physical meshes moved with the NPC) sat inside
// its physics body and PhysX shoved the body out at 16-18 m/s the moment it went live (a10).
// Version 3.2 also hands over the body of a component scripts can't ask for one: the
// Griffin's body and wings are physical skinned meshes, whose CreatePhysicalBodyInterface
// returns nothing to scripts (a12: thrown into the ground at 23 m/s as it went live).
// The real version with the plugin's scripts installed, a harmless one otherwise.
// =============================================================================
module ControllableMechs.Control

@if(ModuleExists("MNCPhysics.V31"))
public abstract class CMPhysColl {
  public static func Present() -> Bool = true
  public static func SetCollision(body: ref<PhysicalBodyInterface>, on: Bool) -> Bool = MNCPhysics_SetCollision(body, on)
}

@if(!ModuleExists("MNCPhysics.V31"))
public abstract class CMPhysColl {
  public static func Present() -> Bool = false
  public static func SetCollision(body: ref<PhysicalBodyInterface>, on: Bool) -> Bool = false
}

@if(ModuleExists("MNCPhysics.V32"))
public abstract class CMPhysBodies {
  public static func Present() -> Bool = true
  public static func Of(c: ref<IComponent>) -> ref<PhysicalBodyInterface> = MNCPhysics_ComponentBody(c, 0)
}

@if(!ModuleExists("MNCPhysics.V32"))
public abstract class CMPhysBodies {
  public static func Present() -> Bool = false
  public static func Of(c: ref<IComponent>) -> ref<PhysicalBodyInterface> = null
}
