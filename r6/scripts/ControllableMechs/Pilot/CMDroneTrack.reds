// =============================================================================
// MECHS OF NIGHT CITY - WHAT A DRONE'S SENSOR SEES (0.7.1)
//
// The drones' displays (round 2, Omar's mockups) show the world round the drone: the
// people in it, what the reticle is on, where the shots come from. CMDroneSense (Control)
// fills a CMDroneTrack every frame; the display draws it (CMDroneHud.Track).
//   a contact    an NPC near the drone (the targeting system's search round it, twice a
//                second) or V: its kind, whether it's armed, in combat, a machine; where it
//                is, how far, where on the screen; its tag (the Wyvern's C-numbers)
//   the lock     what the reticle is on (held a moment after it leaves), and the lead pip:
//                where to aim for a round to meet it
// CMInk: the few shapes the displays draw from thin bars (a ring, a segment, a diamond).
// =============================================================================
module ControllableMechs

public class CMDroneContact {
  public let ent: wref<GameObject>;
  public let id: EntityID;
  public let kind: Int32;       // 0 V, 1 civilian, 2 hostile, 3 neutral, 4 friendly
  public let machine: Bool;     // a drone, a mech, an android
  public let armed: Bool;
  public let combat: Bool;      // in combat (hostile and in combat: it has the drone's scent)
  public let pos: Vector4;      // its centre of mass
  public let vel: Vector4;
  public let dist: Float;       // from the drone
  public let scr: Vector2;      // on the display, 4K units from the centre (9999 off it)
  public let tag: Int32;        // its C-number (0 untagged; V is C-01)
  public let hp: Float;         // 0-1
  public let seen: Float;       // when the last search found it

  public static func KindName(k: Int32) -> String {
    switch k {
      case 0: return "OPERATOR";
      case 1: return "CIVILIAN";
      case 2: return "HOSTILE";
      case 4: return "FRIENDLY";
    }
    return "NEUTRAL";
  }

  // its line in a contacts list: "HOSTILE // ARMED", "V // OPERATOR", "NEUTRAL // MACHINE"
  public func Label() -> String {
    if this.kind == 0 {
      return "V // OPERATOR";
    }
    let s = CMDroneContact.KindName(this.kind);
    if this.machine {
      return s + " // MACHINE";
    }
    if this.armed && this.kind != 1 {
      return s + " // ARMED";
    }
    return s;
  }

  public func Tag() -> String = this.tag <= 0 ? "C-??" : "C-" + (this.tag < 10 ? "0" : "") + IntToString(this.tag)

  public func OnScreen() -> Bool = AbsF(this.scr.X) < 1880.0 && AbsF(this.scr.Y) < 1040.0
}

public class CMDroneTrack {
  public let contacts: array<ref<CMDroneContact>>;
  public let lock: ref<CMDroneContact>;   // what the reticle is on (null: nothing)
  public let lead: Vector2;               // the lead pip for a 320 m/s round
  public let leadOn: Bool;
  public let scan: Float;                 // the Wyvern's scan of the contact under the reticle, 0-1 (-1 none)
  public let tagged: Int32;               // contacts tagged (V too)
  public let hostiles: Int32;             // hostiles within 80 m
  public let detected: Int32;             // hostiles within 80 m in combat
  public let pos: Vector4;                // the drone
  public let aim: Vector4;                // the reticle's point
  public let aimOk: Bool;
  public let yaw: Float;                  // the view's heading, pitch and field of view
  public let camPitch: Float;
  public let fov: Float;
  public let hold: Bool;                  // the gunship hold
  public let holdAt: Vector4;
  public let pingLeft: Float;             // s to the next ping (0 ready)
  public let rounds: Int32;               // rounds fired and struck this link (BDA)
  public let hits: Int32;
  public let now: Float;
  // the Bombus: its payload's blast round the reticle's point (on the ground, projected),
  // whether it is armed, the time to impact on its course, each motor's output
  public let blastR: Float;               // m (0: no payload)
  public let armed: Bool;
  public let ring: array<Vector2>;        // the blast ring's points on the display
  public let ringOk: Bool;
  public let tti: Float;                  // s to reach the reticle's point (-1: not closing)
  public let motors: array<Float>;        // 0-1, front left, front right, back left, back right
  // the Octant (a50, Omar's mockup): the mortar's splash ring on the ground (ring / ringOk /
  // blastR, its time of flight), and the sensor's footprint on the ground (the view's four
  // corners where they meet it, world)
  public let tof: Float;
  public let foot: array<Vector4>;
  public let footOk: Bool;
}

