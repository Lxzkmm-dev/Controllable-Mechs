// =============================================================================
// TERMINAL KIT - TABLES
// Table: a ledger-style line of cells across columns ("L50|R25|R25": each cell
//   left or right aligned in its share of the width, in %), amounts coloured
//   by sign, every other line shaded.
// Board: a departures board line, amber text on dark split-flap tiles, with an
//   optional button on the right.
// =============================================================================
module TerminalKit

public abstract class TKTables {
  // the column spec: alignment and width in % of `w`
  private static func Col(spec: String, w: Float, out right: Bool) -> Float {
    right = StrBeginsWith(spec, "R");
    return w * StringToFloat(StrMid(spec, 1, StrLen(spec) - 1), 0.0) / 100.0;
  }

  public static func Table(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let style = r.color;
    let head = Equals(style, "head");
    let group = Equals(style, "group");
    let total = Equals(style, "total");
    let net = Equals(style, "net");
    let base = TKScale.I("table.font", 28);
    let size = head || group ? Max(14, base - 4) : (net ? base + 4 : base);
    let w = v.RowWidth();
    let h = Cast<Float>(size) * 1.6;
    let c = v.Content();
    if total || net {
      v.Rule(c, 4.0, 0.9);
    }
    let row: ref<inkCanvas> = new inkCanvas();
    row.SetSize(Vector2(w, h));
    row.SetMargin(inkMargin(0.0, group ? 10.0 : 0.0, 0.0, 0.0));
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.Reparent(c);
    v.Grew(h + (group ? 10.0 : 0.0) + (total || net || head ? 6.0 : 0.0));
    if head || group {
      v.tableLine = 0;
    }
    if Equals(style, "line") {
      if v.tableLine % 2 == 1 {
        let shade = TKInk.Rect(row, 0.0, 0.0, w, h);
        v.Paint(shade, "rule");
        shade.SetOpacity(0.25);
      }
      v.tableLine += 1;
    }
    let spec = TKStr.Split(r.value, "|");
    let parts = TKStr.Split(r.text, "|");
    let x = 0.0;
    let k = 0;
    while k < ArraySize(spec) {
      let right: Bool;
      let cw = TKTables.Col(spec[k], w, right);
      let cell: ref<inkCanvas> = new inkCanvas();
      cell.SetSize(Vector2(MaxF(10.0, cw - 24.0), h));
      cell.SetMargin(inkMargin(x + 12.0, 0.0, 0.0, 0.0));
      cell.Reparent(row);
      let s = k < ArraySize(parts) ? parts[k] : "";
      let red = StrBeginsWith(s, "!");
      if red {
        s = StrMid(s, 1, StrLen(s) - 1);
      }
      let t = v.Text(cell, s, size, head || total || net ? n"Semi-Bold" : n"Medium", head ? "text" : "value", 0.0);
      t.SetAnchor(right ? inkEAnchor.CenterRight : inkEAnchor.CenterLeft);
      t.SetAnchorPoint(Vector2(right ? 1.0 : 0.0, 0.5));
      if right {
        t.SetHorizontalAlignment(textHorizontalAlignment.Right);
      }
      if group {
        v.Paint(t, "accent");
      } else {
        if !head {
          if red || StrBeginsWith(s, "-") && StrLen(s) > 1 {
            v.Fix(t, TKTheme.Loss());
          } else {
            if StrBeginsWith(s, "+") {
              v.Fix(t, TKTheme.Gain());
            } else {
              if Equals(s, "-") {
                v.Paint(t, "text");
                t.SetOpacity(0.5);
              }
            }
          }
        }
      }
      x += cw;
      k += 1;
    }
    if head {
      v.Rule(c, 0.0, 0.6);
    }
    if net {
      v.Rule(c, 4.0, 0.9);
      v.Rule(c, 3.0, 0.9);
    }
  }

