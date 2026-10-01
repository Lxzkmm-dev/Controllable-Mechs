module ThermalVision

public enum ThermalVisionMode {
  Thermal = 0,
  RedHot = 1,
  WhiteHot = 2
}

public class ThermalVisionSystem extends ScriptableSystem {
  private let m_sessionActive: Bool;
  private let m_effectsRegistered: Bool;
  private let m_enabled: Bool;
  private let m_suspended: Bool;
  private let m_keyboardActivationModifierHeld: Bool;
  private let m_keyboardCycleModifierHeld: Bool;
  private let m_controllerActivationModifierHeld: Bool;
  private let m_controllerCycleModifierHeld: Bool;
  private let m_inMenu: Bool;
  private let m_inBraindance: Bool;
  private let m_inDeviceTakeover: Bool;
  private let m_inPhotoMode: Bool;
  private let m_playerDead: Bool;
  private let m_visionMonitorRunning: Bool;
  private let m_visualInterruption: Bool;
  private let m_visualInterruptionClearPending: Bool;
  private let m_mode: ThermalVisionMode;
  private let m_boundKeys: array<EInputKey>;

  private let m_player: wref<PlayerPuppet>;
  private let m_inputHandler: ref<CallbackSystemHandler>;
  private let m_equipmentListener: ref<AttachmentSlotsScriptListener>;

  private let m_uiBlackboard: wref<IBlackboard>;
  private let m_braindanceBlackboard: wref<IBlackboard>;
  private let m_deviceBlackboard: wref<IBlackboard>;
  private let m_photoModeBlackboard: wref<IBlackboard>;
  private let m_playerStateBlackboard: wref<IBlackboard>;
  private let m_menuListener: ref<CallbackHandle>;
  private let m_braindanceListener: ref<CallbackHandle>;
  private let m_deviceListener: ref<CallbackHandle>;
  private let m_photoModeListener: ref<CallbackHandle>;
  private let m_vitalsListener: ref<CallbackHandle>;
  private let m_nightVisionFactListenerID: Uint32;
  private let m_visionMonitorID: DelayID;

  private func OnAttach() -> Void {
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/Ready", this, n"OnSessionReady")
      .SetLifetime(CallbackLifetime.Forever);
    GameInstance.GetCallbackSystem()
      .RegisterCallback(n"Session/BeforeEnd", this, n"OnSessionEnd")
      .SetLifetime(CallbackLifetime.Forever);
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) -> Void {
    let requests = GameInstance.GetSystemRequestsHandler();
    if IsDefined(requests) && requests.IsPreGame() {
      return;
    }

    this.EndSession();
    this.m_player = GetPlayer(this.GetGameInstance());
    if !IsDefined(this.m_player) {
      return;
    }

    this.m_sessionActive = true;
    this.m_enabled = false;
    this.m_mode = ThermalVisionMode.Thermal;
    let storage: ref<ThermalVisionModeStorage> = ThermalVisionModeStorage.Get();
    if IsDefined(storage) {
      this.m_mode = storage.GetSelectedMode();
    }
    this.m_effectsRegistered = false;
    this.RegisterEquipmentListener();
    this.RegisterStateListeners();
    this.RegisterNightVisionFactListener();
    this.RebindInput();
    this.RegisterEffects();
    this.StopActiveEffect();
    this.StartVisionMonitor();
  }

  private cb func OnSessionEnd(event: ref<GameSessionEvent>) -> Void {
    this.EndSession();
  }

  private func EndSession() -> Void {
    this.StopActiveEffect();
    this.StopVisionMonitor();
    this.UnregisterNightVisionFactListener();
    this.ResetNightVisionFacts();
    this.UnbindInput();
    this.UnregisterStateListeners();
    this.UnregisterEquipmentListener();
    this.m_sessionActive = false;
    this.m_effectsRegistered = false;
    this.m_enabled = false;
    this.m_suspended = false;
    this.ResetModifierState();
    this.m_inMenu = false;
    this.m_inBraindance = false;
    this.m_inDeviceTakeover = false;
    this.m_inPhotoMode = false;
    this.m_playerDead = false;
    this.m_visionMonitorRunning = false;
    this.m_visualInterruption = false;
    this.m_visualInterruptionClearPending = false;
    this.m_mode = ThermalVisionMode.Thermal;
    this.m_player = null;
  }

