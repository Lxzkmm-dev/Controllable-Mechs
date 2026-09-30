// =============================================================================
// CONTROLLABLE MECHS - PILOT HUD (Militech neural-link overlay)
//
// Built once on the game's HUD layer when piloting starts and removed when it
// ends. While it's up, the vanilla HUD is faded out (and restored exactly as it
// was). Values update ten times a second from CMPilotSystem; only the two
// barrel markers are touched every frame, and only when they change.
// =============================================================================
module ControllableMechs

public class CMPilotHud {
  private let m_root: ref<inkCanvas>;
  private let m_parent: wref<inkCompoundWidget>;

  // hidden vanilla HUD widgets and their opacity before we touched them
  private let m_hidden: array<wref<inkWidget>>;
  private let m_hiddenOpacity: array<Float>;

  private let m_title: ref<inkText>;
  private let m_heading: ref<inkText>;
  private let m_range: ref<inkText>;
  private let m_zoom: ref<inkText>;
  private let m_warn: ref<inkText>;
  private let m_mode: ref<inkText>;
  private let m_link: ref<inkText>;
  private let m_speed: ref<inkText>;
  private let m_hints: ref<inkText>;
  private let m_debug: ref<inkText>;
  private let m_integrityText: ref<inkText>;
  private let m_integrityBar: ref<inkRectangle>;
  private let m_signalText: ref<inkText>;
  private let m_signalBar: ref<inkRectangle>;
  private let m_heatL: ref<inkRectangle>;
  private let m_heatR: ref<inkRectangle>;
  private let m_stateL: ref<inkText>;
  private let m_stateR: ref<inkText>;
  private let m_markL: ref<inkRectangle>;
  private let m_markR: ref<inkRectangle>;
  private let m_markLOn: Bool;
  private let m_markROn: Bool;
  private let m_reticle: ref<inkCanvas>;
  // where each barrel points: a small diamond, placed from the centre in 4K units
  private let m_pipL: ref<inkCanvas>;
  private let m_pipR: ref<inkCanvas>;
  private let m_heatTicksL: array<ref<inkRectangle>>;
  private let m_heatTicksR: array<ref<inkRectangle>>;
  private let m_lockL: Bool;
  private let m_lockR: Bool;
  private let m_litL: Int32;
  private let m_litR: Int32;
  private let m_pipLX: Float;
  private let m_pipLY: Float;
  private let m_pipRX: Float;
  private let m_pipRY: Float;

  private let m_tape: ref<inkCanvas>;
  private let m_tapeLabels: array<ref<inkText>>;
  private let m_tapeBase: Int32;
  private let m_tapeX: Float;
  private let m_pitchMark: ref<inkRectangle>;
  private let m_pitchY: Float;
  private let m_warnPlate: ref<inkCanvas>;
  private let m_flash: Bool;
  private let m_msl: ref<inkText>;
  private let TAPE_Y: Float = 50.0;
  private let TAPE_SPACING: Float = 165.0;   // px per 15 deg
  private let PITCH_PX: Float = 6.0;         // px per degree on the elevation ladder
  private let m_hitBars: array<ref<inkRectangle>>;
  private let m_hitT: Float;

  private let BAR_W: Float = 420.0;

  // The palette: a military fire-control display. Amber() is the primary (kept by name for
  // its callers): phosphor olive. Caution() is the old amber, now only for warnings and heat.
  public static func Amber() -> HDRColor = new HDRColor(0.58, 0.84, 0.36, 1.0)
  public static func Dim() -> HDRColor = new HDRColor(0.30, 0.44, 0.20, 1.0)
  public static func Red() -> HDRColor = new HDRColor(1.0, 0.24, 0.16, 1.0)
  public static func Pale() -> HDRColor = new HDRColor(0.86, 0.90, 0.76, 1.0)
  public static func Caution() -> HDRColor = new HDRColor(1.0, 0.70, 0.10, 1.0)
  public static func Steel() -> HDRColor = new HDRColor(0.035, 0.045, 0.035, 1.0)

  // ---------------------------------------------------------------------------
  // Build / remove
  // ---------------------------------------------------------------------------
  public func Build() -> Bool {
    let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
    if !IsDefined(layer) {
      return false;
    }
    let window = layer.GetVirtualWindow();
    if !IsDefined(window) {
      return false;
    }
    this.m_parent = window;
    this.HideVanilla(window);

    let root = new inkCanvas();
    root.SetName(n"cm_pilot_hud");
    root.SetAnchor(inkEAnchor.Fill);
    root.SetInteractive(false);
    root.Reparent(window);
    this.m_root = root;

    this.BuildFrame(root);
    this.BuildReticle(root);
    this.BuildTop(root);
    this.BuildGuns(root);    // first: its key tags take indices 0-3, the chassis plate's 4-5
    this.BuildLeft(root);
    this.BuildRight(root);
    this.BuildHints(root);
    this.BuildEffects(root);
    return true;
  }

  public func Remove() -> Void {
    if IsDefined(this.m_root) && IsDefined(this.m_parent) {
      this.m_parent.RemoveChild(this.m_root);
    }
    this.m_root = null;
    this.RestoreVanilla();
  }

  private func HideVanilla(window: ref<inkCompoundWidget>) -> Void {
    ArrayClear(this.m_hidden);
    ArrayClear(this.m_hiddenOpacity);
    let count = window.GetNumChildren();
    let i = 0;
    while i < count {
      let child = window.GetWidgetByIndex(i);
      if IsDefined(child) && NotEquals(child.GetName(), n"cm_pilot_hud") {
        ArrayPush(this.m_hidden, child);
        ArrayPush(this.m_hiddenOpacity, child.GetOpacity());
        child.SetOpacity(0.0);
      }
      i += 1;
    }
  }

  private func RestoreVanilla() -> Void {
    let i = 0;
    while i < ArraySize(this.m_hidden) {
      let w = this.m_hidden[i];
      if IsDefined(w) {
        w.SetOpacity(this.m_hiddenOpacity[i]);
      }
      i += 1;
    }
    ArrayClear(this.m_hidden);
    ArrayClear(this.m_hiddenOpacity);
  }

