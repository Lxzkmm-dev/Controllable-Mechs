// =============================================================================
// TERMINAL KIT - LIST ROWS
// The rows that stack down a page: headings, text, pairs, meters, buttons,
// items (with an optional level track), link rows, sections, feed entries,
// dossier headers, two-column pair lists and marked tracks. Each draws into
// the view's current content panel through the view's helpers.
// =============================================================================
module TerminalKit

public abstract class TKRows {
  public static func Heading(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let c = v.Content();
    let head = v.Text(c, r.text, TKScale.I("heading", 46), n"Medium", "accent", 0.0);
    head.SetMargin(inkMargin(0.0, 22.0, 0.0, 6.0));
    v.Grew(Cast<Float>(TKScale.I("heading", 46)) * 1.4 + 45.0);
    let rule: ref<inkRectangle> = new inkRectangle();
    rule.SetSize(Vector2(v.Width() - 40.0, 3.0));
    rule.SetMargin(inkMargin(0.0, 0.0, 0.0, 14.0));
    rule.SetHAlign(inkEHorizontalAlign.Left);
    rule.Reparent(c);
    v.Paint(rule, "rule");
  }

  public static func Text(v: ref<TKView>, r: ref<TKRow>) -> Void {
    v.Tone(v.Text(v.Content(), r.text, TKScale.I("text", 32), n"Regular", "text", 6.0), r.color);
    v.Grew(Cast<Float>(TKScale.I("text", 32)) * 1.4 + 6.0);
  }

  public static func Pair(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let pair = TKInk.Strip(v.Content(), 6.0);
    v.Hoverable(v.Text(pair, r.text, TKScale.I("pair", 30), n"Medium", "text", 0.0), r.tip);
    v.Tone(v.Text(pair, "   " + r.value, TKScale.I("pair", 30), n"Semi-Bold", "value", 0.0), r.color);
    v.Grew(Cast<Float>(TKScale.I("pair", 30)) * 1.4 + 6.0);
  }

  public static func Meter(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let c = v.Content();
    let top = TKInk.Strip(c, 10.0);
    v.Hoverable(v.Text(top, r.text, TKScale.I("meter.font", 30), n"Medium", "text", 0.0), r.tip);
    v.Text(top, "   " + r.value, TKScale.I("meter.font", 30), n"Semi-Bold", "value", 0.0);
    TKInk.Meter(c, MinF(TKScale.F("meter.w", 900.0), v.Width()), TKScale.F("meter.h", 10.0), r.fraction, TKTheme.Gold(), 6.0);
    v.Grew(Cast<Float>(TKScale.I("meter.font", 30)) * 1.4 + TKScale.F("meter.h", 10.0) + 16.0);
  }

  public static func Button(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    v.ActButton(v.Content(), i, 0, r.label, r.on, TKScale.F("button.w", 520.0), TKScale.ButtonH(), TKScale.I("button.font", 30))
      .GetRootWidget().SetMargin(inkMargin(0.0, 14.0, 0.0, 0.0));
    v.Grew(TKScale.ButtonH() + 14.0);
  }

  public static func Note(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let note = v.Text(v.Content(), r.text, TKScale.I("note", 26), n"Regular", "text", 4.0);
    note.SetLetterCase(textLetterCase.OriginalCase);
    note.SetWrapping(true, Equals(r.value, "item") ? v.RowWidth() - TKScale.F("item.w", 380.0) - 40.0 : v.Width());
    note.SetOpacity(0.85);
    v.Grew(TKInk.Lines(r.text, TKScale.I("note", 26), v.Width()) * Cast<Float>(TKScale.I("note", 26)) * 1.4 + 4.0);
  }

  public static func Gap(v: ref<TKView>) -> Void {
    let gap: ref<inkRectangle> = new inkRectangle();
    gap.SetSize(Vector2(10.0, 18.0));
    gap.SetOpacity(0.0);
    gap.Reparent(v.Content());
    v.Grew(18.0);
  }