  public func RebindInput() -> Void {
    this.UnbindInput();
    this.ResetModifierState();
    if !this.m_sessionActive {
      return;
    }

    let settings: ref<ThermalVisionSettings> = ThermalVisionSettings.Get(this.GetGameInstance());
    if !IsDefined(settings) {
      return;
    }

    if Equals(settings.keyboardActivationPrimary, EInputKey.IK_None)
      && Equals(settings.keyboardCyclePrimary, EInputKey.IK_None)
      && Equals(settings.controllerActivationPrimary, EInputKey.IK_None)
      && Equals(settings.controllerCyclePrimary, EInputKey.IK_None) {
      return;
    }

    this.m_inputHandler = GameInstance.GetCallbackSystem().RegisterCallback(n"Input/Key", this, n"OnKeyInput");

    if NotEquals(settings.keyboardActivationPrimary, EInputKey.IK_None) {
      this.AddInputTarget(settings.keyboardActivationPrimary);
      this.AddInputTarget(settings.keyboardActivationModifier);
    }

    if NotEquals(settings.keyboardCyclePrimary, EInputKey.IK_None) {
      this.AddInputTarget(settings.keyboardCyclePrimary);
      this.AddInputTarget(settings.keyboardCycleModifier);
    }

    if NotEquals(settings.controllerActivationPrimary, EInputKey.IK_None) {
      this.AddInputTarget(settings.controllerActivationPrimary);
      this.AddInputTarget(settings.controllerActivationModifier);
    }

    if NotEquals(settings.controllerCyclePrimary, EInputKey.IK_None) {
      this.AddInputTarget(settings.controllerCyclePrimary);
      this.AddInputTarget(settings.controllerCycleModifier);
    }
  }

  private func UnbindInput() -> Void {
    if IsDefined(this.m_inputHandler) {
      this.m_inputHandler.Unregister();
      this.m_inputHandler = null;
    }
    ArrayClear(this.m_boundKeys);
  }

  private func AddInputTarget(key: EInputKey) -> Void {
    if Equals(key, EInputKey.IK_None) {
      return;
    }

    let index: Int32 = 0;
    while index < ArraySize(this.m_boundKeys) {
      if Equals(this.m_boundKeys[index], key) {
        return;
      }
      index += 1;
    }

    this.m_inputHandler.AddTarget(InputTarget.Key(key));
    ArrayPush(this.m_boundKeys, key);
  }

  private func ResetModifierState() -> Void {
    this.m_keyboardActivationModifierHeld = false;
    this.m_keyboardCycleModifierHeld = false;
    this.m_controllerActivationModifierHeld = false;
    this.m_controllerCycleModifierHeld = false;
  }

  private func IsChordPressed(key: EInputKey, primary: EInputKey, modifier: EInputKey, modifierHeld: Bool) -> Bool {
    return Equals(key, primary) && (Equals(modifier, EInputKey.IK_None) || modifierHeld);
  }