public abstract class CMInk {
  // dark glass under a panel: ink draws a thin black fill lighter than it is (a49 in game:
  // the panels read as grey fog, Omar), so the panels use a dense green-black
  public static func Glass() -> HDRColor = new HDRColor(0.004, 0.018, 0.012, 1.0)
  public static func GlassOp() -> Float = 0.82

  // a filled polygon from thin horizontal strips (ink has no polygon fill): `n` strips,
  // each spanning the polygon's width at its height (convex polygons)
  public static func FillBars(root: ref<inkCanvas>, n: Int32, c: HDRColor, op: Float) -> array<ref<inkRectangle>> {
    let out: array<ref<inkRectangle>>;
    let i = 0;
    while i < n {
      let b = CMPilotHud.Bar(root, 0.0, 0.0, 1.0, 1.0, c, op);
      b.SetVisible(false);
      ArrayPush(out, b);
      i += 1;
    }
    return out;
  }

  public static func FillPoly(bars: array<ref<inkRectangle>>, pts: array<Vector2>) -> Void {
    let n = ArraySize(bars);
    let m = ArraySize(pts);
    if n == 0 || m < 3 {
      for b in bars {
        b.SetVisible(false);
      }
      return;
    }
    let y0 = pts[0].Y;
    let y1 = pts[0].Y;
    for p in pts {
      y0 = MinF(y0, p.Y);
      y1 = MaxF(y1, p.Y);
    }
    let h = (y1 - y0) / Cast<Float>(n);
    let i = 0;
    while i < n {
      let y = y0 + (Cast<Float>(i) + 0.5) * h;
      let lo = 99999.0;
      let hi = -99999.0;
      let j = 0;
      while j < m {
        let a = pts[j];
        let b = pts[(j + 1) % m];
        if (a.Y <= y && b.Y > y) || (b.Y <= y && a.Y > y) {
          let x = a.X + (y - a.Y) / (b.Y - a.Y) * (b.X - a.X);
          lo = MinF(lo, x);
          hi = MaxF(hi, x);
        }
        j += 1;
      }
      let bar = bars[i];
      if hi > lo {
        bar.SetVisible(true);
        bar.SetMargin(inkMargin(lo, y0 + Cast<Float>(i) * h, 0.0, 0.0));
        bar.SetSize(Vector2(hi - lo, h + 0.6));
      } else {
        bar.SetVisible(false);
      }
      i += 1;
    }
  }

  // a circle's points (for a filled disc)
  public static func CirclePts(cx: Float, cy: Float, r: Float, n: Int32) -> array<Vector2> {
    let out: array<Vector2>;
    let i = 0;
    while i < n {
      let a = Deg2Rad(Cast<Float>(i) / Cast<Float>(n) * 360.0);
      ArrayPush(out, Vector2(cx + SinF(a) * r, cy - CosF(a) * r));
      i += 1;
    }
    return out;
  }

  // a ring of short bars, each tangent to the circle; the first at the top, clockwise
  // a ring of short strokes (round-capped kit pills, a52: smooth), each tangent to the
  // circle; the first at the top, clockwise. For arcs that fill or hide by segment; a whole
  // static circle is Circle's (one image)
  public static func Ring(root: ref<inkCanvas>, cx: Float, cy: Float, r: Float, segs: Int32, thick: Float, c: HDRColor, op: Float) -> array<ref<inkWidget>> {
    let out: array<ref<inkWidget>>;
    let len = 6.2832 * r / Cast<Float>(segs);
    let i = 0;
    while i < segs {
      let a0 = Deg2Rad(Cast<Float>(i) / Cast<Float>(segs) * 360.0);
      let a1 = Deg2Rad(Cast<Float>(i + 1) / Cast<Float>(segs) * 360.0);
      let b = CMKit.Stroke(root, c, op);
      CMInk.Seg(b, cx + SinF(a0) * r, cy - CosF(a0) * r, cx + SinF(a1) * r, cy - CosF(a1) * r, thick);
      ArrayPush(out, b);
      i += 1;
    }
    return out;
  }

