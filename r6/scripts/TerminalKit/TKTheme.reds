// =============================================================================
// TERMINAL KIT - THEME, SCALE AND INK HELPERS
// TKTheme: colour palettes by role (title, accent, text, value, frame, rule).
//   "hud" follows the game's own UI colours, so HUD recolour mods carry over;
//   the others are fixed palettes. TKTone: the row colour names.
// TKScale: the design tokens (type sizes, spacing) and the layout numbers the
//   renderer asks for by key, with a source the mod can plug in (a tuner, a
//   settings file). TKScale.T(text) runs text through the same source.
// TKInk: small widget builders. Everything stacks in panels, so no row needs
//   hand-placed coordinates.
// =============================================================================
module TerminalKit

public abstract class TKTheme {
  // Any widget, including one painted before (the frame's chrome on a palette change)
  public static func Paint(w: ref<inkWidget>, theme: String, role: String) -> Void {
    if !IsDefined(w) {
      return;
    }
    if Equals(theme, "") || Equals(theme, "hud") {
      w.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
      w.BindProperty(n"tintColor", TKTheme.HudColor(role));
      return;
    }
    // only ever unbind a binding that exists: unbinding on a widget without a
    // style or binding (e.g. a fresh divider line) crashed the game to desktop
    w.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    w.BindProperty(n"tintColor", TKTheme.HudColor(role));
    w.UnbindProperty(n"tintColor");
    w.SetTintColor(TKTheme.Color(theme, role));
  }

  // A widget built without a style (page rows, rebuilt on every draw): bind the
  // HUD colour, or just tint it. Half the property calls of Paint.
  public static func PaintNew(w: ref<inkWidget>, theme: String, role: String) -> Void {
    if Equals(theme, "") || Equals(theme, "hud") {
      w.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
      w.BindProperty(n"tintColor", TKTheme.HudColor(role));
    } else {
      w.SetTintColor(TKTheme.Color(theme, role));
    }
  }

  // A fixed status colour on a widget painted with PaintNew
  public static func Fix(w: ref<inkWidget>, theme: String, color: HDRColor) -> Void {
    if Equals(theme, "") || Equals(theme, "hud") {
      w.UnbindProperty(n"tintColor");   // bound by PaintNew
    }
    w.SetTintColor(color);
  }

  public static func HudColor(role: String) -> CName {
    switch role {
      case "accent": return n"MainColors.Red";
      case "text": return n"MainColors.PanelBlue";
      case "rule": return n"MainColors.DarkRed";
      default: return n"MainColors.Blue";
    }
  }

  // at most white: brighter-than-white (HDR) colours bloom, a soft halo on text
  public static func C(r: Float, g: Float, b: Float) -> HDRColor = new HDRColor(MinF(r, 1.0), MinF(g, 1.0), MinF(b, 1.0), 1.0)

  public static func Ids() -> array<String> = ["hud", "kiroshi", "arasaka", "militech", "netwatch", "mono"]

  public static func Color(theme: String, role: String) -> HDRColor {
    switch theme {
      case "kiroshi":   // cold optics cyan
        switch role {
          case "title": return TKTheme.C(0.37, 0.96, 1.19);
          case "accent": return TKTheme.C(0.55, 1.0, 1.1);
          case "text": return TKTheme.C(0.45, 0.72, 0.78);
          case "rule": return TKTheme.C(0.12, 0.38, 0.44);
          default: return TKTheme.C(0.85, 1.0, 1.0);
        }
      case "arasaka":   // red and white
        switch role {
          case "title": return TKTheme.C(1.0, 0.3, 0.28);
          case "accent": return TKTheme.C(1.0, 0.18, 0.18);
          case "text": return TKTheme.C(0.82, 0.72, 0.72);
          case "rule": return TKTheme.C(0.45, 0.07, 0.07);
          case "frame": return TKTheme.C(1.0, 0.25, 0.25);
          default: return TKTheme.C(1.0, 0.95, 0.95);
        }
      case "militech":  // amber
        switch role {
          case "title": return TKTheme.C(1.0, 0.72, 0.22);
          case "accent": return TKTheme.C(1.0, 0.55, 0.1);
          case "text": return TKTheme.C(0.85, 0.74, 0.52);
          case "rule": return TKTheme.C(0.45, 0.3, 0.08);
          default: return TKTheme.C(1.0, 0.88, 0.58);
        }
      case "netwatch":  // phosphor green
        switch role {
          case "title": return TKTheme.C(0.35, 1.0, 0.6);
          case "accent": return TKTheme.C(0.2, 0.9, 0.5);
          case "text": return TKTheme.C(0.55, 0.82, 0.66);
          case "rule": return TKTheme.C(0.08, 0.4, 0.22);
          default: return TKTheme.C(0.8, 1.0, 0.85);
        }
      case "mono":      // white on grey
        switch role {
          case "title": return TKTheme.C(1.0, 1.0, 1.0);
          case "accent": return TKTheme.C(0.9, 0.9, 0.9);
          case "text": return TKTheme.C(0.62, 0.62, 0.62);
          case "rule": return TKTheme.C(0.3, 0.3, 0.3);
          default: return TKTheme.C(0.95, 0.95, 0.95);
        }
      default:
        return TKTheme.C(0.37, 0.96, 1.19);
    }
  }