  private cb func OnKeyInput(event: ref<KeyInputEvent>) -> Void {
    if !this.m_sessionActive {
      return;
    }

    let settings: ref<ThermalVisionSettings> = ThermalVisionSettings.Get(this.GetGameInstance());
    if !IsDefined(settings) {
      return;
    }

    let key: EInputKey = event.GetKey();
    let action: EInputAction = event.GetAction();
    if Equals(key, settings.keyboardActivationModifier) {
      if Equals(action, EInputAction.IACT_Press) {
        this.m_keyboardActivationModifierHeld = true;
      } else {
        if Equals(action, EInputAction.IACT_Release) {
          this.m_keyboardActivationModifierHeld = false;
        }
      }
    }

    if Equals(key, settings.keyboardCycleModifier) {
      if Equals(action, EInputAction.IACT_Press) {
        this.m_keyboardCycleModifierHeld = true;
      } else {
        if Equals(action, EInputAction.IACT_Release) {
          this.m_keyboardCycleModifierHeld = false;
        }
      }
    }

    if Equals(key, settings.controllerActivationModifier) {
      if Equals(action, EInputAction.IACT_Press) {
        this.m_controllerActivationModifierHeld = true;
      } else {
        if Equals(action, EInputAction.IACT_Release) {
          this.m_controllerActivationModifierHeld = false;
        }
      }
    }

    if Equals(key, settings.controllerCycleModifier) {
      if Equals(action, EInputAction.IACT_Press) {
        this.m_controllerCycleModifierHeld = true;
      } else {
        if Equals(action, EInputAction.IACT_Release) {
          this.m_controllerCycleModifierHeld = false;
        }
      }
    }

    if NotEquals(action, EInputAction.IACT_Press) {
      return;
    }

    if this.ShouldSuspend() {
      return;
    }

    if this.IsChordPressed(key, settings.keyboardCyclePrimary, settings.keyboardCycleModifier, this.m_keyboardCycleModifierHeld) {
      this.CycleMode();
      return;
    }

    if this.IsChordPressed(key, settings.keyboardActivationPrimary, settings.keyboardActivationModifier, this.m_keyboardActivationModifierHeld) {
      this.ToggleVision();
      return;
    }

    if this.IsChordPressed(key, settings.controllerCyclePrimary, settings.controllerCycleModifier, this.m_controllerCycleModifierHeld) {
      this.CycleMode();
      return;
    }

    if this.IsChordPressed(key, settings.controllerActivationPrimary, settings.controllerActivationModifier, this.m_controllerActivationModifierHeld) {
      this.ToggleVision();
    }
  }

  private func ToggleVision() -> Void {
    let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if !IsDefined(quests) {
      this.SetEnabled(!this.m_enabled);
      return;
    }

    let provider: ThermalVisionNightVisionProvider = this.ResolveNightVisionProvider(quests);
    if Equals(provider, ThermalVisionNightVisionProvider.Disabled) {
      this.ToggleStandaloneVision(quests);
      return;
    }

    this.ToggleIntegratedVision(quests, provider);
  }

  public func TryToggleKiroshiIntegration() -> Bool {
    let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if !IsDefined(quests) {
      return false;
    }

    let provider: ThermalVisionNightVisionProvider = this.ResolveNightVisionProvider(quests);
    if NotEquals(provider, ThermalVisionNightVisionProvider.KiroshiOptics) {
      return false;
    }

    if this.ShouldSuspend() {
      return true;
    }

    this.ToggleIntegratedVision(quests, provider);
    return true;
  }

  private func ToggleStandaloneVision(quests: ref<QuestsSystem>) -> Void {
    if !this.m_enabled {
      this.RequestNightVision(quests, false);
      TV_DisableTrueNightVision(this.GetGameInstance(), this.m_player);
    }
    this.SetEnabled(!this.m_enabled);
  }

