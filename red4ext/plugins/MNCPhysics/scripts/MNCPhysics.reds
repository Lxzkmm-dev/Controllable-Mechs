// MNC Physics (the optional plugin): its marker module. This folder is added to the script
// compilation by the plugin itself, so it only exists while the plugin is loaded; MNC
// checks for it with @if(ModuleExists("MNCPhysics.Plugin")). The natives themselves are
// in MNCPhysicsNatives.reds (global, outside any module, as the plugin registers them).
module MNCPhysics.Plugin

public abstract class MNCPhysicsPlugin {
  public static func Present() -> Bool = MNCPhysics_Version() > 0
}