  public static func Board(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    let style = r.color;
    let head = Equals(style, "head");
    let title = Equals(style, "title");
    let size = title ? 42 : (head ? 20 : 26);
    let h = title ? 62.0 : (head ? 32.0 : 50.0);
    let bw = StrLen(r.label) > 0 ? TKScale.F("board.button", 230.0) : 0.0;
    let w = v.RowWidth() - (bw > 0.0 ? bw + 16.0 : 0.0);
    let c = v.Content();
    let row: ref<inkCanvas> = new inkCanvas();
    row.SetSize(Vector2(v.RowWidth(), h));
    row.SetMargin(inkMargin(0.0, head ? 12.0 : (title ? 16.0 : 6.0), 0.0, 0.0));
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.Reparent(c);
    v.Grew(h + (head ? 12.0 : (title ? 27.0 : 6.0)));
    let spec = TKStr.Split(r.value, "|");
    let parts = TKStr.Split(r.text, "|");
    let x = 0.0;
    let k = 0;
    while k < ArraySize(spec) {
      let right: Bool;
      let cw = TKTables.Col(spec[k], w, right);
      if !head && !title {
        // a flap tile, its seam across the middle
        let tile = TKInk.Rect(row, x, 0.0, MaxF(4.0, cw - 5.0), h);
        tile.SetTintColor(new HDRColor(0.035, 0.035, 0.04, 1.0));
        tile.SetOpacity(0.85);
        let seam = TKInk.Rect(row, x, h / 2.0 - 1.0, MaxF(4.0, cw - 5.0), 2.0);
        seam.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 1.0));
        seam.SetOpacity(0.95);
      }
      let cell: ref<inkCanvas> = new inkCanvas();
      cell.SetSize(Vector2(MaxF(10.0, cw - 30.0), h));
      cell.SetMargin(inkMargin(x + 13.0, 0.0, 0.0, 0.0));
      cell.Reparent(row);
      let s = k < ArraySize(parts) ? parts[k] : "";
      let color = TKTheme.Amber();
      let mark = StrLeft(s, 1);
      if Equals(mark, "!") || Equals(mark, "*") || Equals(mark, "^") || Equals(mark, "~") {
        s = StrMid(s, 1, StrLen(s) - 1);
        if Equals(mark, "!") { color = TKTheme.Loss(); }
        if Equals(mark, "*") { color = TKTheme.Gain(); }
        if Equals(mark, "^") { color = new HDRColor(1.0, 0.95, 0.35, 1.0); }
        if Equals(mark, "~") { color = new HDRColor(0.5, 0.5, 0.52, 1.0); }
      }
      let t = v.Text(cell, s, size, n"Semi-Bold", "value", 0.0);
      v.Fix(t, color);
      if head {
        t.SetOpacity(0.65);
      }
      t.SetAnchor(right ? inkEAnchor.CenterRight : inkEAnchor.CenterLeft);
      t.SetAnchorPoint(Vector2(right ? 1.0 : 0.0, 0.5));
      if right {
        t.SetHorizontalAlignment(textHorizontalAlignment.Right);
      }
      x += cw;
      k += 1;
    }
    if bw > 0.0 {
      let root = v.ActButton(row, i, 0, r.label, r.on, bw, h - 4.0, 24).GetRootWidget();
      root.SetAnchor(inkEAnchor.TopRight);
      root.SetAnchorPoint(Vector2(1.0, 0.0));
      root.SetMargin(inkMargin(0.0, 2.0, 0.0, 0.0));
    }
    if title {
      let rule: ref<inkRectangle> = new inkRectangle();
      rule.SetSize(Vector2(v.RowWidth(), 3.0));
      rule.SetMargin(inkMargin(0.0, 4.0, 0.0, 4.0));
      rule.SetHAlign(inkEHorizontalAlign.Left);
      rule.SetTintColor(TKTheme.Amber());
      rule.SetOpacity(0.8);
      rule.Reparent(c);
    }
  }
}