  private func ToggleIntegratedVision(quests: ref<QuestsSystem>, provider: ThermalVisionNightVisionProvider) -> Void {
    if this.m_enabled {
      this.SetEnabled(false);
      this.RequestNightVision(quests, false);
      TV_DisableTrueNightVision(this.GetGameInstance(), this.m_player);
      return;
    }

    if quests.GetFact(n"qc_night_vision_active") > 0 {
      TV_DisableTrueNightVision(this.GetGameInstance(), this.m_player);
      if this.SetEnabled(true) {
        this.RequestNightVision(quests, false);
      }
      return;
    }

    if TV_IsTrueNightVisionEnabled(this.GetGameInstance()) {
      TV_DisableTrueNightVision(this.GetGameInstance(), this.m_player);
      this.RequestNightVision(quests, false);
      this.SetEnabled(true);
      return;
    }

    if this.ShouldSuspend() || !this.HasEligibleOptics() {
      return;
    }

    switch provider {
      case ThermalVisionNightVisionProvider.KiroshiOptics:
        this.RequestNightVision(quests, true);
        this.PlaySound(n"ui_gui_cyberware_tab_open");
        return;
      case ThermalVisionNightVisionProvider.TrueNightVision:
        if this.ToggleTrueNightVision() {
          return;
        }
        break;
    }

    this.SetEnabled(true);
  }

  private func ResolveNightVisionProvider(quests: ref<QuestsSystem>) -> ThermalVisionNightVisionProvider {
    let settings: ref<ThermalVisionSettings> = ThermalVisionSettings.Get(this.GetGameInstance());
    if !IsDefined(settings) {
      return ThermalVisionNightVisionProvider.Disabled;
    }

    switch settings.nightVisionProvider {
      case ThermalVisionNightVisionProvider.KiroshiOptics:
        return this.IsKiroshiNightVisionAvailable(quests) ? ThermalVisionNightVisionProvider.KiroshiOptics : ThermalVisionNightVisionProvider.Disabled;
      case ThermalVisionNightVisionProvider.TrueNightVision:
        return TV_TrueNightVisionInstalled(this.GetGameInstance()) ? ThermalVisionNightVisionProvider.TrueNightVision : ThermalVisionNightVisionProvider.Disabled;
      case ThermalVisionNightVisionProvider.Disabled:
        return ThermalVisionNightVisionProvider.Disabled;
      case ThermalVisionNightVisionProvider.Automatic:
        if this.IsKiroshiNightVisionAvailable(quests) {
          return ThermalVisionNightVisionProvider.KiroshiOptics;
        }
        if TV_TrueNightVisionInstalled(this.GetGameInstance()) {
          return ThermalVisionNightVisionProvider.TrueNightVision;
        }
        return ThermalVisionNightVisionProvider.Disabled;
    }

    return ThermalVisionNightVisionProvider.Disabled;
  }

  private func IsKiroshiNightVisionAvailable(quests: ref<QuestsSystem>) -> Bool {
    return quests.GetFact(n"qc_night_vision_bridge_present") > 0
      && quests.GetFact(n"qc_night_vision_available") > 0;
  }

  private func ToggleTrueNightVision() -> Bool {
    return TV_ToggleTrueNightVision(this.GetGameInstance(), this.m_player);
  }

  private func RequestNightVision(quests: ref<QuestsSystem>, enabled: Bool) -> Void {
    quests.SetFact(n"qc_night_vision_requested", enabled ? 1 : 0);
    quests.SetFact(n"qc_night_vision_request_id", quests.GetFact(n"qc_night_vision_request_id") + 1);
  }

  public func IsEnabled() -> Bool {
    return this.m_enabled;
  }

  public func SetEnabled(enabled: Bool) -> Bool {
    if !enabled {
      if this.m_enabled {
        this.DeactivateVision(true);
      }
      return true;
    }

    if this.m_enabled {
      return true;
    }

    if this.ShouldSuspend() {
      return false;
    }

    if !this.HasEligibleOptics() {
      return false;
    }

    if !this.RegisterEffects() {
      return false;
    }

    this.m_enabled = true;
    if this.StartSelectedEffect() {
      this.PlaySound(n"ui_gui_cyberware_tab_open");
      return true;
    }

    this.DeactivateVision(false);
    return false;
  }

  private func StartVisionMonitor() -> Void {
    if !this.m_sessionActive || this.m_visionMonitorRunning {
      return;
    }

    let callback: ref<ThermalVisionMonitorCallback> = new ThermalVisionMonitorCallback();
    callback.system = this;
    this.m_visionMonitorRunning = true;
    this.m_visionMonitorID = GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(callback, 0.25, false);
  }

