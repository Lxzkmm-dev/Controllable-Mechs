// =============================================================================
// MECHS OF NIGHT CITY - THE GRIFFIN'S DISPLAY: A HUNTER'S HUD (0.7.1, round 2)
//
// Each drone's display befits its role (Omar). The Griffin is light assault: its display is
// a hunter's (Omar's round-2 mockup), phosphor green with red for threats, inside a 16:9
// area in the middle of the screen:
//   top           an angled banner: WEAPONS FREE (red) while hostiles are within 80 m, else
//                 WEAPONS HOLD, chevrons either side; the heading under it
//   top left      the airframe // HUNTER, LIGHT ASSAULT, kills and the streak (kills less
//                 than 10 s apart)
//   top right     the link and the flight's clock
//   centre        the gun cross; its two LMGs either side (a45, the Octant's guns), their
//                 state and their shared heat on an arc
//   the lock      red corners round what the reticle is on (CMDroneSense; held a moment
//                 after it leaves), LOCK // its kind over it, its health and distance under
//                 it, and the lead pip: where to aim for a round to meet it
//   TAKING FIRE   a red chevron at the edge of the view toward whoever just hit the drone
//   left / right  speed with the rotors' spool as a bar under it, height and vertical speed
//   bottom left   the attitude gauge: the nose's angle on an arc, HOVER / CRUISE; the
//                 weapons' block: the LMGs and the laser-guided rocket pod (two a load), the
//                 selected one marked (B), the keys
//   bottom right  the airframe: the Griffin scanned from its own meshes, tinted by the hull
// Built on the Bombus's display (CMBombusHud: its frame, text and bracket helpers); no
// field shares a name with it or its parents (a49).
// =============================================================================
module ControllableMechs

public class CMGriffinHud extends CMBombusHud {
  private let m_grSprite: array<ref<inkImage>>;
  private let m_grClock: Float;
  private let m_grBoot: Float;
  private let m_grLockBars: array<ref<inkRectangle>>;
  private let m_grLockHp: ref<inkImage>;
  private let m_grLockHpBg: ref<inkImage>;
  private let m_grLockT: ref<inkText>;
  private let m_grLockD: ref<inkText>;
  private let m_grLead: ref<inkCanvas>;
  private let m_grHostBars: array<ref<inkRectangle>>;   // every hostile in view: 8 corner bars each (a51)
  private let m_grHostD: array<ref<inkText>>;
  private let m_grLeadLine: ref<inkImage>;
  private let m_grHeatArc: array<ref<inkWidget>>;   // both guns' lit arcs, 15 segments each
  private let m_grSpool: ref<CMSlider>;
  private let m_grNeedle: ref<inkImage>;
  private let m_grThreat: array<ref<inkCanvas>>;
  private let m_grThreatT: array<Float>;
  private let m_grThreatA: array<Float>;
  private let m_grThreatTxt: ref<inkText>;
  private let m_grKills: Int32;
  private let m_grStreak: Int32;
  private let m_grLastKill: Float;

  // the text lines (indices of the text list, in BuildOsd's order)
  private let GR_BANNER: Int32 = 0;
  private let GR_HDG: Int32 = 1;
  private let GR_NAME: Int32 = 2;
  private let GR_ROLE: Int32 = 3;
  private let GR_LINK: Int32 = 4;
  private let GR_TIME: Int32 = 5;
  private let GR_LGUN: Int32 = 6;
  private let GR_LAMMO: Int32 = 7;
  private let GR_RGUN: Int32 = 8;
  private let GR_RAMMO: Int32 = 9;
  private let GR_LHEAT: Int32 = 10;
  private let GR_RHEAT: Int32 = 11;
  private let GR_SPD: Int32 = 12;
  private let GR_SPOOL: Int32 = 13;
  private let GR_ALT: Int32 = 14;
  private let GR_VS: Int32 = 15;
  private let GR_ATT: Int32 = 16;
  private let GR_REGIME: Int32 = 17;
  private let GR_WPN: Int32 = 18;
  private let GR_WPN2: Int32 = 19;
  private let GR_HULL: Int32 = 20;
  private let GR_PODS: Int32 = 21;
  private let GR_WARN: Int32 = 22;
  private let GR_RNG: Int32 = 23;
  private let GR_KEYS: Int32 = 24;

