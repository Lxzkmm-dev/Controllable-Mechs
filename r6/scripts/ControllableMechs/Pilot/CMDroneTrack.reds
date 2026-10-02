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
  public static func Ring(root: ref<inkCanvas>, cx: Float, cy: Float, r: Float, segs: Int32, thick: Float, c: HDRColor, op: Float) -> array<ref<inkRectangle>> {
    let out: array<ref<inkRectangle>>;
    let len = 6.2832 * r / Cast<Float>(segs) + 1.0;
    let i = 0;
    while i < segs {
      let a = Cast<Float>(i) / Cast<Float>(segs) * 360.0;
      let rad = Deg2Rad(a);
      let b = CMPilotHud.Bar(root, cx + SinF(rad) * r - len * 0.5, cy - CosF(rad) * r - thick * 0.5, len, thick, c, op);
      b.SetRenderTransformPivot(Vector2(0.5, 0.5));
      b.SetRotation(a);
      ArrayPush(out, b);
      i += 1;
    }
    return out;
  }

  // a bar laid from one point to another
  public static func Seg(b: ref<inkRectangle>, x1: Float, y1: Float, x2: Float, y2: Float, thick: Float) -> Void {
    let dx = x2 - x1;
    let dy = y2 - y1;
    let len = SqrtF(dx * dx + dy * dy);
    b.SetRenderTransformPivot(Vector2(0.5, 0.5));
    b.SetMargin(inkMargin((x1 + x2) * 0.5 - len * 0.5, (y1 + y2) * 0.5 - thick * 0.5, 0.0, 0.0));
    b.SetSize(Vector2(len, thick));
    b.SetRotation(Rad2Deg(AtanF(dy, dx)));
  }

  public static func Line(root: ref<inkCanvas>, x1: Float, y1: Float, x2: Float, y2: Float, thick: Float, c: HDRColor, op: Float) -> ref<inkRectangle> {
    let b = CMPilotHud.Bar(root, 0.0, 0.0, 1.0, thick, c, op);
    CMInk.Seg(b, x1, y1, x2, y2, thick);
    return b;
  }

  // a diamond outline `s` across, its centre at the canvas's middle (place it by margin)
  public static func Diamond(root: ref<inkCanvas>, s: Float, c: HDRColor) -> ref<inkCanvas> {
    let d = new inkCanvas();
    d.SetSize(Vector2(s, s));
    d.SetRenderTransformPivot(Vector2(0.5, 0.5));
    d.Reparent(root);
    let e = s * 0.7071;
    let o = (s - e) * 0.5;
    let box = new inkCanvas();
    box.SetMargin(inkMargin(o, o, 0.0, 0.0));
    box.SetSize(Vector2(e, e));
    box.SetRenderTransformPivot(Vector2(0.5, 0.5));
    box.SetRotation(45.0);
    box.Reparent(d);
    CMPilotHud.Bar(box, 0.0, 0.0, e, 4.0, c, 1.0);
    CMPilotHud.Bar(box, 0.0, e - 4.0, e, 4.0, c, 1.0);
    CMPilotHud.Bar(box, 0.0, 0.0, 4.0, e, c, 1.0);
    CMPilotHud.Bar(box, e - 4.0, 0.0, 4.0, e, c, 1.0);
    return d;
  }

  // a chevron pointing up, `s` across, on a canvas whose middle it turns about
  public static func Chevron(root: ref<inkCanvas>, s: Float, thick: Float, c: HDRColor) -> ref<inkCanvas> {
    let v = new inkCanvas();
    v.SetSize(Vector2(s, s));
    v.SetRenderTransformPivot(Vector2(0.5, 0.5));
    v.Reparent(root);
    CMInk.Line(v, 0.0, s * 0.75, s * 0.5, s * 0.25, thick, c, 1.0);
    CMInk.Line(v, s * 0.5, s * 0.25, s, s * 0.75, thick, c, 1.0);
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
