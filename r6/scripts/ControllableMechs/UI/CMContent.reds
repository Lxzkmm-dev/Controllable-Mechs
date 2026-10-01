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
        p.SetMessage(link.SpawnTestMech(StringToName(CMContent.Str(arg))));
        break;
      case "spawndrone":
        p.SetMessage(link.SpawnTestDrone(CMContent.Str(arg)));
        break;
      case "cfgprofile":
        cfg.SetCfgProfile(CMContent.Val(arg, 0));
        break;
      case "dlevel":
        cfg.SetDroneLevel(cfg.CfgProfile(), CMContent.Val(arg, 50));
        break;
      case "dtilt":
        cfg.SetDroneTilt(cfg.CfgProfile(), CMContent.Val(arg, 30));
        break;
      case "dshowtilt":
        cfg.SetDroneShowTilt(cfg.CfgProfile(), CMContent.Val(arg, 90));
        break;
      case "drate":
        cfg.SetDroneRate(cfg.CfgProfile(), CMContent.Val(arg, 180));
        break;
      case "dcamup":
        cfg.SetDroneCamUpCm(cfg.CfgProfile(), CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.DroneCamUpCm(cfg.CfgProfile())))));
        break;
      case "dcamfwd":
        cfg.SetDroneCamFwdCm(cfg.CfgProfile(), CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.DroneCamFwdCm(cfg.CfgProfile())))));
        break;
      case "dhide":
        cfg.SetDroneHideInSight(cfg.CfgProfile(), Equals(CMContent.Str(arg), "1"));
        break;
      case "dcamreset":
        cfg.ResetDroneCam(cfg.CfgProfile());
        p.SetMessage("*" + StrUpper(cfg.CfgProfile()) + " SENSOR MOUNT RESET");
        break;
      case "dreset":
        cfg.ResetDrone(cfg.CfgProfile());
        p.SetMessage("*" + StrUpper(cfg.CfgProfile()) + " FLIGHT SETTINGS RESET");
        break;
      case "droneaioff":
        cfg.SetDroneAiOff(Equals(CMContent.Str(arg), "1"));
        break;
      case "dronevis":
        cfg.SetDroneVisualTest(CMContent.Val(arg, 1));
        break;
      case "dronelag":
        cfg.SetDroneCamLag(CMContent.Val(arg, 1));
        break;
      case "dronemove":
        cfg.SetDroneMove(CMContent.Val(arg, 0));
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
        cfg.SetChaseDistCm(CMContent.FtToCm(CMContent.Val(arg, CMContent.CmToFt(cfg.ChaseDistCm(cfg.CfgProfile())))), cfg.CfgProfile());
        break;
      case "chaseup":
        cfg.SetChaseUpCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.ChaseUpCm(cfg.CfgProfile())))), cfg.CfgProfile());
        break;
      case "chaseside":
        cfg.SetChaseSideCm(CMContent.InToCm(CMContent.Val(arg, CMContent.CmToIn(cfg.ChaseSideCm(cfg.CfgProfile())))), cfg.CfgProfile());
        break;
      case "shoulder":
        cfg.SetShoulderLeft(CMContent.Val(arg, 0) == 1, cfg.CfgProfile());
        break;
      case "chasereset":
        cfg.ResetChaseOf(cfg.CfgProfile());
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
    if Equals(link.UnitKind(), "DRONE") {
      p.Heading("PILOT INTERFACE");
      p.Item("FLY THE DRONE", "Test build: WASD tilt and move it, Space/Ctrl climb and descend, the mouse turns, \\ disconnects.", "", "FLY  [\\]", "pilot", "", true);
    }
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
      p.Buttons("SPAWN A MINOTAUR", "", "", "MILITECH|ARASAKA|NCPD|KURT'S", "spawntest|spawntest|spawntest|spawntest", "mch_003__minotaur_militech_01|mch_003__minotaur_arasaka_01|mch_003__minotaur_police_01|mch_003__minotaur_kurt");
      p.SetTip("Spawns one 46 ft in front of you and links it, in that livery.");
      p.Buttons("SPAWN A DRONE (TEST)", "", "", "BOMBUS|GRIFFIN|WYVERN|OCTANT", "spawndrone|spawndrone|spawndrone|spawndrone", "bombus|griffin|wyvern|octant");
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
    p.SetTitle("CONFIGURATION", "PROFILES, OPERATOR AND DISPLAY");
    p.SetSection("settings");

    // whose settings: the mech, or one of the four drone types (each has its own)
    p.Dropdown("PROFILE", "Which unit's dedicated settings are shown below", IntToString(cfg.CfgProfileIndex()), "MECH|BOMBUS|GRIFFIN|WYVERN|OCTANT", "0|1|2|3|4", "cfgprofile", "");
    let kind = cfg.CfgProfile();
    if NotEquals(kind, "mech") {
      this.DroneSettings(p, cfg, kind);
    } else {
      this.MechSettings(p, cfg, session);
    }
    this.CommonSettings(p, cfg, session);
  }

  // the chase camera of one profile: the mech's, or a drone type's own
  private func ChaseSettings(p: ref<TKPage>, cfg: ref<CMPilotSystem>, prof: String) -> Void {
    let drone = NotEquals(prof, "mech");
    p.Heading(drone ? StrUpper(prof) + " // CHASE CAMERA" : "CHASE CAMERA");
    p.Slider("DISTANCE", drone ? "Behind the drone" : "Behind the mech's centre", "", (drone ? "2" : "10") + "|52|1|" + IntToString(CMContent.CmToFt(cfg.ChaseDistCm(prof))) + "| ft", "chasedist", "");
    p.Slider("HEIGHT", drone ? "Above the drone" : "Above the mech's feet", "", (drone ? "0" : "60") + "|354|2|" + IntToString(CMContent.CmToIn(cfg.ChaseUpCm(prof))) + "| in", "chaseup", "");
    p.Slider("SIDE OFFSET", "Off the centre line, toward the shoulder (0 = dead centre)", "", "0|156|2|" + IntToString(CMContent.CmToIn(cfg.ChaseSideCm(prof))) + "| in", "chaseside", "");
    p.Dropdown("SHOULDER", "Which side the camera sits on", cfg.ShoulderLeft(prof) ? "1" : "0", "RIGHT|LEFT", "0|1", "shoulder", "");
    p.Item("DEFAULTS", drone ? "This drone's own framing, centred" : "Distance 20 ft, height 146 in, side offset 71 in, right shoulder", "", "RESET", "chasereset", "", true);
    p.SetTip("Applies at once, even while linked. The camera pulls in when a wall, pole or container is between it and the unit. The view's up and down tilt is the mouse.");
  }

  // a drone type's flight: how much it levels itself, how far and how fast it tilts
  private func DroneSettings(p: ref<TKPage>, cfg: ref<CMPilotSystem>, kind: String) -> Void {
    let base = CMDroneProfiles.For(kind);
    p.Heading(StrUpper(kind) + " // FLIGHT");
    p.Slider("SELF-LEVELLING", "100%: the keys set a tilt and it levels itself when you let go. 0%: acro, the keys set how fast it rolls and pitches and nothing levels it; you fly every attitude. Between: the rates, with a pull back toward level (from the next link-in)", "", "0|100|5|" + IntToString(cfg.DroneLevel(kind)) + "|%", "dlevel", "");
    p.Slider("TILT LIMIT", "How far it leans with the keys held, while it levels itself; more tilt, more speed (from the next link-in)", "", "10|70|1|" + IntToString(cfg.DroneTilt(kind, RoundF(base.tilt))) + "|deg", "dtilt", "");
    p.Slider("ROLL / PITCH RATE", "How fast it rolls and pitches at full key, the acro part of the flight (from the next link-in)", "", "45|600|15|" + IntToString(cfg.DroneRate(kind, RoundF(base.tiltRate))) + "|deg/s", "drate", "");
    p.Slider("MODEL LEAN LIMIT", "How far the drone's model is drawn leaning; the flight itself is never capped (90 = drawn as flown)", "", "10|90|5|" + IntToString(cfg.DroneShowTilt(kind, RoundF(base.showTilt))) + "|deg", "dshowtilt", "");
    p.Item("DEFAULTS", "Self-levelling " + IntToString(CMDroneProfiles.DefaultLevel(kind)) + "%, tilt " + IntToString(RoundF(base.tilt)) + " deg, rate " + IntToString(RoundF(base.tiltRate)) + " deg/s, model lean " + IntToString(RoundF(base.showTilt)) + " deg", "", "RESET", "dreset", "", true);
    p.SetTip("At low self-levelling it will loop and roll right over; upside down its thrust drives it down.");
    p.Heading(StrUpper(kind) + " // OPTICS // SENSOR MOUNT");
    p.Slider("HEIGHT", "Sight view: above the drone's base (its centre by default)", "", "0|118|1|" + IntToString(CMContent.CmToIn(cfg.DroneCamUpCm(kind))) + "| in", "dcamup", "");
    p.Slider("FORWARD", "Sight view: ahead of the drone's centre (its nose by default)", "", "0|157|1|" + IntToString(CMContent.CmToIn(cfg.DroneCamFwdCm(kind))) + "| in", "dcamfwd", "");
    p.Check("HIDE THE DRONE IN SIGHT VIEW", "Its own model isn't drawn while you look through its sensor, so the view isn't inside its shell (third person always shows it)", cfg.DroneHideInSight(kind), "dhide", "");
    p.Item("DEFAULTS", "At the nose, centre height: " + IntToString(CMContent.CmToIn(CMDroneHull.SensorUpCm(kind))) + " in up, " + IntToString(CMContent.CmToIn(CMDroneHull.SensorFwdCm(kind))) + " in forward", "", "RESET", "dcamreset", "", true);
    p.SetTip("Applies at once, even while linked.");
    this.ChaseSettings(p, cfg, kind);
  }

  private func MechSettings(p: ref<TKPage>, cfg: ref<CMPilotSystem>, session: ref<CMCSession>) -> Void {
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

    p.Heading("OPTICS // SENSOR MOUNT");
    p.Slider("HEIGHT", "Sensor view: above the mech's feet", "", "40|177|1|" + IntToString(CMContent.CmToIn(cfg.CamUpCm())) + "| in", "camup", "");
    p.Slider("FORWARD", "Sensor view: ahead of the mech's centre", "", "0|196|1|" + IntToString(CMContent.CmToIn(cfg.CamFwdCm())) + "| in", "camfwd", "");
    p.Item("DEFAULTS", "Height 7 ft 7 in, forward 8 ft 6 in, sensitivity 100%", "", "RESET", "camreset", "", true);
    this.ChaseSettings(p, cfg, "mech");
  }

  // for every unit: the operator, the view, the chase camera and the display
  private func CommonSettings(p: ref<TKPage>, cfg: ref<CMPilotSystem>, session: ref<CMCSession>) -> Void {
    p.Heading("OPERATOR");
    p.Check("DISCONNECT WHEN V IS HIT", "Like hacking a camera: damage to V pulls you out of the mech", !cfg.StayWhenHit(), "dropwhenhit", "");
    p.Check("HIDE V WHILE LINKED", "Enemies' senses don't pick V up while you pilot, so they go for the mech. Off: enemies who see V may still attack V (from the next link-in)", cfg.HideOperator(), "hidev", "");
    p.Slider("MOUSE SENSITIVITY", "On top of the game's own mouse setting (from the next link-in)", "", "25|300|5|" + IntToString(cfg.SensPct()) + "|%", "sens", "");

    p.Heading("OPTICS // VIEW");
    p.Dropdown("VIEW", "V switches it while piloting", session.IsChase() ? "1" : "0", "SENSOR (FIRST PERSON)|CHASE (THIRD PERSON)", "0|1", "view", "");


    p.Heading("DISPLAY");
    p.Dropdown("TERMINAL PALETTE", "The terminal's colours", cfg.Theme(), CMContent.ThemeLabels(), CMContent.ThemeValues(), "theme", "");
    p.Check("DIAGNOSTICS", "Traces hits and session events to the game log (for bug reports); off in normal play", cfg.ShowDebug(), "debug", "");
    if cfg.ShowDebug() {
      p.Check("DRONE AI OFF WHILE FLYING (TEST)", "On: the drone's AI controller is switched off while you fly it and its hover-height animation input is held at zero, so the game stops treating it as an NPC that keeps its own altitude. Off: its AI stays on (from the next link-in)", cfg.DroneAiOff(), "droneaioff", "");
      p.Dropdown("DRONE MOVE METHOD (TEST)", "How a flown drone is put where its flight model says each frame; the log says how close each one lands", IntToString(cfg.DroneMove()), "ENTITY TRANSFORM|AI TELEPORT|AI MOVE CARROT", "4|1|2", "dronemove", "");
      p.Dropdown("DRONE CAMERA FRAME LAG", "How many frames the camera follows a flown drone behind. Its mesh is drawn from where it was a frame earlier, 0 by default; 1 or 2 only to test if the drone jitters in the chase view (applies at once)", IntToString(cfg.DroneCamLag()), "0|1|2", "0|1|2", "dronelag", "");
      p.Dropdown("DRONE NPC SYSTEMS OFF (TEST)", "Which of the drone's own NPC systems are off while you fly it, to find what draws it off the camera in the chase view (from the next link-in)", IntToString(cfg.DroneVisualTest()), "NONE|MOVEMENT|ANIMATION|BOTH", "0|1|2|3", "dronevis", "");
    }
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
