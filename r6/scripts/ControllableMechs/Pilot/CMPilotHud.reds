// =============================================================================
// CONTROLLABLE MECHS - PILOT HUD (Militech neural-link overlay)
//
// Built once on the game's HUD layer when piloting starts and removed when it
// ends. While it's up, the vanilla HUD is faded out (and restored exactly as it
// was). Values update ten times a second from the pilot session; per frame only
// the compass tape, the gun reticles and the heat cells are touched, and only
// when they change.
//
// The art is the game's own, referenced by path (nothing is shipped or edited):
//   - the Basilisk tank HUD atlas (panzer_hud): the cut-corner glass of the two
//     plates, the tick ruler under the bars, the hatch blocks of the warning panel
//   - the Militech turret HUD atlas (turret_hud): the hairline frames above and
//     below each plate
//   - shadow_blobs: the soft shadow under the plates, the glow behind the main
//     readouts, the vignette
// The motion (idle flicker, damage jolt and red flash, hit markers, hot-gun pulse,
// warning sweep) is ink
// animations started on events: the engine runs them, no script runs per frame.
// =============================================================================
module ControllableMechs

import Codeware.UI.ScreenHelper
import ControllableMechs.Control.*

// A bar of cells that light up left to right; the last lit cell fades in by quarters.
// Widgets are only touched when the quarter count or the colour changes.
public class CMHudCells {
  public let box: ref<inkCanvas>;
  public let cells: array<ref<inkRectangle>>;
  private let m_quarters: Int32;   // stored + 1, so 0 means "never set"
  private let m_state: Int32;
  private let m_pulse: ref<inkAnimProxy>;

  // state: 0 nominal, 1 caution, 2 critical
  public func Set(frac: Float, state: Int32) -> Void {
    let n = ArraySize(this.cells);
    let q = RoundF(ClampF(frac, 0.0, 1.0) * Cast<Float>(n) * 4.0);
    if q + 1 == this.m_quarters && state == this.m_state {
      return;
    }
    this.m_quarters = q + 1;
    this.m_state = state;
    let color = state == 2 ? CMPilotHud.Red() : (state == 1 ? CMPilotHud.Caution() : CMPilotHud.Amber());
    let full = q / 4;
    let rem = q % 4;
    let i = 0;
    while i < n {
      if i < full {
        this.cells[i].SetTintColor(color);
        this.cells[i].SetOpacity(0.95);
      } else {
        if i == full && rem > 0 {
          this.cells[i].SetTintColor(color);
          this.cells[i].SetOpacity(0.3 + 0.65 * Cast<Float>(rem) / 4.0);
        } else {
          this.cells[i].SetTintColor(CMPilotHud.Dim());
          this.cells[i].SetOpacity(0.3);
        }
      }
      i += 1;
    }
  }

  // the whole bar throbs while on, and rests at full brightness when off
  public func Pulse(on: Bool) -> Void {
    if on && !IsDefined(this.m_pulse) {
      this.m_pulse = CMPilotHud.Loop(this.box, 1.0, 0.45, 0.22);
    }
    if !on && IsDefined(this.m_pulse) {
      this.m_pulse.Stop();
      this.m_pulse = null;
      this.box.SetOpacity(1.0);
    }
  }
}

public class CMPilotHud {
  private let m_root: ref<inkCanvas>;
  private let m_face: ref<inkCanvas>;    // everything but the sight: it flickers and jolts as one
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
  private let m_integrityText: ref<inkText>;
  private let m_signalText: ref<inkText>;
  private let m_hull: ref<CMHudCells>;
  private let m_heatL: ref<CMHudCells>;
  private let m_heatR: ref<CMHudCells>;
  private let m_stateL: ref<inkText>;
  private let m_stateR: ref<inkText>;
  private let m_markL: ref<inkRectangle>;
  private let m_markR: ref<inkRectangle>;
  private let m_markLOn: Bool;
  private let m_markROn: Bool;
  private let m_reticle: ref<inkCanvas>;
  // where each barrel points: a small ring, placed from the centre in 4K units
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
  private let m_warnSweep: ref<inkRectangle>;
  private let m_warnOn: Bool;
  private let m_warnPulse: ref<inkAnimProxy>;
  private let m_warnSweepAnim: ref<inkAnimProxy>;
  private let m_msl: ref<inkText>;
  private let m_hurt: ref<inkImage>;             // the red edge flash on a hit
  private let m_hitDirs: array<ref<inkCanvas>>;   // where hits come from
  private let m_hitNext: Int32;
  private let TAPE_Y: Float = 50.0;
  private let TAPE_SPACING: Float = 165.0;   // px per 15 deg
  private let PITCH_PX: Float = 6.0;         // px per degree on the elevation ladder
  private let m_hitBars: array<ref<inkRectangle>>;
  private let m_parts: array<ref<CMHudPart>>;     // the damage schematic, one per CMPart
  private let m_sensor: Float;                    // the sensor's integrity: below half, the display suffers
  private let m_schem: ref<inkCanvas>;            // the schematic, shown only for a unit that reports parts
  private let m_hitT: Float;

  private let BAR_W: Float = 415.0;          // 20 cells of 16 with 5 between
  private let PLATE_W: Float = 620.0;
  private let PLATE_X: Float = 200.0;        // plate edge to screen edge
  private let PLATE_GAP: Float = 160.0;      // plate bottom to screen bottom

