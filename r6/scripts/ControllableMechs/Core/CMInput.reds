// =============================================================================
// CONTROLLABLE MECHS - KEYS
// K opens the Mech Link, J links the mech V is looking at
// (r6/input/ControllableMechs.xml, needs Input Loader; rebindable in Mod Settings).
// =============================================================================
module ControllableMechs

public class CMInput extends IScriptable {
  public let player: wref<PlayerPuppet>;

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    if !ListenerAction.IsButtonJustPressed(action) {
      return false;
    }
    switch ListenerAction.GetName(action) {
      case n"CM_OpenLink":
        CMTerminal.Toggle(this.player);
        break;
      case n"CM_LinkLookAt":
        let msg = CMLinkSystem.Get(this.player.GetGame()).LinkLookAt();
        if StrLen(msg) > 0 {
          // the "!" / "*" marks are for the terminal; the HUD gets plain text
          this.player.SetWarningMessage(StrReplaceAll(StrReplaceAll(msg, "!", ""), "*", ""));
        }
        break;
    }
    return false;
  }
}

@addField(PlayerPuppet)
private let m_cmInput: ref<CMInput>;

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
  let result = wrappedMethod();
  this.m_cmInput = new CMInput();
  this.m_cmInput.player = this;
  this.RegisterInputListener(this.m_cmInput, n"CM_OpenLink");
  this.RegisterInputListener(this.m_cmInput, n"CM_LinkLookAt");
  return result;
}

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
  if IsDefined(this.m_cmInput) {
    this.UnregisterInputListener(this.m_cmInput);
    this.m_cmInput = null;
  }
  return wrappedMethod();
}

@if(ModuleExists("ModSettingsModule"))
public class CMKeybinds {
  @runtimeProperty("ModSettings.mod", "Controllable Mechs")
  @runtimeProperty("ModSettings.category", "UI-Settings-KeyBindings")
  @runtimeProperty("ModSettings.displayName", "Open Mech Link")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmOpenLink: EInputKey = EInputKey.IK_K;

  @runtimeProperty("ModSettings.mod", "Controllable Mechs")
  @runtimeProperty("ModSettings.category", "UI-Settings-KeyBindings")
  @runtimeProperty("ModSettings.displayName", "Link the mech you look at")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmLinkLookAt: EInputKey = EInputKey.IK_J;
}

@if(ModuleExists("ModSettingsModule"))
@addField(PlayerPuppet)
private let m_cmKeybinds: ref<CMKeybinds>;

@if(ModuleExists("ModSettingsModule"))
@wrapMethod(PlayerPuppet)
protected cb func OnMakePlayerVisibleAfterSpawn(evt: ref<EndGracePeriodAfterSpawn>) -> Bool {
  if !IsDefined(this.m_cmKeybinds) {
    this.m_cmKeybinds = new CMKeybinds();
    ModSettings.RegisterListenerToClass(this.m_cmKeybinds);
  }
  return wrappedMethod(evt);
}