  private func StopVisionMonitor() -> Void {
    if this.m_visionMonitorRunning {
      GameInstance.GetDelaySystem(this.GetGameInstance()).CancelDelay(this.m_visionMonitorID);
      this.m_visionMonitorRunning = false;
    }
  }

  public func OnVisionMonitor() -> Void {
    this.m_visionMonitorRunning = false;
    if !this.m_sessionActive {
      return;
    }

    this.RefreshVisualInterruption();

    if TV_IsTrueNightVisionEnabled(this.GetGameInstance()) {
      if this.m_enabled {
        this.DeactivateVision(false);
      }

      let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
      if IsDefined(quests) && quests.GetFact(n"qc_night_vision_active") > 0 {
        this.RequestNightVision(quests, false);
      }
    }

    this.StartVisionMonitor();
  }

  private func IsVisualInterruptionActive() -> Bool {
    return IsDefined(this.m_player)
      && (StatusEffectSystem.ObjectHasStatusEffect(this.m_player, t"BaseStatusEffect.Drunk")
        || StatusEffectSystem.ObjectHasStatusEffect(this.m_player, t"BaseStatusEffect.JohnnySicknessHeavy"));
  }

  private func RefreshVisualInterruption() -> Void {
    let active: Bool = this.IsVisualInterruptionActive();
    if active {
      this.m_visualInterruptionClearPending = false;
      if !this.m_visualInterruption {
        this.m_visualInterruption = true;
        this.RefreshSuspension();
      }
      return;
    }

    if !this.m_visualInterruption {
      this.m_visualInterruptionClearPending = false;
      return;
    }

    if !this.m_visualInterruptionClearPending {
      this.m_visualInterruptionClearPending = true;
      return;
    }

    this.m_visualInterruptionClearPending = false;
    this.m_visualInterruption = false;
    this.RefreshSuspension();
  }

  private func CycleMode() -> Void {
    if !this.m_enabled || this.ShouldSuspend() {
      return;
    }

    if !this.HasEligibleOptics() || !this.RegisterEffects() {
      this.DeactivateVision(false);
      return;
    }

    this.StopActiveEffect();
    switch this.m_mode {
      case ThermalVisionMode.Thermal:
        this.m_mode = ThermalVisionMode.RedHot;
        break;
      case ThermalVisionMode.RedHot:
        this.m_mode = ThermalVisionMode.WhiteHot;
        break;
      default:
        this.m_mode = ThermalVisionMode.Thermal;
    }

    if this.StartSelectedEffect() {
      let storage: ref<ThermalVisionModeStorage> = ThermalVisionModeStorage.Get();
      if IsDefined(storage) {
        storage.SaveSelectedMode(this.m_mode);
      }
      this.PlaySound(n"ui_gui_cyberware_tab_open");
    } else {
      this.DeactivateVision(false);
    }
  }

  public func OnEquipmentChanged() -> Void {
    if this.m_enabled && !this.HasEligibleOptics() {
      this.DeactivateVision(true);
    }
  }

  private func HasEligibleOptics() -> Bool {
    if !IsDefined(this.m_player) {
      return false;
    }

    let equipment: ref<EquipmentSystemPlayerData> = EquipmentSystem.GetData(this.m_player);
    if !IsDefined(equipment) {
      return false;
    }

    let slotCount: Int32 = equipment.GetNumberOfSlots(gamedataEquipmentArea.EyesCW, true);
    let index: Int32 = 0;
    while index < slotCount {
      let itemID: ItemID = equipment.GetItemInEquipSlot(gamedataEquipmentArea.EyesCW, index);
      if ItemID.IsValid(itemID) && RPGManager.GetCombinedItemQualityValue(this.GetGameInstance(), itemID) >= 4 {
        return true;
      }
      index += 1;
    }

    return false;
  }

