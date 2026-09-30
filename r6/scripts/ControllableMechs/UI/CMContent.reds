// =============================================================================
// CONTROLLABLE MECHS - ROBOT LINK PAGES (TerminalKit content provider)
// Every page is built fresh from CMLinkSystem / CMPilotSystem when it's shown,
// so the terminal holds no state of its own and costs nothing while closed.
// The TOOLS tab is TerminalKit Tools (inspect what V looks at, spawn records,
// log positions): handy for finding robot records to test.
// =============================================================================
module ControllableMechs

import TerminalKit.*
import TerminalKit.Tools.*

public class CMContent extends TKContent {
  public let game: GameInstance;

  public func Request(p: ref<TKPage>, page: String, arg: String) -> Void {
    p.SetTheme(CMPilotSystem.Get(this.game).Theme());
    if TKTools.Request(p, page, arg) {
      p.SetSection("tk_tools");
      return;
    }
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
    if TKTools.Act(p, action, arg) {
      return;
    }
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
        let why = pilot.CanPilot(true);
        if StrLen(why) > 0 {
          p.SetMessage(why);
          break;
        }
        // the terminal has to close before the view can switch
        CMTerminal.CloseOpen(this.game);
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
        pilot.SetFireMode(StringToInt(arg, 0));
        break;
      case "dropwhenhit":
        pilot.SetStayWhenHit(!Equals(arg, "1"));
        break;
      case "theme":
        pilot.SetTheme(arg);
        p.SetTheme(arg);
        break;
    }
  }

  // ---- LINK: status, direct control, orders ----
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
      p.Item("PILOT THE MECH", "Take its sensor feed: WASD walks, the mouse turns the torso, LMB fires the MK.31s, L disconnects.", "", "PILOT  [L]", "pilot", "", true);
    }
    p.Heading("ORDERS");
    p.Buttons("Command the linked unit", "", "", "FOLLOW|HOLD|MOVE TO TARGET", "follow|hold|move", "||");
    p.SetTip("MOVE TO TARGET sends the unit to what you look at when you press it, or 15 m ahead of you.");
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
    p.Heading("PILOT");
    p.Dropdown("FIRE MODE", "How LMB / RMB fire the two MK.31s (B cycles it while piloting)",
      IntToString(pilot.FireMode()),
      CMFireMode.Name(0) + "|" + CMFireMode.Name(1) + "|" + CMFireMode.Name(2), "0|1|2", "firemode", "");
    p.SetTip("STAGGERED: LMB fires both, barrels alternating. LINKED SALVO: LMB fires both at once. SPLIT: LMB left gun, RMB right gun, MMB optics.");
    p.Check("DISCONNECT WHEN V IS HIT", "Like hacking a camera: damage to V pulls you out of the mech", !pilot.StayWhenHit(), "dropwhenhit", "");
    p.Heading("PALETTE");
    p.Dropdown("TERMINAL PALETTE", "The terminal's colours", pilot.Theme(), CMContent.ThemeLabels(), CMContent.ThemeValues(), "theme", "");
  }

  public static func ThemeLabels() -> String {
    let ids = TKTheme.Ids();
    let s = "";
    for id in ids {
      s += (StrLen(s) > 0 ? "|" : "") + StrUpper(id);
    }
    return s;
  }

  public static func ThemeValues() -> String {
    let ids = TKTheme.Ids();
    let s = "";
    for id in ids {
      s += (StrLen(s) > 0 ? "|" : "") + id;
    }
    return s;
  }

  public static func OrderName(order: Int32) -> String {
    if order == CMOrder.Follow() { return "FOLLOW"; }
    if order == CMOrder.Hold() { return "HOLD"; }
    if order == CMOrder.MoveTo() { return "MOVING"; }
    if order == CMOrder.Pilot() { return "PILOTED"; }
    return "IDLE";
  }
}
