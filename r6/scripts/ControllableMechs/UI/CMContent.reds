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
      return;
    }
    p.Dossier(link.UnitName(), "Linked " + StrLower(link.UnitKind()), "ONLINE", "green");
    let hp = link.HealthFraction();
    p.Stat("INTEGRITY", IntToString(RoundF(hp * 100.0)) + "%", hp < 0.3 ? "!CRITICAL" : "*NOMINAL", hp);
    p.Stat("SIGNAL", IntToString(RoundF(link.Distance())) + " m", "", link.SignalFraction());
    p.Stat("ORDER", CMContent.OrderName(link.Order()), "", -1.0);
    p.Heading("ORDERS");
    p.Buttons("Command the linked unit", "", "", "FOLLOW|HOLD|MOVE TO TARGET", "follow|hold|move", "||");
    p.SetTip("MOVE TO TARGET sends the unit to what you look at when the link closes, or 15 m ahead of you.");
    p.Gap();
    p.Button("CLOSE LINK", "unlink", "", true);
  }

  // ---- SETTINGS: palette ----
  private func Settings(p: ref<TKPage>) -> Void {
    p.SetTitle("SETTINGS", "LINK DISPLAY");
    p.SetSection("settings");
    p.Heading("PALETTE");
    for id in TKTheme.Ids() {
      p.Item(StrUpper(id), "", "", "USE", "theme", id, true);
    }
  }

  public static func OrderName(order: Int32) -> String {
    if order == CMOrder.Follow() { return "FOLLOW"; }
    if order == CMOrder.Hold() { return "HOLD"; }
    if order == CMOrder.MoveTo() { return "MOVING"; }
    return "IDLE";
  }
}
