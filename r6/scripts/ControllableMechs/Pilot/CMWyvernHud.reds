// =============================================================================
// MECHS OF NIGHT CITY - THE WYVERN'S DISPLAY: A SCOUT'S ISR FEED (0.7.1, round 2)
//
// Each drone's display befits its role (Omar). The Wyvern scouts: its display is an ISR
// camera's (Omar's round-2 mockup), in teal with amber for what matters, inside a 16:9 area
// in the middle of the screen, a viewfinder's corners round it and the feed graded cold:
//   top left      the airframe, ISR // SCOUT, its task and the link
//   top centre    the optics: EO / IR and the zoom, the field of view, the sensor's mode,
//                 the focus (AF LOCK while the laser has a return)
//   top right     REC ISR and the flight's clock (a red dot blinking), the grid it is over
//   right edge    the zoom ladder and where the optics are on it
//   centre        a focus box and crosshair; the scan ring that fills while the reticle is
//                 held on an untagged contact (CMDroneSense: SCAN_TIME tags it), SCAN n% or
//                 TAGGED C-nn; the range and the elevation under it
//   the feed      a diamond on every tagged contact in view, its C-number, kind, distance
//   left          the contacts log: V (C-01) and the tagged contacts, nearest first; the
//                 ping (G: tags everything near, then cools down)
//   bottom left   the radar: heading up, 100 m, a sweep; every contact the sweep found, the
//                 tagged ones bright
//   bottom centre its signature (the rotors' spool and its speed: how loud it is) and how
//                 many hostiles near are in combat (DETECTED BY)
//   left / right  speed, and height with the vertical speed
//   bottom right  the airframe: the Wyvern scanned from its own meshes, wings unfolded (all
//                 six rotors), tinted by the hull
// Built on the Bombus's display (CMBombusHud: its frame, text and bracket helpers); no
// field shares a name with it or its parents (a49).
// =============================================================================
module ControllableMechs

public class CMWyvernHud extends CMBombusHud {
  private let m_wySprite: array<ref<inkImage>>;
  private let m_wyClock: Float;
  private let m_wyBoot: Float;
  private let m_wyBlink: Float;
  private let m_wyRec: ref<inkImage>;
  private let m_wyZoomMark: ref<inkText>;
  private let m_wyRing: array<ref<inkWidget>>;
  private let m_wyDia: array<ref<inkCanvas>>;
  private let m_wyDiaTag: array<ref<inkText>>;
  private let m_wyDiaLine: array<ref<inkText>>;
  private let m_wyDots: array<ref<inkImage>>;
  private let m_wyV: ref<inkCanvas>;
  private let m_wySweep: ref<inkImage>;
  private let m_wySig: ref<CMSlider>;
  private let m_wySpool: Float;
  private let m_wySpeed: Float;
  private let m_wyFocus: String;       // the sensor's mode and focus, from the last refresh
  private let m_wyHeat: ref<CMSlider>;   // the guns' heat
  private let m_wyGunHeat: Float;

  // the text lines (indices of the text list, in BuildOsd's order)
  private let WY_NAME: Int32 = 0;
  private let WY_ROLE: Int32 = 1;
  private let WY_EO: Int32 = 2;
  private let WY_FOV: Int32 = 3;
  private let WY_REC: Int32 = 4;
  private let WY_GRID: Int32 = 5;
  private let WY_ZOOM: Int32 = 6;
  private let WY_SCAN: Int32 = 7;
  private let WY_RNG: Int32 = 8;
  private let WY_LOG: Int32 = 9;
  private let WY_ROW0: Int32 = 10;      // four rows of three: tag, label, distance
  private let WY_PING: Int32 = 22;
  private let WY_RADAR: Int32 = 23;
  private let WY_SIG: Int32 = 24;
  private let WY_SIGV: Int32 = 25;
  private let WY_DET: Int32 = 26;
  private let WY_DETV: Int32 = 27;
  private let WY_SPD: Int32 = 28;
  private let WY_ALT: Int32 = 29;
  private let WY_VS: Int32 = 30;
  private let WY_HULL: Int32 = 31;
  private let WY_ROTORS: Int32 = 32;
  private let WY_WARN: Int32 = 33;
  private let WY_GUN: Int32 = 34;
  private let WY_KEYS: Int32 = 35;