  // ---------------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------------
  // The frame is four heavy corner brackets and nothing else: the display is sparse on
  // purpose (the compass tape, the sight, one chassis plate, one weapons plate).
  private func BuildFrame(root: ref<inkCanvas>) -> Void {
    this.Corner(root, inkEAnchor.TopLeft, 1.0, 1.0);
    this.Corner(root, inkEAnchor.TopRight, -1.0, 1.0);
    this.Corner(root, inkEAnchor.BottomLeft, 1.0, -1.0);
    this.Corner(root, inkEAnchor.BottomRight, -1.0, -1.0);
  }

  // The display's wear, kept very faint: a scanline every 36 px and slightly darker glass
  // at the left and right edges. Static (built once, never touched again).
  private func BuildEffects(root: ref<inkCanvas>) -> Void {
    let y = 0.0;
    while y < 2160.0 {
      CMPilotHud.Box(root, inkEAnchor.TopFillHorizontaly, 0.0, y, 0.0, 3.0, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.05);
      y += 36.0;
    }
    let i = 0;
    while i < 2 {
      let w = 120.0 + Cast<Float>(i) * 120.0;
      CMPilotHud.Box(root, inkEAnchor.LeftFillVerticaly, 0.0, 0.0, w, 0.0, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.07);
      let r = CMPilotHud.Box(root, inkEAnchor.RightFillVerticaly, 0.0, 0.0, w, 0.0, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.07);
      r.SetAnchorPoint(Vector2(1.0, 0.0));
      i += 1;
    }
    // the boot text (StartBoot / Boot run it)
    this.m_boot = CMPilotHud.Label(root, inkEAnchor.Centered, 0.0, -330.0, "", 34, n"Semi-Bold", CMPilotHud.Amber());
    this.m_boot.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_boot.SetVisible(false);
  }

  // The link coming up: for BOOT_TIME the display flickers for the first half second and
  // the boot lines appear one by one, then it settles. Boot() is called every frame by the
  // session and returns at once when there is nothing to do.
  private let m_boot: ref<inkText>;
  private let m_bootT: Float;
  private let m_bootStage: Int32;
  private let BOOT_TIME: Float = 1.8;

