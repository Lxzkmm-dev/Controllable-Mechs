// =============================================================================
// MECHS OF NIGHT CITY - THE WYVERN'S DISPLAY: AN ESCORT'S (0.7.1)
//
// Each drone's display befits its role (Omar). The Wyvern flies escort: its display is a
// bodyguard's, built round the one it guards. Clean digital, in amber, inside a 16:9 area
// in the middle of the screen:
//   centre        a ring reticle and the laser range under it
//   under it      the escort block: an arrow to V, the distance, and whether the Wyvern
//                 is ON STATION (within 40 m of V) or has to CLOSE UP
//   top left      the airframe, its role, the link; top right the spool and the timer
//   top centre    the heading
//   left / right  speed, and height with the vertical speed
//   bottom left   the weapons' lines and the escort orders; centre the warnings
//   bottom right  the airframe: the Wyvern scanned from its own meshes (body, both rotor
//                 arms folded as they rest), tinted by the hull
// Built on the Bombus's display (CMBombusHud); no field shares a name with it or its
// parents (a49).
// =============================================================================
module ControllableMechs

public class CMWyvernHud extends CMBombusHud {
  private let m_wArrow: ref<inkCanvas>;
  private let m_wSprite: array<ref<inkImage>>;
  private let m_wClock: Float;
  private let m_wBoot: Float;

  private let W_NAME: Int32 = 0;
  private let W_LINK: Int32 = 1;
  private let W_THR: Int32 = 2;
  private let W_TIME: Int32 = 3;
  private let W_HDG: Int32 = 4;
  private let W_RNG: Int32 = 5;
  private let W_V: Int32 = 6;
  private let W_STATION: Int32 = 7;
  private let W_SPD: Int32 = 8;
  private let W_ALT: Int32 = 9;
  private let W_VS: Int32 = 10;
  private let W_PRI: Int32 = 11;
  private let W_SEC: Int32 = 12;
  private let W_WARN: Int32 = 13;
  private let W_HULL: Int32 = 14;
  private let W_ORD: Int32 = 15;

  private let ON_STATION: Float = 40.0;   // m from V the escort counts as close