  // status colours that mean the same in every palette
  public static func Gain() -> HDRColor = new HDRColor(0.36, 0.94, 0.55, 1.0)
  public static func Loss() -> HDRColor = new HDRColor(1.0, 0.36, 0.33, 1.0)
  public static func Amber() -> HDRColor = new HDRColor(1.0, 0.72, 0.22, 1.0)
  public static func Gold() -> HDRColor = new HDRColor(1.0, 0.86, 0.35, 1.0)
  public static func Ink() -> HDRColor = new HDRColor(0.02, 0.03, 0.05, 1.0)

  // Row colour names on a widget painted with PaintNew: "blue" / "dim" / "red"
  // are palette roles, the rest are status colours ("" keeps the role it was
  // painted with)
  public static func Tone(w: ref<inkWidget>, theme: String, color: String) -> Void {
    switch color {
      case "blue": TKTheme.PaintNew(w, theme, "value"); break;
      case "dim": TKTheme.PaintNew(w, theme, "text"); break;
      case "red": TKTheme.PaintNew(w, theme, "accent"); break;
      case "yellow": TKTheme.Fix(w, theme, TKTheme.Gold()); break;
      case "green": TKTheme.Fix(w, theme, TKTheme.Gain()); break;
      case "grey": TKTheme.Fix(w, theme, new HDRColor(0.45, 0.45, 0.45, 1.0)); break;
      case "orange": TKTheme.Fix(w, theme, new HDRColor(1.0, 0.55, 0.15, 1.0)); break;
      case "purple": TKTheme.Fix(w, theme, new HDRColor(0.72, 0.36, 1.0, 1.0)); break;
      case "pink": TKTheme.Fix(w, theme, new HDRColor(1.0, 0.36, 0.76, 1.0)); break;
      case "cyan": TKTheme.Fix(w, theme, new HDRColor(0.15, 0.86, 0.8, 1.0)); break;
      case "white": TKTheme.Fix(w, theme, new HDRColor(0.92, 0.94, 0.96, 1.0)); break;
      case "amber": TKTheme.Fix(w, theme, TKTheme.Amber()); break;
      default: break;
    }
  }

  // the card marks: a leading "!" red, "*" green (neither shown); "+" amounts green
  public static func Unmark(s: String, out red: Bool, out green: Bool) -> String {
    red = StrBeginsWith(s, "!");
    green = StrBeginsWith(s, "*");
    if red || green {
      return StrMid(s, 1, StrLen(s) - 1);
    }
    green = StrBeginsWith(s, "+");
    return s;
  }
}

// Where layout numbers and text replacements come from (a tuner, a file);
// the kit's defaults apply when nothing is plugged in
public abstract class TKScaleSource extends IScriptable {
  public func Value(key: String, def: Float) -> Float { return def; }
  public func Text(text: String) -> String { return text; }
}

public class TKScaleSystem extends ScriptableSystem {
  public let source: ref<TKScaleSource>;

  public static func Get() -> ref<TKScaleSystem> = GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"TerminalKit.TKScaleSystem") as TKScaleSystem
}

public abstract class TKScale {
  public static func Use(source: ref<TKScaleSource>) -> Void {
    let sys = TKScaleSystem.Get();
    if IsDefined(sys) {
      sys.source = source;
    }
  }

  // A layout number by key, or `def` when the source hasn't set it
  public static func F(key: String, def: Float) -> Float {
    let sys = TKScaleSystem.Get();
    return IsDefined(sys) && IsDefined(sys.source) ? sys.source.Value(key, def) : def;
  }

  public static func I(key: String, def: Int32) -> Int32 = RoundF(TKScale.F(key, Cast<Float>(def)))

  // A text with the source's replacements applied
  public static func T(text: String) -> String {
    let sys = TKScaleSystem.Get();
    return IsDefined(sys) && IsDefined(sys.source) && StrLen(text) > 0 ? sys.source.Text(text) : text;
  }

  // ---- the tokens: five type sizes and four spacings, so rows share a scale ----
  // The frame is laid out on a 4K canvas and shrunk to the screen, so the
  // smallest sizes are already two points above where they would read blurry.
  public static func TypeXS() -> Int32 = TKScale.I("type.xs", 24)     // captions, tags, table heads
  public static func TypeSM() -> Int32 = TKScale.I("type.sm", 28)     // details, notes
  public static func TypeMD() -> Int32 = TKScale.I("type.md", 32)     // row titles, body
  public static func TypeLG() -> Int32 = TKScale.I("type.lg", 46)     // headings
  public static func TypeXL() -> Int32 = TKScale.I("type.xl", 54)     // big values
  public static func SpaceXS() -> Float = TKScale.F("space.xs", 4.0)
  public static func SpaceSM() -> Float = TKScale.F("space.sm", 8.0)
  public static func SpaceMD() -> Float = TKScale.F("space.md", 16.0)
  public static func SpaceLG() -> Float = TKScale.F("space.lg", 24.0)
  public static func ButtonH() -> Float = TKScale.F("button.h", 64.0)
}

