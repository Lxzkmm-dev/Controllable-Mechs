// =============================================================================
// MECHS OF NIGHT CITY - THE GRIFFIN'S DISPLAY: A STRIKE HUD (0.7.1)
//
// Each drone's display befits its role (Omar). The Griffin flies strike: its display is a
// Militech attack aircraft's head-up display in one phosphor green, clean and digital (no
// analog feed), inside a 16:9 area in the middle of the screen:
//   top centre    the heading box and the compass points either side
//   upper centre  a bank scale: fixed ticks on an arc and a pointer that swings with the
//                 roll (no horizon line across the view), the pitch beside it
//   centre        the gun cross and the laser range under it
//   left / right  speed, and height with the vertical speed, in boxes
//   top left      the airframe, its role, the link; top right the rotors' spool, the timer
//   bottom left   the weapons' lines; centre the warnings
//   bottom right  the airframe: the Griffin scanned from its own meshes (body, both wing
//                 pods), tinted by the hull
// Built on the Bombus's display (CMBombusHud: its frame, text and bracket helpers); no
// field shares a name with it or its parents (a49).
// =============================================================================
module ControllableMechs

public class CMGriffinHud extends CMBombusHud {
  private let m_gBank: ref<inkCanvas>;
  private let m_gSprite: array<ref<inkImage>>;
  private let m_gClock: Float;
  private let m_gBoot: Float;

  // the HUD lines (indices of the text list)
  private let G_NAME: Int32 = 0;
  private let G_LINK: Int32 = 1;
  private let G_THR: Int32 = 2;
  private let G_TIME: Int32 = 3;
  private let G_HDG: Int32 = 4;
  private let G_CL: Int32 = 5;
  private let G_CR: Int32 = 6;
  private let G_PIT: Int32 = 7;
  private let G_RNG: Int32 = 8;
  private let G_SPD: Int32 = 9;
  private let G_ALT: Int32 = 10;
  private let G_VS: Int32 = 11;
  private let G_PRI: Int32 = 12;
  private let G_SEC: Int32 = 13;
  private let G_WARN: Int32 = 14;
  private let G_HULL: Int32 = 15;
  private let G_ARM: Int32 = 16;