  private func RegisterEffects() -> Bool {
    if this.m_effectsRegistered {
      return true;
    }
    if !IsDefined(this.m_player) {
      return false;
    }

    let component: ref<entEffectSpawnerComponent> = this.m_player.FindComponentByName(n"fx_status_effects") as entEffectSpawnerComponent;
    if !IsDefined(component) {
      return false;
    }

    let orangeReady: Bool = this.EnsureEffect(component, n"qc_thermal_vision_orange", r"base\\fx\\qc\\thermal_vision_orange.effect");
    let redReady: Bool = this.EnsureEffect(component, n"qc_thermal_vision_spike", r"base\\fx\\qc\\thermal_vision_spike.effect");
    let whiteReady: Bool = this.EnsureEffect(component, n"qc_thermal_vision_white_hot", r"base\\fx\\qc\\thermal_vision_white_hot.effect");
    this.m_effectsRegistered = orangeReady && redReady && whiteReady;
    return this.m_effectsRegistered;
  }

  private func EnsureEffect(component: ref<entEffectSpawnerComponent>, effectName: CName, path: ResRef) -> Bool {
    let index: Int32 = 0;
    while index < ArraySize(component.effectDescs) {
      if Equals(component.effectDescs[index].effectName, effectName) {
        return true;
      }
      index += 1;
    }

    let descriptor: ref<entEffectDesc> = new entEffectDesc();
    descriptor.effectName = effectName;
    descriptor.effect *= path;
    ArrayPush(component.effectDescs, descriptor);
    return true;
  }

  private func StartSelectedEffect() -> Bool {
    if !IsDefined(this.m_player) || !this.m_effectsRegistered {
      return false;
    }

    let effectName: CName;
    switch this.m_mode {
      case ThermalVisionMode.Thermal:
        effectName = n"qc_thermal_vision_orange";
        break;
      case ThermalVisionMode.RedHot:
        effectName = n"qc_thermal_vision_spike";
        break;
      case ThermalVisionMode.WhiteHot:
        effectName = n"qc_thermal_vision_white_hot";
        break;
      default:
        return false;
    }

    this.StopActiveEffect();
    GameObjectEffectHelper.StartEffectEvent(this.m_player, effectName, true);
    this.SetActiveFact(true);
    return true;
  }

  private func StopActiveEffect() -> Void {
    if IsDefined(this.m_player) {
      GameObjectEffectHelper.StopEffectEvent(this.m_player, n"qc_thermal_vision_orange");
      GameObjectEffectHelper.StopEffectEvent(this.m_player, n"qc_thermal_vision_spike");
      GameObjectEffectHelper.StopEffectEvent(this.m_player, n"qc_thermal_vision_white_hot");
    }
    this.SetActiveFact(false);
  }

  private func SetActiveFact(active: Bool) -> Void {
    let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if IsDefined(quests) {
      quests.SetFact(n"qc_thermal_vision_active", active ? 1 : 0);
    }
  }

  private func ResetNightVisionFacts() -> Void {
    let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if IsDefined(quests) {
      quests.SetFact(n"qc_night_vision_bridge_present", 0);
      quests.SetFact(n"qc_night_vision_available", 0);
      quests.SetFact(n"qc_night_vision_active", 0);
      quests.SetFact(n"qc_night_vision_requested", 0);
    }
  }

  private func RegisterNightVisionFactListener() -> Void {
    let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if IsDefined(quests) && this.m_nightVisionFactListenerID == 0u {
      this.m_nightVisionFactListenerID = quests.RegisterListener(n"qc_night_vision_active", this, n"OnKiroshiNightVisionChanged");
    }
  }

  private func UnregisterNightVisionFactListener() -> Void {
    let quests: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
    if IsDefined(quests) && this.m_nightVisionFactListenerID > 0u {
      quests.UnregisterListener(n"qc_night_vision_active", this.m_nightVisionFactListenerID);
    }
    this.m_nightVisionFactListenerID = 0u;
  }