  private let WY_RING_R: Float = 250.0;
  private let WY_RING_N: Int32 = 60;
  private let WY_RADAR_R: Float = 250.0;
  private let WY_RADAR_M: Float = 100.0;   // the radar's reach, m

  // the whole screen's width, edge to edge (a52, Omar: not the Bombus's 16:9 goggle area)
  private func WyL() -> Float = 40.0
  private func WyR() -> Float = this.FW() - 40.0

  protected func Acc() -> HDRColor = new HDRColor(0.62, 1.05, 1.00, 1.0)
  private func Amb() -> HDRColor = CMPilotHud.Caution()

  // the radar's middle and the scan ring's (design units)
  private func RadarX() -> Float = this.WyL() + 470.0
  private func RadarY() -> Float = 1700.0

  // a clean digital feed graded cold, a viewfinder's corners round the 16:9 area
  protected func BuildFeed(root: ref<inkCanvas>) -> Void {
    let x0 = this.WyL();
    let w = this.WyR() - x0;
    CMPilotHud.Bar(root, 0.0, 0.0, this.FW(), 2160.0, new HDRColor(0.08, 0.16, 0.20, 1.0), 0.15);   // the cold grade over the whole feed
    CMKit.Vignette(root, this.FW(), 2160.0, 180.0, 0.35);
    let L = 90.0;
    let fx = x0 + 120.0;
    let fy = 110.0;
    let fw = w - 240.0;
    let fh = 1940.0;
    let c = this.Acc();
    CMKit.Brackets(root, fx, fy, fw, fh, L, c, 0.8);
  }