  // a whole circle: one smooth ring image
  public static func Circle(root: ref<inkCanvas>, cx: Float, cy: Float, r: Float, c: HDRColor, op: Float) -> ref<inkImage> {
    let part = r <= 40.0 ? n"ring_s" : (r <= 170.0 ? n"ring_m" : n"ring_l");
    return CMKit.Img(root, part, cx - r, cy - r, r * 2.0, r * 2.0, c, op);
  }

  // a stroke laid from one point to another (a kit pill: round caps, smooth when turned; a
  // plain bar works too)
  public static func Seg(b: ref<inkWidget>, x1: Float, y1: Float, x2: Float, y2: Float, thick: Float) -> Void {
    let dx = x2 - x1;
    let dy = y2 - y1;
    let len = SqrtF(dx * dx + dy * dy) + thick;
    b.SetRenderTransformPivot(Vector2(0.5, 0.5));
    b.SetMargin(inkMargin((x1 + x2) * 0.5 - len * 0.5, (y1 + y2) * 0.5 - thick * 0.5, 0.0, 0.0));
    b.SetSize(Vector2(len, thick));
    b.SetRotation(Rad2Deg(AtanF(dy, dx)));
  }

  public static func Line(root: ref<inkCanvas>, x1: Float, y1: Float, x2: Float, y2: Float, thick: Float, c: HDRColor, op: Float) -> ref<inkWidget> {
    let b = CMKit.Stroke(root, c, op);
    CMInk.Seg(b, x1, y1, x2, y2, thick);
    return b;
  }

  // a diamond outline `s` across, its centre at the canvas's middle (place it by margin)
  public static func Diamond(root: ref<inkCanvas>, s: Float, c: HDRColor) -> ref<inkCanvas> {
    let d = new inkCanvas();
    d.SetSize(Vector2(s, s));
    d.SetRenderTransformPivot(Vector2(0.5, 0.5));
    d.Reparent(root);
    CMKit.Img(d, n"diamond_line", 0.0, 0.0, s, s, c, 1.0);
    return d;
  }

  // a chevron pointing up, `s` across, on a canvas whose middle it turns about
  public static func Chevron(root: ref<inkCanvas>, s: Float, thick: Float, c: HDRColor) -> ref<inkCanvas> {
    let v = new inkCanvas();
    v.SetSize(Vector2(s, s));
    v.SetRenderTransformPivot(Vector2(0.5, 0.5));
    v.Reparent(root);
    CMKit.Img(v, n"chevron", 0.0, s * 0.2, s, s * 0.625, c, 1.0);
    return v;
  }
  // the contacts' colours, one set per display
  public static func KindColor(k: Int32, acc: HDRColor) -> HDRColor {
    switch k {
      case 0: return new HDRColor(0.60, 1.10, 0.66, 1.0);
      case 2: return CMPilotHud.Caution();
      case 4: return new HDRColor(0.45, 0.85, 1.15, 1.0);
      case 3: return new HDRColor(0.85, 0.88, 0.86, 1.0);
    }
    return acc;
  }

  public static func Clock(t: Float) -> String {
    let secs = FloorF(t);
    let mm = secs / 60;
    let ss = secs % 60;
    return (mm < 10 ? "0" : "") + IntToString(mm) + ":" + (ss < 10 ? "0" : "") + IntToString(ss);
  }

  public static func Hdg(h: Float) -> Int32 {
    let d = RoundF(h) % 360;
    return d < 0 ? d + 360 : d;
  }
}

// =============================================================================
// The shape kit (a52, Omar: the HUDs looked built from squares): smooth anti-aliased shapes
// from mnc\hud\ui_kit.inkatlas (tools/hud/uikit.py), drawn tinted. Pills and rounded panels
// nine-slice: any length keeps its round caps and corners.
// =============================================================================
public abstract class CMKit {
  public static func Atlas() -> ResRef = r"mnc\\hud\\ui_kit.inkatlas"

  public static func Img(root: ref<inkCanvas>, part: CName, x: Float, y: Float, w: Float, h: Float, c: HDRColor, op: Float) -> ref<inkImage> {
    let img = new inkImage();
    img.SetAtlasResource(CMKit.Atlas());
    img.SetTexturePart(part);
    img.SetMargin(inkMargin(x, y, 0.0, 0.0));
    img.SetSize(Vector2(w, h));
    img.SetTintColor(c);
    img.SetOpacity(op);
    img.SetInteractive(false);
    img.Reparent(root);
    return img;
  }