  private final func OnKiroshiNightVisionChanged(value: Int32) -> Void {
    if value <= 0 {
      return;
    }

    TV_DisableTrueNightVision(this.GetGameInstance(), this.m_player);
    if this.m_enabled {
      this.DeactivateVision(false);
    }
  }

  private func DeactivateVision(playSound: Bool) -> Void {
    this.StopActiveEffect();
    this.m_enabled = false;
    this.m_suspended = false;
    if playSound {
      this.PlaySound(n"ui_gui_cyberware_tab_close");
    }
  }

  private func RegisterEquipmentListener() -> Void {
    if IsDefined(this.m_player) {
      this.m_equipmentListener = GameInstance.GetTransactionSystem(this.GetGameInstance()).RegisterAttachmentSlotListener(this.m_player, ThermalVisionEquipmentCallback.Create(this));
    }
  }

  private func UnregisterEquipmentListener() -> Void {
    if IsDefined(this.m_player) && IsDefined(this.m_equipmentListener) {
      GameInstance.GetTransactionSystem(this.GetGameInstance()).UnregisterAttachmentSlotListener(this.m_player, this.m_equipmentListener);
    }
    this.m_equipmentListener = null;
  }

  private func RegisterStateListeners() -> Void {
    let blackboards: ref<BlackboardSystem> = GameInstance.GetBlackboardSystem(this.GetGameInstance());
    this.m_uiBlackboard = blackboards.Get(GetAllBlackboardDefs().UI_System);
    this.m_braindanceBlackboard = blackboards.Get(GetAllBlackboardDefs().Braindance);
    this.m_deviceBlackboard = blackboards.Get(GetAllBlackboardDefs().DeviceTakeControl);
    this.m_photoModeBlackboard = blackboards.Get(GetAllBlackboardDefs().PhotoMode);
    this.m_playerStateBlackboard = blackboards.GetLocalInstanced(this.m_player.GetEntityID(), GetAllBlackboardDefs().PlayerStateMachine);

    this.m_menuListener = this.m_uiBlackboard.RegisterListenerBool(GetAllBlackboardDefs().UI_System.IsInMenu, this, n"OnMenuChanged");
    this.m_braindanceListener = this.m_braindanceBlackboard.RegisterListenerBool(GetAllBlackboardDefs().Braindance.IsActive, this, n"OnBraindanceChanged");
    this.m_deviceListener = this.m_deviceBlackboard.RegisterListenerEntityID(GetAllBlackboardDefs().DeviceTakeControl.ActiveDevice, this, n"OnDeviceChanged");
    this.m_photoModeListener = this.m_photoModeBlackboard.RegisterListenerBool(GetAllBlackboardDefs().PhotoMode.IsActive, this, n"OnPhotoModeChanged");
    this.m_vitalsListener = this.m_playerStateBlackboard.RegisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.Vitals, this, n"OnVitalsChanged");

