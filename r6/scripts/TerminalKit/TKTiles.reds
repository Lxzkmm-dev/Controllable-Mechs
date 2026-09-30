// =============================================================================
// TERMINAL KIT - TILES AND CARDS
// Everything laid out in a grid (side by side, wrapping): the stat tile, the
// market ticker tile (with a sparkline), the opener tile with a button, and
// the listing card with a tag, a price, details and buttons along the bottom.
// =============================================================================
module TerminalKit

public abstract class TKTiles {
  // ---- stat tile: name, the value large, a line under it, a bar along the bottom ----
  public static func Stat(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let w = TKScale.F("stat.w", 355.0);
    let h = TKScale.F("stat.h", 176.0);
    let tile = v.GridCell(TKKind.Stat(), w, h);
    v.Panel(tile, w, h, 0.45);
    let parts = TKStr.Split(r.text, "|");
    v.Paint(TKInk.Rect(tile, 0.0, 0.0, w, 4.0), "accent");
    let name = v.Text(tile, parts[0], 22, n"Semi-Bold", "text", 0.0);
    name.SetMargin(inkMargin(18.0, 16.0, 0.0, 0.0));
    v.Hoverable(name, r.tip);
    let red: Bool;
    let green: Bool;
    let value = v.Text(tile, TKTheme.Unmark(ArraySize(parts) > 1 ? parts[1] : "", red, green), 50, n"Semi-Bold", "value", 0.0);
    value.SetMargin(inkMargin(18.0, 42.0, 0.0, 0.0));
    v.Mark(value, red, green);
    if ArraySize(parts) > 2 && StrLen(parts[2]) > 0 {
      let sub = v.Marked(tile, parts[2], 22, n"Medium", 0.0, w - 36.0);
      sub.SetMargin(inkMargin(18.0, 108.0, 0.0, 0.0));
    }
    if r.fraction >= 0.0 {
      let bed = TKInk.Rect(tile, 18.0, h - 24.0, w - 36.0, 8.0);
      bed.SetOpacity(0.5);
      v.Paint(bed, "rule");
      let fill = TKInk.Rect(tile, 18.0, h - 24.0, MaxF(3.0, (w - 36.0) * ClampF(r.fraction, 0.0, 1.0)), 8.0);
      v.Paint(fill, "value");
      v.Mark(fill, red, green);
    }
  }

  // ---- opener tile: a bar and the name in its colour, the value, a line, a button ----
  public static func Tile(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    let w = TKScale.F("tile.w", 350.0);
    let h = TKScale.F("tile.h", 236.0);
    let tile = v.GridCell(TKKind.Tile(), w, h);
    if !r.on {
      tile.SetOpacity(0.6);
    }
    v.Panel(tile, w, h, 0.45);
    let parts = TKStr.Split(r.text, "|");
    let bar = TKInk.Rect(tile, 0.0, 0.0, w, 6.0);
    v.Paint(bar, "value");
    v.Tone(bar, r.color);
    let name = v.Text(tile, parts[0], 26, n"Semi-Bold", "value", 0.0);
    name.SetMargin(inkMargin(18.0, 18.0, 0.0, 0.0));
    v.Tone(name, r.color);
    v.Hoverable(name, r.tip);
    let red: Bool;
    let green: Bool;
    let value = v.Text(tile, TKTheme.Unmark(ArraySize(parts) > 1 ? parts[1] : "", red, green), 34, n"Semi-Bold", "value", 0.0);
    value.SetMargin(inkMargin(18.0, 54.0, 0.0, 0.0));
    v.Mark(value, red, green);
    if ArraySize(parts) > 2 && StrLen(parts[2]) > 0 {
      let sub = v.Marked(tile, parts[2], 22, n"Medium", 0.0, w - 36.0);
      sub.SetMargin(inkMargin(18.0, 100.0, 0.0, 0.0));
    }
    if StrLen(r.label) > 0 {
      let root = v.ActButton(tile, i, 0, r.label, true, w - 36.0, 54.0, 24).GetRootWidget();
      root.SetAnchor(inkEAnchor.BottomLeft);
      root.SetAnchorPoint(Vector2(0.0, 1.0));
      root.SetMargin(inkMargin(18.0, 0.0, 0.0, 16.0));
    }
  }

  // ---- market tile: name, today's value large, the change, a week's line, a note ----
  public static func Ticker(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let w = TKScale.F("tick.w", 355.0);
    let h = TKScale.F("tick.h", 250.0);
    let tile = v.GridCell(TKKind.Ticker(), w, h);
    v.Panel(tile, w, h, 0.45);
    let parts = TKStr.Split(r.text, "|");
    v.Paint(TKInk.Rect(tile, 0.0, 0.0, w, 4.0), "accent");
    let name = v.Text(tile, parts[0], 24, n"Semi-Bold", "text", 0.0);
    name.SetMargin(inkMargin(18.0, 16.0, 0.0, 0.0));
    let value = v.Text(tile, ArraySize(parts) > 1 ? parts[1] : "", 52, n"Semi-Bold", "value", 0.0);
    value.SetMargin(inkMargin(18.0, 44.0, 0.0, 0.0));
    let red: Bool;
    let green: Bool;
    let change = v.Text(tile, TKTheme.Unmark(ArraySize(parts) > 2 ? parts[2] : "", red, green), 26, n"Semi-Bold", "text", 0.0);
    v.Mark(change, red, green);
    change.SetAnchor(inkEAnchor.TopRight);
    change.SetAnchorPoint(Vector2(1.0, 0.0));
    change.SetHorizontalAlignment(textHorizontalAlignment.Right);
    change.SetMargin(inkMargin(0.0, 68.0, 18.0, 0.0));
    TKTiles.Spark(v, tile, 18.0, 122.0, w - 36.0, 66.0, r.value, 1.0);
    if ArraySize(parts) > 3 && StrLen(parts[3]) > 0 {
      let note = v.Marked(tile, parts[3], 20, n"Medium", 0.0, w - 36.0);
      note.SetMargin(inkMargin(18.0, h - 40.0, 0.0, 0.0));
    }
  }

