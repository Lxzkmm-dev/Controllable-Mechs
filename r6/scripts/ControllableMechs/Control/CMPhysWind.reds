// =============================================================================
// MECHS OF NIGHT CITY - THE CYBERPUNK WIND FRAMEWORK, IF IT IS THERE
//
// The Wind Framework's prop layer drags every loose PhysX body near the player; a V3
// drone's body has its air from MNC's own flight model, so it is kept out of that drag
// (CWF_IgnoreNear, called every frame with one id per body). A no-op without the framework.
// =============================================================================
module ControllableMechs.Control

@if(ModuleExists("CyberpunkWindFramework"))
public abstract class CMPhysWind {
  public static func IgnoreNear(id: Int32, position: Vector4, radius: Float) -> Void {
    CWF_IgnoreNear(id, position, radius);
  }
}

@if(!ModuleExists("CyberpunkWindFramework"))
public abstract class CMPhysWind {
  public static func IgnoreNear(id: Int32, position: Vector4, radius: Float) -> Void {}
}
