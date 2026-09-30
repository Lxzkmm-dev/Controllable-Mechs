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
      case "spikes":
        CMSpikeSystem.Get(this.game).Page(p);
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
    if StrBeginsWith(action, "sp_") && CMSpikeSystem.Get(this.game).Act(p, action, arg) {
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
        let why = pilot.CanPilot(true);
        if StrLen(why) > 0 {
          p.SetMessage(why);
          break;
        }
        // the terminal has to close before the view can switch
        CMTerminal.CloseOpen(this.game);
        // the framework (M1) while its preview is on, else the alpha's Pilot Mode
        if CMCSession.Get(this.game).Armed() {
          CMCSession.Get(this.game).RequestBegin(0.4);
        } else {
          pilot.RequestEnter(0.4);
        }
        break;
      case "spawntest":
        p.SetMessage(link.SpawnTestMech());
        break;
      case "despawntest":
        link.DespawnTestMech();
        p.SetMessage("TEST MECH REMOVED");
        break;
      case "firemode":
        pilot.SetFireMode(CMContent.Val(arg, 0));
        break;
      case "dropwhenhit":
        pilot.SetStayWhenHit(!Equals(CMContent.Str(arg), "1"));
        break;
      case "camup":
        pilot.SetCamUpCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(pilot.CamUpCm()))));
        break;
      case "camfwd":
        pilot.SetCamFwdCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(pilot.CamFwdCm()))));
        break;
      case "sens":
        pilot.SetSensPct(CMContent.Val(arg, pilot.SensPct()));
        break;
      case "armtrack":
        pilot.SetArmTrack(Equals(CMContent.Str(arg), "1"));
        break;
      case "damage":
        pilot.SetDamagePct(CMContent.Val(arg, pilot.DamagePct()));
        break;
      case "cammode":
        pilot.SetCamMode(CMContent.Val(arg, 0));
        break;
      case "chasedist":
        pilot.SetChaseDistCm(CMContent.FtToCm(CMContent.Val(arg, CMContent.CmToFt(pilot.ChaseDistCm()))));
        break;
      case "chaseup":
        pilot.SetChaseUpCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(pilot.ChaseUpCm()))));
        break;
      case "aimmode":
        pilot.SetAimMode(CMContent.Val(arg, 0));
        break;
      case "traverse":
        pilot.SetTraverse(CMContent.Val(arg, pilot.Traverse()));
        break;
      case "camreset":
        pilot.ResetCamera();
        p.SetMessage("*CAMERA SETTINGS RESET");
        break;
      case "debug":
        pilot.SetShowDebug(Equals(CMContent.Str(arg), "1"));
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
      p.Item("PILOT THE MECH", "Take its sensor feed: WASD walks, the mouse turns the torso, LMB fires the MK.31s, \\ disconnects.", "", "PILOT  [\\]", "pilot", "", true);
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
  }

  // ---- SETTINGS: pilot and palette ----
  private func Settings(p: ref<TKPage>) -> Void {
    let pilot = CMPilotSystem.Get(this.game);
    p.SetTitle("CONFIGURATION", "FIRE CONTROL, OPTICS AND DISPLAY");
    p.SetSection("settings");
    p.Heading("FIRE CONTROL");
    p.Dropdown("FIRE MODE", "How LMB / RMB fire the two MK.31s (B cycles it while piloting)",
      IntToString(pilot.FireMode()),
      CMFireMode.Name(0) + "|" + CMFireMode.Name(1) + "|" + CMFireMode.Name(2), "0|1|2", "firemode", "");
    p.SetTip("STAGGERED: LMB fires both, barrels alternating. LINKED SALVO: LMB fires both at once. SPLIT: LMB left gun, RMB right gun, MMB optics.");
    p.Dropdown("AIM MODE", "Where the rounds go", IntToString(pilot.AimMode()), "GIMBALLED|TO THE RETICLE|ALONG THE BARRELS", "0|1|2", "aimmode", "");
    p.SetTip("GIMBALLED: rounds go to what the reticle is on, within each gun's travel around its mount (12 deg side to side, 40 down, 25 up); the pips show where they'll land. TO THE RETICLE: always at the reticle; the guns wait for the chassis to line up. ALONG THE BARRELS: straight out of the muzzles.");
    p.Check("ARM TRACKING (EXPERIMENTAL)", "The mech's arms turn toward the aim point, so the barrel effects follow the rounds", pilot.ArmTrackOn(), "armtrack", "");
    p.Slider("MK.31 DAMAGE", "Damage of the two HMGs while you pilot", "", "100|300|10|" + IntToString(pilot.DamagePct()) + "|%", "damage", "");
    p.Check("DISCONNECT WHEN V IS HIT", "Like hacking a camera: damage to V pulls you out of the mech", !pilot.StayWhenHit(), "dropwhenhit", "");
    p.Heading("OPTICS // VIEW");
    p.Dropdown("VIEW", "V switches it while piloting", IntToString(pilot.CamMode()), "SENSOR (FIRST PERSON)|CHASE (THIRD PERSON)", "0|1", "cammode", "");
    p.Slider("CHASE DISTANCE", "Chase view: behind the mech's centre", "", "13|52|1|" + IntToString(CMContent.CmToFt(pilot.ChaseDistCm())) + "| ft", "chasedist", "");
    p.Slider("CHASE HEIGHT", "Chase view: above the mech's feet", "", "79|354|2|" + IntToString(CMContent.CmToIn(pilot.ChaseUpCm())) + "| in", "chaseup", "");
    p.SetTip("Both views pull in when a wall, pole or container is between the mech and the camera.");
    p.Heading("OPTICS // SENSOR MOUNT");
    p.Slider("HEIGHT", "Above the mech's feet", "", "40|177|1|" + IntToString(CMContent.CmToIn(pilot.CamUpCm())) + "| in", "camup", "");
    p.SetTip("Applies live: change it, then press \\ to check the view.");
    p.Slider("FORWARD", "Ahead of the mech's centre", "", "0|196|1|" + IntToString(CMContent.CmToIn(pilot.CamFwdCm())) + "| in", "camfwd", "");
    p.Slider("TRAVERSE SPEED", "How fast the torso can turn", "", "15|120|5|" + IntToString(pilot.Traverse()) + "| deg/s", "traverse", "");
    p.Slider("MOUSE SENSITIVITY", "On top of the game's own mouse setting", "", "25|300|5|" + IntToString(pilot.SensPct()) + "|%", "sens", "");
    p.Item("DEFAULTS", "Height 7 ft 7 in, forward 8 ft 6 in, traverse 40 deg/s, sensitivity 100%", "", "RESET", "camreset", "", true);
    p.Check("DEBUG READOUT", "A diagnostic line on the pilot HUD (frames, inputs, locks)", pilot.ShowDebug(), "debug", "");
    p.Heading("DISPLAY");
    p.Dropdown("TERMINAL PALETTE", "The terminal's colours", pilot.Theme(), CMContent.ThemeLabels(), CMContent.ThemeValues(), "theme", "");
  }

  // A control's value from Act's arg. TerminalKit's slider always hands on "arg:value", so
  // with an empty row arg it arrives as ":230" (TKView.SlideCommit; its README says
  // just the value). StringToInt(":230", current) fell back to the current value, so no
  // slider ever changed anything. Take what follows the last ":", whichever form arrives.
  // (docs/terminalkit-dev-request-slider.md asks for the fix in TerminalKit.)
  public static func Str(arg: String) -> String {
    let s = arg;
    while StrContains(s, ":") {
      s = StrAfterFirst(s, ":");
    }
    return s;
  }

  public static func Val(arg: String, def: Int32) -> Int32 = StringToInt(CMContent.Str(arg), def)

  // settings show in imperial; the pilot system keeps centimetres
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