  // text + value on the left, a button on the right, and a level track (extra
  // "level:max") left of the button
  public static func Item(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    let iw = TKScale.F("item.w", 380.0);
    let track = StrLen(r.extra) > 0 ? TKRows.PipsWidth(r.extra) + 24.0 : 0.0;
    let item = v.RowBox(v.RowWidth() - iw - 40.0 - track, r.text, r.value, r.color, r.tip);
    if StrLen(r.label) > 0 {
      v.PinRight(v.ActButton(item, i, 0, r.label, r.on, iw, TKScale.ButtonH(), TKScale.I("button.font", 30)).GetRootWidget());
    }
    if StrLen(r.extra) > 0 {
      TKRows.Pips(v, item, r.extra, iw + 24.0);
    }
  }

  // several buttons on the right, sharing the row
  public static func Buttons(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    let n = ArraySize(r.labels);
    // buttons shrink when there are many (e.g. one per patrol node)
    let bw: Float = n > 4 ? TKScale.F("multi.wSmall", 170.0) : TKScale.F("multi.w", 280.0);
    let line = v.RowBox(MaxF(400.0, v.RowWidth() - Cast<Float>(n) * (bw + 16.0) - 40.0), r.text, r.value, r.color, r.tip);
    let group: ref<inkHorizontalPanel> = new inkHorizontalPanel();
    group.Reparent(line);
    v.PinRight(group);
    let k = 0;
    while k < n {
      let b = v.ActButton(group, i, k, r.labels[k], true, bw, TKScale.F("multi.h", 60.0), TKScale.I("multi.font", 24));
      b.GetRootWidget().SetMargin(inkMargin(16.0, 6.0, 0.0, 0.0));
      k += 1;
    }
  }

  // a row of page links; the current one shown pressed
  public static func Links(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let row = TKInk.Strip(v.Content(), 8.0);
    let names = StrSplit(r.text, "|");
    let targets = StrSplit(r.value, "|");
    let n = 0;
    let width = MinF(TKScale.F("link.w", 360.0), (v.Width() - 20.0) / Cast<Float>(Max(1, ArraySize(names))) - 16.0);
    v.linkRows += 1;
    if v.linkRows > 1 {
      let used = Cast<Float>(ArraySize(names)) * (width + 16.0);
      row.SetMargin(inkMargin(MaxF(0.0, (v.RowWidth() - used) / 2.0), 8.0, 0.0, 0.0));
    }
    while n < ArraySize(names) && n < ArraySize(targets) {
      let b = v.LinkButton(row, names[n], targets[n], Equals(targets[n], r.label), width, TKScale.F("link.h", 58.0), TKScale.I("link.font", 26));
      b.GetRootWidget().SetMargin(inkMargin(0.0, 0.0, 16.0, 0.0));
      n += 1;
    }
    v.Grew(TKScale.F("link.h", 58.0) + 16.0);
  }

  // ---- collapsible section: [+] TITLE  value ........................ [OPEN] ----
  public static func Section(v: ref<TKView>, i: Int32, r: ref<TKRow>) -> Void {
    let size = TKScale.I("heading", 46);
    let c = v.Content();
    let row: ref<inkCanvas> = new inkCanvas();
    row.SetSize(Vector2(v.RowWidth(), MaxF(Cast<Float>(size) * 1.4, TKScale.ButtonH())));
    row.SetMargin(inkMargin(0.0, 18.0, 0.0, 0.0));
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.Reparent(c);
    let strip: ref<inkHorizontalPanel> = new inkHorizontalPanel();
    strip.Reparent(row);
    v.Text(strip, (r.on ? "[-]  " : "[+]  ") + r.text, size, n"Medium", "accent", 0.0);
    let note = v.Text(strip, "     " + r.value, TKScale.I("row.detail", 29), n"Regular", "text", 0.0);
    note.SetVAlign(inkEVerticalAlign.Center);
    v.PinRight(v.ActButton(row, i, 0, r.label, true, 220.0, TKScale.ButtonH(), TKScale.I("button.font", 30)).GetRootWidget());
    let rule: ref<inkRectangle> = new inkRectangle();
    rule.SetSize(Vector2(v.RowWidth(), 3.0));
    rule.SetMargin(inkMargin(0.0, 4.0, 0.0, 8.0));
    rule.SetHAlign(inkEHorizontalAlign.Left);
    rule.Reparent(c);
    v.Paint(rule, "rule");
    v.Grew(MaxF(Cast<Float>(size) * 1.4, TKScale.ButtonH()) + 33.0);
  }