  public static func Nine(root: ref<inkCanvas>, part: CName, grid: inkMargin, x: Float, y: Float, w: Float, h: Float, c: HDRColor, op: Float) -> ref<inkImage> {
    let img = CMKit.Img(root, part, x, y, w, h, c, op);
    img.SetNineSliceScale(true);
    img.SetNineSliceGrid(grid);
    return img;
  }

  // a horizontal pill (round caps), and a vertical one
  public static func Pill(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, c: HDRColor, op: Float) -> ref<inkImage> = CMKit.Nine(root, n"pill_h", inkMargin(8.0, 0.0, 8.0, 0.0), x, y, w, h, c, op)
  public static func VPill(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, c: HDRColor, op: Float) -> ref<inkImage> = CMKit.Nine(root, n"pill_v", inkMargin(0.0, 8.0, 0.0, 8.0), x, y, w, h, c, op)
  // a stroke for CMInk.Seg: a thin pill
  public static func Stroke(root: ref<inkCanvas>, c: HDRColor, op: Float) -> ref<inkImage> = CMKit.Pill(root, 0.0, 0.0, 4.0, 3.0, c, op)

  // a rounded panel: dark glass and a thin line round it; `small` for boxes and rows
  public static func Panel(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, line: HDRColor, lineOp: Float) -> Void {
    CMKit.Nine(root, n"rrect_fill", inkMargin(14.0, 14.0, 14.0, 14.0), x, y, w, h, CMInk.Glass(), CMInk.GlassOp());
    CMKit.Nine(root, n"rrect_line", inkMargin(14.0, 14.0, 14.0, 14.0), x, y, w, h, line, lineOp);
  }
  public static func Box(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, line: HDRColor, lineOp: Float) -> ref<inkImage> {
    CMKit.Nine(root, n"rrect_fill_s", inkMargin(7.0, 7.0, 7.0, 7.0), x, y, w, h, CMInk.Glass(), CMInk.GlassOp());
    return CMKit.Nine(root, n"rrect_line_s", inkMargin(7.0, 7.0, 7.0, 7.0), x, y, w, h, line, lineOp);
  }
  public static func Fill(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, c: HDRColor, op: Float) -> ref<inkImage> = CMKit.Nine(root, n"rrect_fill_s", inkMargin(7.0, 7.0, 7.0, 7.0), x, y, w, h, c, op)

  // a disc centred on (cx, cy)
  public static func Disc(root: ref<inkCanvas>, cx: Float, cy: Float, r: Float, c: HDRColor, op: Float) -> ref<inkImage> = CMKit.Img(root, n"disc", cx - r, cy - r, r * 2.0, r * 2.0, c, op)

  // move a disc
  public static func Place(img: ref<inkWidget>, cx: Float, cy: Float, r: Float) -> Void {
    img.SetMargin(inkMargin(cx - r, cy - r, 0.0, 0.0));
    img.SetSize(Vector2(r * 2.0, r * 2.0));
  }

  // a straight line, axis-aligned: a thin pill (soft, round-ended), lying or standing by its
  // shape
  public static func Ln(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, c: HDRColor, op: Float) -> ref<inkImage> {
    if w >= h {
      return CMKit.Pill(root, x, y, w, h, c, op);
    }
    return CMKit.VPill(root, x, y, w, h, c, op);
  }

  // four bracket corners (one image each, turned): top left, top right, bottom right,
  // bottom left; PlaceCorners puts them round a box with legs L long
  public static func Corners(root: ref<inkCanvas>, c: HDRColor, op: Float, big: Bool) -> array<ref<inkImage>> {
    let out: array<ref<inkImage>>;
    let i = 0;
    while i < 4 {
      let img = CMKit.Img(root, big ? n"corner_l" : n"corner", 0.0, 0.0, 26.0, 26.0, c, op);
      img.SetRenderTransformPivot(Vector2(0.5, 0.5));
      img.SetRotation(Cast<Float>(i) * 90.0);
      ArrayPush(out, img);
      i += 1;
    }
    return out;
  }