public abstract class TKInk {
  public static func Font(t: ref<inkText>, size: Int32, weight: CName) -> Void {
    t.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    t.SetFontStyle(weight);
    t.SetFontSize(size);
    t.SetLetterCase(textLetterCase.UpperCase);
  }

  public static func Strip(parent: ref<inkCompoundWidget>, above: Float) -> ref<inkHorizontalPanel> {
    let strip: ref<inkHorizontalPanel> = new inkHorizontalPanel();
    strip.SetMargin(inkMargin(0.0, above, 0.0, 0.0));
    strip.SetHAlign(inkEHorizontalAlign.Left);
    strip.Reparent(parent);
    return strip;
  }

  // a text with no colour of its own (the caller paints it)
  public static func Plain(parent: ref<inkCompoundWidget>, text: String, size: Int32, weight: CName, above: Float) -> ref<inkText> {
    let t: ref<inkText> = new inkText();
    TKInk.Font(t, size, weight);
    t.SetMargin(inkMargin(0.0, above, 0.0, 0.0));
    t.SetVAlign(inkEVerticalAlign.Bottom);
    t.SetText(text);
    t.Reparent(parent);
    return t;
  }

  public static func Line(parent: ref<inkCompoundWidget>, text: String, size: Int32, weight: CName, color: CName, above: Float) -> ref<inkText> {
    let t = TKInk.Plain(parent, text, size, weight, above);
    t.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    t.BindProperty(n"tintColor", color);
    return t;
  }

  public static func Tinted(parent: ref<inkCompoundWidget>, text: String, size: Int32, weight: CName, color: HDRColor, above: Float) -> ref<inkText> {
    let t = TKInk.Plain(parent, text, size, weight, above);
    t.SetTintColor(color);
    return t;
  }

  // Left-to-right fill for 0..1 values
  public static func Meter(parent: ref<inkCompoundWidget>, width: Float, height: Float, fraction: Float, color: HDRColor, above: Float) -> Void {
    let track: ref<inkCanvas> = TKInk.Track(parent, width, height, above);
    let fill: ref<inkRectangle> = new inkRectangle();
    fill.SetSize(Vector2(MaxF(2.0, width * ClampF(fraction, 0.0, 1.0)), height));
    fill.SetTintColor(color);
    fill.Reparent(track);
  }

  public static func Track(parent: ref<inkCompoundWidget>, width: Float, height: Float, above: Float) -> ref<inkCanvas> {
    let track: ref<inkCanvas> = new inkCanvas();
    track.SetSize(Vector2(width, height));
    track.SetMargin(inkMargin(0.0, above, 0.0, 0.0));
    track.SetHAlign(inkEHorizontalAlign.Left);
    track.Reparent(parent);

    let bed: ref<inkRectangle> = new inkRectangle();
    bed.SetSize(Vector2(width, height));
    bed.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    bed.BindProperty(n"tintColor", n"MainColors.DarkRed");
    bed.SetOpacity(0.5);
    bed.Reparent(track);
    return track;
  }

  // a rectangle at (x, y), w x h, in a canvas
  public static func Rect(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float) -> ref<inkRectangle> {
    let r: ref<inkRectangle> = new inkRectangle();
    r.SetSize(Vector2(w, h));
    r.SetMargin(inkMargin(x, y, 0.0, 0.0));
    r.Reparent(parent);
    return r;
  }

  // a line from a to b, `t` thick (a rotated bar)
  public static func Seg(parent: ref<inkCanvas>, a: Vector2, b: Vector2, t: Float, color: HDRColor, opacity: Float) -> Void {
    let dx = b.X - a.X;
    let dy = b.Y - a.Y;
    let len = SqrtF(dx * dx + dy * dy);
    if len < 0.5 {
      return;
    }
    let w = len + t * 0.5;
    let bar: ref<inkRectangle> = new inkRectangle();
    bar.SetAnchor(inkEAnchor.TopLeft);
    bar.SetAnchorPoint(Vector2(0.0, 0.0));
    bar.SetRenderTransformPivot(Vector2(0.5, 0.5));
    bar.SetSize(Vector2(w, t));
    bar.SetMargin(inkMargin((a.X + b.X) / 2.0 - w / 2.0, (a.Y + b.Y) / 2.0 - t / 2.0, 0.0, 0.0));
    bar.SetRotation(Rad2Deg(AtanF(dy, dx)));
    bar.SetTintColor(color);
    bar.SetOpacity(opacity);
    bar.Reparent(parent);
  }

  // Rough line count of a text wrapped at `width` (caps are ~0.55 of the font size wide)
  public static func Lines(s: String, size: Int32, width: Float) -> Float {
    if StrLen(s) == 0 {
      return 0.0;
    }
    let total = 0.0;
    for part in StrSplit(s, "\n") {
      let need = Cast<Float>(Max(1, StrLen(part))) * 0.58 * Cast<Float>(size) / width;
      let n = Cast<Int32>(need);
      if Cast<Float>(n) < need {
        n += 1;
      }
      total += Cast<Float>(Max(1, n));
    }
    return total;
  }
}