  protected func Acc() -> HDRColor = new HDRColor(0.34, 1.02, 0.46, 1.0)

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
    let x0 = this.FX0();
    let x1 = x0 + MinF(3840.0, this.FW());
    let cx = this.FW() * 0.5;
    let cy = 1080.0;
    // in the G_ order
    this.Osd(root, x0 + 200.0, 150.0, 36, 0);          // name
    this.Osd(root, x0 + 200.0, 200.0, 32, 0);          // link
    this.Osd(root, x1 - 200.0, 150.0, 36, 2);          // spool
    this.Osd(root, x1 - 200.0, 200.0, 32, 2);          // timer
    this.Osd(root, cx, 150.0, 46, 1);                  // heading
    this.Osd(root, cx - 300.0, 156.0, 34, 1);          // compass left
    this.Osd(root, cx + 300.0, 156.0, 34, 1);          // compass right
    this.Osd(root, cx + 420.0, 470.0, 32, 0);          // pitch
    this.Osd(root, cx, 1190.0, 34, 1);                 // range
    this.Osd(root, cx - 760.0, 1050.0, 50, 2);         // speed
    this.Osd(root, cx + 760.0, 1050.0, 50, 0);         // height
    this.Osd(root, cx + 760.0, 1112.0, 30, 0);         // vertical speed
    this.Osd(root, x0 + 200.0, 1840.0, 36, 0);         // weapons, first
    this.Osd(root, x0 + 200.0, 1892.0, 36, 0);         // weapons, second
    this.Osd(root, cx, 820.0, 52, 1);                  // warnings
    this.Osd(root, x1 - 330.0, 2000.0, 30, 1);         // hull
    this.Osd(root, x0 + 200.0, 1786.0, 30, 0);         // master arm
    this.Brackets(root, x0 + 180.0, 136.0, 560.0, 112.0);
    this.Brackets(root, x1 - 520.0, 136.0, 340.0, 112.0);
    // the heading box and the compass ticks
    this.Brackets(root, cx - 110.0, 138.0, 220.0, 76.0);
    let k = -5;
    while k <= 5 {
      if k != 0 {
        CMPilotHud.Bar(root, cx + Cast<Float>(k) * 60.0 - 2.0, 222.0, 4.0, k % 2 == 0 ? 24.0 : 12.0, this.Acc(), 0.8);
      }
      k += 1;
    }
    // the bank scale: ticks on an arc over the gun cross, and the pointer that swings round
    // it with the roll
    let ac = 760.0;     // the arc's centre, below it
    let rad = 300.0;
    for deg in [-60.0, -45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0] {
      let a = Deg2Rad(deg);
      let len = AbsF(deg) % 30.0 < 1.0 ? 30.0 : 16.0;
      let tick = CMPilotHud.Bar(root, cx + SinF(a) * rad - 2.0, ac - CosF(a) * rad - len, 4.0, len, this.Acc(), 0.85);
      tick.SetRenderTransformPivot(Vector2(0.5, 1.0));
      tick.SetRotation(deg);
    }
    let bank = new inkCanvas();
    bank.SetMargin(inkMargin(cx - rad, ac - rad, 0.0, 0.0));
    bank.SetSize(Vector2(rad * 2.0, rad * 2.0));
    bank.SetRenderTransformPivot(Vector2(0.5, 0.5));
    bank.Reparent(root);
    let pl = CMPilotHud.Bar(bank, rad - 16.0, 14.0, 18.0, 5.0, this.Ink(), 1.0);
    pl.SetRotation(35.0);
    let pr = CMPilotHud.Bar(bank, rad - 2.0, 14.0, 18.0, 5.0, this.Ink(), 1.0);
    pr.SetRotation(-35.0);
    this.m_gBank = bank;
    // the gun cross: four gapped arms and a centre pip
    CMPilotHud.Bar(root, cx - 90.0, cy - 2.0, 60.0, 4.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx + 30.0, cy - 2.0, 60.0, 4.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx - 2.0, cy - 90.0, 4.0, 60.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx - 2.0, cy + 30.0, 4.0, 60.0, this.Acc(), 1.0);
    CMPilotHud.Bar(root, cx - 4.0, cy - 4.0, 8.0, 8.0, this.Ink(), 1.0);
    // speed and height boxes
    this.Brackets(root, cx - 1000.0, 1030.0, 260.0, 100.0);
    this.Brackets(root, cx + 740.0, 1030.0, 260.0, 100.0);
    this.Brackets(root, x0 + 180.0, 1770.0, 700.0, 190.0);
    this.SetT(this.G_ARM, "MASTER ARM // STRIKE");
    this.Tint(this.G_WARN, CMPilotHud.Red());
    this.Tint(this.G_ARM, this.Acc());
  }

  // the Griffin, scanned from its own meshes, bottom right
  protected func BuildSprite(root: ref<inkCanvas>) -> Void {
    let x1 = this.FX0() + MinF(3840.0, this.FW());
    let k = 260.0 / 360.0;
    let bx = x1 - 200.0 - 311.0 * k;
    let by = 1700.0;
    this.Brackets(root, bx - 20.0, by - 20.0, 311.0 * k + 40.0, 300.0);
    let box = new inkCanvas();
    box.SetMargin(inkMargin(bx, by, 0.0, 0.0));
    box.SetSize(Vector2(311.0 * k, 260.0));
    box.Reparent(root);
    this.GPart(box, k, n"griffin_body", 31.0, 46.0, 250.0, 309.0);
    this.GPart(box, k, n"griffin_wing_l", 6.0, 5.0, 79.0, 246.0);
    this.GPart(box, k, n"griffin_wing_r", 227.0, 5.0, 80.0, 246.0);
  }

  private func GPart(box: ref<inkCanvas>, k: Float, name: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let img = new inkImage();
    img.SetAtlasResource(CMDroneHud.Atlas());
    img.SetTexturePart(name);
    img.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    img.SetSize(Vector2(w * k, h * k));
    img.SetTintColor(this.Acc());
    img.SetInteractive(false);
    img.Reparent(box);
    ArrayPush(this.m_gSprite, img);
  }

  private static func GPoint(h: Int32) -> String {
    let p = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    let i = ((h + 22) / 45) % 8;
    return p[i];
  }

  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.SetT(this.G_NAME, s.title + "  //  " + s.role);
    this.SetT(this.G_LINK, "LINK " + IntToString(RoundF(ClampF(s.signal, 0.0, 1.0) * 100.0)) + "%   " + FloatToStringPrec(s.distance / 1000.0, 2) + " KM");
    this.SetT(this.G_THR, "SPOOL " + IntToString(RoundF(ClampF(s.spool, 0.0, 1.0) * 100.0)) + "%");
    let h = (s.heading % 360 + 360) % 360;
    this.SetT(this.G_HDG, (h < 100 ? (h < 10 ? "00" : "0") : "") + IntToString(h));
    this.SetT(this.G_CL, CMGriffinHud.GPoint((h + 270) % 360));
    this.SetT(this.G_CR, CMGriffinHud.GPoint((h + 90) % 360));
    this.SetT(this.G_RNG, s.range > 0.0 && s.range < 2000.0 ? "RNG " + IntToString(RoundF(s.range)) + " M" : "RNG ---- M");
    this.SetT(this.G_PRI, s.priText);
    this.SetT(this.G_SEC, s.secText);
    let warn = s.warning;
    if s.signal < 0.35 {
      warn = "LINK WEAK";
    } else {
      if s.integrity < 0.3 {
        warn = "HULL CRITICAL";
      }
    }
    this.SetT(this.G_WARN, warn);
    let hull = ClampF(s.integrity, 0.0, 1.0);
    this.SetT(this.G_HULL, "AIRFRAME " + IntToString(RoundF(hull * 100.0)) + "%");
    let c = hull < 0.3 ? CMPilotHud.Red() : (hull < 0.6 ? CMPilotHud.Caution() : this.Acc());
    for img in this.m_gSprite {
      img.SetTintColor(c);
    }
  }

  public func SetFlight(pitch: Float, roll: Float, speed: Float, alt: Float, vs: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_gBank.SetRotation(-roll);
    this.SetT(this.G_PIT, "PITCH " + (pitch >= 0.0 ? "+" : "") + IntToString(RoundF(pitch)));
    this.SetT(this.G_SPD, IntToString(RoundF(speed * 3.6)) + " KMH");
    this.SetT(this.G_ALT, alt >= 0.0 ? FloatToStringPrec(alt, 1) + " M" : "--- M");
    this.SetT(this.G_VS, "VS " + (vs >= 0.0 ? "+" : "") + FloatToStringPrec(vs, 1));
  }

  public func StartBoot() -> Void {
    this.m_gBoot = 0.8;
    this.m_gClock = 0.0;
    if IsDefined(this.FRoot()) {
      this.FRoot().SetOpacity(0.0);
    }
  }

  public func Boot(dt: Float) -> Void {
    if !IsDefined(this.FRoot()) {
      return;
    }
    this.m_gClock += dt;
    if this.m_gBoot > 0.0 {
      this.m_gBoot = MaxF(0.0, this.m_gBoot - dt);
      this.FRoot().SetOpacity(1.0 - this.m_gBoot / 0.8);
    }
    let secs = FloorF(this.m_gClock);
    let mm = secs / 60;
    let ss = secs % 60;
    this.SetT(this.G_TIME, "T+ " + (mm < 10 ? "0" : "") + IntToString(mm) + ":" + (ss < 10 ? "0" : "") + IntToString(ss));
  }

  public func Hit(kill: Bool) -> Void {}
}