    let emptyEntity: EntityID;
    this.m_inMenu = this.m_uiBlackboard.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu);
    this.m_inBraindance = this.m_braindanceBlackboard.GetBool(GetAllBlackboardDefs().Braindance.IsActive);
    this.m_inDeviceTakeover = this.m_deviceBlackboard.GetEntityID(GetAllBlackboardDefs().DeviceTakeControl.ActiveDevice) != emptyEntity;
    this.m_inPhotoMode = this.m_photoModeBlackboard.GetBool(GetAllBlackboardDefs().PhotoMode.IsActive);
    this.m_playerDead = this.m_playerStateBlackboard.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Vitals) == EnumInt(gamePSMVitals.Dead);
  }

  private func UnregisterStateListeners() -> Void {
    if IsDefined(this.m_uiBlackboard) && IsDefined(this.m_menuListener) {
      this.m_uiBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().UI_System.IsInMenu, this.m_menuListener);
    }
    if IsDefined(this.m_braindanceBlackboard) && IsDefined(this.m_braindanceListener) {
      this.m_braindanceBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().Braindance.IsActive, this.m_braindanceListener);
    }
    if IsDefined(this.m_deviceBlackboard) && IsDefined(this.m_deviceListener) {
      this.m_deviceBlackboard.UnregisterListenerEntityID(GetAllBlackboardDefs().DeviceTakeControl.ActiveDevice, this.m_deviceListener);
    }
    if IsDefined(this.m_photoModeBlackboard) && IsDefined(this.m_photoModeListener) {
      this.m_photoModeBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().PhotoMode.IsActive, this.m_photoModeListener);
    }
    if IsDefined(this.m_playerStateBlackboard) && IsDefined(this.m_vitalsListener) {
      this.m_playerStateBlackboard.UnregisterListenerInt(GetAllBlackboardDefs().PlayerStateMachine.Vitals, this.m_vitalsListener);
    }

    this.m_uiBlackboard = null;
    this.m_braindanceBlackboard = null;
    this.m_deviceBlackboard = null;
    this.m_photoModeBlackboard = null;
    this.m_playerStateBlackboard = null;
    this.m_menuListener = null;
    this.m_braindanceListener = null;
    this.m_deviceListener = null;
    this.m_photoModeListener = null;
    this.m_vitalsListener = null;
  }

  private cb func OnMenuChanged(value: Bool) -> Void {
    this.m_inMenu = value;
    this.RefreshSuspension();
  }

  private cb func OnBraindanceChanged(value: Bool) -> Void {
    this.m_inBraindance = value;
    this.RefreshSuspension();
  }

  private cb func OnDeviceChanged(value: EntityID) -> Void {
    let emptyEntity: EntityID;
    this.m_inDeviceTakeover = value != emptyEntity;
    this.RefreshSuspension();
  }

  private cb func OnPhotoModeChanged(value: Bool) -> Void {
    this.m_inPhotoMode = value;
    this.RefreshSuspension();
  }

  private cb func OnVitalsChanged(value: Int32) -> Void {
    this.m_playerDead = value == EnumInt(gamePSMVitals.Dead);
    this.RefreshSuspension();
  }

  private func ShouldSuspend() -> Bool {
    return this.m_inMenu || this.m_inBraindance || this.m_inDeviceTakeover || this.m_inPhotoMode || this.m_playerDead || this.m_visualInterruption || this.IsVisualInterruptionActive();
  }

  private func RefreshSuspension() -> Void {
    if this.ShouldSuspend() {
      this.ResetModifierState();
      if !this.m_enabled {
        this.m_suspended = false;
        return;
      }
      if !this.m_suspended {
        this.StopActiveEffect();
        this.m_suspended = true;
      }
      return;
    }

    if !this.m_enabled {
      this.m_suspended = false;
      return;
    }

    if this.m_suspended {
      if !this.HasEligibleOptics() || !this.RegisterEffects() || !this.StartSelectedEffect() {
        this.DeactivateVision(false);
        return;
      }
      this.m_suspended = false;
    }
  }

  private func PlaySound(soundName: CName) -> Void {
    if IsDefined(this.m_player) {
      let sound: ref<SoundPlayEvent> = new SoundPlayEvent();
      sound.soundName = soundName;
      this.m_player.QueueEvent(sound);
    }
  }

  public static func Get(gameInstance: GameInstance) -> ref<ThermalVisionSystem> {
    return GameInstance.GetScriptableSystemsContainer(gameInstance).Get(n"ThermalVision.ThermalVisionSystem") as ThermalVisionSystem;
  }
}

public class ThermalVisionMonitorCallback extends DelayCallback {
  public let system: wref<ThermalVisionSystem>;

  public func Call() -> Void {
    if IsDefined(this.system) {
      this.system.OnVisionMonitor();
    }
  }
}