  // ---- feed entry: panels size to their content, so entries never overlap ----
  public static func Entry(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let box: ref<inkVerticalPanel> = new inkVerticalPanel();
    box.SetMargin(inkMargin(0.0, 14.0, 0.0, 0.0));
    box.SetHAlign(inkEHorizontalAlign.Left);
    box.Reparent(v.Content());
    let small = TKScale.I("row.detail", 29);
    let parts = StrSplit(r.label, "|");
    let top = TKInk.Strip(box, 0.0);
    v.Text(top, ArraySize(parts) > 0 ? parts[0] : "", small, n"Semi-Bold", "value", 0.0);
    v.Sep(top, small);
    v.Tone(v.Text(top, ArraySize(parts) > 1 ? parts[1] : "", small, n"Semi-Bold", "value", 0.0), r.color);
    v.Sep(top, small);
    v.Text(top, ArraySize(parts) > 2 ? parts[2] : "", small, n"Medium", "accent", 0.0);
    let h = v.Text(box, r.text, TKScale.I("row.title", 32), n"Medium", "value", 4.0);
    h.SetWrapping(true, v.RowWidth());
    v.Tone(h, r.color);
    // details, packed into lines that fit the row
    if StrLen(r.value) > 0 {
      let line = TKInk.Strip(box, 4.0);
      let used = 0.0;
      let first = true;
      for item in StrSplit(r.value, "|") {
        let w = Cast<Float>(StrLen(item)) * 0.55 * Cast<Float>(small) + 34.0;
        if !first && used + w > v.RowWidth() {
          line = TKInk.Strip(box, 2.0);
          used = 0.0;
          first = true;
        }
        if !first {
          v.Sep(line, small);
        }
        v.Text(line, item, small, n"Regular", "text", 0.0);
        used += w;
        first = false;
      }
    }
    if StrLen(r.action) > 0 {
      let q = v.Text(box, r.action, TKScale.I("note", 26), n"Regular", "text", 4.0);
      q.SetLetterCase(textLetterCase.OriginalCase);
      q.SetWrapping(true, v.RowWidth());
      q.SetOpacity(0.8);
    }
    v.Rule(box, 14.0, 0.5);
    v.Grew(Cast<Float>(small) * 1.4 + TKInk.Lines(r.text, TKScale.I("row.title", 32), v.RowWidth()) * 42.0 + (StrLen(r.value) > 0 ? Cast<Float>(small) * 1.4 + 4.0 : 0.0)
      + (StrLen(r.action) > 0 ? TKInk.Lines(r.action, TKScale.I("note", 26), v.RowWidth()) * 36.0 + 4.0 : 0.0) + 32.0);
  }

