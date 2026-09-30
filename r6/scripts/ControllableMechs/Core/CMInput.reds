// =============================================================================
// CONTROLLABLE MECHS - KEYS
// K opens the Robot Link, J links the robot V is looking at (mech, android, drone, spiderbot),
// L pilots the linked mech (and disconnects again)
// (r6/input/ControllableMechs.xml, needs Input Loader; rebindable in Mod Settings).
// =============================================================================
module ControllableMechs

public class CMInput extends IScriptable {
  public let player: wref<PlayerPuppet>;

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    if !ListenerAction.IsButtonJustPressed(action) {
      return false;
    }
    let pilot = CMPilotSystem.Get(this.player.GetGame());
    let name = ListenerAction.GetName(action);
    if Equals(name, n"CM_Pilot") {
      pilot.Toggle();
      return false;
    }
    if pilot.IsPiloting() {
      return false;   // the terminal and look-at linking wait until V is back
    }
    switch name {
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
  this.RegisterInputListener(this.m_cmInput, n"CM_Pilot");
  return result;
}

// While piloting, the game's own actions (move, sprint, attack, aim, camera mouse) go to
// the mech instead of V. Set only while piloting, so otherwise this costs one check.
@addField(PlayerPuppet)
public let m_cmPilot: wref<CMPilotSystem>;

@wrapMethod(PlayerPuppet)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
  if IsDefined(this.m_cmPilot) {
    if this.m_cmPilot.OnGameAction(ListenerAction.GetName(action), ListenerAction.GetType(action), ListenerAction.GetValue(action)) {
      return true;
    }
  }
  return wrappedMethod(action, consumer);
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
  @runtimeProperty("ModSettings.displayName", "Open Robot Link")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmOpenLink: EInputKey = EInputKey.IK_K;

  @runtimeProperty("ModSettings.mod", "Controllable Mechs")
  @runtimeProperty("ModSettings.category", "UI-Settings-KeyBindings")
  @runtimeProperty("ModSettings.displayName", "Link the robot you look at")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmLinkLookAt: EInputKey = EInputKey.IK_J;

  @runtimeProperty("ModSettings.mod", "Controllable Mechs")
  @runtimeProperty("ModSettings.category", "UI-Settings-KeyBindings")
  @runtimeProperty("ModSettings.displayName", "Pilot the linked mech")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmPilot: EInputKey = EInputKey.IK_L;
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