  protected func BuildOsd(root: ref<inkCanvas>) -> Void {
    let x0 = this.WyL();
    let x1 = this.WyR();
    let cx = this.FW() * 0.5;
    let cy = 1080.0;
    let lx = x0 + 200.0;
    let ly = 560.0;
    // in the WY_ order
    this.Osd(root, x0 + 200.0, 150.0, 40, 0);          // name
    this.Osd(root, x0 + 200.0, 204.0, 30, 0);          // role, task, link
    this.Osd(root, cx, 140.0, 46, 1);                  // EO / IR
    this.Osd(root, cx, 200.0, 28, 1);                  // field of view, sensor, focus
    this.Osd(root, x1 - 200.0, 150.0, 38, 2);          // REC
    this.Osd(root, x1 - 200.0, 204.0, 28, 2);          // grid
    this.Osd(root, x1 - 210.0, 500.0, 24, 1);          // ZOOM
    this.Osd(root, cx + 270.0, cy - 250.0, 30, 0);     // scan
    this.Osd(root, cx, cy + 130.0, 28, 1);             // range, elevation
    this.Osd(root, lx, ly, 30, 0);                     // the log's head
    let r = 0;
    while r < 4 {
      let ry = ly + 70.0 + Cast<Float>(r) * 80.0;
      this.Osd(root, lx, ry, 28, 0);
      this.Osd(root, lx + 110.0, ry, 28, 0);
      this.Osd(root, lx + 560.0, ry, 28, 2);
      r += 1;
    }
    this.Osd(root, lx, ly + 400.0, 24, 0);             // ping
    this.Osd(root, this.RadarX(), this.RadarY() + this.WY_RADAR_R + 16.0, 24, 1);
    this.Osd(root, cx - 360.0, 1830.0, 26, 0);         // signature
    this.Osd(root, cx, 1868.0, 28, 0);
    this.Osd(root, cx + 160.0, 1830.0, 26, 0);         // detected by
    this.Osd(root, cx + 160.0, 1866.0, 34, 0);
    this.Osd(root, cx - 760.0, 1040.0, 44, 2);         // speed
    this.Osd(root, cx + 760.0, 1040.0, 44, 0);         // height
    this.Osd(root, cx + 760.0, 1094.0, 26, 0);         // vertical speed
    this.Osd(root, x1 - 335.0, 1975.0, 26, 1);         // airframe
    this.Osd(root, x1 - 335.0, 2015.0, 24, 1);         // rotors
    this.Osd(root, cx, 820.0, 52, 1);                  // warnings
    this.Osd(root, lx, 1080.0, 30, 0);                 // the guns (a45)
    this.Osd(root, lx, 1176.0, 22, 0);                 // their keys
    // the guns' heat
    CMKit.Panel(root, lx - 20.0, 1060.0, 600.0, 160.0, this.Acc(), 0.6);
    this.m_wyHeat = CMSlider.Make(root, lx, 1134.0, 400.0, 18.0, false, this.Amb());
    for i in [this.WY_ROLE, this.WY_FOV, this.WY_GRID, this.WY_ZOOM, this.WY_SCAN, this.WY_PING, this.WY_RADAR, this.WY_SIG, this.WY_DET, this.WY_VS, this.WY_ROTORS] {
      this.Tint(i, this.Acc());
    }
    this.Tint(this.WY_SIGV, this.Amb());
    this.Tint(this.WY_KEYS, this.Acc());
    this.SetT(this.WY_KEYS, "[LMB] FIRE   [G] PING   [RMB] ZOOM   [T] SENSOR");
    this.Tint(this.WY_WARN, CMPilotHud.Red());
    this.SetT(this.WY_ZOOM, "ZOOM");
    this.SetT(this.WY_SIG, "SIGNATURE");
    this.SetT(this.WY_DET, "DETECTED BY");
    this.SetT(this.WY_RADAR, IntToString(RoundF(this.WY_RADAR_M)) + " M   HDG UP");
    // the recording dot
    this.m_wyRec = CMKit.Disc(root, x1 - 626.0, 174.0, 14.0, CMPilotHud.Red(), 1.0);
    // the zoom ladder, right edge
    let zx = x1 - 230.0;
    let z = 0;
    while z < 9 {
      CMKit.Ln(root, zx, 560.0 + Cast<Float>(z) * 90.0, z % 2 == 0 ? 40.0 : 22.0, 4.0, this.Acc(), 0.8);
      z += 1;
    }
    this.m_wyZoomMark = CMPilotHud.Label(root, inkEAnchor.TopLeft, zx - 16.0, 560.0, "> X1", 30, n"Semi-Bold", this.Amb());
    this.m_wyZoomMark.SetAnchorPoint(Vector2(1.0, 0.5));
    // the focus box, the crosshair
    this.Brackets(root, cx - 150.0, cy - 110.0, 300.0, 220.0);
    CMKit.Ln(root, cx - 14.0, cy - 2.0, 28.0, 4.0, this.Ink(), 1.0);
    CMKit.Ln(root, cx - 2.0, cy - 14.0, 4.0, 28.0, this.Ink(), 1.0);
    // the scan ring: a dim circle, and the bright one that fills clockwise from the top
    CMInk.Circle(root, cx, cy, this.WY_RING_R, this.Acc(), 0.25);
    this.m_wyRing = CMInk.Ring(root, cx, cy, this.WY_RING_R, this.WY_RING_N, 8.0, this.Acc(), 1.0);
    for b in this.m_wyRing {
      b.SetVisible(false);
    }
    // the contacts log's panel
    CMKit.Panel(root, lx - 20.0, ly - 30.0, 600.0, 470.0, this.Acc(), 0.6);
    this.Brackets(root, lx - 20.0, ly - 30.0, 600.0, 470.0);
    // the radar: three rings, the cross, the sweep, the contacts, V
    let rx = this.RadarX();
    let ry = this.RadarY();
    let rr = this.WY_RADAR_R;
    // a dark disc under it (a50, the mockup's; a square read as a grey block)
    CMKit.Disc(root, rx, ry, rr, CMInk.Glass(), CMInk.GlassOp());
    CMInk.Circle(root, rx, ry, rr, this.Acc(), 0.6);
    CMInk.Circle(root, rx, ry, rr * 0.66, this.Acc(), 0.45);
    CMInk.Circle(root, rx, ry, rr * 0.33, this.Acc(), 0.45);
    CMKit.Ln(root, rx - rr, ry - 1.0, rr * 2.0, 2.0, this.Acc(), 0.3);
    CMKit.Ln(root, rx - 1.0, ry - rr, 2.0, rr * 2.0, this.Acc(), 0.3);
    this.m_wySweep = CMKit.Stroke(root, this.Acc(), 0.85);
    let d = 0;
    while d < 32 {
      let dot = CMKit.Disc(root, rx, ry, 8.0, this.Acc(), 1.0);
      dot.SetVisible(false);
      ArrayPush(this.m_wyDots, dot);
      d += 1;
    }
    this.m_wyV = CMInk.Chevron(root, 30.0, 5.0, CMInk.KindColor(0, this.Acc()));
    CMKit.Disc(root, rx, ry, 6.0, this.Ink(), 1.0);   // the Wyvern
    // the signature's meter
    this.m_wySig = CMSlider.Make(root, cx - 360.0, 1876.0, 330.0, 18.0, false, this.Amb());
    // the tagged contacts' diamonds on the feed
    let t = 0;
    while t < 12 {
      let dia = CMInk.Diamond(root, 56.0, this.Ink());
      dia.SetVisible(false);
      ArrayPush(this.m_wyDia, dia);
      let tg = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 26, n"Semi-Bold", this.Acc());
      tg.SetVisible(false);
      ArrayPush(this.m_wyDiaTag, tg);
      let ln = CMPilotHud.Label(root, inkEAnchor.TopLeft, 0.0, 0.0, "", 24, n"Medium", this.Acc());
      ln.SetVisible(false);
      ArrayPush(this.m_wyDiaLine, ln);
      t += 1;
    }
    this.Brackets(root, cx - 1000.0, 1020.0, 260.0, 120.0);
    this.Brackets(root, cx + 740.0, 1020.0, 260.0, 120.0);
  }

  // the Wyvern, scanned from its own meshes in three-quarter view (a46, Omar: from the front
  // its wings stacked, two of six showed), from ahead, to its right and above, its wings
  // unfolded as it flies; bottom right
  protected func BuildSprite(root: ref<inkCanvas>) -> Void {
    let x1 = this.WyR();
    let k = 290.0 / 360.0;
    let bx = x1 - 335.0 - 273.0 * k * 0.5;
    let by = 1640.0;
    this.Brackets(root, bx - 30.0, by - 20.0, 273.0 * k + 60.0, 330.0);
    let box = new inkCanvas();
    box.SetMargin(inkMargin(bx, by, 0.0, 0.0));
    box.SetSize(Vector2(273.0 * k, 290.0));
    box.Reparent(root);
    this.WyPart(box, k, n"wyvern_arm_l", 146.0, 52.0, 123.0, 205.0);
    this.WyPart(box, k, n"wyvern_arm_r", 5.0, 101.0, 145.0, 189.0);
    this.WyPart(box, k, n"wyvern_body", 42.0, 5.0, 189.0, 337.0);
    this.WyPart(box, k, n"wyvern_gun", 170.0, 324.0, 28.0, 31.0);
  }

  private func WyPart(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let img = new inkImage();
    img.SetAtlasResource(CMDroneHud.Atlas());
    img.SetTexturePart(name);
    img.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    img.SetSize(Vector2(w * k, h * k));
    img.SetTintColor(this.Acc());
    img.SetInteractive(false);
    img.Reparent(box);
    ArrayPush(this.m_wySprite, img);
  }

  // ---- ten times a second ------------------------------------------------------------
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_wySpool = ClampF(s.spool, 0.0, 1.0);
    this.SetT(this.WY_NAME, s.title);
    this.SetT(this.WY_ROLE, "ISR // SCOUT    TASK: OVERWATCH V    LINK " + IntToString(RoundF(ClampF(s.signal, 0.0, 1.0) * 100.0)) + "%");
    let warn = s.warning;
    if s.signal < 0.35 {
      warn = "LINK WEAK";
    } else {
      if s.integrity < 0.3 {
        warn = "HULL CRITICAL";
      }
    }
    this.SetT(this.WY_WARN, warn);
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.SetT(this.WY_HULL, "AIRFRAME " + IntToString(RoundF(hull * 100.0)) + "%");
    this.SetT(this.WY_ROTORS, "6/6 ROTORS");
    let c = hull < 0.3 ? CMPilotHud.Red() : (hull < 0.6 ? CMPilotHud.Caution() : this.Acc());
    for img in this.m_wySprite {
      img.SetTintColor(c);
    }
    this.m_wyFocus = "SNS " + s.sensor + (s.range > 0.0 && s.range < 2000.0 ? "   AF LOCK" : "   AF HUNT");
    // the guns: their line and their heat
    let gs = ArraySize(s.wStat) > 0 ? s.wStat[0] : "RDY";
    this.SetT(this.WY_GUN, (ArraySize(s.wSub) > 0 ? s.wSub[0] : "LMG 7.62 x2") + "   " + gs);
    this.Tint(this.WY_GUN, Equals(gs, "OVERHEAT") ? CMPilotHud.Red() : (Equals(gs, "HOT") ? this.Amb() : this.Ink()));
    this.m_wyGunHeat = ClampF(s.secHeat, 0.0, 1.0);
    this.m_wyHeat.Set(this.m_wyGunHeat, this.m_wyGunHeat >= 0.99 ? CMPilotHud.Red() : this.Amb());
  }

  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_wySpeed = speed;
    this.SetT(this.WY_SPD, IntToString(RoundF(speed * 3.6)) + " KMH");
    this.SetT(this.WY_ALT, alt >= 0.0 ? FloatToStringPrec(alt, 1) + " M" : "--- M");
    this.SetT(this.WY_VS, "VS " + (vs >= 0.0 ? "+" : "") + FloatToStringPrec(vs, 1));
  }

  // ---- every frame: what the sensor sees -----------------------------------------------
  public func Track(t: ref<CMDroneTrack>) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    let cx = this.FW() * 0.5;
    let cy = 1080.0;
    // the optics: the zoom against a 70 degree view
    let zoom = ClampF(TanF(Deg2Rad(35.0)) / TanF(Deg2Rad(MaxF(1.0, t.fov) * 0.5)), 1.0, 9.0);
    this.SetT(this.WY_EO, "EO / IR   X" + FloatToStringPrec(zoom, 1));
    let fovLine = "FOV " + FloatToStringPrec(t.fov, 1);
    this.SetT(this.WY_GRID, "NC GRID " + FloatToStringPrec(t.pos.X, 1) + " / " + FloatToStringPrec(t.pos.Y, 1));
    let zi = ClampF((zoom - 1.0) / 8.0, 0.0, 1.0);
    this.m_wyZoomMark.SetMargin(inkMargin(this.WyR() - 246.0, 560.0 + (1.0 - zi) * 720.0, 0.0, 0.0));
    this.m_wyZoomMark.SetText("> X" + FloatToStringPrec(zoom, 1));
    // the scan ring
    let lit = t.scan < 0.0 ? 0 : RoundF(t.scan * Cast<Float>(this.WY_RING_N));
    let i = 0;
    while i < ArraySize(this.m_wyRing) {
      this.m_wyRing[i].SetVisible(i < lit);
      this.m_wyRing[i].SetTintColor(t.scan >= 1.0 ? this.Amb() : this.Acc());
      i += 1;
    }
    if t.scan < 0.0 || !IsDefined(t.lock) {
      this.SetT(this.WY_SCAN, "");
    } else {
      this.SetT(this.WY_SCAN, t.scan >= 1.0 ? "TAGGED " + t.lock.Tag() + "   " + t.lock.Label() : "SCAN " + IntToString(RoundF(t.scan * 100.0)) + "%");
    }
    this.SetT(this.WY_RNG, (t.aimOk ? "RNG " + IntToString(RoundF(Vector4.Distance(t.pos, t.aim))) + " M" : "RNG --- M") + "   ELEV " + CMDroneHud.Signed(t.camPitch));
    // the diamonds on the feed: the tagged contacts in view
    let n = 0;
    for c in t.contacts {
      if n < ArraySize(this.m_wyDia) && c.tag > 0 && c.kind != 0 && c.OnScreen() {
        let col = CMInk.KindColor(c.kind, this.Acc());
        let x = cx + c.scr.X;
        let y = cy + c.scr.Y;
        let d = this.m_wyDia[n];
        d.SetVisible(true);
        d.SetMargin(inkMargin(x - 28.0, y - 28.0, 0.0, 0.0));
        d.SetTintColor(col);
        let tg = this.m_wyDiaTag[n];
        tg.SetVisible(true);
        tg.SetMargin(inkMargin(x + 40.0, y - 50.0, 0.0, 0.0));
        tg.SetText(c.Tag());
        tg.SetTintColor(col);
        let ln = this.m_wyDiaLine[n];
        ln.SetVisible(true);
        ln.SetMargin(inkMargin(x + 40.0, y - 18.0, 0.0, 0.0));
        ln.SetText(c.Label() + "  " + IntToString(RoundF(c.dist)) + " M");
        ln.SetTintColor(col);
        n += 1;
      }
    }
    while n < ArraySize(this.m_wyDia) {
      this.m_wyDia[n].SetVisible(false);
      this.m_wyDiaTag[n].SetVisible(false);
      this.m_wyDiaLine[n].SetVisible(false);
      n += 1;
    }
    // the contacts log: V, then the tagged contacts nearest first
    let rows: array<ref<CMDroneContact>>;
    for c in t.contacts {
      if c.tag > 0 {
        let at = ArraySize(rows);
        let j = 0;
        while j < ArraySize(rows) {
          if c.kind == 0 || (rows[j].kind != 0 && c.dist < rows[j].dist) {
            at = j;
            j = ArraySize(rows);
          }
          j += 1;
        }
        ArrayInsert(rows, at, c);
      }
    }
    this.SetT(this.WY_LOG, "CONTACTS   " + IntToString(t.tagged) + " TAGGED   " + IntToString(ArraySize(t.contacts)) + " IN RANGE");
    let r = 0;
    while r < 4 {
      let b = this.WY_ROW0 + r * 3;
      if r < ArraySize(rows) {
        let c = rows[r];
        let col = CMInk.KindColor(c.kind, this.Acc());
        this.SetT(b, c.Tag());
        this.SetT(b + 1, c.Label());
        this.SetT(b + 2, IntToString(RoundF(c.dist)) + " M");
        this.Tint(b, col);
        this.Tint(b + 1, col);
        this.Tint(b + 2, col);
      } else {
        this.SetT(b, "");
        this.SetT(b + 1, "");
        this.SetT(b + 2, "");
      }
      r += 1;
    }
    this.SetT(this.WY_PING, t.pingLeft > 0.0 ? "[G] PING   " + IntToString(CeilF(t.pingLeft)) + " S" : "[G] PING AREA   //   HOLD THE RETICLE ON A CONTACT TO TAG IT");
    // the radar: heading up
    let rx = this.RadarX();
    let ry = this.RadarY();
    let rr = this.WY_RADAR_R;
    let view = -t.yaw;
    n = 0;
    for c in t.contacts {
      if n < ArraySize(this.m_wyDots) {
        let dx = c.pos.X - t.pos.X;
        let dy = c.pos.Y - t.pos.Y;
        let flat = SqrtF(dx * dx + dy * dy);
        let rel = Deg2Rad(Rad2Deg(AtanF(dx, dy)) - view);
        let rad = flat / this.WY_RADAR_M * rr;
        let px = rx + SinF(rel) * rad;
        let py = ry - CosF(rel) * rad;
        if c.kind == 0 {
          this.m_wyV.SetVisible(rad <= rr);
          this.m_wyV.SetMargin(inkMargin(px - 15.0, py - 15.0, 0.0, 0.0));
        } else {
          let dot = this.m_wyDots[n];
          dot.SetVisible(rad <= rr);
          dot.SetMargin(inkMargin(px - 8.0, py - 8.0, 0.0, 0.0));
          dot.SetTintColor(CMInk.KindColor(c.kind, this.Acc()));
          dot.SetOpacity(c.tag > 0 ? 1.0 : 0.4);
          n += 1;
        }
      }
    }
    while n < ArraySize(this.m_wyDots) {
      this.m_wyDots[n].SetVisible(false);
      n += 1;
    }
    // how loud it is, and who has noticed
    // (its guns are loud: their heat counts too)
    let sig = ClampF(0.1 + this.m_wySpool * 0.4 + this.m_wySpeed / 25.0 * 0.5 + this.m_wyGunHeat * 0.6, 0.0, 1.0);
    this.m_wySig.Set(sig, sig >= 0.7 ? CMPilotHud.Red() : this.Amb());
    this.SetT(this.WY_SIGV, sig < 0.35 ? "LOW" : (sig < 0.7 ? "MED" : "HIGH"));
    this.SetT(this.WY_DETV, t.detected > 0 ? IntToString(t.detected) + " HOSTILE" : "NONE");
    this.Tint(this.WY_DETV, t.detected > 0 ? CMPilotHud.Red() : CMInk.KindColor(0, this.Acc()));
    this.SetT(this.WY_FOV, fovLine + "   " + this.m_wyFocus);
  }

  public func StartBoot() -> Void {
    this.m_wyBoot = 0.8;
    this.m_wyClock = 0.0;
    if IsDefined(this.FRoot()) {
      this.FRoot().SetOpacity(0.0);
    }
  }

  public func Boot(dt: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_wyClock += dt;
    this.m_wyBlink += dt;
    if this.m_wyBoot > 0.0 {
      this.m_wyBoot = MaxF(0.0, this.m_wyBoot - dt);
      this.FRoot().SetOpacity(1.0 - this.m_wyBoot / 0.8);
    }
    this.SetT(this.WY_REC, "REC ISR   " + CMInk.Clock(this.m_wyClock));
    let ph = this.m_wyBlink - Cast<Float>(FloorF(this.m_wyBlink));
    this.m_wyRec.SetOpacity(ph < 0.5 ? 1.0 : 0.15);
    // the radar's sweep: once round every 3 s
    let a = Deg2Rad((this.m_wyBlink / 3.0 - Cast<Float>(FloorF(this.m_wyBlink / 3.0))) * 360.0);
    let rx = this.RadarX();
    let ry = this.RadarY();
    let rr = this.WY_RADAR_R;
    CMInk.Seg(this.m_wySweep, rx, ry, rx + SinF(a) * rr, ry - CosF(a) * rr, 4.0);
  }

  public func Hit(kill: Bool) -> Void {}
}