  // ---- dossier header: the name large, a line under it, a status stamp on the right ----
  public static func Dossier(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let c = v.Content();
    let row: ref<inkCanvas> = new inkCanvas();
    row.SetSize(Vector2(v.RowWidth(), 118.0));
    row.SetMargin(inkMargin(0.0, 8.0, 0.0, 0.0));
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.Reparent(c);
    let col: ref<inkVerticalPanel> = new inkVerticalPanel();
    col.Reparent(row);
    v.Text(col, r.text, TKScale.TypeXL(), n"Semi-Bold", "title", 0.0);
    v.Text(col, r.value, TKScale.I("row.detail", 29), n"Medium", "text", 4.0);
    // the stamp: a bordered box with the status, slightly tilted
    let size = 30;
    let w = Cast<Float>(StrLen(r.label)) * 0.62 * Cast<Float>(size) + 48.0;
    let box: ref<inkCanvas> = new inkCanvas();
    box.SetSize(Vector2(w, 60.0));
    box.SetAnchor(inkEAnchor.TopRight);
    box.SetAnchorPoint(Vector2(1.0, 0.0));
    box.SetMargin(inkMargin(0.0, 20.0, 10.0, 0.0));
    box.SetRotation(-4.0);
    box.Reparent(row);
    v.TonedFrame(box, w, 60.0, 3.0, r.color);
    let t = v.Text(box, r.label, size, n"Semi-Bold", "value", 0.0);
    t.SetAnchor(inkEAnchor.Centered);
    t.SetAnchorPoint(Vector2(0.5, 0.5));
    v.Tone(t, r.color);
    v.Rule(c, 6.0, 0.8);
    v.Grew(134.0);
  }

  // ---- two columns of label / value pairs ----
  public static func Columns(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let strip = TKInk.Strip(v.Content(), 10.0);
    let colW = v.RowWidth() / 2.0 - 20.0;
    TKRows.PairColumn(v, strip, colW, r.text, r.value);
    TKRows.PairColumn(v, strip, colW, r.label, r.action);
    v.Grew(Cast<Float>(Max(ArraySize(StrSplit(r.text, "|")), ArraySize(StrSplit(r.label, "|")))) * Cast<Float>(TKScale.I("pair", 30)) * 1.4 + 30.0);
  }

  private static func PairColumn(v: ref<TKView>, parent: ref<inkCompoundWidget>, width: Float, labels: String, values: String) -> Void {
    let col: ref<inkVerticalPanel> = new inkVerticalPanel();
    col.SetMargin(inkMargin(0.0, 0.0, 40.0, 0.0));
    col.SetSize(Vector2(width, 10.0));
    col.Reparent(parent);
    let names = StrSplit(labels, "|");
    let vals = StrSplit(values, "|");
    let size = TKScale.I("pair", 30);
    let k = 0;   // values skip the headings
    let i = 0;
    while i < ArraySize(names) {
      if StrBeginsWith(names[i], "#") {
        v.Text(col, StrAfterFirst(names[i], "#"), size, n"Semi-Bold", "accent", i == 0 ? 0.0 : 14.0);
        let rule: ref<inkRectangle> = new inkRectangle();
        rule.SetSize(Vector2(width, 2.0));
        rule.SetMargin(inkMargin(0.0, 4.0, 0.0, 6.0));
        rule.SetOpacity(0.6);
        rule.Reparent(col);
        v.Paint(rule, "rule");
      } else {
        let row: ref<inkCanvas> = new inkCanvas();
        row.SetSize(Vector2(width, Cast<Float>(size) * 1.4));
        row.Reparent(col);
        v.Text(row, names[i], size, n"Medium", "text", 0.0);
        let val = v.Text(row, k < ArraySize(vals) ? vals[k] : "", size, n"Semi-Bold", "value", 0.0);
        k += 1;
        val.SetAnchor(inkEAnchor.TopRight);
        val.SetAnchorPoint(Vector2(1.0, 0.0));
        val.SetHorizontalAlignment(textHorizontalAlignment.Right);
      }
      i += 1;
    }
  }

