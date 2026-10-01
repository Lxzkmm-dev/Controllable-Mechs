// =============================================================================
// MECHS OF NIGHT CITY - SENSOR THERMAL MODES
//
// T while piloting (a drone or a mech) cycles the sensor: off, WHT (white hot), THERMAL
// (orange), RED HOT. Built from Kiroshi Optics Thermal Vision by permission (credited on
// Nexus): the same full-screen colour grade, split by render object type (characters
// through a hot lookup table, the world through a cold one), made for a sensor
// (tools/thermal/build.py): vehicles read hot, the cold world has more contrast, bloom is
// off in every mode, and it lives under mnc\fx\thermal so it can't clash with the original.
// Nothing of the original's machinery (its settings, night-vision bridges, optics
// requirement, localization) is needed: the effects are registered on V's effect spawner
// when first used and stopped when the link closes.
// =============================================================================
module ControllableMechs.Control

public abstract class CMThermal {
  public static func Count() -> Int32 = 4   // off, white, orange, red

  public static func Name(mode: Int32) -> String {
    switch mode {
      case 1: return "WHT";
      case 2: return "THERMAL";
      case 3: return "RED HOT";
    }
    return "DAY";
  }

  private static func Effect(mode: Int32) -> CName {
    switch mode {
      case 1: return n"mnc_thermal_white";
      case 2: return n"mnc_thermal_orange";
      case 3: return n"mnc_thermal_red";
    }
    return n"";
  }

  // the three effects on V's effect spawner (once; the spawner keeps them)
  private static func Register(player: ref<GameObject>) -> Bool {
    let spawner = player.FindComponentByName(n"fx_status_effects") as entEffectSpawnerComponent;
    if !IsDefined(spawner) {
      return false;
    }
    CMThermal.Ensure(spawner, n"mnc_thermal_white", r"mnc\\fx\\thermal\\white.effect");
    CMThermal.Ensure(spawner, n"mnc_thermal_orange", r"mnc\\fx\\thermal\\orange.effect");
    CMThermal.Ensure(spawner, n"mnc_thermal_red", r"mnc\\fx\\thermal\\red.effect");
    return true;
  }

  private static func Ensure(spawner: ref<entEffectSpawnerComponent>, name: CName, path: ResRef) -> Void {
    for d in spawner.effectDescs {
      if Equals(d.effectName, name) {
        return;
      }
    }
    let desc = new entEffectDesc();
    desc.effectName = name;
    desc.effect *= path;
    ArrayPush(spawner.effectDescs, desc);
  }

  // the sensor in `mode` (0 = off); false when the effects couldn't be registered
  public static func Set(game: GameInstance, mode: Int32) -> Bool {
    let player = GetPlayer(game);
    if !IsDefined(player) {
      return false;
    }
    GameObjectEffectHelper.StopEffectEvent(player, n"mnc_thermal_white");
    GameObjectEffectHelper.StopEffectEvent(player, n"mnc_thermal_orange");
    GameObjectEffectHelper.StopEffectEvent(player, n"mnc_thermal_red");
    if mode <= 0 {
      return true;
    }
    if !CMThermal.Register(player) {
      return false;
    }
    GameObjectEffectHelper.StartEffectEvent(player, CMThermal.Effect(mode), true);
    return true;
  }
}