  private let GR_GAUGE_R: Float = 120.0;

  // the whole screen's width, edge to edge (a52, Omar: not the Bombus's 16:9 goggle area)
  private func GrL() -> Float = 40.0
  private func GrR() -> Float = this.FW() - 40.0

  protected func Acc() -> HDRColor = new HDRColor(0.40, 1.05, 0.52, 1.0)
  private func Hot() -> HDRColor = CMPilotHud.Red()

  private func GaugeX() -> Float = this.GrL() + 330.0
  private func GaugeY() -> Float = 1760.0

  // a clean digital feed: only the edges a little darker
  protected func BuildFeed(root: ref<inkCanvas>) -> Void {
    let e = 0;
    while e < 3 {
      let d = Cast<Float>(e) * 40.0;
      CMPilotHud.Bar(root, 0.0, d, this.FW(), 40.0, this.Blk(), 0.06);
      CMPilotHud.Bar(root, 0.0, 2120.0 - d, this.FW(), 40.0, this.Blk(), 0.06);
      e += 1;
    }
  }

  protected func BuildOsd(root: ref<inkCanvas>) -> Void {
    let x0 = this.GrL();
    let x1 = this.GrR();
    let cx = this.FW() * 0.5;
    let cy = 1080.0;
    // the banner: an angled plate, chevrons either side
    let tb = 120.0;
    CMPilotHud.Bar(root, cx - 720.0, tb + 3.0, 1440.0, 74.0, CMInk.Glass(), CMInk.GlassOp());
    CMPilotHud.Bar(root, cx - 760.0, tb, 1520.0, 4.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx - 700.0, tb + 76.0, 1400.0, 4.0, this.Acc(), 1.0);
    CMInk.Line(root, cx - 760.0, tb + 2.0, cx - 700.0, tb + 78.0, 4.0, this.Acc(), 1.0);
    CMInk.Line(root, cx + 760.0, tb + 2.0, cx + 700.0, tb + 78.0, 4.0, this.Acc(), 1.0);
    let sg = -1;
    while sg <= 1 {
      let k = 0;
      while k < 3 {
        let x = cx + Cast<Float>(sg) * (560.0 + Cast<Float>(k) * 40.0);
        let s = Cast<Float>(sg);
        CMInk.Line(root, x, tb + 20.0, x + s * 24.0, tb + 40.0, 5.0, this.Acc(), 1.0);
        CMInk.Line(root, x + s * 24.0, tb + 40.0, x, tb + 60.0, 5.0, this.Acc(), 1.0);
        k += 1;
      }
      sg += 2;
    }
    // in the GR_ order
    this.Osd(root, cx, tb + 12.0, 50, 1);              // banner
    this.Osd(root, cx, tb + 96.0, 30, 1);              // heading
    this.Osd(root, x0 + 200.0, 150.0, 40, 0);          // name
    this.Osd(root, x0 + 200.0, 204.0, 30, 0);          // role, kills, streak
    this.Osd(root, x1 - 200.0, 150.0, 38, 2);          // link
    this.Osd(root, x1 - 200.0, 204.0, 30, 2);          // clock
    this.Osd(root, cx - 200.0, cy - 70.0, 26, 1);      // L GUN
    this.Osd(root, cx - 200.0, cy - 36.0, 44, 1);
    this.Osd(root, cx + 200.0, cy - 70.0, 26, 1);      // R GUN
    this.Osd(root, cx + 200.0, cy - 36.0, 44, 1);
    this.Osd(root, cx - 200.0, cy + 54.0, 20, 1);      // HEAT
    this.Osd(root, cx + 200.0, cy + 54.0, 20, 1);
    this.Osd(root, cx - 760.0, 1040.0, 50, 2);         // speed
    this.Osd(root, cx - 1000.0, 1150.0, 24, 0);        // SPOOL
    this.Osd(root, cx + 760.0, 1040.0, 50, 0);         // height
    this.Osd(root, cx + 760.0, 1100.0, 28, 0);         // vertical speed
    this.Osd(root, this.GaugeX() + 30.0, this.GaugeY() - 64.0, 30, 0);    // attitude
    this.Osd(root, this.GaugeX() + 30.0, this.GaugeY() - 24.0, 24, 0);    // regime
    this.Osd(root, x0 + 200.0, 1860.0, 30, 0);         // weapons
    this.Osd(root, x0 + 200.0, 1904.0, 24, 0);
    this.Osd(root, x1 - 335.0, 1975.0, 26, 1);         // airframe
    this.Osd(root, x1 - 335.0, 2015.0, 24, 1);         // pods
    this.Osd(root, cx, 820.0, 52, 1);                  // warnings
    this.Osd(root, cx, cy + 140.0, 28, 1);             // range
    for i in [this.GR_ROLE, this.GR_TIME, this.GR_HDG, this.GR_LGUN, this.GR_RGUN, this.GR_LHEAT, this.GR_RHEAT, this.GR_SPOOL, this.GR_VS, this.GR_REGIME, this.GR_WPN2, this.GR_PODS] {
      this.Tint(i, this.Acc());
    }
    this.Tint(this.GR_WARN, this.Hot());
    this.SetT(this.GR_LGUN, "L GUN");
    this.SetT(this.GR_RGUN, "R GUN");
    this.SetT(this.GR_LHEAT, "HEAT");
    this.SetT(this.GR_RHEAT, "HEAT");
    this.SetT(this.GR_SPOOL, "SPOOL");
    this.Osd(root, x0 + 200.0, 1952.0, 22, 0);         // the keys
    this.Tint(this.GR_KEYS, this.Acc());
    this.SetT(this.GR_KEYS, "[LMB] FIRE   [B] SELECT   [G] ROCKETS   [RMB] ZOOM   [T] SENSOR");
    this.SetT(this.GR_LAMMO, "UNLTD");
    this.SetT(this.GR_RAMMO, "UNLTD");
    // the gun cross: a ring, its arms, a centre pip
    CMInk.Circle(root, cx, cy, 60.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx - 120.0, cy - 2.0, 50.0, 4.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx + 70.0, cy - 2.0, 50.0, 4.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx - 2.0, cy - 120.0, 4.0, 50.0, this.Acc(), 1.0);
    CMKit.Disc(root, cx, cy, 6.0, this.Acc(), 1.0);
    // each gun's heat: an arc over its HEAT, 140 degrees, lit from its left end (the two
    // guns share the heat, as the Octant's do)
    let side = 0;
    while side < 2 {
      let gx = cx + (side == 0 ? -200.0 : 200.0);
      let ring = CMInk.Ring(root, gx, cy + 70.0, 46.0, 36, 6.0, this.Acc(), 0.25);
      let lit = CMInk.Ring(root, gx, cy + 70.0, 46.0, 36, 6.0, CMPilotHud.Caution(), 1.0);
      let j = 0;
      while j < 36 {
        let a = Cast<Float>(j) * 10.0;
        ring[j].SetVisible(a >= 290.0 || a <= 70.0);
        lit[j].SetVisible(false);
        j += 1;
      }
      // from 290 round through the top to 70
      for k in [29, 30, 31, 32, 33, 34, 35, 0, 1, 2, 3, 4, 5, 6, 7] {
        ArrayPush(this.m_grHeatArc, lit[k]);
      }
      side += 1;
    }
    // speed and height boxes; the spool bar
    this.Brackets(root, cx - 1000.0, 1020.0, 260.0, 120.0);
    this.Brackets(root, cx + 740.0, 1020.0, 260.0, 120.0);
    this.m_grSpool = CMSlider.Make(root, cx - 1000.0, 1112.0, 240.0, 18.0, false, this.Acc());
    // the lock: eight corner bars, its health, its words; the lead pip and its line
    let n = 0;
    while n < 8 {
      ArrayPush(this.m_grLockBars, CMPilotHud.Bar(root, 0.0, 0.0, 4.0, 4.0, this.Hot(), 1.0));
      n += 1;
    }
    // the other hostiles in view: red corners round each, its distance under it (Omar, a51)
    let hb = 0;
    while hb < 12 * 8 {
      let b = CMPilotHud.Bar(root, 0.0, 0.0, 4.0, 4.0, this.Hot(), 0.85);
      b.SetVisible(false);
      ArrayPush(this.m_grHostBars, b);
      hb += 1;
    }
    hb = 0;
    while hb < 12 {
      let d = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 22, n"Medium", this.Hot());
      d.SetAnchorPoint(Vector2(0.5, 0.0));
      d.SetVisible(false);
      ArrayPush(this.m_grHostD, d);
      hb += 1;
    }
    this.m_grLockHpBg = CMKit.Pill(root, 0.0, 0.0, 10.0, 10.0, this.Hot(), 0.25);
    this.m_grLockHp = CMKit.Pill(root, 0.0, 0.0, 10.0, 10.0, this.Hot(), 0.95);
    this.m_grLockT = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 28, n"Semi-Bold", this.Hot());
    this.m_grLockT.SetAnchorPoint(Vector2(0.5, 1.0));
    this.m_grLockD = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 26, n"Medium", this.Hot());
    this.m_grLockD.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_grLeadLine = CMKit.Stroke(root, CMPilotHud.Caution(), 0.6);
    let lead = new inkCanvas();
    lead.SetSize(Vector2(40.0, 40.0));
    lead.Reparent(root);
    CMInk.Circle(lead, 20.0, 20.0, 18.0, CMPilotHud.Caution(), 1.0);
    this.m_grLead = lead;
    this.GrLockShow(false);
    // TAKING FIRE: four chevrons round the view
    let c = 0;
    while c < 4 {
      let ch = CMInk.Chevron(root, 80.0, 8.0, this.Hot());
      ch.SetVisible(false);
      ArrayPush(this.m_grThreat, ch);
      ArrayPush(this.m_grThreatT, 0.0);
      ArrayPush(this.m_grThreatA, 0.0);
      c += 1;
    }
    this.m_grThreatTxt = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "TAKING FIRE", 26, n"Semi-Bold", this.Hot());
    this.m_grThreatTxt.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_grThreatTxt.SetVisible(false);
    // the attitude gauge: a quarter arc from level (left) to nose down (top), its needle
    let gx = this.GaugeX();
    let gy = this.GaugeY();
    let gr = CMInk.Ring(root, gx, gy, this.GR_GAUGE_R, 48, 3.0, this.Acc(), 0.6);
    let q = 0;
    while q < 48 {
      let a = Cast<Float>(q) * 7.5;
      gr[q].SetVisible(a >= 270.0);
      q += 1;
    }
    this.m_grNeedle = CMKit.Stroke(root, this.Ink(), 1.0);
    this.Brackets(root, x0 + 180.0, 1840.0, 1000.0, 150.0);
  }

  // the Griffin, scanned from its own meshes, bottom right
  protected func BuildSprite(root: ref<inkCanvas>) -> Void {
    let x1 = this.GrR();
    let k = 300.0 / 360.0;
    let bx = x1 - 335.0 - 311.0 * k * 0.5;
    let by = 1640.0;
    this.Brackets(root, bx - 30.0, by - 20.0, 311.0 * k + 60.0, 340.0);
    let box = new inkCanvas();
    box.SetMargin(inkMargin(bx, by, 0.0, 0.0));
    box.SetSize(Vector2(311.0 * k, 300.0));
    box.Reparent(root);
    this.GrPart(box, k, n"griffin_body", 31.0, 46.0, 250.0, 309.0);
    this.GrPart(box, k, n"griffin_wing_l", 6.0, 5.0, 79.0, 246.0);
    this.GrPart(box, k, n"griffin_wing_r", 227.0, 5.0, 80.0, 246.0);
  }

  private func GrPart(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let img = new inkImage();
    img.SetAtlasResource(CMDroneHud.Atlas());
    img.SetTexturePart(name);
    img.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    img.SetSize(Vector2(w * k, h * k));
    img.SetTintColor(this.Acc());
    img.SetInteractive(false);
    img.Reparent(box);
    ArrayPush(this.m_grSprite, img);
  }

  private func GrLockShow(on: Bool) -> Void {
    for b in this.m_grLockBars {
      b.SetVisible(on);
    }
    this.m_grLockHp.SetVisible(on);
    this.m_grLockHpBg.SetVisible(on);
    this.m_grLockT.SetVisible(on);
    this.m_grLockD.SetVisible(on);
    if !on {
      this.m_grLead.SetVisible(false);
      this.m_grLeadLine.SetVisible(false);
    }
  }

  // ---- ten times a second ------------------------------------------------------------
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.SetT(this.GR_NAME, s.title + "  //  HUNTER");
    this.SetT(this.GR_ROLE, "LIGHT ASSAULT    KILLS " + (this.m_grKills < 10 ? "0" : "") + IntToString(this.m_grKills) + (this.m_grStreak > 1 ? "    STREAK X" + IntToString(this.m_grStreak) : ""));
    this.SetT(this.GR_LINK, "LINK " + IntToString(RoundF(ClampF(s.signal, 0.0, 1.0) * 100.0)) + "%");
    let h = (s.heading % 360 + 360) % 360;
    this.SetT(this.GR_HDG, "HDG " + CMPilotHud.Pad3(h) + "  " + CMPilotHud.Cardinal(h));
    this.SetT(this.GR_RNG, s.range > 0.0 && s.range < 2000.0 ? "RNG " + IntToString(RoundF(s.range)) + " M" : "RNG ---- M");
    let spool = ClampF(s.spool, 0.0, 1.0);
    this.m_grSpool.Set(spool, this.Acc());
    let warn = s.warning;
    if s.signal < 0.35 {
      warn = "LINK WEAK";
    } else {
      if s.integrity < 0.3 {
        warn = "HULL CRITICAL";
      }
    }
    this.SetT(this.GR_WARN, warn);
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.SetT(this.GR_HULL, "AIRFRAME " + IntToString(RoundF(hull * 100.0)) + "%");
    this.SetT(this.GR_PODS, "PODS  L OK   R OK");
    let c = hull < 0.3 ? CMPilotHud.Red() : (hull < 0.6 ? CMPilotHud.Caution() : this.Acc());
    for img in this.m_grSprite {
      img.SetTintColor(c);
    }
    // the guns: their shared heat on both arcs, their state either side of the cross
    let heat = ClampF(s.secHeat, 0.0, 1.0);
    let n = 0;
    while n < ArraySize(this.m_grHeatArc) {
      let lit = heat * 15.0 > Cast<Float>(n % 15) + 0.05;
      this.m_grHeatArc[n].SetVisible(lit);
      this.m_grHeatArc[n].SetTintColor(heat >= 0.99 ? this.Hot() : CMPilotHud.Caution());
      n += 1;
    }
    let gs = ArraySize(s.wStat) > 0 ? s.wStat[0] : "RDY";
    let gc = Equals(gs, "OVERHEAT") ? this.Hot() : (Equals(gs, "HOT") ? CMPilotHud.Caution() : this.Ink());
    this.SetT(this.GR_LAMMO, Equals(gs, "OVERHEAT") ? "OVHT" : "UNLTD");
    this.SetT(this.GR_RAMMO, Equals(gs, "OVERHEAT") ? "OVHT" : "UNLTD");
    this.Tint(this.GR_LAMMO, gc);
    this.Tint(this.GR_RAMMO, gc);
    // the weapons block: the selected one marked
    let gunLine = ArraySize(s.wSub) > 0 ? s.wSub[0] : "LMG 7.62 x2";
    let rkLine = ArraySize(s.wSub) > 1 ? s.wSub[1] : "";
    let rkStat = ArraySize(s.wStat) > 1 ? s.wStat[1] : "";
    this.SetT(this.GR_WPN, (s.weapon == 0 ? ">  " : "    ") + gunLine + "   " + gs);
    this.SetT(this.GR_WPN2, (s.weapon == 1 ? ">  " : "    ") + rkLine + "   " + rkStat);
    this.Tint(this.GR_WPN, s.weapon == 0 ? this.Ink() : this.Acc());
    this.Tint(this.GR_WPN2, s.weapon == 1 ? this.Ink() : (StrBeginsWith(rkStat, "RLD") ? CMPilotHud.Caution() : this.Acc()));
  }

  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.SetT(this.GR_SPD, IntToString(RoundF(speed * 3.6)) + " KMH");
    this.SetT(this.GR_ALT, alt >= 0.0 ? FloatToStringPrec(alt, 1) + " M" : "--- M");
    this.SetT(this.GR_VS, "VS " + (vs >= 0.0 ? "+" : "") + FloatToStringPrec(vs, 1));
    // the attitude gauge: level points left, 90 degrees nose down points up
    let nose = ClampF(-pitch, 0.0, 90.0);
    let a = Deg2Rad(270.0 + nose);
    let gx = this.GaugeX();
    let gy = this.GaugeY();
    CMInk.Seg(this.m_grNeedle, gx, gy, gx + SinF(a) * this.GR_GAUGE_R, gy - CosF(a) * this.GR_GAUGE_R, 6.0);
    this.SetT(this.GR_ATT, "NOSE " + CMDroneHud.Signed(pitch) + "   ROLL " + CMDroneHud.Signed(roll));
    this.SetT(this.GR_REGIME, speed < 3.0 ? "[ HOVER ]   >   CRUISE" : "HOVER   >   [ CRUISE ]");
  }

  // ---- every frame: the lock and the lead ----------------------------------------------
  public func Track(t: ref<CMDroneTrack>) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    let cx = this.FW() * 0.5;
    let cy = 1080.0;
    // the banner
    let hot = t.hostiles > 0;
    this.Tint(this.GR_BANNER, hot ? this.Hot() : this.Acc());
    this.SetT(this.GR_BANNER, hot ? "WEAPONS FREE" : "WEAPONS HOLD");
    this.GrHostiles(t, cx, cy);
    let c = t.lock;
    if !IsDefined(c) || !c.OnScreen() {
      this.GrLockShow(false);
      return;
    }
    this.GrLockShow(true);
    let col = c.kind == 2 ? this.Hot() : CMInk.KindColor(c.kind, this.Acc());
    let scale = 1080.0 / TanF(Deg2Rad(MaxF(1.0, t.fov) * 0.5));
    let hh = ClampF(1.9 / MaxF(1.0, c.dist) * scale, 70.0, 520.0);
    let hw = MaxF(60.0, hh * 0.5);
    let x = cx + c.scr.X - hw * 0.5;
    let y = cy + c.scr.Y - hh * 0.5;
    let L = MinF(34.0, hw * 0.4);
    // the eight corner bars: top left (2), top right (2), bottom left (2), bottom right (2)
    this.GrBar(0, x, y, L, 4.0, col);
    this.GrBar(1, x, y, 4.0, L, col);
    this.GrBar(2, x + hw - L, y, L, 4.0, col);
    this.GrBar(3, x + hw - 4.0, y, 4.0, L, col);
    this.GrBar(4, x, y + hh - 4.0, L, 4.0, col);
    this.GrBar(5, x, y + hh - L, 4.0, L, col);
    this.GrBar(6, x + hw - L, y + hh - 4.0, L, 4.0, col);
    this.GrBar(7, x + hw - 4.0, y + hh - L, 4.0, L, col);
    this.m_grLockT.SetMargin(inkMargin(x + hw * 0.5, y - 10.0, 0.0, 0.0));
    this.m_grLockT.SetText((c.kind == 2 ? "LOCK  //  " : "TRACK  //  ") + c.Label());
    this.m_grLockT.SetTintColor(col);
    this.m_grLockHpBg.SetMargin(inkMargin(x, y + hh + 12.0, 0.0, 0.0));
    this.m_grLockHpBg.SetSize(Vector2(hw, 10.0));
    this.m_grLockHpBg.SetTintColor(col);
    this.m_grLockHp.SetMargin(inkMargin(x, y + hh + 12.0, 0.0, 0.0));
    this.m_grLockHp.SetSize(Vector2(MaxF(10.0, hw * ClampF(c.hp, 0.0, 1.0)), 10.0));
    this.m_grLockHp.SetVisible(c.hp > 0.01);
    this.m_grLockHp.SetTintColor(col);
    this.m_grLockD.SetMargin(inkMargin(x + hw * 0.5, y + hh + 30.0, 0.0, 0.0));
    this.m_grLockD.SetText(IntToString(RoundF(c.dist)) + " M");
    this.m_grLockD.SetTintColor(col);
    // the lead pip, for a moving target
    if t.leadOn {
      let lx = cx + t.lead.X;
      let ly = cy + t.lead.Y;
      this.m_grLead.SetVisible(true);
      this.m_grLead.SetMargin(inkMargin(lx - 20.0, ly - 20.0, 0.0, 0.0));
      this.m_grLeadLine.SetVisible(true);
      CMInk.Seg(this.m_grLeadLine, cx + c.scr.X, cy + c.scr.Y, lx, ly, 2.0);
    } else {
      this.m_grLead.SetVisible(false);
      this.m_grLeadLine.SetVisible(false);
    }
  }

  // every hostile in view but the locked one: four red corners sized to it, its distance
  private func GrHostiles(t: ref<CMDroneTrack>, cx: Float, cy: Float) -> Void {
    let scale = 1080.0 / TanF(Deg2Rad(MaxF(1.0, t.fov) * 0.5));
    let n = 0;
    for c in t.contacts {
      let isLock = IsDefined(t.lock) && Equals(c.id, t.lock.id);
      if n < ArraySize(this.m_grHostD) && c.kind == 2 && !isLock && c.OnScreen() {
        let hh = ClampF(1.9 / MaxF(1.0, c.dist) * scale, 50.0, 420.0);
        let hw = MaxF(44.0, hh * 0.5);
        let x = cx + c.scr.X - hw * 0.5;
        let y = cy + c.scr.Y - hh * 0.5;
        let L = MinF(26.0, hw * 0.35);
        let b = n * 8;
        this.HostBar(b, x, y, L, 3.0);
        this.HostBar(b + 1, x, y, 3.0, L);
        this.HostBar(b + 2, x + hw - L, y, L, 3.0);
        this.HostBar(b + 3, x + hw - 3.0, y, 3.0, L);
        this.HostBar(b + 4, x, y + hh - 3.0, L, 3.0);
        this.HostBar(b + 5, x, y + hh - L, 3.0, L);
        this.HostBar(b + 6, x + hw - L, y + hh - 3.0, L, 3.0);
        this.HostBar(b + 7, x + hw - 3.0, y + hh - L, 3.0, L);
        let d = this.m_grHostD[n];
        d.SetVisible(true);
        d.SetMargin(inkMargin(x + hw * 0.5, y + hh + 6.0, 0.0, 0.0));
        d.SetText(IntToString(RoundF(c.dist)) + " M");
        n += 1;
      }
    }
    while n < ArraySize(this.m_grHostD) {
      let k = 0;
      while k < 8 {
        this.m_grHostBars[n * 8 + k].SetVisible(false);
        k += 1;
      }
      this.m_grHostD[n].SetVisible(false);
      n += 1;
    }
  }

  private func HostBar(i: Int32, x: Float, y: Float, w: Float, h: Float) -> Void {
    let b = this.m_grHostBars[i];
    b.SetVisible(true);
    b.SetMargin(inkMargin(x, y, 0.0, 0.0));
    b.SetSize(Vector2(w, h));
  }

  private func GrBar(i: Int32, x: Float, y: Float, w: Float, h: Float, c: HDRColor) -> Void {
    let b = this.m_grLockBars[i];
    b.SetMargin(inkMargin(x, y, 0.0, 0.0));
    b.SetSize(Vector2(w, h));
    b.SetTintColor(c);
  }

  // shot at: a chevron toward the shooter (`off`: the session's yaw off the view, + left)
  public func HitFrom(off: Float) -> Void {
    let best = 0;
    let i = 1;
    while i < ArraySize(this.m_grThreatT) {
      if this.m_grThreatT[i] < this.m_grThreatT[best] {
        best = i;
      }
      i += 1;
    }
    if ArraySize(this.m_grThreatT) > 0 {
      this.m_grThreatT[best] = 2.0;
      this.m_grThreatA[best] = -off;
    }
  }

  public func StartBoot() -> Void {
    this.m_grBoot = 0.8;
    this.m_grClock = 0.0;
    if IsDefined(this.FRoot()) {
      this.FRoot().SetOpacity(0.0);
    }
  }

  public func Boot(dt: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_grClock += dt;
    if this.m_grBoot > 0.0 {
      this.m_grBoot = MaxF(0.0, this.m_grBoot - dt);
      this.FRoot().SetOpacity(1.0 - this.m_grBoot / 0.8);
    }
    this.SetT(this.GR_TIME, "T+ " + CMInk.Clock(this.m_grClock));
    if this.m_grStreak > 0 && this.m_grClock - this.m_grLastKill > 10.0 {
      this.m_grStreak = 0;
    }
    // the threat chevrons fade over 2 s
    let cx = this.FW() * 0.5;
    let any = false;
    let txtX = cx;
    let txtY = 1080.0;
    let i = 0;
    while i < ArraySize(this.m_grThreat) {
      let ch = this.m_grThreat[i];
      if this.m_grThreatT[i] > 0.0 {
        this.m_grThreatT[i] -= dt;
        let a = Deg2Rad(this.m_grThreatA[i]);
        let px = cx + SinF(a) * 780.0;
        let py = 1080.0 - CosF(a) * 780.0;
        ch.SetVisible(true);
        ch.SetMargin(inkMargin(px - 40.0, py - 40.0, 0.0, 0.0));
        ch.SetRotation(this.m_grThreatA[i]);
        ch.SetOpacity(ClampF(this.m_grThreatT[i], 0.0, 1.0));
        any = true;
        txtX = px;
        txtY = py + 50.0;
      } else {
        ch.SetVisible(false);
      }
      i += 1;
    }
    this.m_grThreatTxt.SetVisible(any);
    this.m_grThreatTxt.SetMargin(inkMargin(txtX, txtY, 0.0, 0.0));
  }

  // a round of ours connected; a kill counts, and kills less than 10 s apart are a streak
  public func Hit(kill: Bool) -> Void {
    if kill {
      this.m_grKills += 1;
      this.m_grStreak = this.m_grClock - this.m_grLastKill <= 10.0 ? this.m_grStreak + 1 : 1;
      this.m_grLastKill = this.m_grClock;
    }
  }
}