  // ---- meter with named marks (e.g. crew trust and who will take your call) ----
  public static func Track(v: ref<TKView>, r: ref<TKRow>) -> Void {
    let c = v.Content();
    if StrLen(r.text) > 0 || StrLen(r.value) > 0 {
      let top = TKInk.Strip(c, 10.0);
      v.Hoverable(v.Text(top, r.text, TKScale.I("meter.font", 30), n"Medium", "text", 0.0), r.tip);
      v.Text(top, "   " + r.value, TKScale.I("meter.font", 30), n"Semi-Bold", "value", 0.0);
      v.Grew(Cast<Float>(TKScale.I("meter.font", 30)) * 1.4 + 10.0);
    }
    let w = MinF(TKScale.F("track.w", 1400.0), v.RowWidth());
    let h = TKScale.F("meter.h", 10.0);
    let font = TKScale.I("note", 26);
    let box: ref<inkCanvas> = new inkCanvas();
    box.SetSize(Vector2(w, h + 26.0 + Cast<Float>(font) * 1.3));
    box.SetMargin(inkMargin(0.0, 8.0, 0.0, 6.0));
    box.SetHAlign(inkEHorizontalAlign.Left);
    box.Reparent(c);
    v.Grew(h + 26.0 + Cast<Float>(font) * 1.3 + 14.0);
    TKInk.Meter(box, w, h, r.fraction, TKTheme.Gold(), 8.0);
    let labels = StrSplit(r.label, "|");
    let at = StrSplit(r.action, "|");
    let n = 0;
    while n < ArraySize(labels) && n < ArraySize(at) {
      let f = ClampF(StringToFloat(at[n]), 0.0, 1.0);
      let reached = r.fraction >= f;
      let tick = TKInk.Rect(box, w * f, 0.0, 3.0, h + 16.0);
      v.Paint(tick, reached ? "value" : "rule");
      let name = v.Text(box, labels[n], font, n"Semi-Bold", reached ? "value" : "text", 0.0);
      name.SetMargin(inkMargin(w * f + 8.0, h + 18.0, 0.0, 0.0));
      name.SetVAlign(inkEVerticalAlign.Top);
      if !reached {
        name.SetOpacity(0.5);
      }
      n += 1;
    }
  }

  // ---- level track: boxes I, II, III..., the owned ones filled, the next outlined ----
  public static func PipsWidth(spec: String) -> Float {
    let max = Cast<Float>(Max(1, StringToInt(TKStr.Part(spec, ":", 1), 3)));
    return max * 72.0 + (max - 1.0) * 10.0;
  }

  public static func Pips(v: ref<TKView>, row: ref<inkCanvas>, spec: String, right: Float) -> Void {
    let level = StringToInt(TKStr.Part(spec, ":", 0), 0);
    let max = Max(1, StringToInt(TKStr.Part(spec, ":", 1), 3));
    let roman = ["I", "II", "III", "IV", "V", "VI"];
    let h = 48.0;
    let group: ref<inkHorizontalPanel> = new inkHorizontalPanel();
    group.SetAnchor(inkEAnchor.TopRight);
    group.SetAnchorPoint(Vector2(1.0, 0.0));
    group.SetMargin(inkMargin(0.0, 2.0 + (TKScale.ButtonH() - h) / 2.0, right, 0.0));
    group.Reparent(row);
    let k = 0;
    while k < max {
      let lit = k < level;
      let box: ref<inkCanvas> = new inkCanvas();
      box.SetSize(Vector2(72.0, h));
      box.SetMargin(inkMargin(k > 0 ? 10.0 : 0.0, 0.0, 0.0, 0.0));
      box.Reparent(group);
      if lit {
        v.Paint(TKInk.Rect(box, 0.0, 0.0, 72.0, h), "value");
      } else {
        v.Frame(box, 72.0, h, 2.0, k == level ? "value" : "rule", k == level ? 0.8 : 1.0);
      }
      let t = v.Text(box, k < ArraySize(roman) ? roman[k] : IntToString(k + 1), 26, n"Semi-Bold", lit ? "value" : "text", 0.0);
      t.SetAnchor(inkEAnchor.Centered);
      t.SetAnchorPoint(Vector2(0.5, 0.5));
      if lit {
        v.Fix(t, TKTheme.Ink());
      } else {
        if k > level {
          t.SetOpacity(0.5);
        }
      }
      k += 1;
    }
  }
}
