// =============================================================================
// CONTROLLABLE MECHS - KEYS
// ] opens the Robot Link, [ links the robot V is looking at (mech, android, drone, spiderbot),
// \ pilots the linked mech (and disconnects again). Not K/J/L: those are vanilla crafting,
// the journal and Night City Empires' Fixer Link.
// (r6/input/ControllableMechs.xml, needs Input Loader; rebindable in Mod Settings).
// =============================================================================
module ControllableMechs

import ControllableMechs.Control.*

public class CMInput extends IScriptable {
  public let player: wref<PlayerPuppet>;

  private let m_lastName: CName;
  private let m_lastTime: Float;

  protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    if !ListenerAction.IsButtonJustPressed(action) {
      return false;
    }
    let name = ListenerAction.GetName(action);
    // the keys live in several input contexts (so they work in combat); one press heard
    // twice must not toggle twice
    let now = EngineTime.ToFloat(GameInstance.GetEngineTime(this.player.GetGame()));
    if Equals(name, this.m_lastName) && now - this.m_lastTime < 0.25 {
      return false;
    }
    this.m_lastName = name;
    this.m_lastTime = now;
    let pilot = CMPilotSystem.Get(this.player.GetGame());
    let session = CMCSession.Get(this.player.GetGame());
    if Equals(name, n"CM_Pilot") {
      // the framework (M1) while its preview is on, else the alpha's Pilot Mode
      if session.IsActive() || (session.Armed() && !pilot.IsPiloting()) {
        session.Toggle();
      } else {
        pilot.Toggle();
      }
      return false;
    }
    if pilot.IsPiloting() || session.IsActive() {
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
  if IsDefined(this.m_cmcSession) {
    if this.m_cmcSession.OnGameAction(ListenerAction.GetName(action), ListenerAction.GetType(action), ListenerAction.GetValue(action)) {
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
  public let cmOpenLink: EInputKey = EInputKey.IK_RightBracket;

  @runtimeProperty("ModSettings.mod", "Controllable Mechs")
  @runtimeProperty("ModSettings.category", "UI-Settings-KeyBindings")
  @runtimeProperty("ModSettings.displayName", "Link the robot you look at")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmLinkLookAt: EInputKey = EInputKey.IK_LeftBracket;

  @runtimeProperty("ModSettings.mod", "Controllable Mechs")
  @runtimeProperty("ModSettings.category", "UI-Settings-KeyBindings")
  @runtimeProperty("ModSettings.displayName", "Pilot the linked mech")
  @runtimeProperty("ModSettings.description", "UI-Settings-Bind")
  public let cmPilot: EInputKey = EInputKey.IK_Backslash;
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