  public func StartBoot() -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    this.m_bootT = this.BOOT_TIME;
    this.m_bootStage = -1;
    this.m_boot.SetVisible(true);
  }

  public func Boot(dt: Float) -> Void {
    if this.m_bootT <= 0.0 || !IsDefined(this.m_root) {
      return;
    }
    this.m_bootT -= dt;
    let elapsed = this.BOOT_TIME - this.m_bootT;
    if this.m_bootT <= 0.0 {
      this.m_boot.SetVisible(false);
      this.m_root.SetOpacity(1.0);
      return;
    }
    this.m_root.SetOpacity(elapsed < 0.5 ? RandRangeF(0.3, 1.0) : 1.0);
    let stage = FloorF(elapsed / 0.3);
    if stage != this.m_bootStage {
      this.m_bootStage = stage;
      let text = "MILITECH FCS  //  COLD START";
      if stage >= 1 { text += "\nNEURAL UPLINK ........ SECURE"; }
      if stage >= 2 { text += "\nCHASSIS BUS .......... OK"; }
      if stage >= 3 { text += "\nMK.31 L / R .......... ARMED"; }
      if stage >= 4 { text += "\nOPTICS / LRF ......... OK"; }
      if stage >= 5 { text += "\nPILOT HAS CONTROL"; }
      this.m_boot.SetText(text);
    }
  }

  // ---- key tags: the controls, stencilled onto the plate each one works. Bright for the
  // first seconds after the link comes up, then faint; a tag lights again for a moment
  // when its key is used (TagFlash). Tags() runs every frame but only touches a tag
  // while its timer is running.
  private let m_tags: array<ref<inkText>>;
  private let m_tagT: array<Float>;
  private let m_tagDim: array<Float>;   // each tag's resting opacity
  private let m_tagSplit: Bool;
  private let TAG_DIM: Float = 0.28;
  private let TAG_INTRO: Float = 7.0;    // seconds bright after the link comes up (boot included)
  private let TAG_FLASH: Float = 1.2;    // seconds bright after its key is used

  public static func TagFire() -> Int32 = 0
  public static func TagMode() -> Int32 = 1
  public static func TagMissile() -> Int32 = 2
  public static func TagZoom() -> Int32 = 3
  public static func TagView() -> Int32 = 4
  public static func TagExit() -> Int32 = 5

  private func Tag(root: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, text: String, right: Bool) -> ref<inkText> {
    let t = CMPilotHud.Label(root, anchor, x, y, text, 26, n"Semi-Bold", CMPilotHud.Caution());
    if right {
      t.SetAnchorPoint(Vector2(1.0, 0.0));
    }
    if Equals(anchor, inkEAnchor.Centered) {
      t.SetAnchorPoint(Vector2(0.5, 0.0));
    }
    ArrayPush(this.m_tags, t);
    ArrayPush(this.m_tagT, this.TAG_INTRO);
    ArrayPush(this.m_tagDim, this.TAG_DIM);
    return t;
  }

  public func TagFlash(i: Int32) -> Void {
    if i >= 0 && i < ArraySize(this.m_tagT) {
      this.m_tagT[i] = MaxF(this.m_tagT[i], this.TAG_FLASH);
      this.m_tags[i].SetOpacity(1.0);
    }
  }

  public func Tags(dt: Float) -> Void {
    let i = 0;
    while i < ArraySize(this.m_tagT) {
      if this.m_tagT[i] > 0.0 {
        this.m_tagT[i] -= dt;
        // the last half second fades down to the resting level
        let dim = this.m_tagDim[i];
        this.m_tags[i].SetOpacity(this.m_tagT[i] > 0.5 ? 1.0 : dim + (1.0 - dim) * MaxF(0.0, this.m_tagT[i]) / 0.5);
      }
      i += 1;
    }
  }

  // split fire mode moves the keys: LMB and RMB are the two guns, the optics go to MMB
  private func TagTexts(split: Bool) -> Void {
    if ArraySize(this.m_tags) < 6 {
      return;
    }
    this.m_tags[0].SetText(split ? "[LMB] L GUN   [RMB] R GUN" : "[LMB] FIRE");
    this.m_tags[3].SetText(split ? "[MMB] ZOOM" : "[RMB] ZOOM");
  }

  // a dark steel plate behind a block of readouts, with a heavy edge bar
  private func Plate(root: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, w: Float, h: Float) -> Void {
    let right = Equals(anchor, inkEAnchor.TopRight) || Equals(anchor, inkEAnchor.BottomRight);
    let ap = Vector2(right ? 1.0 : 0.0, 0.0);
    let plate = CMPilotHud.Box(root, anchor, x, y, w, h, CMPilotHud.Steel(), 0.55);
    plate.SetAnchorPoint(ap);
    let edge = CMPilotHud.Box(root, anchor, x, y, 10.0, h, CMPilotHud.Amber(), 0.9);
    edge.SetAnchorPoint(ap);
  }

  // nine dark dividers over a bar, so it reads as ten armoured segments
  private func Segments(root: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, h: Float) -> Void {
    let right = Equals(anchor, inkEAnchor.TopRight) || Equals(anchor, inkEAnchor.BottomRight);
    let i = 1;
    while i < 10 {
      let d = CMPilotHud.Box(root, anchor, x + this.BAR_W * Cast<Float>(i) / 10.0 - 3.0, y, 6.0, h, CMPilotHud.Steel(), 1.0);
      d.SetAnchorPoint(Vector2(right ? 1.0 : 0.0, 0.0));
      i += 1;
    }
  }

  private func Corner(root: ref<inkCanvas>, anchor: inkEAnchor, sx: Float, sy: Float) -> Void {
    let inset = 90.0;   // 4% of the screen height in from every edge
    let len = 170.0;
    let t = 10.0;
    let ax = sx > 0.0 ? 0.0 : 1.0;
    let ay = sy > 0.0 ? 0.0 : 1.0;
    let h = new inkRectangle();
    h.SetAnchor(anchor);
    h.SetAnchorPoint(Vector2(ax, ay));
    h.SetSize(Vector2(len, t));
    h.SetMargin(inkMargin(sx > 0.0 ? inset : 0.0, sy > 0.0 ? inset : 0.0, sx < 0.0 ? inset : 0.0, sy < 0.0 ? inset : 0.0));
    h.SetTintColor(CMPilotHud.Amber());
    h.SetOpacity(0.8);
    h.Reparent(root);
    let v = new inkRectangle();
    v.SetAnchor(anchor);
    v.SetAnchorPoint(Vector2(ax, ay));
    v.SetSize(Vector2(t, len));
    v.SetMargin(inkMargin(sx > 0.0 ? inset : 0.0, sy > 0.0 ? inset : 0.0, sx < 0.0 ? inset : 0.0, sy < 0.0 ? inset : 0.0));
    v.SetTintColor(CMPilotHud.Amber());
    v.SetOpacity(0.8);
    v.Reparent(root);
  }

  private func BuildReticle(root: ref<inkCanvas>) -> Void {
    let r = new inkCanvas();
    r.SetAnchor(inkEAnchor.Centered);
    r.SetAnchorPoint(Vector2(0.5, 0.5));
    r.SetSize(Vector2(400.0, 400.0));
    r.Reparent(root);
    this.m_reticle = r;
    let c = CMPilotHud.Amber();
    // the sight: four heavy arms with a wide centre gap and a chevron at the aim point
    CMPilotHud.Bar(r, 200.0 - 5.0, 200.0 - 110.0, 10.0, 60.0, c, 0.95);   // up
    CMPilotHud.Bar(r, 200.0 - 5.0, 200.0 + 50.0, 10.0, 60.0, c, 0.95);    // down
    CMPilotHud.Bar(r, 200.0 - 150.0, 200.0 - 5.0, 100.0, 10.0, c, 0.95);  // left
    CMPilotHud.Bar(r, 200.0 + 50.0, 200.0 - 5.0, 100.0, 10.0, c, 0.95);   // right
    let cl = CMPilotHud.Bar(r, 200.0 - 17.0, 200.0 + 3.0, 22.0, 5.0, CMPilotHud.Pale(), 1.0);
    cl.SetRotation(-38.0);
    let cr = CMPilotHud.Bar(r, 200.0 - 5.0, 200.0 + 3.0, 22.0, 5.0, CMPilotHud.Pale(), 1.0);
    cr.SetRotation(38.0);
    // hit marker: four short diagonals round the centre, shown when a round connects (M1)
    for sx in [-1.0, 1.0] {
      for sy in [-1.0, 1.0] {
        let d = CMPilotHud.Bar(r, 200.0 + sx * 34.0 - 12.0, 200.0 + sy * 34.0 - 3.0, 24.0, 6.0, CMPilotHud.Pale(), 0.0);
        d.SetRotation(sx * sy > 0.0 ? 45.0 : -45.0);
        ArrayPush(this.m_hitBars, d);
      }
    }
    // barrel markers at the ends of the side arms: light up when that gun fires
    this.m_markL = CMPilotHud.Bar(r, 200.0 - 166.0, 200.0 - 30.0, 10.0, 60.0, c, 0.35);
    this.m_markR = CMPilotHud.Bar(r, 200.0 + 156.0, 200.0 - 30.0, 10.0, 60.0, c, 0.35);
    // each gun's own reticle (hidden until the pilot system places them)
    this.m_pipL = this.GunReticle(root, true);
    this.m_pipR = this.GunReticle(root, false);
    // the rangefinder box under the sight, the zoom key beside it, the optics line below
    this.m_range = CMPilotHud.Label(root, inkEAnchor.Centered, 0.0, 170.0, "[ LRF ---- M ]", 38, n"Semi-Bold", c);
    this.m_range.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_zoom = CMPilotHud.Label(root, inkEAnchor.Centered, 0.0, 262.0, "", 26, n"Semi-Bold", CMPilotHud.Dim());
    this.m_zoom.SetAnchorPoint(Vector2(0.5, 0.0));
  }

  private let m_ladder: ref<inkCanvas>;

  private func BuildTop(root: ref<inkCanvas>) -> Void {
    // the unit, once, small, in the top-left corner
    this.m_title = CMPilotHud.Label(root, inkEAnchor.TopLeft, 200.0, 130.0, "MILITECH MINOTAUR", 26, n"Semi-Bold", CMPilotHud.Dim());

    // the compass tape: nine bearings 15 deg apart and a tick every 5, sliding under a
    // fixed index; SetAttitude moves it every frame (SPACING px per 15 deg)
    let tape = new inkCanvas();
    tape.SetAnchor(inkEAnchor.TopCenter);
    tape.SetAnchorPoint(Vector2(0.5, 0.0));
    tape.SetSize(Vector2(2.0, 2.0));
    tape.SetMargin(inkMargin(0.0, this.TAPE_Y, 0.0, 0.0));
    tape.Reparent(root);
    this.m_tape = tape;
    let k = -4;
    while k <= 4 {
      let t = CMPilotHud.Label(tape, inkEAnchor.TopLeft, Cast<Float>(k) * this.TAPE_SPACING, 0.0, "000", 30, n"Semi-Bold", CMPilotHud.Pale());
      t.SetAnchorPoint(Vector2(0.5, 0.0));
      ArrayPush(this.m_tapeLabels, t);
      k += 1;
    }
    let m = -12;
    while m <= 12 {
      let major = m % 3 == 0;
      CMPilotHud.Bar(tape, Cast<Float>(m) * this.TAPE_SPACING / 3.0 - 2.0, 44.0, 4.0, major ? 22.0 : 12.0, major ? CMPilotHud.Amber() : CMPilotHud.Dim(), 0.95);
      m += 1;
    }
    this.m_tapeBase = -999;
    // the fixed index and the boxed bearing under the tape
    let idx = CMPilotHud.Box(root, inkEAnchor.TopCenter, 0.0, this.TAPE_Y + 38.0, 6.0, 36.0, CMPilotHud.Caution(), 1.0);
    idx.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_heading = CMPilotHud.Label(root, inkEAnchor.TopCenter, 0.0, 140.0, "[ HDG 000 N ]", 38, n"Semi-Bold", CMPilotHud.Pale());
    this.m_heading.SetAnchorPoint(Vector2(0.5, 0.0));

    // the warning panel: a steel plate with hazard stripes either end, shown and flashed
    // only while there is a warning
    let wp = new inkCanvas();
    wp.SetAnchor(inkEAnchor.TopCenter);
    wp.SetAnchorPoint(Vector2(0.5, 0.0));
    wp.SetSize(Vector2(2.0, 2.0));
    wp.SetMargin(inkMargin(0.0, 230.0, 0.0, 0.0));
    wp.SetVisible(false);
    wp.Reparent(root);
    CMPilotHud.Bar(wp, -560.0, 0.0, 1120.0, 74.0, CMPilotHud.Steel(), 0.8);
    CMPilotHud.Bar(wp, -560.0, 0.0, 1120.0, 6.0, CMPilotHud.Red(), 0.95);
    CMPilotHud.Bar(wp, -560.0, 68.0, 1120.0, 6.0, CMPilotHud.Red(), 0.95);
    let s = 0;
    while s < 3 {
      let l = CMPilotHud.Bar(wp, -540.0 + Cast<Float>(s) * 36.0, 8.0, 16.0, 58.0, CMPilotHud.Caution(), 0.9);
      l.SetRotation(28.0);
      let r = CMPilotHud.Bar(wp, 524.0 - Cast<Float>(s) * 36.0, 8.0, 16.0, 58.0, CMPilotHud.Caution(), 0.9);
      r.SetRotation(-28.0);
      s += 1;
    }
    this.m_warnPlate = wp;
    this.m_warn = CMPilotHud.Label(root, inkEAnchor.TopCenter, 0.0, 240.0, "", 44, n"Semi-Bold", CMPilotHud.Red());
    this.m_warn.SetAnchorPoint(Vector2(0.5, 0.0));

    // the elevation ladder left of the sight, shown only through the optics: a tick every
    // 5 deg from +30 to -30 and a marker at the view's pitch (moved by SetAttitude)
    let lad = new inkCanvas();
    lad.SetAnchor(inkEAnchor.Centered);
    lad.SetAnchorPoint(Vector2(0.5, 0.5));
    lad.SetSize(Vector2(2.0, 2.0));
    lad.SetMargin(inkMargin(-360.0, 0.0, 0.0, 0.0));
    lad.SetVisible(false);
    lad.Reparent(root);
    this.m_ladder = lad;
    let p = -6;
    while p <= 6 {
      let big = p % 2 == 0;
      CMPilotHud.Bar(lad, big ? -26.0 : -14.0, -Cast<Float>(p) * 5.0 * this.PITCH_PX - 2.0, big ? 26.0 : 14.0, 4.0, CMPilotHud.Amber(), 0.9);
      if big {
        let n = CMPilotHud.Label(lad, inkEAnchor.TopLeft, -40.0, -Cast<Float>(p) * 5.0 * this.PITCH_PX - 18.0, IntToString(p * 5), 26, n"Semi-Bold", CMPilotHud.Dim());
        n.SetAnchorPoint(Vector2(1.0, 0.0));
      }
      p += 1;
    }
    CMPilotHud.Bar(lad, 0.0, -30.0 * this.PITCH_PX, 4.0, 60.0 * this.PITCH_PX, CMPilotHud.Dim(), 0.8);
    this.m_pitchMark = CMPilotHud.Bar(lad, 6.0, -3.0, 30.0, 6.0, CMPilotHud.Caution(), 1.0);
  }

  // every frame while piloting: the compass tape and the elevation marker. Widgets move
  // only when they shift by more than a pixel; the bearings are relabelled only when the
  // tape crosses a 15 deg step.
  public func SetAttitude(heading: Float, pitch: Float) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    let h = heading < 0.0 ? heading + 360.0 : heading;
    let base = FloorF(h / 15.0) * 15;
    if base != this.m_tapeBase {
      this.m_tapeBase = base;
      let i = 0;
      while i < ArraySize(this.m_tapeLabels) {
        let b = (base + (i - 4) * 15 + 720) % 360;
        this.m_tapeLabels[i].SetText(CMPilotHud.Bearing(b));
        i += 1;
      }
    }
    let x = -(h - Cast<Float>(base)) / 15.0 * this.TAPE_SPACING;
    if AbsF(x - this.m_tapeX) > 1.0 {
      this.m_tapeX = x;
      this.m_tape.SetMargin(inkMargin(x, this.TAPE_Y, 0.0, 0.0));
    }
    let y = -ClampF(pitch, -32.0, 32.0) * this.PITCH_PX - 3.0;
    if AbsF(y - this.m_pitchY) > 1.0 {
      this.m_pitchY = y;
      this.m_pitchMark.SetMargin(inkMargin(6.0, y, 0.0, 0.0));
    }
  }

  private static func Bearing(b: Int32) -> String {
    switch b {
      case 0: return "N";
      case 90: return "E";
      case 180: return "S";
      case 270: return "W";
    }
    return CMPilotHud.Pad3(b);
  }

  // The chassis plate, bottom left: the hull as a ten-segment bar, the uplink and ground
  // speed on one small line, and the view and disconnect keys.
  private func BuildLeft(root: ref<inkCanvas>) -> Void {
    let x = 200.0;   // the plate's edge sits 160 px in from the screen edge
    this.Plate(root, inkEAnchor.BottomLeft, x - 40.0, 420.0, this.BAR_W + 80.0, 290.0);
    this.m_integrityText = CMPilotHud.Label(root, inkEAnchor.BottomLeft, x, 395.0, "HULL 100%", 38, n"Semi-Bold", CMPilotHud.Amber());
    CMPilotHud.Box(root, inkEAnchor.BottomLeft, x, 336.0, this.BAR_W, 28.0, CMPilotHud.Dim(), 0.35);
    this.m_integrityBar = CMPilotHud.Box(root, inkEAnchor.BottomLeft, x, 336.0, this.BAR_W, 28.0, CMPilotHud.Amber(), 0.95);
    this.Segments(root, inkEAnchor.BottomLeft, x, 336.0, 28.0);
    this.m_signalText = CMPilotHud.Label(root, inkEAnchor.BottomLeft, x, 286.0, "UPLINK", 26, n"Semi-Bold", CMPilotHud.Pale());
    this.m_speed = CMPilotHud.Label(root, inkEAnchor.BottomLeft, x + 250.0, 286.0, "GND 0.0 M/S", 26, n"Semi-Bold", CMPilotHud.Pale());
    // the uplink has no bar any more; the widget stays so the refresh has something to set
    this.m_signalBar = CMPilotHud.Box(root, inkEAnchor.BottomLeft, x, 286.0, 0.0, 0.0, CMPilotHud.Amber(), 0.0);
    this.Tag(root, inkEAnchor.BottomLeft, x, 226.0, "[V] VIEW", false);            // TagView = 4 (pushed in index order below)
    this.Tag(root, inkEAnchor.BottomLeft, x + 190.0, 226.0, "[\\] DISCONNECT", false);   // TagExit = 5
  }

  // The operator range and the old fire-control lines are folded into the two plates; the
  // widgets the refresh still writes to are kept, hidden.
  private func BuildRight(root: ref<inkCanvas>) -> Void {
    this.m_link = CMPilotHud.Label(root, inkEAnchor.TopRight, 200.0, 130.0, "", 26, n"Semi-Bold", CMPilotHud.Dim());
    this.m_link.SetAnchorPoint(Vector2(1.0, 0.0));
  }

  // The weapons plate, bottom right: each MK.31's state and a ten-segment temperature bar,
  // the fire mode, the missile, and their keys.
  private func BuildGuns(root: ref<inkCanvas>) -> Void {
    let x = 200.0;
    this.Plate(root, inkEAnchor.BottomRight, x - 40.0, 520.0, this.BAR_W + 80.0, 390.0);
    // the four tags are pushed in index order: fire 0, mode 1, missile 2, zoom 3
    this.Tag(root, inkEAnchor.BottomRight, x, 226.0, "[LMB] FIRE", true);
    // the fire mode and the missile are status lines with their key in front, so they stay
    // readable at rest and only brighten when the key is used
    this.m_mode = this.StatusTag(root, x, 324.0, "[B] MODE STAGGERED");
    this.m_msl = this.StatusTag(root, x, 276.0, "[G] MSL READY");
    this.Tag(root, inkEAnchor.Centered, 0.0, 222.0, "[RMB] ZOOM", false);

    this.m_stateL = CMPilotHud.Label(root, inkEAnchor.BottomRight, x, 495.0, "L  ARMED", 30, n"Semi-Bold", CMPilotHud.Pale());
    this.m_stateL.SetAnchorPoint(Vector2(1.0, 0.0));
    let bgL = CMPilotHud.Box(root, inkEAnchor.BottomRight, x, 450.0, this.BAR_W, 24.0, CMPilotHud.Dim(), 0.35);
    bgL.SetAnchorPoint(Vector2(1.0, 0.0));
    this.m_heatL = CMPilotHud.Box(root, inkEAnchor.BottomRight, x, 450.0, 0.0, 24.0, CMPilotHud.Amber(), 0.95);
    this.m_heatL.SetAnchorPoint(Vector2(1.0, 0.0));
    this.Segments(root, inkEAnchor.BottomRight, x, 450.0, 24.0);

    this.m_stateR = CMPilotHud.Label(root, inkEAnchor.BottomRight, x, 410.0, "R  ARMED", 30, n"Semi-Bold", CMPilotHud.Pale());
    this.m_stateR.SetAnchorPoint(Vector2(1.0, 0.0));
    let bgR = CMPilotHud.Box(root, inkEAnchor.BottomRight, x, 365.0, this.BAR_W, 24.0, CMPilotHud.Dim(), 0.35);
    bgR.SetAnchorPoint(Vector2(1.0, 0.0));
    this.m_heatR = CMPilotHud.Box(root, inkEAnchor.BottomRight, x, 365.0, 0.0, 24.0, CMPilotHud.Amber(), 0.95);
    this.m_heatR.SetAnchorPoint(Vector2(1.0, 0.0));
    this.Segments(root, inkEAnchor.BottomRight, x, 365.0, 24.0);

  }

  private func StatusTag(root: ref<inkCanvas>, x: Float, y: Float, text: String) -> ref<inkText> {
    let t = this.Tag(root, inkEAnchor.BottomRight, x, y, text, true);
    t.SetFontSize(30);
    t.SetTintColor(CMPilotHud.Amber());
    this.m_tagDim[ArraySize(this.m_tagDim) - 1] = 0.85;
    return t;
  }

  // the old hint line is replaced by the key tags; the widget stays for the refresh, hidden
  private func BuildHints(root: ref<inkCanvas>) -> Void {
    this.m_hints = CMPilotHud.Label(root, inkEAnchor.BottomCenter, 0.0, 70.0, "", 26, n"Medium", CMPilotHud.Dim());
    this.m_hints.SetAnchorPoint(Vector2(0.5, 1.0));
    this.m_hints.SetVisible(false);
    // diagnostics (SETTINGS > DEBUG READOUT); a line that never changes means the frame loop never ran
    this.m_debug = CMPilotHud.Label(root, inkEAnchor.BottomCenter, 0.0, 70.0, "DBG  WAITING FOR FIRST FRAME", 26, n"Medium", CMPilotHud.Pale());
    this.m_debug.SetAnchorPoint(Vector2(0.5, 1.0));
    this.m_debug.SetVisible(false);
  }

  // ---------------------------------------------------------------------------
  // Updates
  // ---------------------------------------------------------------------------
  // every frame: barrel markers, only on change
  public func Flash(left: Bool, right: Bool) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    if NotEquals(left, this.m_markLOn) {
      this.m_markLOn = left;
      this.m_markL.SetOpacity(left ? 1.0 : 0.35);
    }
    if NotEquals(right, this.m_markROn) {
      this.m_markROn = right;
      this.m_markR.SetOpacity(right ? 1.0 : 0.35);
    }
  }

  // the optics (M1): dark bands close in from the sides and a fine range scale sits
  // under the reticle; built on first use, then only shown or hidden
  private let m_optics: ref<inkCanvas>;

  public func SetOptics(on: Bool) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    if !IsDefined(this.m_optics) {
      if !on {
        return;
      }
      let o = new inkCanvas();
      o.SetAnchor(inkEAnchor.Fill);
      o.SetInteractive(false);
      o.Reparent(this.m_root);
      let left = CMPilotHud.Box(o, inkEAnchor.LeftFillVerticaly, 0.0, 0.0, 700.0, 0.0, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.8);
      let right = CMPilotHud.Box(o, inkEAnchor.RightFillVerticaly, 0.0, 0.0, 700.0, 0.0, new HDRColor(0.0, 0.0, 0.0, 1.0), 0.8);
      right.SetAnchorPoint(Vector2(1.0, 0.0));
      // stadiametric ticks under the centre, and a long horizon line either side
      let i = 1;
      while i <= 4 {
        let t = CMPilotHud.Bar(o, 0.0, 0.0, 4.0, 18.0 - Cast<Float>(i) * 2.0, CMPilotHud.Amber(), 0.9);
        t.SetAnchor(inkEAnchor.Centered);
        t.SetMargin(inkMargin(-2.0, 40.0 + Cast<Float>(i) * 45.0, 0.0, 0.0));
        i += 1;
      }
      let hl = CMPilotHud.Bar(o, 0.0, 0.0, 520.0, 3.0, CMPilotHud.Amber(), 0.6);
      hl.SetAnchor(inkEAnchor.Centered);
      hl.SetMargin(inkMargin(-680.0, -1.5, 0.0, 0.0));
      let hr = CMPilotHud.Bar(o, 0.0, 0.0, 520.0, 3.0, CMPilotHud.Amber(), 0.6);
      hr.SetAnchor(inkEAnchor.Centered);
      hr.SetMargin(inkMargin(160.0, -1.5, 0.0, 0.0));
      this.m_optics = o;
    }
    this.m_optics.SetVisible(on);
    this.m_ladder.SetVisible(on);   // the elevation ladder belongs to the optics
  }

  // a round connected: the marker flashes (red for a kill) and fades over 0.25 s
  public func Hit(kill: Bool) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    this.m_hitT = kill ? 0.45 : 0.25;
    for d in this.m_hitBars {
      d.SetTintColor(kill ? CMPilotHud.Red() : CMPilotHud.Pale());
      d.SetOpacity(1.0);
    }
  }

  // every frame, only while a marker is showing
  public func FadeHit(dt: Float) -> Void {
    if this.m_hitT <= 0.0 {
      return;
    }
    this.m_hitT = MaxF(0.0, this.m_hitT - dt);
    let a = ClampF(this.m_hitT / 0.25, 0.0, 1.0);
    for d in this.m_hitBars {
      d.SetOpacity(a);
    }
  }

  // every frame while piloting; widgets only move when a pip shifts by more than 2 units
  public func SetPips(lx: Float, ly: Float, lOn: Bool, rx: Float, ry: Float, rOn: Bool) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    this.m_pipL.SetVisible(lOn);
    this.m_pipR.SetVisible(rOn);
    if lOn && (AbsF(lx - this.m_pipLX) > 2.0 || AbsF(ly - this.m_pipLY) > 2.0) {
      this.m_pipLX = lx;
      this.m_pipLY = ly;
      this.m_pipL.SetMargin(inkMargin(lx, ly, 0.0, 0.0));
    }
    if rOn && (AbsF(rx - this.m_pipRX) > 2.0 || AbsF(ry - this.m_pipRY) > 2.0) {
      this.m_pipRX = rx;
      this.m_pipRY = ry;
      this.m_pipR.SetMargin(inkMargin(rx, ry, 0.0, 0.0));
    }
  }

  // A gun's reticle, where its barrel points: a broken ring of eight short segments with a
  // centre dot and an L / R tag, and outside it a ring of twelve heat ticks that light up
  // as that gun heats (red near overheat). Locked (the barrel inside the fire gate) the
  // reticle is tight and bright; converging it's larger and dim. Shapes only, no assets.
  private func GunReticle(root: ref<inkCanvas>, left: Bool) -> ref<inkCanvas> {
    let c = new inkCanvas();
    c.SetAnchor(inkEAnchor.Centered);
    c.SetAnchorPoint(Vector2(0.5, 0.5));
    c.SetSize(Vector2(120.0, 120.0));
    c.SetRenderTransformPivot(Vector2(0.5, 0.5));
    c.SetVisible(false);
    c.Reparent(root);
    let i = 0;
    while i < 8 {
      let a = Deg2Rad(Cast<Float>(i) * 45.0 + 22.5);
      let seg = CMPilotHud.Bar(c, 60.0 + CosF(a) * 26.0 - 7.0, 60.0 + SinF(a) * 26.0 - 1.5, 14.0, 3.0, CMPilotHud.Pale(), 1.0);
      seg.SetRotation(Cast<Float>(i) * 45.0 + 22.5 + 90.0);
      i += 1;
    }
    CMPilotHud.Bar(c, 57.5, 57.5, 5.0, 5.0, CMPilotHud.Pale(), 1.0);
    let tag = new inkText();
    tag.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    tag.SetFontStyle(n"Semi-Bold");
    tag.SetFontSize(22);
    tag.SetTintColor(CMPilotHud.Pale());
    tag.SetText(left ? "L" : "R");
    tag.SetMargin(inkMargin(left ? 8.0 : 100.0, 84.0, 0.0, 0.0));
    tag.Reparent(c);
    // heat ticks, clockwise from the top
    let k = 0;
    while k < 12 {
      let a = Deg2Rad(Cast<Float>(k) * 30.0 - 90.0);
      let tick = CMPilotHud.Bar(c, 60.0 + CosF(a) * 42.0 - 5.0, 60.0 + SinF(a) * 42.0 - 2.0, 10.0, 4.0, CMPilotHud.Caution(), 0.12);
      tick.SetRotation(Cast<Float>(k) * 30.0);
      if left {
        ArrayPush(this.m_heatTicksL, tick);
      } else {
        ArrayPush(this.m_heatTicksR, tick);
      }
      k += 1;
    }
    c.SetScale(Vector2(1.25, 1.25));
    c.SetOpacity(0.5);
    return c;
  }

  // every frame while piloting, but widgets are only touched when something changed:
  // each gun's lock state, and how many of its heat ticks are lit
  public func SetGunState(lockedL: Bool, heatL: Float, lockedR: Bool, heatR: Float) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    if NotEquals(lockedL, this.m_lockL) {
      this.m_lockL = lockedL;
      this.m_pipL.SetScale(lockedL ? Vector2(1.0, 1.0) : Vector2(1.25, 1.25));
      this.m_pipL.SetOpacity(lockedL ? 1.0 : 0.5);
    }
    if NotEquals(lockedR, this.m_lockR) {
      this.m_lockR = lockedR;
      this.m_pipR.SetScale(lockedR ? Vector2(1.0, 1.0) : Vector2(1.25, 1.25));
      this.m_pipR.SetOpacity(lockedR ? 1.0 : 0.5);
    }
    let litL = RoundF(ClampF(heatL, 0.0, 1.0) * 12.0);
    if litL != this.m_litL {
      this.m_litL = litL;
      CMPilotHud.LightTicks(this.m_heatTicksL, litL);
    }
    let litR = RoundF(ClampF(heatR, 0.0, 1.0) * 12.0);
    if litR != this.m_litR {
      this.m_litR = litR;
      CMPilotHud.LightTicks(this.m_heatTicksR, litR);
    }
  }

  private static func LightTicks(ticks: array<ref<inkRectangle>>, lit: Int32) -> Void {
    let hot = lit >= 10;
    let i = 0;
    while i < ArraySize(ticks) {
      let on = i < lit;
      ticks[i].SetOpacity(on ? 1.0 : 0.12);
      ticks[i].SetTintColor(on && hot ? CMPilotHud.Red() : CMPilotHud.Caution());
      i += 1;
    }
  }

  public func ShowDebug(on: Bool) -> Void {
    if IsDefined(this.m_debug) {
      this.m_debug.SetVisible(on);
    }
  }

  public func SetDebug(text: String) -> Void {
    if IsDefined(this.m_debug) {
      this.m_debug.SetText(text);
    }
  }

  // ten times a second
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    this.m_title.SetText(s.title);
    this.m_heading.SetText("[ HDG " + CMPilotHud.Pad3(s.heading) + " " + CMPilotHud.Cardinal(s.heading) + " ]");
    this.m_range.SetText(s.range > 0.0 ? "[ LRF " + CMPilotHud.Pad4(RoundF(s.range)) + " M ]" : "[ LRF ---- M ]");
    this.m_zoom.SetText(s.zoomed ? "OPTICS 2.5X" : "");

    this.m_integrityText.SetText("HULL " + IntToString(RoundF(s.integrity * 100.0)) + "%" + (s.integrity < 0.3 ? "  CRITICAL" : ""));
    this.m_integrityBar.SetWidth(this.BAR_W * ClampF(s.integrity, 0.0, 1.0));
    this.m_integrityBar.SetTintColor(s.integrity < 0.3 ? CMPilotHud.Red() : CMPilotHud.Amber());
    this.m_signalText.SetText("UPLINK " + IntToString(RoundF(s.signal * 100.0)) + "%");
    this.m_signalText.SetTintColor(s.signal < 0.25 ? CMPilotHud.Red() : CMPilotHud.Pale());
    this.m_speed.SetText("GND " + FloatToStringPrec(s.speed, 1) + " M/S");

    this.m_mode.SetText("[B] MODE " + CMFireMode.Name(s.fireMode));
    let split = s.fireMode == CMFireMode.Split();
    if NotEquals(split, this.m_tagSplit) {
      this.m_tagSplit = split;
      this.TagTexts(split);
    }
    this.m_link.SetText("OPERATOR " + IntToString(RoundF(s.distance)) + " M");

    this.Gun(this.m_heatL, this.m_stateL, "L  ", s.heatL, s.lockedL, s.hasL);
    this.Gun(this.m_heatR, this.m_stateR, "R  ", s.heatR, s.lockedR, s.hasR);

    this.m_warn.SetText(s.warning);
    // the warning panel shows and flashes only while there is a warning
    let warned = StrLen(s.warning) > 0;
    this.m_flash = !this.m_flash;
    this.m_warnPlate.SetVisible(warned);
    if warned {
      this.m_warnPlate.SetOpacity(this.m_flash ? 1.0 : 0.5);
    }
    this.m_msl.SetText(StrLen(s.missile) > 0 ? "[G] " + s.missile : "");
    this.m_msl.SetTintColor(StrContains(s.missile, "READY") ? CMPilotHud.Amber() : CMPilotHud.Caution());
    this.m_hints.SetText(s.hints);
    if StrLen(s.debug) > 0 {
      this.m_debug.SetText(s.debug);
    }
  }

  private func Gun(bar: ref<inkRectangle>, state: ref<inkText>, side: String, heat: Float, locked: Bool, has: Bool) -> Void {
    bar.SetWidth(this.BAR_W * ClampF(heat, 0.0, 1.0));
    bar.SetTintColor(locked || heat > 0.8 ? CMPilotHud.Red() : (heat > 0.5 ? CMPilotHud.Caution() : CMPilotHud.Amber()));
    if !has {
      state.SetText(side + "NO WEAPON");
      state.SetTintColor(CMPilotHud.Red());
    } else {
      if locked {
        state.SetText(side + "OVERTEMP - LOCKED");
        state.SetTintColor(CMPilotHud.Red());
      } else {
        state.SetText(side + "MK.31  " + IntToString(RoundF(heat * 100.0)) + "%");
        state.SetTintColor(CMPilotHud.Pale());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Small ink helpers
  // ---------------------------------------------------------------------------
  public static func Label(parent: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, text: String, size: Int32, weight: CName, color: HDRColor) -> ref<inkText> {
    let t = new inkText();
    t.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    t.SetFontStyle(weight);
    t.SetFontSize(size);
    t.SetLetterCase(textLetterCase.UpperCase);
    t.SetAnchor(anchor);
    t.SetMargin(CMPilotHud.Edge(anchor, x, y));
    t.SetTintColor(color);
    t.SetText(text);
    t.Reparent(parent);
    return t;
  }

  public static func Box(parent: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
    let r = new inkRectangle();
    r.SetAnchor(anchor);
    r.SetMargin(CMPilotHud.Edge(anchor, x, y));
    r.SetSize(Vector2(w, h));
    r.SetTintColor(color);
    r.SetOpacity(opacity);
    r.Reparent(parent);
    return r;
  }

  // a rectangle at an absolute position inside a canvas
  public static func Bar(parent: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
    let r = new inkRectangle();
    r.SetMargin(inkMargin(x, y, 0.0, 0.0));
    r.SetSize(Vector2(w, h));
    r.SetTintColor(color);
    r.SetOpacity(opacity);
    r.Reparent(parent);
    return r;
  }

  // x/y measured in from the anchored edge(s)
  private static func Edge(anchor: inkEAnchor, x: Float, y: Float) -> inkMargin {
    switch anchor {
      case inkEAnchor.TopRight:
        return inkMargin(0.0, y, x, 0.0);
      case inkEAnchor.BottomLeft:
        return inkMargin(x, 0.0, 0.0, y);
      case inkEAnchor.BottomRight:
        return inkMargin(0.0, 0.0, x, y);
      case inkEAnchor.BottomCenter:
      case inkEAnchor.BottomFillHorizontaly:
        return inkMargin(x, 0.0, 0.0, y);
    }
    return inkMargin(x, y, 0.0, 0.0);
  }

  public static func Pad4(v: Int32) -> String {
    if v < 10 { return "000" + IntToString(v); }
    if v < 100 { return "00" + IntToString(v); }
    if v < 1000 { return "0" + IntToString(v); }
    return IntToString(v);
  }

  public static func Pad3(v: Int32) -> String {
    if v < 10 { return "00" + IntToString(v); }
    if v < 100 { return "0" + IntToString(v); }
    return IntToString(v);
  }

  public static func Cardinal(h: Int32) -> String {
    let i = RoundF(Cast<Float>(h) / 45.0) % 8;
    switch i {
      case 0: return "N";
      case 1: return "NE";
      case 2: return "E";
      case 3: return "SE";
      case 4: return "S";
      case 5: return "SW";
      case 6: return "W";
    }
    return "NW";
  }
}

// What the HUD shows, filled by CMPilotSystem each slow tick
public class CMPilotHudState {
  public let title: String;
  public let heading: Int32;
  public let range: Float;
  public let zoomed: Bool;
  public let missile: String;   // the secondary's status line ("MSL READY", "MSL 4S"), empty when there is none
  public let integrity: Float;
  public let signal: Float;
  public let distance: Float;
  public let speed: Float;
  public let fireMode: Int32;
  public let heatL: Float;
  public let heatR: Float;
  public let lockedL: Bool;
  public let lockedR: Bool;
  public let hasL: Bool;
  public let hasR: Bool;
  public let warning: String;
  public let hints: String;
  public let debug: String;
}
