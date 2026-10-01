module ThermalVision

@if(ModuleExists("TrueNightVision"))
import TrueNightVision.*

@if(ModuleExists("TrueNightVision"))
public func TV_TrueNightVisionInstalled(gameInstance: GameInstance) -> Bool {
  let system: ref<TNVSystem> = TNVSystem.Get(gameInstance);
  return IsDefined(system);
}

@if(!ModuleExists("TrueNightVision"))
public func TV_TrueNightVisionInstalled(gameInstance: GameInstance) -> Bool {
  return false;
}

@if(ModuleExists("TrueNightVision"))
public func TV_IsTrueNightVisionEnabled(gameInstance: GameInstance) -> Bool {
  let system: ref<TNVSystem> = TNVSystem.Get(gameInstance);
  return IsDefined(system) && system.IsEnabled();
}

@if(!ModuleExists("TrueNightVision"))
public func TV_IsTrueNightVisionEnabled(gameInstance: GameInstance) -> Bool {
  return false;
}

@if(ModuleExists("TrueNightVision"))
public func TV_ToggleTrueNightVision(gameInstance: GameInstance, player: ref<PlayerPuppet>) -> Bool {
  let system: ref<TNVSystem> = TNVSystem.Get(gameInstance);
  if !IsDefined(system) || !IsDefined(player) {
    return false;
  }

  system.ToggleNightVision(player);
  return system.IsEnabled();
}

@if(!ModuleExists("TrueNightVision"))
public func TV_ToggleTrueNightVision(gameInstance: GameInstance, player: ref<PlayerPuppet>) -> Bool {
  return false;
}

@if(ModuleExists("TrueNightVision"))
public func TV_DisableTrueNightVision(gameInstance: GameInstance, player: ref<PlayerPuppet>) -> Void {
  let system: ref<TNVSystem> = TNVSystem.Get(gameInstance);
  if IsDefined(system) && IsDefined(player) && system.IsEnabled() {
    system.ToggleNightVision(player);
  }
}

@if(!ModuleExists("TrueNightVision"))
public func TV_DisableTrueNightVision(gameInstance: GameInstance, player: ref<PlayerPuppet>) -> Void {
}
