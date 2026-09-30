// =============================================================================
// CONTROLLABLE MECHS - MECH LINK PAGES (TerminalKit content provider)
// Every page is built fresh from CMLinkSystem when it's shown, so the terminal
// holds no state of its own and costs nothing while closed.
// =============================================================================
module ControllableMechs

import TerminalKit.*

public class CMContent extends TKContent {
  public let game: GameInstance;

  public func Request(p: ref<TKPage>, page: String, arg: String) -> Void {
    switch page {
      case "settings":
        this.Settings(p);
        break;
      default:
        this.Link(p);
        break;
    }
  }

  public func Act(p: ref<TKPage>, action: String, arg: String) -> Void {
    let link = CMLinkSystem.Get(this.game);
    let pilot = CMPilotSystem.Get(this.game);
    switch action {
      case "link":
        p.SetMessage(link.LinkLookAt());
        break;
      case "unlink":
        link.Unlink();
        p.SetMessage("LINK CLOSED");
        break;
      case "follow":
        link.Follow();
        p.SetMessage("*FOLLOWING");
        break;
      case "hold":
        link.Hold();
        p.SetMessage("*HOLDING POSITION");
        break;
      case "move":
        link.MoveToLookAt();
        p.SetMessage("*MOVING TO TARGET");
        break;
      case "pilot":
        let why = pilot.CanPilot();
        if StrLen(why) > 0 && NotEquals(why, "!NOT NOW") {
          p.SetMessage(why);
          break;
        }
        // the terminal has to close before the view can switch
        let state = CMTerminalState.Get(this.game);
        if IsDefined(state.open) {
          state.open.Close();
        }
        pilot.RequestEnter(0.4);
        break;
      case "spawntest":
        p.SetMessage(link.SpawnTestMech());
        break;
      case "despawntest":
        link.DespawnTestMech();
        p.SetMessage("TEST MECH REMOVED");
        break;
      case "firemode":
        pilot.SetFireMode(StringToInt(arg));
        break;
      case "stayhit":
        pilot.ToggleStayWhenHit();
        break;
      case "theme":
        p.SetTheme(arg);
        break;
    }
  }

  // ---- LINK: status and orders ----
  private func Link(p: ref<TKPage>) -> Void {
    let link = CMLinkSystem.Get(this.game);
    p.SetTitle("ROBOT LINK", "REMOTE OPERATION // NEURAL UPLINK");
    p.SetSection("link");
    if !link.IsLinked() {
      p.Dossier("NO UNIT LINKED", "Look at a mech, android, drone or spiderbot within 60 m and press J, or link it from here.", "OFFLINE", "red");
      p.Gap();
      p.Button("LINK LOOKED-AT ROBOT", "link", "", true);
      this.Test(p, link);
      return;
    }
    p.Dossier(link.UnitName(), "Linked " + StrLower(link.UnitKind()), "ONLINE", "green");
    let hp = link.HealthFraction();
    p.Stat("INTEGRITY", IntToString(RoundF(hp * 100.0)) + "%", hp < 0.3 ? "!CRITICAL" : "*NOMINAL", hp);
    p.Stat("SIGNAL", IntToString(RoundF(link.Distance())) + " m", "", link.SignalFraction());
    p.Stat("ORDER", CMContent.OrderName(link.Order()), "", -1.0);
    if Equals(link.UnitKind(), "MECH") {
      p.Heading("DIRECT CONTROL");
      p.Button("PILOT THE MECH  [L]", "pilot", "", true);
      p.SetTip("Takes the mech's sensor feed: WASD walks, the mouse turns the torso, LMB fires the MK.31s. L disconnects.");
    }
    p.Heading("ORDERS");
    p.Buttons("Command the linked unit", "", "", "FOLLOW|HOLD|MOVE TO TARGET", "follow|hold|move", "||");
    p.Gap();
    p.Button("CLOSE LINK", "unlink", "", true);
    this.Test(p, link);
  }

  // ---- test tools: a Minotaur on demand ----
  private func Test(p: ref<TKPage>, link: ref<CMLinkSystem>) -> Void {
    p.Heading("TEST");
    if link.HasTestMech() {
      p.Item("TEST MINOTAUR", "Spawned for testing; not kept in the save.", "", "REMOVE", "despawntest", "", true);
    } else {
      p.Item("MILITECH MINOTAUR", "Spawns one 14 m in front of you and links it.", "", "SPAWN", "spawntest", "", true);
    }
  }

  // ---- SETTINGS: pilot and palette ----
  private func Settings(p: ref<TKPage>) -> Void {
    let pilot = CMPilotSystem.Get(this.game);
    p.SetTitle("SETTINGS", "PILOT AND DISPLAY");
    p.SetSection("settings");
    p.Heading("FIRE MODE");
    let mode = pilot.FireMode();
    let i = 0;
    while i < 3 {
      let note = "";
      if i == CMFireMode.Stagger() { note = "LMB fires both guns, barrels alternating."; }
      if i == CMFireMode.Together() { note = "LMB fires both guns at once."; }
      if i == CMFireMode.Split() { note = "LMB fires the left gun, RMB the right. MMB for optics."; }
      p.Item(CMFireMode.Name(i), note, i == mode ? "*ACTIVE" : "", "USE", "firemode", IntToString(i), i != mode);
      i += 1;
    }
    p.Heading("LINK");
    let stay = pilot.StayWhenHit();
    p.Item("DISCONNECT WHEN V IS HIT", stay ? "Off: you stay in the mech while V takes damage." : "On: like hacking a camera, damage to V pulls you out.", stay ? "OFF" : "*ON", "TOGGLE", "stayhit", "", true);
    p.Heading("PALETTE");
    for id in TKTheme.Ids() {
      p.Item(StrUpper(id), "", "", "USE", "theme", id, true);
    }
  }

  public static func OrderName(order: Int32) -> String {
    if order == CMOrder.Follow() { return "FOLLOW"; }
    if order == CMOrder.Hold() { return "HOLD"; }
    if order == CMOrder.MoveTo() { return "MOVING"; }
    if order == CMOrder.Pilot() { return "PILOTED"; }
    return "IDLE";
  }
}