  // The palette: a phosphor fire-control display. Amber() is the primary (kept by name for
  // its callers): phosphor green. Caution() is the amber of keys, warnings and heat. The
  // values just over 1 pick up the game's HUD bloom, like its own HUD colours do.
  public static func Amber() -> HDRColor = new HDRColor(0.34, 1.02, 0.46, 1.0)
  public static func Dim() -> HDRColor = new HDRColor(0.14, 0.45, 0.22, 1.0)
  public static func Red() -> HDRColor = new HDRColor(1.18, 0.30, 0.22, 1.0)
  public static func Pale() -> HDRColor = new HDRColor(0.80, 0.96, 0.82, 1.0)
  public static func Caution() -> HDRColor = new HDRColor(1.10, 0.64, 0.14, 1.0)
  public static func Steel() -> HDRColor = new HDRColor(0.015, 0.06, 0.035, 1.0)
  public static func Black() -> HDRColor = new HDRColor(0.0, 0.0, 0.0, 1.0)
  public static func Grey() -> HDRColor = new HDRColor(0.40, 0.43, 0.41, 1.0)

  // the game's own HUD art
  public static func Panzer() -> ResRef = r"base\\gameplay\\gui\\widgets\\tank_hud\\panzer_hud.inkatlas"
  public static func Turret() -> ResRef = r"base\\gameplay\\gui\\widgets\\turret_hud\\turret_hud.inkatlas"
  public static func Blobs() -> ResRef = r"base\\gameplay\\gui\\common\\shadow_blobs.inkatlas"

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
    root.SetInteractive(false);
    // The HUD layer's window is in real screen pixels, and everything here is laid out on
    // a 2160-high screen like the game's own HUD. So the root is that design space (as
    // wide as the screen's shape makes it) scaled down to the real height, and the HUD is
    // the same size relative to the screen on 1080p, 1440p, 4K and ultrawide.
    let screen = ScreenHelper.GetScreenSize(GetGameInstance());
    if screen.Y > 100.0 {
      let k = screen.Y / 2160.0;
      root.SetAnchor(inkEAnchor.TopLeft);
      root.SetSize(Vector2(screen.X / k, 2160.0));
      root.SetRenderTransformPivot(Vector2(0.0, 0.0));
      root.SetScale(Vector2(k, k));
    } else {
      root.SetAnchor(inkEAnchor.Fill);
    }
    root.Reparent(window);
    this.m_root = root;

    let face = new inkCanvas();
    face.SetAnchor(inkEAnchor.Fill);
    face.SetInteractive(false);
    face.Reparent(root);
    this.m_face = face;