  public static func PlaceCorners(cs: array<ref<inkImage>>, at: Int32, x: Float, y: Float, w: Float, h: Float, L: Float) -> Void {
    if at + 3 >= ArraySize(cs) {
      return;
    }
    let xs = [x, x + w - L, x + w - L, x];
    let ys = [y, y, y + h - L, y + h - L];
    let i = 0;
    while i < 4 {
      let img = cs[at + i];
      img.SetMargin(inkMargin(xs[i], ys[i], 0.0, 0.0));
      img.SetSize(Vector2(L, L));
      i += 1;
    }
  }

  public static func ShowCorners(cs: array<ref<inkImage>>, at: Int32, on: Bool, c: HDRColor) -> Void {
    let i = 0;
    while i < 4 && at + i < ArraySize(cs) {
      cs[at + i].SetVisible(on);
      cs[at + i].SetTintColor(c);
      i += 1;
    }
  }

  // a bracket box in one call (static)
  public static func Brackets(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, L: Float, c: HDRColor, op: Float) -> Void {
    let cs = CMKit.Corners(root, c, op, L > 60.0);
    CMKit.PlaceCorners(cs, 0, x, y, w, h, L);
  }

  // the Griffin's banner plate: a trapezoid (wide at the top), glass and a line
  public static func Banner(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, line: HDRColor) -> Void {
    CMKit.Nine(root, n"banner_fill", inkMargin(60.0, 0.0, 60.0, 0.0), x, y, w, h, CMInk.Glass(), CMInk.GlassOp());
    CMKit.Nine(root, n"banner_line", inkMargin(60.0, 0.0, 60.0, 0.0), x, y, w, h, line, 1.0);
  }

  // a soft dark fade in from each edge of the screen (a vignette)
  public static func Vignette(root: ref<inkCanvas>, W: Float, H: Float, depth: Float, op: Float) -> Void {
    let k = new HDRColor(0.0, 0.0, 0.0, 1.0);
    CMKit.Img(root, n"fade", 0.0, 0.0, W, depth, k, op);
    let b = CMKit.Img(root, n"fade", 0.0, H - depth, W, depth, k, op);
    b.SetRenderTransformPivot(Vector2(0.5, 0.5));
    b.SetRotation(180.0);
    // the sides: a fade H long turned on its side, centred on each edge
    let l = CMKit.Img(root, n"fade", depth * 0.5 - H * 0.5, H * 0.5 - depth * 0.5, H, depth, k, op);
    l.SetRenderTransformPivot(Vector2(0.5, 0.5));
    l.SetRotation(-90.0);
    let r = CMKit.Img(root, n"fade", W - depth * 0.5 - H * 0.5, H * 0.5 - depth * 0.5, H, depth, k, op);
    r.SetRenderTransformPivot(Vector2(0.5, 0.5));
    r.SetRotation(90.0);
  }
}

// A smooth meter: a dim pill track and a bright pill fill (round caps both), horizontal
// filling from the left, or vertical filling from the bottom (a52: meters were rows of
// squares, Omar)
public class CMSlider {
  public let track: ref<inkImage>;
  public let fill: ref<inkImage>;
  private let x: Float;
  private let y: Float;
  private let w: Float;
  private let h: Float;
  private let vertical: Bool;

  public static func Make(root: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, vertical: Bool, c: HDRColor) -> ref<CMSlider> {
    let s = new CMSlider();
    s.x = x;
    s.y = y;
    s.w = w;
    s.h = h;
    s.vertical = vertical;
    s.track = vertical ? CMKit.VPill(root, x, y, w, h, c, 0.18) : CMKit.Pill(root, x, y, w, h, c, 0.18);
    s.fill = vertical ? CMKit.VPill(root, x, y, w, h, c, 1.0) : CMKit.Pill(root, x, y, w, h, c, 1.0);
    return s;
  }

  public func Set(f: Float, c: HDRColor) -> Void {
    let v = ClampF(f, 0.0, 1.0);
    this.fill.SetVisible(v > 0.005);
    this.fill.SetTintColor(c);
    this.track.SetTintColor(c);
    if this.vertical {
      let len = MaxF(this.w, this.h * v);
      this.fill.SetMargin(inkMargin(this.x, this.y + this.h - len, 0.0, 0.0));
      this.fill.SetSize(Vector2(this.w, len));
    } else {
      let len = MaxF(this.h, this.w * v);
      this.fill.SetMargin(inkMargin(this.x, this.y, 0.0, 0.0));
      this.fill.SetSize(Vector2(len, this.h));
    }
  }
}