module ThermalVision

public enum ThermalVisionNightVisionProvider {
  Automatic = 0,
  KiroshiOptics = 1,
  TrueNightVision = 2,
  Disabled = 3
}

public class ThermalVisionModeStorage extends ScriptableService {
  private persistent let m_selectedMode: ThermalVisionMode;

  public func GetSelectedMode() -> ThermalVisionMode {
    switch this.m_selectedMode {
      case ThermalVisionMode.Thermal:
        return ThermalVisionMode.Thermal;
      case ThermalVisionMode.RedHot:
        return ThermalVisionMode.RedHot;
      case ThermalVisionMode.WhiteHot:
        return ThermalVisionMode.WhiteHot;
    }

    return ThermalVisionMode.Thermal;
  }

  public func SaveSelectedMode(mode: ThermalVisionMode) -> Void {
    this.m_selectedMode = mode;
  }

  public static func Get() -> ref<ThermalVisionModeStorage> {
    return GameInstance.GetScriptableServiceContainer().GetService(n"ThermalVision.ThermalVisionModeStorage") as ThermalVisionModeStorage;
  }
}

public class ThermalVisionSettings extends ScriptableSystem {
  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Integration")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-NightVisionProvider")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-NightVisionProvider-Description")
  @runtimeProperty("ModSettings.displayValues.Automatic", "ThermalVision-Settings-NightVisionProvider-Automatic")
  @runtimeProperty("ModSettings.displayValues.KiroshiOptics", "ThermalVision-Settings-NightVisionProvider-KiroshiOptics")
  @runtimeProperty("ModSettings.displayValues.TrueNightVision", "ThermalVision-Settings-NightVisionProvider-TrueNightVision")
  @runtimeProperty("ModSettings.displayValues.Disabled", "ThermalVision-Settings-NightVisionProvider-Disabled")
  public let nightVisionProvider: ThermalVisionNightVisionProvider = ThermalVisionNightVisionProvider.Automatic;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-KeyboardActivationPrimary")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-KeyboardActivationPrimary-Description")
  public let keyboardActivationPrimary: EInputKey = EInputKey.IK_F10;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-KeyboardActivationModifier")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-KeyboardActivationModifier-Description")
  public let keyboardActivationModifier: EInputKey = EInputKey.IK_None;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-KeyboardCyclePrimary")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-KeyboardCyclePrimary-Description")
  public let keyboardCyclePrimary: EInputKey = EInputKey.IK_F10;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-KeyboardCycleModifier")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-KeyboardCycleModifier-Description")
  public let keyboardCycleModifier: EInputKey = EInputKey.IK_LShift;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-ControllerActivationPrimary")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-ControllerActivationPrimary-Description")
  public let controllerActivationPrimary: EInputKey = EInputKey.IK_None;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-ControllerActivationModifier")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-ControllerActivationModifier-Description")
  public let controllerActivationModifier: EInputKey = EInputKey.IK_None;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-ControllerCyclePrimary")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-ControllerCyclePrimary-Description")
  public let controllerCyclePrimary: EInputKey = EInputKey.IK_None;

  @runtimeProperty("ModSettings.mod", "Kiroshi Optics Thermal Vision")
  @runtimeProperty("ModSettings.category", "ThermalVision-Settings-Input")
  @runtimeProperty("ModSettings.category.order", "0")
  @runtimeProperty("ModSettings.displayName", "ThermalVision-Settings-ControllerCycleModifier")
  @runtimeProperty("ModSettings.description", "ThermalVision-Settings-ControllerCycleModifier-Description")
  public let controllerCycleModifier: EInputKey = EInputKey.IK_None;

  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
    ModSettings.RegisterListenerToModifications(this);
  }

  private func OnDetach() -> Void {
    ModSettings.UnregisterListenerToClass(this);
    ModSettings.UnregisterListenerToModifications(this);
  }

  private func OnModSettingsChange() -> Void {
    let system: ref<ThermalVisionSystem> = ThermalVisionSystem.Get(this.GetGameInstance());
    if IsDefined(system) {
      system.RebindInput();
    }
  }

  public static func Get(gameInstance: GameInstance) -> ref<ThermalVisionSettings> {
    return GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"ThermalVision.ThermalVisionSettings") as ThermalVisionSettings;
  }
}
