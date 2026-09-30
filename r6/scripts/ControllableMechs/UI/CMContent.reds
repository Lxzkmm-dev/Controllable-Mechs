// =============================================================================
// CONTROLLABLE MECHS - ROBOT LINK PAGES (TerminalKit content provider)
// Every page is built fresh from CMLinkSystem, the pilot session and the pilot
// settings when it's shown, so the terminal holds no state of its own and costs
// nothing while closed.
//   UNIT    the linked robot: status, the pilot interface, orders, the test spawn
//   CONFIG  fire control, the operator, the chase camera, the sensor mount,
//           the display (lengths shown in feet and inches)
//   TOOLS   TerminalKit Tools (inspect what V looks at, spawn records, log
//           positions): handy for finding robot records to test
// =============================================================================
module ControllableMechs

import TerminalKit.*
import TerminalKit.Tools.*
import ControllableMechs.Control.*

public class CMToolsHost extends TKToolsHost {
  public func Storage() -> String = "ControllableMechs"
}

public class CMContent extends TKContent {
  public let game: GameInstance;

  public func Request(p: ref<TKPage>, page: String, arg: String) -> Void {
    p.SetTheme(CMPilotSystem.Get(this.game).Theme());
    this.UseTools();
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

  // TerminalKit Tools keep one host at a time; ours stores under r6/storages/ControllableMechs
  // (UseFor only switches when another mod's host was last in)
  private let m_tools: ref<CMToolsHost>;

  private func UseTools() -> Void {
    if !IsDefined(this.m_tools) {
      this.m_tools = new CMToolsHost();
    }
    TKTools.UseFor(this.m_tools);
  }

  public func Act(p: ref<TKPage>, action: String, arg: String) -> Void {
    this.UseTools();
    if TKTools.Act(p, action, arg) {
      return;
    }
    let link = CMLinkSystem.Get(this.game);
    let cfg = CMPilotSystem.Get(this.game);
    let session = CMCSession.Get(this.game);
    switch action {
      case "link":
        p.SetMessage(link.LinkLookAt());
        break;
      case "unlink":
        link.Unlink();
        p.SetMessage("UPLINK CLOSED");
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
        let why = session.CanPilot();
        if StrLen(why) > 0 {
          p.SetMessage(why);
          break;
        }
        // the terminal has to close before the view can switch
        CMTerminal.CloseOpen(this.game);
        session.RequestBegin(0.4);
        break;
      case "spawntest":
        p.SetMessage(link.SpawnTestMech());
        break;
      case "despawntest":
        link.DespawnTestMech();
        p.SetMessage("TEST MECH REMOVED");
        break;
      // ---- CONFIG ----
      case "firemode":
        session.SetFireMode(CMContent.Val(arg, 0));
        break;
      case "creditv":
        session.SetCreditV(Equals(CMContent.Str(arg), "1"));
        break;
      case "gate":
        cfg.SetFireGate(Equals(CMContent.Str(arg), "1"));
        break;
      case "recoil":
        cfg.SetRecoilPct(CMContent.Val(arg, cfg.RecoilPct()));
        break;
      case "turn":
        cfg.SetTurnPct(CMContent.Val(arg, cfg.TurnPct()));
        break;
      case "hull":
        session.SetHullMult(CMContent.Val(arg, 4));
        break;
      case "dropwhenhit":
        cfg.SetStayWhenHit(!Equals(CMContent.Str(arg), "1"));
        break;
      case "hidev":
        cfg.SetHideOperator(Equals(CMContent.Str(arg), "1"));
        break;
      case "sens":
        cfg.SetSensPct(CMContent.Val(arg, cfg.SensPct()));
        break;
      case "view":
        session.SetChaseView(CMContent.Val(arg, 0) == 1);
        break;
      case "chasedist":
        cfg.SetChaseDistCm(CMContent.FtToCm(CMContent.Val(arg, CMContent.CmToFt(cfg.ChaseDistCm()))));
        break;
      case "chaseup":
        cfg.SetChaseUpCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.ChaseUpCm()))));
        break;
      case "chaseside":
        cfg.SetChaseSideCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.ChaseSideCm()))));
        break;
      case "shoulder":
        cfg.SetShoulderLeft(CMContent.Val(arg, 0) == 1);
        break;
      case "chasereset":
        cfg.ResetChase();
        p.SetMessage("*CHASE CAMERA RESET");
        break;
      case "camup":
        cfg.SetCamUpCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.CamUpCm()))));
        break;
      case "camfwd":
        cfg.SetCamFwdCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.CamFwdCm()))));
        break;
      case "camreset":
        cfg.ResetCamera();
        p.SetMessage("*SENSOR MOUNT AND SENSITIVITY RESET");
        break;
      case "debug":
        cfg.SetShowDebug(Equals(CMContent.Str(arg), "1"));
        break;
      case "parts":
        cfg.SetPartDamage(Equals(CMContent.Str(arg), "1"));
        break;
      case "restoreparts":
        if !IsDefined(link.Unit()) {
          p.SetMessage("!NO UNIT ON UPLINK");
          break;
        }
        CMCParts.Get(this.game).Restore(link.Unit());
        p.SetMessage("*ALL PARTS RESTORED");
        break;
      case "damagetest":
        if !IsDefined(link.Unit()) {
          p.SetMessage("!NO UNIT ON UPLINK");
          break;
        }
        CMCParts.Get(this.game).SetTest(link.Unit(), Equals(CMContent.Str(arg), "1"));
        break;
      case "breakpart":
        if !IsDefined(link.Unit()) {
          p.SetMessage("!NO UNIT ON UPLINK");
          break;
        }
        CMCParts.Get(this.game).Break(link.Unit(), CMContent.Val(arg, -1));
        p.SetMessage("*" + CMPart.Name(CMContent.Val(arg, -1)) + " BROKEN (TEST)");
        break;
      case "theme":
        cfg.SetTheme(CMContent.Str(arg));
        p.SetTheme(CMContent.Str(arg));
        break;
    }
  }

  // ---- UNIT: status, the pilot interface, orders ----
  private func Link(p: ref<TKPage>) -> Void {
    let link = CMLinkSystem.Get(this.game);
    p.SetTitle("UNIT CONTROL", "MT-FCS FIELD TERMINAL // REMOTE OPERATION");
    p.SetSection("link");
    if !link.IsLinked() {
      p.Dossier("NO UNIT ON UPLINK", "Look at a mech, android, drone or spiderbot within 200 ft and press [, or link it from here.", "OFFLINE", "red");
      p.Gap();
      p.Button("LINK LOOKED-AT ROBOT", "link", "", true);
      this.Test(p, link);
      return;
    }
    p.Dossier(link.UnitName(), "Linked " + StrLower(link.UnitKind()), "ONLINE", "green");
    let hp = link.HealthFraction();
    p.Stat("HULL", IntToString(RoundF(hp * 100.0)) + "%", hp < 0.3 ? "!CRITICAL" : "*NOMINAL", hp);
    p.Stat("UPLINK", IntToString(RoundF(link.Distance() * 3.28084)) + " ft", "", link.SignalFraction());
    p.Stat("ORDER", CMContent.OrderName(link.Order()), "", -1.0);
    if Equals(link.UnitKind(), "MECH") {
      p.Heading("PILOT INTERFACE");
      p.Item("PILOT THE MECH", "WASD walks, the mouse aims, LMB fires the MK.31s, RMB optics, G missile, V view, B fire mode, \\ disconnects.", "", "PILOT  [\\]", "pilot", "", true);
    }
    p.Heading("UNIT ORDERS");
    p.Buttons("Command the linked unit", "", "", "FOLLOW|HOLD|MOVE TO TARGET", "follow|hold|move", "||");
    p.SetTip("MOVE TO TARGET sends the unit to what you look at when you press it, or 50 ft ahead of you.");
    p.Gap();
    p.Button("CLOSE LINK", "unlink", "", true);
    this.Test(p, link);
  }

  // ---- test tools: a Minotaur on demand ----
  private func Test(p: ref<TKPage>, link: ref<CMLinkSystem>) -> Void {
    p.Heading("MOTOR POOL // TEST");
    if link.HasTestMech() {
      p.Item("TEST MINOTAUR", "Spawned for testing; not kept in the save.", "", "REMOVE", "despawntest", "", true);
    } else {
      p.Item("MILITECH MINOTAUR", "Spawns one 46 ft in front of you and links it.", "", "SPAWN", "spawntest", "", true);
    }
    // dev tools for part damage, while DIAGNOSTICS is on (repairs are a planned mechanic)
    if CMPilotSystem.Get(this.game).ShowDebug() && link.IsLinked() && Equals(link.UnitKind(), "MECH") {
      p.Check("DAMAGE TEST", "Dev tool: shoot the linked mech to try part damage. It can't die and won't turn on you; each hit names the part it wore. Off when you close the link", CMCParts.Get(this.game).Testing(), "damagetest", "");
      p.Item("RESTORE MECH PARTS", "Dev tool: every part of the linked mech whole again, guns back on, hull full.", "", "RESTORE", "restoreparts", "", true);
      p.Buttons("BREAK A PART (TEST)", "", "", "MK.31 L|MK.31 R|SENSOR|LEG L|PODS", "breakpart|breakpart|breakpart|breakpart|breakpart", "2|3|0|4|6");
    }
  }

  // ---- CONFIG ----
  private func Settings(p: ref<TKPage>) -> Void {
    let cfg = CMPilotSystem.Get(this.game);
    let session = CMCSession.Get(this.game);
    p.SetTitle("CONFIGURATION", "FIRE CONTROL, OPTICS AND DISPLAY");
    p.SetSection("settings");

    p.Heading("FIRE CONTROL");
    p.Dropdown("FIRE MODE", "How LMB / RMB fire the two MK.31s (B cycles it while piloting)",
      IntToString(session.FireMode()),
      CMFireMode.Name(0) + "|" + CMFireMode.Name(1) + "|" + CMFireMode.Name(2), "0|1|2", "firemode", "");
    p.SetTip("STAGGERED: LMB fires both, barrels alternating. LINKED SALVO: LMB fires both at once. SPLIT: LMB left gun, RMB right gun, MMB optics.");
    p.Check("KILLS CREDITED TO V", "The mech's hits count as yours: kills, XP, NCPD heat, who enemies turn on", session.CreditV(), "creditv", "");
    p.Check("HOLD FIRE UNTIL ON TARGET", "On: each gun waits until its barrel has swung onto the reticle. Off: the guns fire while they traverse; rounds go to the reticle either way (from the next link-in)", cfg.FireGate(), "gate", "");
    p.Slider("RECOIL", "How much the guns shake the view; it never moves the aim (from the next link-in)", "", "0|200|10|" + IntToString(cfg.RecoilPct()) + "|%", "recoil", "");
    p.Slider("HULL", "The mech's health while you pilot it, times its own (the Minotaur has about 1,000 on its own; from the next link-in)", "", "1|50|1|" + IntToString(RoundF(session.HullMult())) + "|x", "hull", "");

    p.Heading("CHASSIS");
    p.Slider("TURN SPEED", "How fast the view traverses and the chassis turns; 100% is the heavy baseline (from the next link-in)", "", "50|300|25|" + IntToString(cfg.TurnPct()) + "|%", "turn", "");
    p.Check("PART DAMAGE", "Hits wear down the part they land on: guns can be shot off, the sensor, legs and missile pods knocked out. Off: only the hull (from the next link-in)", cfg.PartDamage(), "parts", "");

    p.Heading("OPERATOR");
    p.Check("DISCONNECT WHEN V IS HIT", "Like hacking a camera: damage to V pulls you out of the mech", !cfg.StayWhenHit(), "dropwhenhit", "");
    p.Check("HIDE V WHILE LINKED", "Enemies' senses don't pick V up while you pilot, so they go for the mech. Off: enemies who see V may still attack V (from the next link-in)", cfg.HideOperator(), "hidev", "");
    p.Slider("MOUSE SENSITIVITY", "On top of the game's own mouse setting (from the next link-in)", "", "25|300|5|" + IntToString(cfg.SensPct()) + "|%", "sens", "");

    p.Heading("OPTICS // VIEW");
    p.Dropdown("VIEW", "V switches it while piloting", session.IsChase() ? "1" : "0", "SENSOR (FIRST PERSON)|CHASE (THIRD PERSON)", "0|1", "view", "");

    p.Heading("CHASE CAMERA");
    p.Slider("DISTANCE", "Behind the mech's centre", "", "10|52|1|" + IntToString(CMContent.CmToFt(cfg.ChaseDistCm())) + "| ft", "chasedist", "");
    p.Slider("HEIGHT", "Above the mech's feet", "", "60|354|2|" + IntToString(CMContent.CmToIn(cfg.ChaseUpCm())) + "| in", "chaseup", "");
    p.Slider("SIDE OFFSET", "Off the centre line, toward the shoulder (0 = dead centre)", "", "0|156|2|" + IntToString(CMContent.CmToIn(cfg.ChaseSideCm())) + "| in", "chaseside", "");
    p.Dropdown("SHOULDER", "Which side the camera sits on", cfg.ShoulderLeft() ? "1" : "0", "RIGHT|LEFT", "0|1", "shoulder", "");
    p.Item("DEFAULTS", "Distance 20 ft, height 146 in, side offset 71 in, right shoulder", "", "RESET", "chasereset", "", true);
    p.SetTip("All four apply live while you pilot. The camera pulls in when a wall, pole or container is between it and the mech. The view's up and down tilt is the mouse.");

    p.Heading("OPTICS // SENSOR MOUNT");
    p.Slider("HEIGHT", "Sensor view: above the mech's feet", "", "40|177|1|" + IntToString(CMContent.CmToIn(cfg.CamUpCm())) + "| in", "camup", "");
    p.Slider("FORWARD", "Sensor view: ahead of the mech's centre", "", "0|196|1|" + IntToString(CMContent.CmToIn(cfg.CamFwdCm())) + "| in", "camfwd", "");
    p.Item("DEFAULTS", "Height 7 ft 7 in, forward 8 ft 6 in, sensitivity 100%", "", "RESET", "camreset", "", true);

    p.Heading("DISPLAY");
    p.Dropdown("TERMINAL PALETTE", "The terminal's colours", cfg.Theme(), CMContent.ThemeLabels(), CMContent.ThemeValues(), "theme", "");
    p.Check("DIAGNOSTICS", "Traces hits and session events to the game log (for bug reports); off in normal play", cfg.ShowDebug(), "debug", "");
  }

  // A control's value from Act's arg. TerminalKit's slider used to hand on "arg:value" even
  // with an empty row arg (":230"); it now sends just the value. Taking what follows the
  // last ":" reads both forms.
  public static func Str(arg: String) -> String {
    let s = arg;
    while StrContains(s, ":") {
      s = StrAfterFirst(s, ":");
    }
    return s;
  }

  public static func Val(arg: String, def: Int32) -> Int32 = StringToInt(CMContent.Str(arg), def)

  // settings show in imperial; the pilot settings keep centimetres
  public static func CmToIn(cm: Int32) -> Int32 = RoundF(Cast<Float>(cm) / 2.54)
  public static func InToCm(inches: Int32) -> Int32 = RoundF(Cast<Float>(inches) * 2.54)
  public static func CmToFt(cm: Int32) -> Int32 = RoundF(Cast<Float>(cm) / 30.48)
  public static func FtToCm(ft: Int32) -> Int32 = RoundF(Cast<Float>(ft) * 30.48)

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