  // a line chart through `values` ("a,b,c") in a w x h box at (x, y): green when
  // it ends higher than it started, red when lower; a faint line at `base` when
  // that's in range, and a dot on the last point
  public static func Spark(v: ref<TKView>, parent: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float, values: String, base: Float) -> Void {
    let vals: array<Float>;
    for s in TKStr.Split(values, ",") {
      if StrLen(s) > 0 {
        ArrayPush(vals, StringToFloat(s, 0.0));
      }
    }
    let n = ArraySize(vals);
    if n < 2 {
      return;
    }
    let lo = vals[0];
    let hi = vals[0];
    for val in vals {
      lo = MinF(lo, val);
      hi = MaxF(hi, val);
    }
    let pad = MaxF((hi - lo) * 0.18, 0.03);
    lo -= pad;
    hi += pad;
    let color = vals[n - 1] >= vals[0] ? TKTheme.Gain() : TKTheme.Loss();
    if base > lo && base < hi {
      let mark = TKInk.Rect(parent, x, y + h - (base - lo) / (hi - lo) * h - 1.0, w, 2.0);
      mark.SetOpacity(0.35);
      v.Paint(mark, "text");
    }
    let pts: array<Vector2>;
    let k = 0;
    while k < n {
      ArrayPush(pts, Vector2(x + w * Cast<Float>(k) / Cast<Float>(n - 1), y + h - (vals[k] - lo) / (hi - lo) * h));
      k += 1;
    }
    k = 0;
    while k < n - 1 {
      TKInk.Seg(parent, pts[k], pts[k + 1], 3.0, color, 1.0);
      k += 1;
    }
    let dot = TKInk.Rect(parent, pts[n - 1].X - 6.0, pts[n - 1].Y - 6.0, 12.0, 12.0);
    dot.SetRenderTransformPivot(Vector2(0.5, 0.5));
    dot.SetRotation(45.0);
    dot.SetTintColor(color);
  }

  // ---- listing card: a tag band, the name, a large price, details, buttons along the bottom ----
  public static func Card(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    let w = TKScale.F("card.w", 530.0);
    let h = TKScale.F("card.h", 400.0);
    let card = v.GridCell(TKKind.Card(), w, h);
    if !r.on {
      card.SetOpacity(0.7);
    }
    v.Panel(card, w, h, 0.45);
    // "*colour": the card being pointed at (a map pin opened it): a thick frame in its colour
    let color = r.color;
    if StrBeginsWith(color, "*") {
      color = StrMid(color, 1, StrLen(color) - 1);
      card.SetOpacity(1.0);
      v.TonedFrame(card, w, h, 5.0, color);
    }
    let parts = TKStr.Split(r.text, "|");
    // the tag: a bar in the card's colour over a dark strip, the tag in that colour
    // (dark text on a bright band washed out in the game's HUD blending)
    let strip = TKInk.Rect(card, 0.0, 0.0, w, 46.0);
    strip.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 1.0));
    strip.SetOpacity(0.7);
    let band = TKInk.Rect(card, 0.0, 0.0, w, 6.0);
    v.Paint(band, "value");
    v.Tone(band, color);
    let tag = v.Text(card, parts[0], 24, n"Semi-Bold", "value", 0.0);
    tag.SetMargin(inkMargin(20.0, 11.0, 0.0, 0.0));
    v.Tone(tag, color);
    v.Hoverable(tag, r.tip);
    // name, where, price, details
    let tw = w - 40.0;
    let body: ref<inkVerticalPanel> = new inkVerticalPanel();
    body.SetMargin(inkMargin(20.0, 56.0, 0.0, 0.0));
    body.Reparent(card);
    v.Wrap(v.Text(body, ArraySize(parts) > 1 ? parts[1] : "", 30, n"Semi-Bold", "value", 0.0), tw);
    if ArraySize(parts) > 2 && StrLen(parts[2]) > 0 {
      v.Wrap(v.Text(body, parts[2], 22, n"Regular", "text", 2.0), tw);
    }
    let money = ArraySize(parts) > 3 ? parts[3] : "";
    let price = v.Marked(body, money, 40, n"Semi-Bold", 8.0, tw);
    if !StrBeginsWith(money, "!") && !StrBeginsWith(money, "*") && !StrBeginsWith(money, "+") {
      v.Fix(price, TKTheme.Gold());
    }
    for d in TKStr.Split(r.value, "|") {
      if StrLen(d) > 0 {
        v.Marked(body, d, 24, n"Regular", 4.0, tw);
      }
    }
    // buttons along the bottom, sharing the width
    let n = ArraySize(r.labels);
    if n > 0 && StrLen(r.label) > 0 {
      let bar: ref<inkHorizontalPanel> = new inkHorizontalPanel();
      bar.SetAnchor(inkEAnchor.BottomLeft);
      bar.SetAnchorPoint(Vector2(0.0, 1.0));
      bar.SetMargin(inkMargin(20.0, 0.0, 0.0, 16.0));
      bar.Reparent(card);
      let bw = (tw - 14.0 * Cast<Float>(n - 1)) / Cast<Float>(n);
      let k = 0;
      while k < n {
        let b = v.ActButton(bar, i, k, r.labels[k], true, bw, 54.0, 24);
        b.GetRootWidget().SetMargin(inkMargin(k > 0 ? 14.0 : 0.0, 0.0, 0.0, 0.0));
        k += 1;
      }
    }
  }
}