    this.BuildBackdrop(face);
    this.BuildFrame(face);
    this.BuildReticle(root);
    this.BuildTop(face);
    this.BuildGuns(face, root);    // first: its key tags take indices 0-3, the chassis plate's 4-5
    this.BuildLeft(face);
    this.BuildParts(face);
    this.BuildRight(face);
    this.BuildEffects(root);
    this.Flicker();
    return true;
  }

  public func Remove() -> Void {
    if IsDefined(this.m_root) && IsDefined(this.m_parent) {
      // every running animation stopped before the widgets go: the root's, the display's
      // flicker, and the schematic's blinks and hit flashes
      this.m_root.StopAllAnimations();
      if IsDefined(this.m_face) {
        this.m_face.StopAllAnimations();
      }
      for p in this.m_parts {
        if IsDefined(p) && IsDefined(p.canvas) {
          p.canvas.StopAllAnimations();
        }
      }
      for m in this.m_hitDirs {
        if IsDefined(m) {
          m.StopAllAnimations();
        }
      }
      if IsDefined(this.m_warnPulse) {
        this.m_warnPulse.Stop();
      }
      if IsDefined(this.m_warnSweepAnim) {
        this.m_warnSweepAnim.Stop();
      }
      if IsDefined(this.m_hurt) {
        this.m_hurt.StopAllAnimations();
      }
      this.m_parent.RemoveChild(this.m_root);
    }
    ArrayClear(this.m_parts);
    ArrayClear(this.m_hitDirs);
    this.m_root = null;
    this.m_face = null;
    this.m_warnPulse = null;
    this.m_warnSweepAnim = null;
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
  // Behind everything: the glass darkens toward the screen edges, and a faint scanline
  // every 36 px. Static (built once, never touched again).
  private func BuildBackdrop(root: ref<inkCanvas>) -> Void {
    let v = CMPilotHud.Img(root, inkEAnchor.Fill, 0.0, 0.0, 0.0, 0.0, CMPilotHud.Blobs(), n"vignette", CMPilotHud.Black(), 0.4);
    v.SetAnchor(inkEAnchor.Fill);
    let y = 0.0;
    while y < 2160.0 {
      CMPilotHud.Box(root, inkEAnchor.TopFillHorizontaly, 0.0, y, 0.0, 3.0, CMPilotHud.Black(), 0.05);
      y += 36.0;
    }
  }

  // The frame is four fine corner brackets and nothing else: the display is sparse on
  // purpose (the compass tape, the sight, one chassis plate, one weapons plate).
  private func BuildFrame(root: ref<inkCanvas>) -> Void {
    this.Corner(root, inkEAnchor.TopLeft, 1.0, 1.0);
    this.Corner(root, inkEAnchor.TopRight, -1.0, 1.0);
    this.Corner(root, inkEAnchor.BottomLeft, 1.0, -1.0);
    this.Corner(root, inkEAnchor.BottomRight, -1.0, -1.0);
  }

  // On top of everything: the red edge flash a hit throws on the display, the markers that
  // show where hits come from (all hidden until a hit plays them), and the boot text
  // (StartBoot / Boot run it).
  private func BuildEffects(root: ref<inkCanvas>) -> Void {
    this.m_hurt = CMPilotHud.Img(root, inkEAnchor.Fill, 0.0, 0.0, 0.0, 0.0, CMPilotHud.Blobs(), n"vignette", CMPilotHud.Red(), 0.0);
    let i = 0;
    while i < 4 {
      ArrayPush(this.m_hitDirs, this.HitMarker(root));
      i += 1;
    }
    this.m_boot = CMPilotHud.Label(root, inkEAnchor.Centered, 0.0, -330.0, "", 34, n"Semi-Bold", CMPilotHud.Amber());
    this.m_boot.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_boot.SetVisible(false);
  }

  // one direction marker: a heavy chevron with a thin arc bar behind it, pointing outward
  // from the sight toward whoever fired; placed and turned by HitFrom
  private func HitMarker(root: ref<inkCanvas>) -> ref<inkCanvas> {
    let c = new inkCanvas();
    c.SetAnchor(inkEAnchor.Centered);
    c.SetAnchorPoint(Vector2(0.5, 0.5));
    c.SetSize(Vector2(240.0, 80.0));
    c.SetRenderTransformPivot(Vector2(0.5, 0.5));
    c.SetOpacity(0.0);
    c.Reparent(root);
    CMPilotHud.Bar(c, 20.0, 54.0, 200.0, 5.0, CMPilotHud.Red(), 0.6);
    let l = CMPilotHud.Bar(c, 76.0, 22.0, 52.0, 12.0, CMPilotHud.Red(), 1.0);
    l.SetRotation(-32.0);
    let r = CMPilotHud.Bar(c, 112.0, 22.0, 52.0, 12.0, CMPilotHud.Red(), 1.0);
    r.SetRotation(32.0);
    return c;
  }
  // The display's idle flicker: two short dips in brightness every 5.5 s, looped by the
  // engine for as long as the HUD is up.
  private func Flicker() -> Void {
    let def = new inkAnimDef();
    def.AddInterpolator(CMPilotHud.Fade(1.0, 0.72, 0.04, 4.20));
    def.AddInterpolator(CMPilotHud.Fade(0.72, 1.0, 0.05, 4.24));
    def.AddInterpolator(CMPilotHud.Fade(1.0, 0.86, 0.03, 4.45));
    def.AddInterpolator(CMPilotHud.Fade(0.86, 1.0, 0.05, 4.48));
    def.AddInterpolator(CMPilotHud.Fade(1.0, 1.0, 1.0, 4.53));
    let opt: inkAnimOptions;
    opt.loopType = inkanimLoopType.Cycle;
    opt.loopInfinite = true;
    this.m_face.PlayAnimationWithOptions(def, opt);
  }

  // The mech took damage: the screen edges flash red and the display jolts, harder the
  // more hull the hit took (`lost` is the fraction of the hull lost since the last reading;
  // 8% or more is the full effect). Two short engine animations per hit.
  public func Damage(lost: Float) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    let k = ClampF(lost * 12.0, 0.25, 1.0);
    let jolt = new inkAnimDef();
    let move = new inkAnimTranslation();
    move.SetStartTranslation(Vector2(RandRangeF(-30.0, 30.0) * k, RandRangeF(-12.0, 12.0) * k));
    move.SetEndTranslation(Vector2(0.0, 0.0));
    move.SetDuration(0.14 + 0.12 * k);
    move.SetType(inkanimInterpolationType.Quadratic);
    move.SetMode(inkanimInterpolationMode.EasyOut);
    jolt.AddInterpolator(move);
    this.m_face.PlayAnimation(jolt);
    let flash = new inkAnimDef();
    flash.AddInterpolator(CMPilotHud.Fade(0.25 + 0.5 * k, 0.0, 0.35 + 0.35 * k, 0.0));
    this.m_hurt.PlayAnimation(flash);
  }

  // A hit on the mech from `off` degrees off the view (positive = to the left, 180 =
  // behind): a red chevron on a ring round the sight points toward it and fades over a
  // second. Four markers are reused in turn.
  public func HitFrom(off: Float) -> Void {
    if !IsDefined(this.m_root) || ArraySize(this.m_hitDirs) == 0 || this.m_sensor <= 0.0 {
      return;
    }
    let m = this.m_hitDirs[this.m_hitNext];
    this.m_hitNext = (this.m_hitNext + 1) % ArraySize(this.m_hitDirs);
    let a = Deg2Rad(off);
    m.SetMargin(inkMargin(-SinF(a) * 330.0, -CosF(a) * 330.0, 0.0, 0.0));
    m.SetRotation(-off);
    let fade = new inkAnimDef();
    fade.AddInterpolator(CMPilotHud.Fade(1.0, 1.0, 0.35, 0.0));
    fade.AddInterpolator(CMPilotHud.Fade(1.0, 0.0, 0.8, 0.35));
    m.PlayAnimation(fade);
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
  private let TAG_DIM: Float = 0.4;
  private let TAG_INTRO: Float = 7.0;    // seconds bright after the link comes up (boot included)
  private let TAG_FLASH: Float = 1.2;    // seconds bright after its key is used

  public static func TagFire() -> Int32 = 0
  public static func TagMode() -> Int32 = 1
  public static func TagMissile() -> Int32 = 2
  public static func TagZoom() -> Int32 = 3
  public static func TagView() -> Int32 = 4

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

  // a status line with its key in front: readable at rest, brighter when the key is used
  private func StatusTag(root: ref<inkCanvas>, x: Float, y: Float, text: String) -> ref<inkText> {
    let t = this.Tag(root, inkEAnchor.BottomRight, x, y, text, true);
    t.SetFontSize(30);
    t.SetTintColor(CMPilotHud.Amber());
    this.m_tagDim[ArraySize(this.m_tagDim) - 1] = 0.85;
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

  // A plate behind a block of readouts, from the game's own HUD art: a soft shadow, the
  // Basilisk HUD's cut-corner glass (solid at the screen edge, fading toward the middle)
  // and the Militech turret HUD's hairline frames above and below. `y` is the plate's top,
  // measured up from the bottom of the screen; right-hand plates are mirrored.
  private func Plate(root: ref<inkCanvas>, right: Bool, x: Float, y: Float, w: Float, h: Float) -> Void {
    let anchor = right ? inkEAnchor.BottomRight : inkEAnchor.BottomLeft;
    let pieces: array<ref<inkImage>>;
    ArrayPush(pieces, CMPilotHud.Img(root, anchor, x - 90.0, y + 80.0, w + 180.0, h + 160.0, CMPilotHud.Blobs(), n"shadowBlobSquare_big", CMPilotHud.Black(), 0.55));
    ArrayPush(pieces, CMPilotHud.Img(root, anchor, x, y, w, h, CMPilotHud.Panzer(), n"ramp", CMPilotHud.Steel(), 0.92));
    ArrayPush(pieces, CMPilotHud.Img(root, anchor, x, y + 30.0, w, 34.0, CMPilotHud.Turret(), n"frame_top", CMPilotHud.Amber(), 0.9));
    ArrayPush(pieces, CMPilotHud.Img(root, anchor, x, y - h + 4.0, w, 42.0, CMPilotHud.Turret(), n"frame_bottom", CMPilotHud.Amber(), 0.9));
    if right {
      for p in pieces {
        p.SetAnchorPoint(Vector2(1.0, 0.0));
        p.SetBrushMirrorType(inkBrushMirrorType.Horizontal);
      }
    }
  }

  // A bar of `n` cells in its own canvas (so the whole bar can pulse), with the Basilisk
  // HUD's tick ruler under it. `y` is the bar's top, measured up from the screen bottom.
  private func CellBar(root: ref<inkCanvas>, right: Bool, x: Float, y: Float, h: Float) -> ref<CMHudCells> {
    let anchor = right ? inkEAnchor.BottomRight : inkEAnchor.BottomLeft;
    let bar = new CMHudCells();
    let box = new inkCanvas();
    box.SetAnchor(anchor);
    box.SetAnchorPoint(Vector2(right ? 1.0 : 0.0, 0.0));
    box.SetMargin(CMPilotHud.Edge(anchor, x, y));
    box.SetSize(Vector2(this.BAR_W, h));
    box.Reparent(root);
    bar.box = box;
    let i = 0;
    while i < 20 {
      ArrayPush(bar.cells, CMPilotHud.Bar(box, Cast<Float>(i) * 21.0, 0.0, 16.0, h, CMPilotHud.Dim(), 0.3));
      i += 1;
    }
    let ruler = CMPilotHud.Img(root, anchor, x, y - h - 8.0, this.BAR_W, 10.0, CMPilotHud.Panzer(), n"gauge_hp", CMPilotHud.Dim(), 0.9);
    if right {
      ruler.SetAnchorPoint(Vector2(1.0, 0.0));
    }
    return bar;
  }

  // the soft glow behind a main readout (left-anchored text `w` wide, or right-anchored)
  private func Glow(root: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, w: Float, h: Float, color: HDRColor) -> ref<inkImage> {
    let g = CMPilotHud.Img(root, anchor, x, y, w, h, CMPilotHud.Blobs(), n"shadowBlobText", color, 0.2);
    if Equals(anchor, inkEAnchor.BottomRight) || Equals(anchor, inkEAnchor.TopRight) {
      g.SetAnchorPoint(Vector2(1.0, 0.0));
    }
    if Equals(anchor, inkEAnchor.TopCenter) || Equals(anchor, inkEAnchor.Centered) {
      g.SetAnchorPoint(Vector2(0.5, 0.0));
    }
    return g;
  }

  private func Corner(root: ref<inkCanvas>, anchor: inkEAnchor, sx: Float, sy: Float) -> Void {
    let inset = 80.0;   // clear of the screen edge on any aspect ratio
    let len = 170.0;
    let t = 6.0;
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
    // the sight: four arms with a wide centre gap and a chevron at the aim point
    CMPilotHud.Bar(r, 200.0 - 4.0, 200.0 - 110.0, 8.0, 60.0, c, 0.95);   // up
    CMPilotHud.Bar(r, 200.0 - 4.0, 200.0 + 50.0, 8.0, 60.0, c, 0.95);    // down
    CMPilotHud.Bar(r, 200.0 - 150.0, 200.0 - 4.0, 100.0, 8.0, c, 0.95);  // left
    CMPilotHud.Bar(r, 200.0 + 50.0, 200.0 - 4.0, 100.0, 8.0, c, 0.95);   // right
    let cl = CMPilotHud.Bar(r, 200.0 - 17.0, 200.0 + 3.0, 22.0, 5.0, CMPilotHud.Pale(), 1.0);
    cl.SetRotation(-38.0);
    let cr = CMPilotHud.Bar(r, 200.0 - 5.0, 200.0 + 3.0, 22.0, 5.0, CMPilotHud.Pale(), 1.0);
    cr.SetRotation(38.0);
    // hit marker: four short diagonals round the centre, shown when a round connects
    for sx in [-1.0, 1.0] {
      for sy in [-1.0, 1.0] {
        let d = CMPilotHud.Bar(r, 200.0 + sx * 34.0 - 12.0, 200.0 + sy * 34.0 - 3.0, 24.0, 6.0, CMPilotHud.Pale(), 0.0);
        d.SetRotation(sx * sy > 0.0 ? 45.0 : -45.0);
        ArrayPush(this.m_hitBars, d);
      }
    }
    // barrel markers at the ends of the side arms: light up when that gun fires
    this.m_markL = CMPilotHud.Bar(r, 200.0 - 166.0, 200.0 - 30.0, 8.0, 60.0, c, 0.35);
    this.m_markR = CMPilotHud.Bar(r, 200.0 + 158.0, 200.0 - 30.0, 8.0, 60.0, c, 0.35);
    // each gun's own reticle (hidden until the unit places them)
    this.m_pipL = this.GunReticle(root, true);
    this.m_pipR = this.GunReticle(root, false);
    // the rangefinder box under the sight, the zoom key beside it, the optics line below
    this.Glow(root, inkEAnchor.Centered, 0.0, 156.0, 420.0, 76.0, c);
    this.m_range = CMPilotHud.Label(root, inkEAnchor.Centered, 0.0, 170.0, "[ LRF ---- M ]", 38, n"Semi-Bold", c);
    this.m_range.SetAnchorPoint(Vector2(0.5, 0.0));
    this.m_zoom = CMPilotHud.Label(root, inkEAnchor.Centered, 0.0, 262.0, "", 26, n"Semi-Bold", CMPilotHud.Dim());
    this.m_zoom.SetAnchorPoint(Vector2(0.5, 0.0));
  }

  private let m_ladder: ref<inkCanvas>;

  private func BuildTop(root: ref<inkCanvas>) -> Void {
    // the unit, once, small, in the top-left corner
    this.m_title = CMPilotHud.Label(root, inkEAnchor.TopLeft, 200.0, 110.0, "MILITECH MINOTAUR", 26, n"Semi-Bold", CMPilotHud.Dim());

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
    this.Glow(root, inkEAnchor.TopCenter, 0.0, 126.0, 420.0, 76.0, CMPilotHud.Pale());
    this.m_heading = CMPilotHud.Label(root, inkEAnchor.TopCenter, 0.0, 140.0, "[ HDG 000 N ]", 38, n"Semi-Bold", CMPilotHud.Pale());
    this.m_heading.SetAnchorPoint(Vector2(0.5, 0.0));

    // The warning panel: dark glass between two red rules, the Basilisk HUD's hatch
    // blocks either end, and a bright bar that sweeps across it. Shown only while there
    // is a warning; its pulse and sweep are two engine animations that run only then.
    let wp = new inkCanvas();
    wp.SetAnchor(inkEAnchor.TopCenter);
    wp.SetAnchorPoint(Vector2(0.5, 0.0));
    wp.SetSize(Vector2(2.0, 2.0));
    wp.SetMargin(inkMargin(0.0, 230.0, 0.0, 0.0));
    wp.SetVisible(false);
    wp.Reparent(root);
    let shadow = CMPilotHud.Img(wp, inkEAnchor.TopLeft, -620.0, -40.0, 1240.0, 160.0, CMPilotHud.Blobs(), n"shadowBlobSquare_big", CMPilotHud.Black(), 0.6);
    shadow.SetAnchor(inkEAnchor.TopLeft);
    CMPilotHud.Bar(wp, -560.0, 0.0, 1120.0, 74.0, CMPilotHud.Steel(), 0.85);
    CMPilotHud.Bar(wp, -560.0, 0.0, 1120.0, 4.0, CMPilotHud.Red(), 0.95);
    CMPilotHud.Bar(wp, -560.0, 70.0, 1120.0, 4.0, CMPilotHud.Red(), 0.95);
    CMPilotHud.Img(wp, inkEAnchor.TopLeft, -546.0, 14.0, 220.0, 46.0, CMPilotHud.Panzer(), n"gauge_boost", CMPilotHud.Caution(), 0.9);
    let hr = CMPilotHud.Img(wp, inkEAnchor.TopLeft, 326.0, 14.0, 220.0, 46.0, CMPilotHud.Panzer(), n"gauge_boost", CMPilotHud.Caution(), 0.9);
    hr.SetBrushMirrorType(inkBrushMirrorType.Horizontal);
    this.m_warnSweep = CMPilotHud.Bar(wp, -40.0, 4.0, 80.0, 66.0, CMPilotHud.Red(), 0.22);
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

  // The chassis plate, bottom left: the hull as a bar of twenty cells, the uplink and
  // ground speed on one small line, and the view and disconnect keys.
  private func BuildLeft(root: ref<inkCanvas>) -> Void {
    let h = 300.0;
    let top = this.PLATE_GAP + h;          // the plate's top, up from the screen bottom
    let x = this.PLATE_X + 60.0;           // the text column
    this.Plate(root, false, this.PLATE_X, top, this.PLATE_W, h);
    this.Glow(root, inkEAnchor.BottomLeft, x - 30.0, top - 14.0, 300.0, 76.0, CMPilotHud.Amber());
    this.m_integrityText = CMPilotHud.Label(root, inkEAnchor.BottomLeft, x, top - 28.0, "HULL 100%", 40, n"Semi-Bold", CMPilotHud.Amber());
    this.m_hull = this.CellBar(root, false, x, top - 88.0, 28.0);
    this.m_signalText = CMPilotHud.Label(root, inkEAnchor.BottomLeft, x, top - 150.0, "UPLINK", 26, n"Medium", CMPilotHud.Pale());
    this.m_speed = CMPilotHud.Label(root, inkEAnchor.BottomLeft, x + 240.0, top - 150.0, "GND 0.0 M/S", 26, n"Medium", CMPilotHud.Pale());
    this.Tag(root, inkEAnchor.BottomLeft, x, top - 218.0, "[V] VIEW", false);                  // TagView = 4
    this.Tag(root, inkEAnchor.BottomLeft, x + 190.0, top - 218.0, "[\\] DISCONNECT", false);   // tag 5
  }

  // The damage schematic, above the chassis plate: the Minotaur's own model, wireframed in
  // a straight front view (flipped, so its left gun is on the left) and cut into its seven
  // parts, each a white layer of the mod's atlas (archive/pc/mod/MechsOfNightCity.archive,
  // built by tools/schematic) tinted by its damage. The pods sit behind the torso and
  // show through it. Built once; a part is only touched when its value changes (SetPart)
  // or it is hit (PartHit).
  public static func Schematic() -> ResRef = r"mnc\\hud\\minotaur_schematic.inkatlas"

  private func BuildParts(root: ref<inkCanvas>) -> Void {
    ArrayClear(this.m_parts);
    ArrayResize(this.m_parts, CMPart.Count());
    this.m_sensor = 1.0;
    let k = 0.62;                               // atlas pixels to design units
    let w = 689.0 * k;
    let h = 768.0 * k;
    let top = this.PLATE_GAP + 300.0 + h + 30.0;   // above the chassis plate
    let x = this.PLATE_X + 40.0;
    let holder = new inkCanvas();
    holder.SetAnchor(inkEAnchor.Fill);
    holder.SetInteractive(false);
    holder.Reparent(root);
    holder.SetVisible(false);   // until a unit reports its parts (Refresh)
    this.m_schem = holder;
    this.Glow(holder, inkEAnchor.BottomLeft, x - 60.0, top + 40.0, w + 120.0, h + 80.0, CMPilotHud.Black());
    let box = new inkCanvas();
    box.SetAnchor(inkEAnchor.BottomLeft);
    box.SetMargin(CMPilotHud.Edge(inkEAnchor.BottomLeft, x, top));
    box.SetSize(Vector2(w, h));
    box.SetInteractive(false);
    box.Reparent(holder);
    CMPilotHud.Label(holder, inkEAnchor.BottomLeft, x + w + 10.0, top - h + 30.0, "CHASSIS", 22, n"Medium", CMPilotHud.Dim());
    // back to front; the offsets and sizes are the layers' place in the 689 x 768 front view
    // (tools/schematic writes them to layout.reds.txt)
    this.PartLayer(box, k, CMPart.Pods(), n"pods", 188.0, 162.0, 318.0, 159.0);
    this.PartLayer(box, k, CMPart.LegL(), n"leg_l", 167.0, 262.0, 150.0, 502.0);
    this.PartLayer(box, k, CMPart.LegR(), n"leg_r", 373.0, 262.0, 150.0, 502.0);
    this.PartLayer(box, k, CMPart.Torso(), n"torso", 140.0, 59.0, 410.0, 409.0);
    this.PartLayer(box, k, CMPart.ArmL(), n"arm_l", 4.0, 64.0, 186.0, 174.0);
    this.PartLayer(box, k, CMPart.ArmR(), n"arm_r", 499.0, 64.0, 186.0, 174.0);
    this.PartLayer(box, k, CMPart.Sensor(), n"sensor", 252.0, 4.0, 187.0, 136.0);
  }

  // one part: its layer of the atlas
  private func PartLayer(box: ref<inkCanvas>, k: Float, i: Int32, texture: CName, x: Float, y: Float, w: Float, h: Float) -> Void {
    let p = new CMHudPart();
    p.hp = -1.0;
    p.canvas = new inkCanvas();
    p.canvas.SetMargin(inkMargin(x * k, y * k, 0.0, 0.0));
    p.canvas.SetSize(Vector2(w * k, h * k));
    p.canvas.SetInteractive(false);
    p.canvas.Reparent(box);
    p.image = CMPilotHud.Img(p.canvas, inkEAnchor.TopLeft, 0.0, 0.0, w * k, h * k, CMPilotHud.Schematic(), texture, CMPilotHud.Amber(), 1.0);
    this.m_parts[i] = p;
  }
  // A part's integrity (0-1): green, amber below 70%, red below 35%, and greyed out once
  // broken, blinking for two seconds as it goes.
  private func SetPart(i: Int32, hp: Float) -> Void {
    if i >= ArraySize(this.m_parts) {
      return;
    }
    let p = this.m_parts[i];
    if AbsF(hp - p.hp) < 0.01 {
      return;
    }
    let broke = hp <= 0.0 && p.hp > 0.0;
    p.hp = hp;
    let color = hp <= 0.0 ? CMPilotHud.Grey() : (hp < 0.35 ? CMPilotHud.Red() : (hp < 0.7 ? CMPilotHud.Caution() : CMPilotHud.Amber()));
    p.image.SetTintColor(color);
    p.image.SetOpacity(hp <= 0.0 ? 0.7 : 1.0);   // broken: greyed out
    if broke {
      let blink = new inkAnimDef();
      let t = 0.0;
      while t < 2.0 {
        blink.AddInterpolator(CMPilotHud.Fade(1.0, 0.2, 0.2, t));
        blink.AddInterpolator(CMPilotHud.Fade(0.2, 1.0, 0.2, t + 0.2));
        t += 0.4;
      }
      p.canvas.PlayAnimation(blink);
    }
  }

  // The sensor's state on the display: once it is gone, the compass tape and the pitch
  // ladder go dark (no heading or attitude), and the hit-direction markers stop.
  private func SetSensor(hp: Float) -> Void {
    let was = this.m_sensor;
    this.m_sensor = hp;
    if NotEquals(hp <= 0.0, was <= 0.0) {
      this.m_tape.SetVisible(hp > 0.0);
      this.m_pitchMark.SetVisible(hp > 0.0);
    }
  }

  // a burst of static: the display drops out and jolts for a moment
  private func Static() -> Void {
    let def = new inkAnimDef();
    def.AddInterpolator(CMPilotHud.Fade(1.0, 0.15, 0.03, 0.0));
    def.AddInterpolator(CMPilotHud.Fade(0.15, 0.8, 0.05, 0.03));
    def.AddInterpolator(CMPilotHud.Fade(0.8, 0.3, 0.04, 0.08));
    def.AddInterpolator(CMPilotHud.Fade(0.3, 1.0, 0.1, 0.12));
    let move = new inkAnimTranslation();
    move.SetStartTranslation(Vector2(RandRangeF(-18.0, 18.0), RandRangeF(-6.0, 6.0)));
    move.SetEndTranslation(Vector2(0.0, 0.0));
    move.SetDuration(0.2);
    def.AddInterpolator(move);
    this.m_root.PlayAnimation(def);
  }

  // a part that just took a hit flashes, so you can see what is being hit
  public func PartHit(i: Int32) -> Void {
    if !IsDefined(this.m_root) || i < 0 || i >= ArraySize(this.m_parts) {
      return;
    }
    let flash = new inkAnimDef();
    flash.AddInterpolator(CMPilotHud.Fade(0.2, 1.0, 0.3, 0.0));
    this.m_parts[i].canvas.PlayAnimation(flash);
  }

  // the operator's range, small, in the top-right corner
  private func BuildRight(root: ref<inkCanvas>) -> Void {
    this.m_link = CMPilotHud.Label(root, inkEAnchor.TopRight, 200.0, 110.0, "", 26, n"Semi-Bold", CMPilotHud.Dim());
    this.m_link.SetAnchorPoint(Vector2(1.0, 0.0));
  }

  // The weapons plate, bottom right: each MK.31's state over a bar of twenty heat cells,
  // then the fire mode and the missile with their keys, and the trigger. The zoom key sits
  // under the sight, on `sight` (the layer that doesn't flicker).
  private func BuildGuns(root: ref<inkCanvas>, sight: ref<inkCanvas>) -> Void {
    let h = 400.0;
    let top = this.PLATE_GAP + h;
    let x = this.PLATE_X + 60.0;
    this.Plate(root, true, this.PLATE_X, top, this.PLATE_W, h);
    // the four tags are pushed in index order: fire 0, mode 1, missile 2, zoom 3
    this.Tag(root, inkEAnchor.BottomRight, x, top - 322.0, "[LMB] FIRE", true);
    this.Glow(root, inkEAnchor.BottomRight, x - 30.0, top - 200.0, 420.0, 76.0, CMPilotHud.Amber());
    this.m_mode = this.StatusTag(root, x, top - 214.0, "[B] MODE STAGGERED");
    this.m_msl = this.StatusTag(root, x, top - 262.0, "[G] MSL READY");
    this.Tag(sight, inkEAnchor.Centered, 0.0, 222.0, "[RMB] ZOOM", false);

    this.m_stateL = CMPilotHud.Label(root, inkEAnchor.BottomRight, x, top - 26.0, "L  ARMED", 30, n"Semi-Bold", CMPilotHud.Pale());
    this.m_stateL.SetAnchorPoint(Vector2(1.0, 0.0));
    this.m_heatL = this.CellBar(root, true, x, top - 70.0, 24.0);
    this.m_stateR = CMPilotHud.Label(root, inkEAnchor.BottomRight, x, top - 112.0, "R  ARMED", 30, n"Semi-Bold", CMPilotHud.Pale());
    this.m_stateR.SetAnchorPoint(Vector2(1.0, 0.0));
    this.m_heatR = this.CellBar(root, true, x, top - 156.0, 24.0);
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

  // the optics: dark bands close in from the sides and a fine range scale sits
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
      let left = CMPilotHud.Box(o, inkEAnchor.LeftFillVerticaly, 0.0, 0.0, 700.0, 0.0, CMPilotHud.Black(), 0.8);
      let right = CMPilotHud.Box(o, inkEAnchor.RightFillVerticaly, 0.0, 0.0, 700.0, 0.0, CMPilotHud.Black(), 0.8);
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
  // reticle is tight and bright; converging it's larger and dim.
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
  // each gun's lock state, how many of its heat ticks are lit, and its heat cells on the
  // weapons plate (so the bars fill and drain smoothly, a quarter cell at a time)
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
    this.m_heatL.Set(heatL, heatL > 0.8 ? 2 : (heatL > 0.5 ? 1 : 0));
    this.m_heatR.Set(heatR, heatR > 0.8 ? 2 : (heatR > 0.5 ? 1 : 0));
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

  // ten times a second
  public func Refresh(s: ref<CMPilotHudState>) -> Void {
    if !IsDefined(this.m_root) {
      return;
    }
    this.m_title.SetText(s.title);
    if ArraySize(s.parts) > 0 {
      this.SetSensor(s.parts[CMPart.Sensor()]);
    }
    this.m_heading.SetText(this.m_sensor <= 0.0 ? "[ HDG --- ]" : "[ HDG " + CMPilotHud.Pad3(s.heading) + " " + CMPilotHud.Cardinal(s.heading) + " ]");
    // a damaged sensor throws static bursts on the display, more often once it is gone
    if this.m_sensor < 0.5 && RandF() < (this.m_sensor <= 0.0 ? 0.05 : 0.025) {
      this.Static();
    }
    this.m_range.SetText(s.range > 0.0 ? "[ LRF " + CMPilotHud.Pad4(RoundF(s.range)) + " M ]" : "[ LRF ---- M ]");
    this.m_zoom.SetText(s.zoomed ? "OPTICS 2.5X" : "");

    let low = s.integrity < 0.3;
    this.m_integrityText.SetText("HULL " + IntToString(RoundF(s.integrity * 100.0)) + "%" + (low ? "  CRITICAL" : ""));
    this.m_integrityText.SetTintColor(low ? CMPilotHud.Red() : CMPilotHud.Amber());
    this.m_hull.Set(s.integrity, low ? 2 : (s.integrity < 0.6 ? 1 : 0));
    this.m_hull.Pulse(low);
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

    this.Gun(this.m_heatL, this.m_stateL, "L  ", s.heatL, s.lockedL, s.hasL, s.lostL);
    this.Gun(this.m_heatR, this.m_stateR, "R  ", s.heatR, s.lockedR, s.hasR, s.lostR);
    // the Minotaur schematic only for a unit that reports its parts (not a drone)
    if IsDefined(this.m_schem) {
      this.m_schem.SetVisible(ArraySize(s.parts) == CMPart.Count());
    }
    let i = 0;
    while i < ArraySize(s.parts) {
      this.SetPart(i, s.parts[i]);
      i += 1;
    }

    this.m_warn.SetText(s.warning);
    this.Warn(StrLen(s.warning) > 0);
    this.m_msl.SetText(StrLen(s.missile) > 0 ? "[G] " + s.missile : "");
    this.m_msl.SetTintColor(StrContains(s.missile, "READY") ? CMPilotHud.Amber() : CMPilotHud.Caution());
  }

  // the warning panel: shown with its pulse and its sweep while there is a warning; the
  // two animations start when it appears and stop when it goes
  private func Warn(on: Bool) -> Void {
    if Equals(on, this.m_warnOn) {
      return;
    }
    this.m_warnOn = on;
    this.m_warnPlate.SetVisible(on);
    if on {
      this.m_warnPulse = CMPilotHud.Loop(this.m_warnPlate, 1.0, 0.6, 0.35);
      let def = new inkAnimDef();
      let move = new inkAnimTranslation();
      move.SetStartTranslation(Vector2(-520.0, 0.0));
      move.SetEndTranslation(Vector2(520.0, 0.0));
      move.SetDuration(1.1);
      move.SetType(inkanimInterpolationType.Linear);
      move.SetMode(inkanimInterpolationMode.EasyIn);
      def.AddInterpolator(move);
      let opt: inkAnimOptions;
      opt.loopType = inkanimLoopType.Cycle;
      opt.loopInfinite = true;
      this.m_warnSweepAnim = this.m_warnSweep.PlayAnimationWithOptions(def, opt);
    } else {
      if IsDefined(this.m_warnPulse) {
        this.m_warnPulse.Stop();
      }
      if IsDefined(this.m_warnSweepAnim) {
        this.m_warnSweepAnim.Stop();
      }
      this.m_warnPulse = null;
      this.m_warnSweepAnim = null;
    }
  }

  // ten times a second: a gun's state line, and its bar throbbing while it is near or past
  // overheat (the cells themselves are set every frame by SetGunState)
  private func Gun(bar: ref<CMHudCells>, state: ref<inkText>, side: String, heat: Float, locked: Bool, has: Bool, lost: Bool) -> Void {
    bar.Pulse(locked || heat > 0.8);
    if !has {
      state.SetText(side + (lost ? "MK.31 OFFLINE" : "NO WEAPON"));
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

  // one part of a game atlas, stretched to w x h and tinted
  public static func Img(parent: ref<inkCanvas>, anchor: inkEAnchor, x: Float, y: Float, w: Float, h: Float, atlas: ResRef, part: CName, color: HDRColor, opacity: Float) -> ref<inkImage> {
    let i = new inkImage();
    i.SetAtlasResource(atlas);
    i.SetTexturePart(part);
    i.SetAnchor(anchor);
    i.SetMargin(CMPilotHud.Edge(anchor, x, y));
    i.SetSize(Vector2(w, h));
    i.SetTintColor(color);
    i.SetOpacity(opacity);
    i.SetInteractive(false);
    i.Reparent(parent);
    return i;
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

  // one step of opacity: from -> to over `duration`, starting after `delay`
  public static func Fade(from: Float, to: Float, duration: Float, delay: Float) -> ref<inkAnimTransparency> {
    let a = new inkAnimTransparency();
    a.SetStartTransparency(from);
    a.SetEndTransparency(to);
    a.SetDuration(duration);
    a.SetStartDelay(delay);
    a.SetType(inkanimInterpolationType.Linear);
    a.SetMode(inkanimInterpolationMode.EasyIn);
    return a;
  }

  // an endless back-and-forth of a widget's opacity, run by the engine until stopped
  public static func Loop(widget: ref<inkWidget>, from: Float, to: Float, duration: Float) -> ref<inkAnimProxy> {
    let def = new inkAnimDef();
    def.AddInterpolator(CMPilotHud.Fade(from, to, duration, 0.0));
    let opt: inkAnimOptions;
    opt.loopType = inkanimLoopType.PingPong;
    opt.loopInfinite = true;
    return widget.PlayAnimationWithOptions(def, opt);
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

// What the HUD shows, filled by the pilot session and the unit each slow tick
public class CMPilotHudState {
  public let title: String;
  public let heading: Int32;
  public let range: Float;
  public let zoomed: Bool;
  public let missile: String;   // the secondary's status ("MSL READY", "MSL RELOAD 4S"), empty when there is none
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
  public let lostL: Bool;         // shot off (part damage)
  public let lostR: Bool;
  public let parts: array<Float>; // each CMPart's integrity, 0-1 (the torso is the hull)
  public let warning: String;
}

// one part on the damage schematic
public class CMHudPart {
  public let canvas: ref<inkCanvas>;
  public let image: ref<inkImage>;
  public let hp: Float;
}