  protected func Acc() -> HDRColor = new HDRColor(1.10, 0.74, 0.26, 1.0)

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
    let x0 = this.FX0();
    let x1 = x0 + MinF(3840.0, this.FW());
    let cx = this.FW() * 0.5;
    let cy = 1080.0;
    this.Osd(root, x0 + 200.0, 150.0, 36, 0);          // name
    this.Osd(root, x0 + 200.0, 200.0, 32, 0);          // link
    this.Osd(root, x1 - 200.0, 150.0, 36, 2);          // spool
    this.Osd(root, x1 - 200.0, 200.0, 32, 2);          // timer
    this.Osd(root, cx, 150.0, 46, 1);                  // heading
    this.Osd(root, cx, 1180.0, 32, 1);                 // range
    this.Osd(root, cx + 80.0, 1290.0, 40, 0);          // V and the distance
    this.Osd(root, cx, 1356.0, 34, 1);                 // on station
    this.Osd(root, cx - 760.0, 1050.0, 50, 2);         // speed
    this.Osd(root, cx + 760.0, 1050.0, 50, 0);         // height
    this.Osd(root, cx + 760.0, 1112.0, 30, 0);         // vertical speed
    this.Osd(root, x0 + 200.0, 1840.0, 36, 0);         // weapons, first
    this.Osd(root, x0 + 200.0, 1892.0, 36, 0);         // weapons, second
    this.Osd(root, cx, 820.0, 52, 1);                  // warnings
    this.Osd(root, x1 - 300.0, 2000.0, 30, 1);         // hull
    this.Osd(root, x0 + 200.0, 1786.0, 30, 0);         // orders
    this.Brackets(root, x0 + 180.0, 136.0, 560.0, 112.0);
    this.Brackets(root, x1 - 520.0, 136.0, 340.0, 112.0);
    this.Brackets(root, cx - 110.0, 138.0, 220.0, 76.0);
    // the ring reticle: eight short ticks round a circle, a centre dot
    let a = 0;
    while a < 8 {
      let ang = Cast<Float>(a) * 45.0;
      let r = Deg2Rad(ang);
      let tick = CMPilotHud.Bar(root, cx + SinF(r) * 80.0 - 2.0, cy - CosF(r) * 80.0 - 12.0, 4.0, 24.0, this.Acc(), 1.0);
      tick.SetRotation(ang);
      a += 1;
    }
    CMPilotHud.Bar(root, cx - 4.0, cy - 4.0, 8.0, 8.0, this.Ink(), 1.0);
    // the escort block: the arrow to V
    this.Brackets(root, cx - 260.0, 1260.0, 520.0, 150.0);
    let arrow = new inkCanvas();
    arrow.SetMargin(inkMargin(cx - 120.0, 1286.0, 0.0, 0.0));
    arrow.SetSize(Vector2(80.0, 80.0));
    arrow.SetRenderTransformPivot(Vector2(0.5, 0.5));
    arrow.Reparent(root);
    let l = CMPilotHud.Bar(arrow, 18.0, 30.0, 34.0, 6.0, this.Acc(), 1.0);
    l.SetRotation(-45.0);
    let r2 = CMPilotHud.Bar(arrow, 30.0, 30.0, 34.0, 6.0, this.Acc(), 1.0);
    r2.SetRotation(45.0);
    CMPilotHud.Bar(arrow, 37.0, 30.0, 6.0, 34.0, this.Acc(), 1.0);
    this.m_wArrow = arrow;
    this.Brackets(root, cx - 1000.0, 1030.0, 260.0, 100.0);
    this.Brackets(root, cx + 740.0, 1030.0, 260.0, 100.0);
    this.Brackets(root, x0 + 180.0, 1770.0, 700.0, 190.0);
    this.SetT(this.W_ORD, "ESCORT // GUARD THE OPERATOR");
    this.Tint(this.W_WARN, CMPilotHud.Red());
    this.Tint(this.W_ORD, this.Acc());
  }

  // the Wyvern, scanned from its own meshes, bottom right
  protected func BuildSprite(root: ref<inkCanvas>) -> Void {
    let x1 = this.FX0() + MinF(3840.0, this.FW());
    let k = 260.0 / 360.0;
    let bx = x1 - 240.0 - 123.0 * k;
    let by = 1700.0;
    this.Brackets(root, bx - 60.0, by - 20.0, 123.0 * k + 120.0, 300.0);
    let box = new inkCanvas();
    box.SetMargin(inkMargin(bx, by, 0.0, 0.0));
    box.SetSize(Vector2(123.0 * k, 260.0));
    box.Reparent(root);
    this.WPart(box, k, n"wyvern_body", 14.0, 5.0, 96.0, 350.0);
    this.WPart(box, k, n"wyvern_arm_l", 5.0, 68.0, 24.0, 229.0);
    this.WPart(box, k, n"wyvern_arm_r", 95.0, 68.0, 24.0, 229.0);
  }

  private func WPart(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let img = new inkImage();
    img.SetAtlasResource(CMDroneHud.Atlas());
    img.SetTexturePart(name);
    img.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    img.SetSize(Vector2(w * k, h * k));
    img.SetTintColor(this.Acc());
    img.SetInteractive(false);
    img.Reparent(box);
    ArrayPush(this.m_wSprite, img);
  }

  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.SetT(this.W_NAME, s.title + "  //  " + s.role);
    this.SetT(this.W_LINK, "LINK " + IntToString(RoundF(ClampF(s.signal, 0.0, 1.0) * 100.0)) + "%");
    this.SetT(this.W_THR, "SPOOL " + IntToString(RoundF(ClampF(s.spool, 0.0, 1.0) * 100.0)) + "%");
    let h = (s.heading % 360 + 360) % 360;
    this.SetT(this.W_HDG, (h < 100 ? (h < 10 ? "00" : "0") : "") + IntToString(h));
    this.SetT(this.W_RNG, s.range > 0.0 && s.range < 2000.0 ? "RNG " + IntToString(RoundF(s.range)) + " M" : "RNG ---- M");
    // the escort: V's way and distance, and whether it is on station
    if s.home < 900.0 {
      this.m_wArrow.SetVisible(true);
      this.m_wArrow.SetRotation(s.home + 180.0);
    } else {
      this.m_wArrow.SetVisible(false);
    }
    this.SetT(this.W_V, "V  " + IntToString(RoundF(s.distance)) + " M");
    let near = s.distance <= this.ON_STATION;
    this.SetT(this.W_STATION, near ? "ON STATION" : "CLOSE UP ON V");
    this.Tint(this.W_STATION, near ? this.Acc() : CMPilotHud.Red());
    this.SetT(this.W_PRI, s.priText);
    this.SetT(this.W_SEC, s.secText);
    let warn = s.warning;
    if s.signal < 0.35 {
      warn = "LINK WEAK";
    } else {
      if s.integrity < 0.3 {
        warn = "HULL CRITICAL";
      }
    }
    this.SetT(this.W_WARN, warn);
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.SetT(this.W_HULL, "AIRFRAME " + IntToString(RoundF(hull * 100.0)) + "%");
    let c = hull < 0.3 ? CMPilotHud.Red() : (hull < 0.6 ? CMPilotHud.Caution() : this.Acc());
    for img in this.m_wSprite {
      img.SetTintColor(c);
    }
  }

  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.SetT(this.W_SPD, IntToString(RoundF(speed * 3.6)) + " KMH");
    this.SetT(this.W_ALT, alt >= 0.0 ? FloatToStringPrec(alt, 1) + " M" : "--- M");
    this.SetT(this.W_VS, "VS " + (vs >= 0.0 ? "+" : "") + FloatToStringPrec(vs, 1));
  }

  public func StartBoot() -> Void {
    this.m_wBoot = 0.8;
    this.m_wClock = 0.0;
    if IsDefined(this.FRoot()) {
      this.FRoot().SetOpacity(0.0);
    }
  }

  public func Boot(dt: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_wClock += dt;
    if this.m_wBoot > 0.0 {
      this.m_wBoot = MaxF(0.0, this.m_wBoot - dt);
      this.FRoot().SetOpacity(1.0 - this.m_wBoot / 0.8);
    }
    let secs = FloorF(this.m_wClock);
    let mm = secs / 60;
    let ss = secs % 60;
    this.SetT(this.W_TIME, "T+ " + (mm < 10 ? "0" : "") + IntToString(mm) + ":" + (ss < 10 ? "0" : "") + IntToString(ss));
  }

  public func Hit(kill: Bool) -> Void {}
}
