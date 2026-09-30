// =============================================================================
// TERMINAL KIT - THE PAGE RENDERER
// A frame builds its own chrome (registering each piece with Chrome() so the
// palette reaches it), hands the view a title, subtitle, status line and content
// panel (Bind), the scroll area the content sits in (BindScroll) and adds tabs
// through it (AddTab). Show(page, arg) asks the content provider for the page
// and draws it, row by row, through the component classes (TKRows, TKTables,
// TKTiles); this file holds the state they share, the shared drawing helpers,
// the action and tab clicks, scrolling and the slider (whose callbacks need the
// view as their target).
// =============================================================================
module TerminalKit

import Codeware.UI.*
import RedFunctions.*

public class TKView extends IScriptable {
  // ---- what the frame gave us ----
  private let m_content: wref<inkVerticalPanel>;
  private let m_title: wref<inkText>;
  private let m_subtitle: wref<inkText>;
  private let m_message: wref<inkText>;
  private let m_width: Float;
  private let m_theme: String = "hud";
  private let m_frame: ref<TKFrame>;
  private let m_provider: ref<TKContent>;
  private let m_chrome: array<wref<inkWidget>>;
  private let m_roles: array<String>;
  private let m_tabs: array<ref<TKButton>>;
  // ---- scrolling ----
  private let m_scroll: wref<inkScrollArea>;
  private let m_scrollH: Float;
  private let m_scrollY: Float;
  private let m_bar: wref<inkRectangle>;
  private let m_barTrack: wref<inkRectangle>;
  public let grown: Float;                   // the page's height as the components count it (the scroll clamp's fallback)
  // ---- history (Back: the right mouse button in the frame) ----
  private let m_history: array<String>;      // pages left behind, "page~arg", newest last
  private let m_noPush: Bool;                // a Show from Back: the page left isn't recorded
  // ---- tooltips ----
  private let m_tipLayer: wref<inkCanvas>;
  private let m_tips: array<String>;
  private let m_tip: wref<inkWidget>;
  // ---- the page being shown ----
  private let m_data: ref<TKPage>;
  private let m_page: String;
  private let m_arg: String;
  private let m_buttons: array<ref<TKButton>>;
  private let m_sliders: array<ref<TKSlider>>;
  private let m_inputs: array<ref<HubTextInput>>;
  private let m_inputKeys: array<String>;
  private let m_drag: Int32;                 // slider being dragged (index into m_sliders), -1 = none
  private let m_custom: array<ref<TKCustom>>; // live custom rows (stopped when the page goes)
  // ---- layout state the components share ----
  public let linkRows: Int32;                // Links rows drawn on this page (the 2nd+ are centred)
  public let tableLine: Int32;               // table lines since the last heading (every other one shaded)
  private let m_cards: wref<inkHorizontalPanel>;   // the line of cards (or tiles) being filled
  private let m_cardCount: Int32;
  private let m_gridKind: Int32;
  private let m_split: wref<inkHorizontalPanel>;   // Column rows: the strip the columns sit in
  private let m_pageContent: wref<inkVerticalPanel>;
  private let m_pageWidth: Float;

  // ---------------------------------------------------------------------------
  // Set-up
  // ---------------------------------------------------------------------------
  public func Bind(content: ref<inkVerticalPanel>, title: ref<inkText>, subtitle: ref<inkText>, message: ref<inkText>, width: Float) -> Void {
    this.m_content = content;
    this.m_title = title;
    this.m_subtitle = subtitle;
    this.m_message = message;
    this.m_width = width;
    this.Chrome(title, "title");
    this.Chrome(subtitle, "text");
    this.Chrome(message, "value");
  }

  // The content panel sits in `area` (a clipping scroll area `height` tall):
  // the wheel moves it, `bar` (optional) shows where in the page the view is
  public func BindScroll(area: ref<inkScrollArea>, height: Float, track: ref<inkRectangle>, bar: ref<inkRectangle>) -> Void {
    this.m_scroll = area;
    this.m_scrollH = height;
    this.m_barTrack = track;
    this.m_bar = bar;
    this.m_scrollY = 0.0;
    // the wheel over the page itself (the frame's global input covers the rest)
    area.SetInteractive(true);
    area.RegisterToCallback(n"OnRelative", this, n"OnAreaRelative");
  }

  // where tooltips are drawn: a canvas over the page (the frame's viewport)
  public func SetTipLayer(layer: ref<inkCanvas>) -> Void { this.m_tipLayer = layer; }

  public func SetContent(provider: ref<TKContent>) -> Void { this.m_provider = provider; }
  public func SetFrame(frame: ref<TKFrame>) -> Void { this.m_frame = frame; }
  public func Owner() -> ref<inkCustomController> = IsDefined(this.m_frame) ? this.m_frame.Owner() : null
  public func Provider() -> ref<TKContent> = this.m_provider

  // A piece of the frame that follows the palette
  public func Chrome(w: ref<inkWidget>, role: String) -> Void {
    ArrayPush(this.m_chrome, w);
    ArrayPush(this.m_roles, role);
    TKTheme.Paint(w, this.m_theme, role);
  }

  public func AddTab(parent: ref<inkCompoundWidget>, text: String, page: String, width: Float, height: Float, size: Int32) -> ref<TKButton> {
    let b = TKButton.Make(parent, text, "tab_" + page, width, height, size);
    b.RegisterToCallback(n"OnBtnClick", this, n"OnTabClick");
    ArrayPush(this.m_tabs, b);
    TKTheme.Paint(b.GetLabel(), this.m_theme, "value");
    return b;
  }

  public func CurrentPage() -> String { return this.m_page; }
  public func CurrentArg() -> String { return this.m_arg; }
  // a page changed its own state without a redraw (a map after a drag): the frame reopens on it
  public func SetArg(arg: String) -> Void { this.m_arg = arg; }
  public func Theme() -> String { return this.m_theme; }
  public func Content() -> ref<inkVerticalPanel> { return this.m_content; }
  public func Page() -> ref<TKPage> { return this.m_data; }
  public func RowWidth() -> Float { return this.m_width - 40.0; }
  public func Width() -> Float { return this.m_width; }

  // the frame is closing: live rows (a map mid-drag) let go of the frame's input
  public func StopCustom() -> Void {
    for c in this.m_custom {
      if IsDefined(c) {
        c.Stop();
      }
    }
    ArrayClear(this.m_custom);
  }

  private func SetTheme(theme: String) -> Void {
    if Equals(theme, "") || Equals(theme, this.m_theme) {
      return;
    }
    this.m_theme = theme;
    let i = 0;
    while i < ArraySize(this.m_chrome) {
      TKTheme.Paint(this.m_chrome[i], theme, this.m_roles[i]);
      i += 1;
    }
    for tab in this.m_tabs {
      TKTheme.Paint(tab.GetLabel(), theme, "value");
    }
  }

  // ---------------------------------------------------------------------------
  // Scrolling: the wheel over the page moves the content; the position is kept
  // when the same page redraws after an action, reset when the page changes
  // ---------------------------------------------------------------------------
  // the frame's global relative input: true when the wheel moved the page
  public func OnWheel(e: ref<inkPointerEvent>) -> Bool {
    if !IsDefined(this.m_scroll) || !e.IsAction(n"mouse_wheel") || e.IsHandled() {
      return false;
    }
    if IsDefined(this.m_data) && this.m_data.wheelReserved {
      return false;
    }
    let d = e.GetAxisData();
    if d == 0.0 {
      return false;
    }
    this.ScrollTo(this.m_scrollY - d * TKScale.F("scroll.step", 140.0));
    e.Handle();
    return true;
  }

  // the wheel over the scroll area itself
  protected cb func OnAreaRelative(e: ref<inkPointerEvent>) -> Bool {
    return this.OnWheel(e);
  }

  // a component adds the height it drew (GetDesiredSize can lag a frame or read 0)
  public func Grew(h: Float) -> Void { this.grown += h; }

  private func ScrollMax() -> Float {
    if !IsDefined(this.m_content) {
      return 0.0;
    }
    return MaxF(0.0, MaxF(this.m_content.GetDesiredSize().Y, this.grown) - this.m_scrollH);
  }

  public func ScrollTo(y: Float) -> Void {
    if !IsDefined(this.m_scroll) || !IsDefined(this.m_content) {
      return;
    }
    let max = this.ScrollMax();
    this.m_scrollY = ClampF(y, 0.0, max);
    this.m_content.SetTranslation(Vector2(0.0, -this.m_scrollY));
    this.PaintBar(max);
  }

  private func PaintBar(max: Float) -> Void {
    if !IsDefined(this.m_bar) || !IsDefined(this.m_barTrack) {
      return;
    }
    let show = max > 1.0;
    this.m_bar.SetVisible(show);
    this.m_barTrack.SetVisible(show);
    if !show {
      return;
    }
    let total = max + this.m_scrollH;
    let h = MaxF(24.0, this.m_scrollH * this.m_scrollH / total);
    this.m_bar.SetSize(Vector2(this.m_bar.GetSize().X, h));
    this.m_bar.SetMargin(inkMargin(0.0, (this.m_scrollH - h) * (this.m_scrollY / max), 0.0, 0.0));
  }

  // once the page has laid out (the frame calls it a moment after Show, or a
  // component after it grew): the bar and the clamp catch up
  public func Settle() -> Void {
    this.ScrollTo(this.m_scrollY);
  }

  // ---------------------------------------------------------------------------
  // History: the page before this one (the frame's right mouse button)
  // ---------------------------------------------------------------------------
  public func Back() -> Bool {
    let n = ArraySize(this.m_history);
    if n == 0 {
      return false;
    }
    let last = this.m_history[n - 1];
    ArrayPop(this.m_history);
    this.m_noPush = true;
    this.Show(StrBeforeFirst(last, "~"), StrAfterFirst(last, "~"), "");
    return true;
  }

  // ---------------------------------------------------------------------------
  // Tooltips: the cursor resting on a row's title shows what it means
  // ---------------------------------------------------------------------------
  public func Hoverable(w: ref<inkWidget>, tip: String) -> Void {
    if StrLen(tip) == 0 || !IsDefined(w) || !IsDefined(this.m_tipLayer) {
      return;
    }
    w.SetName(StringToName("tip_" + IntToString(ArraySize(this.m_tips))));
    ArrayPush(this.m_tips, tip);
    w.SetInteractive(true);
    w.RegisterToCallback(n"OnHoverOver", this, n"OnTipOver");
    w.RegisterToCallback(n"OnHoverOut", this, n"OnTipOut");
  }

  protected cb func OnTipOver(e: ref<inkPointerEvent>) -> Bool {
    let name = NameToString(e.GetTarget().GetName());
    if !StrBeginsWith(name, "tip_") || !IsDefined(this.m_tipLayer) {
      return false;
    }
    let i = StringToInt(StrAfterFirst(name, "tip_"), -1);
    if i < 0 || i >= ArraySize(this.m_tips) {
      return false;
    }
    this.HideTip();
    let at = WidgetUtils.GlobalToLocal(this.m_tipLayer, e.GetScreenSpacePosition());
    let w = TKScale.F("tip.w", 640.0);
    let font = TKScale.I("note", 26);
    let h = TKInk.Lines(this.m_tips[i], font, w - 40.0) * Cast<Float>(font) * 1.35 + 36.0;
    let x = MinF(at.X + 24.0, MaxF(0.0, this.m_tipLayer.GetSize().X - w));
    let y = MaxF(0.0, at.Y - h - 12.0);
    let box: ref<inkCanvas> = new inkCanvas();
    box.SetSize(Vector2(w, h));
    box.SetMargin(inkMargin(x, y, 0.0, 0.0));
    box.Reparent(this.m_tipLayer);
    let fill = TKInk.Rect(box, 0.0, 0.0, w, h);
    fill.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 1.0));
    fill.SetOpacity(0.92);
    this.Frame(box, w, h, 2.0, "value", 0.9);
    let t = this.Text(box, this.m_tips[i], font, n"Regular", "text", 0.0);
    t.SetLetterCase(textLetterCase.OriginalCase);
    t.SetMargin(inkMargin(20.0, 14.0, 0.0, 0.0));
    t.SetVAlign(inkEVerticalAlign.Top);
    t.SetWrapping(true, w - 40.0);
    this.m_tip = box;
    return false;
  }

  protected cb func OnTipOut(e: ref<inkPointerEvent>) -> Bool {
    this.HideTip();
    return false;
  }

  private func HideTip() -> Void {
    if IsDefined(this.m_tip) && IsDefined(this.m_tipLayer) {
      this.m_tipLayer.RemoveChild(this.m_tip);
    }
    this.m_tip = null;
  }

  // ---------------------------------------------------------------------------
  // Clicks
  // ---------------------------------------------------------------------------
  // "tab_<page>" or "tab_<page>~<arg>"
  protected cb func OnTabClick(widget: wref<inkWidget>) -> Bool {
    let target = StrAfterFirst(NameToString(widget.GetName()), "tab_");
    if StrContains(target, "~") {
      this.Show(StrBeforeFirst(target, "~"), StrAfterFirst(target, "~"), "");
    } else {
      this.Show(target, "", "");
    }
    return true;
  }

  // "act_<row>" or "act_<row>_<button>"
  protected cb func OnActClick(widget: wref<inkWidget>) -> Bool {
    let id = StrAfterFirst(NameToString(widget.GetName()), "act_");
    let n = 0;
    if StrContains(id, "_") {
      n = StringToInt(StrAfterFirst(id, "_"), 0);
      id = StrBeforeFirst(id, "_");
    }
    let i = StringToInt(id, -1);
    if !IsDefined(this.m_data) || i < 0 || i >= this.m_data.Count() {
      return true;
    }
    let row = this.m_data.Row(i);
    if n < 0 || n >= ArraySize(row.actions) {
      return true;
    }
    this.Act(row.actions[n], row.args[n]);
    return true;
  }

  // runs an action on the current page and redraws (the next page if it named one)
  public func Act(action: String, arg: String) -> Void {
    let act: ref<TKPage> = new TKPage();
    act.content = this.m_provider;
    act.page = this.m_page;
    this.Fields(act);
    act.Act(action, arg);
    if act.rebuild && IsDefined(this.m_provider) {
      this.m_provider.Rebuild();
    }
    if act.skipRedraw {
      return;
    }
    let next = StrLen(act.nextPage) > 0 ? act.nextPage : this.m_page;
    let nextArg = StrLen(act.nextPage) > 0 ? act.nextArg : this.m_arg;
    this.Show(next, nextArg, act.message);
  }

  // ---------------------------------------------------------------------------
  // Build the page and draw it
  // ---------------------------------------------------------------------------
  public func Show(page: String, arg: String, message: String) -> Void {
    if !IsDefined(this.m_content) {
      return;
    }
    let same = Equals(page, this.m_page) && Equals(arg, this.m_arg);
    if !same && StrLen(this.m_page) > 0 && !this.m_noPush {
      ArrayPush(this.m_history, this.m_page + "~" + this.m_arg);
      while ArraySize(this.m_history) > 30 {
        ArrayErase(this.m_history, 0);
      }
    }
    this.m_noPush = false;
    this.m_page = page;
    this.m_arg = arg;
    this.StopCustom();
    this.HideTip();
    ArrayClear(this.m_tips);
    this.grown = 0.0;
    this.m_content.RemoveAllChildren();
    ArrayClear(this.m_buttons);
    ArrayClear(this.m_sliders);
    ArrayClear(this.m_inputs);
    ArrayClear(this.m_inputKeys);
    this.m_drag = -1;
    this.linkRows = 0;
    this.tableLine = 0;
    this.m_cards = null;
    this.m_cardCount = 0;
    this.m_split = null;
    this.m_data = new TKPage();
    this.m_data.content = this.m_provider;
    this.m_data.page = page;
    this.m_data.Request(page, arg);
    this.SetTheme(this.m_data.theme);
    this.m_message.SetText(TKScale.T(message));
    // the sidebar highlights the section the page belongs to
    let section = StrLen(this.m_data.section) > 0 ? this.m_data.section : page;
    let i = 0;
    while i < ArraySize(this.m_tabs) {
      this.m_tabs[i].SetDisabled(Equals(NameToString(this.m_tabs[i].GetName()), "tab_" + section));
      i += 1;
    }
    if IsDefined(this.m_frame) {
      this.m_frame.SetBare(this.m_data.bare);
    }
    if !this.m_data.answered {
      this.m_title.SetText(TKScale.T("LINK OFFLINE"));
      this.m_subtitle.SetText(TKScale.T("Load a save first, then try again."));
      return;
    }
    this.m_title.SetText(TKScale.T(this.m_data.title));
    this.m_subtitle.SetText(TKScale.T(this.m_data.subtitle));
    if StrLen(this.m_data.message) > 0 {
      this.m_message.SetText(TKScale.T(this.m_data.message));
    }
    // Column rows send the rows after them to columns; the page's own panel and
    // width come back afterwards
    let content = this.m_content;
    let width = this.m_width;
    i = 0;
    while i < this.m_data.Count() {
      this.Draw(i, this.m_data.Row(i));
      i += 1;
    }
    this.m_content = content;
    this.m_width = width;
    // a redraw of the same page keeps its place; a new page starts at the top
    this.ScrollTo(same ? this.m_scrollY : 0.0);
  }

  private func Draw(i: Int32, r: ref<TKRow>) -> Void {
    let kind = r.kind;
    if kind != TKKind.Card() && kind != TKKind.Ticker() && kind != TKKind.Stat() && kind != TKKind.Tile() {
      this.m_cards = null;   // the next card or tile starts a new line
    }
    switch kind {
      case 1: TKRows.Heading(this, r); break;
      case 2: TKRows.Text(this, r); break;
      case 3: TKRows.Pair(this, r); break;
      case 4: TKRows.Meter(this, r); break;
      case 5: TKRows.Button(this, i, r); break;
      case 6: TKRows.Note(this, r); break;
      case 7: TKRows.Gap(this); break;
      case 8: TKRows.Item(this, i, r); break;
      case 9: TKRows.Links(this, r); break;
      case 12: TKRows.Buttons(this, i, r); break;
      case 13: this.SliderRow(i, r); break;
      case 14: TKRows.Track(this, r); break;
      case 15: TKRows.Section(this, i, r); break;
      case 16: this.InputRow(r); break;
      case 17: TKRows.Entry(this, r); break;
      case 18: TKRows.Dossier(this, r); break;
      case 19: TKRows.Columns(this, r); break;
      case 20: this.CustomRow(r); break;
      case 21: TKTables.Table(this, r); break;
      case 22: TKTiles.Card(this, i, r); break;
      case 23: TKTables.Board(this, i, r); break;
      case 24: this.ColumnStart(r.fraction); break;
      case 25: this.ColumnsEnd(); break;
      case 26: TKTiles.Ticker(this, r); break;
      case 27: TKTiles.Stat(this, r); break;
      case 28: TKTiles.Tile(this, i, r); break;
      default: break;
    }
  }

  private func CustomRow(r: ref<TKRow>) -> Void {
    if IsDefined(this.m_provider) {
      let live = this.m_provider.Custom(this, this.m_content, this.m_data, r);
      if IsDefined(live) {
        ArrayPush(this.m_custom, live);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Shared drawing helpers (the components draw through these)
  // ---------------------------------------------------------------------------
  public func Text(parent: ref<inkCompoundWidget>, text: String, size: Int32, weight: CName, role: String, above: Float) -> ref<inkText> {
    let t = TKInk.Plain(parent, TKScale.T(text), size, weight, above);
    TKTheme.PaintNew(t, this.m_theme, role);
    return t;
  }

  public func Tone(w: ref<inkWidget>, color: String) -> Void { TKTheme.Tone(w, this.m_theme, color); }

  // a widget painted with PaintNew, in a mark's colour
  public func Mark(t: ref<inkWidget>, red: Bool, green: Bool) -> Void {
    if red {
      TKTheme.Fix(t, this.m_theme, TKTheme.Loss());
    } else {
      if green {
        TKTheme.Fix(t, this.m_theme, TKTheme.Gain());
      }
    }
  }

  // a wrapped text with the card marks
  public func Marked(parent: ref<inkCompoundWidget>, s: String, size: Int32, weight: CName, above: Float, width: Float) -> ref<inkText> {
    let red: Bool;
    let green: Bool;
    let t = this.Wrap(this.Text(parent, TKTheme.Unmark(s, red, green), size, weight, "text", above), width);
    this.Mark(t, red, green);
    return t;
  }

  public func Wrap(t: ref<inkText>, width: Float) -> ref<inkText> {
    t.SetWrapping(true, width);
    return t;
  }

  public func Paint(w: ref<inkWidget>, role: String) -> Void { TKTheme.PaintNew(w, this.m_theme, role); }
  public func Fix(w: ref<inkWidget>, color: HDRColor) -> Void { TKTheme.Fix(w, this.m_theme, color); }

  // a short vertical bar between two pieces on one line
  public func Sep(parent: ref<inkCompoundWidget>, size: Int32) -> Void {
    let bar: ref<inkRectangle> = new inkRectangle();
    bar.SetSize(Vector2(2.0, Cast<Float>(size) * 0.8));
    bar.SetMargin(inkMargin(16.0, Cast<Float>(size) * 0.2, 16.0, 0.0));
    bar.SetVAlign(inkEVerticalAlign.Center);
    bar.Reparent(parent);
    TKTheme.PaintNew(bar, this.m_theme, "rule");
  }

  // a full-width line under a block
  public func Rule(parent: ref<inkCompoundWidget>, above: Float, opacity: Float) -> Void {
    let rule: ref<inkRectangle> = new inkRectangle();
    rule.SetSize(Vector2(this.RowWidth(), 2.0));
    rule.SetMargin(inkMargin(0.0, above, 0.0, 0.0));
    rule.SetHAlign(inkEHorizontalAlign.Left);
    rule.SetOpacity(opacity);
    rule.Reparent(parent);
    TKTheme.PaintNew(rule, this.m_theme, "rule");
  }

  // a thin frame around a w x h box
  public func Frame(box: ref<inkCanvas>, w: Float, h: Float, t: Float, role: String, opacity: Float) -> Void {
    let edges = [Vector4(0.0, 0.0, w, t), Vector4(0.0, h - t, w, t), Vector4(0.0, 0.0, t, h), Vector4(w - t, 0.0, t, h)];
    for r in edges {
      let e = TKInk.Rect(box, r.X, r.Y, r.Z, r.W);
      e.SetOpacity(opacity);
      TKTheme.PaintNew(e, this.m_theme, role);
    }
  }

  // a frame in a row colour (a card pointed at, a dossier stamp)
  public func TonedFrame(box: ref<inkCanvas>, w: Float, h: Float, t: Float, color: String) -> Void {
    let edges = [Vector4(0.0, 0.0, w, t), Vector4(0.0, h - t, w, t), Vector4(0.0, 0.0, t, h), Vector4(w - t, 0.0, t, h)];
    for r in edges {
      let e = TKInk.Rect(box, r.X, r.Y, r.Z, r.W);
      TKTheme.PaintNew(e, this.m_theme, "value");
      this.Tone(e, color);
    }
  }

  // a dark panel with a thin frame
  public func Panel(box: ref<inkCanvas>, w: Float, h: Float, opacity: Float) -> Void {
    let fill = TKInk.Rect(box, 0.0, 0.0, w, h);
    fill.SetTintColor(new HDRColor(0.0, 0.0, 0.0, 1.0));
    fill.SetOpacity(opacity);
    this.Frame(box, w, h, 2.0, "rule", 1.0);
  }

  // A cell in a grid of cards or tiles: side by side, a new line when the row is
  // full (or when the kind of row changes)
  public func GridCell(kind: Int32, w: Float, h: Float) -> ref<inkCanvas> {
    let gap = TKScale.SpaceLG();
    let per = Max(1, Cast<Int32>((this.RowWidth() + gap) / (w + gap)));
    if !IsDefined(this.m_cards) || this.m_cardCount >= per || this.m_gridKind != kind {
      this.m_cards = TKInk.Strip(this.m_content, IsDefined(this.m_cards) && this.m_gridKind == kind ? gap : 12.0);
      this.m_cardCount = 0;
      this.m_gridKind = kind;
      this.grown += h + gap;
    }
    let cell: ref<inkCanvas> = new inkCanvas();
    cell.SetSize(Vector2(w, h));
    cell.SetMargin(inkMargin(this.m_cardCount > 0 ? gap : 0.0, 0.0, 0.0, 0.0));
    cell.Reparent(this.m_cards);
    this.m_cardCount += 1;
    return cell;
  }

  // A full-width row of fixed size: text on the left (wrapping at textW), and
  // whatever is pinned to its right edge (PinRight) lines up on every row.
  // Canvases keep the size they're given, unlike panels that shrink to content.
  public func RowBox(textW: Float, text: String, value: String, color: String, opt tip: String) -> ref<inkCanvas> {
    let ts = TKScale.I("row.title", 32);
    let vs = TKScale.I("row.detail", 29);
    let h = MaxF(TKScale.F("row.minh", 66.0), TKInk.Lines(text, ts, textW) * Cast<Float>(ts) * 1.32
      + TKInk.Lines(value, vs, textW) * Cast<Float>(vs) * 1.32 + 8.0);
    let row: ref<inkCanvas> = new inkCanvas();
    row.SetSize(Vector2(this.RowWidth(), h));
    row.SetMargin(inkMargin(0.0, TKScale.F("row.gap", 10.0), 0.0, 0.0));
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.Reparent(this.m_content);
    this.grown += h + TKScale.F("row.gap", 10.0);
    let col: ref<inkVerticalPanel> = new inkVerticalPanel();
    col.Reparent(row);
    if StrLen(text) > 0 {
      let title = this.Wrap(this.Text(col, text, ts, n"Medium", "value", 0.0), textW);
      this.Tone(title, color);
      this.Hoverable(title, tip);
    }
    if StrLen(value) > 0 {
      this.Wrap(this.Text(col, value, vs, n"Regular", "text", 2.0), textW);
    }
    return row;
  }

  public func PinRight(w: ref<inkWidget>) -> Void {
    w.SetAnchor(inkEAnchor.TopRight);
    w.SetAnchorPoint(Vector2(1.0, 0.0));
    w.SetMargin(inkMargin(0.0, 2.0, 0.0, 0.0));
  }

  // a button that runs row i's button n (its label from the row: a leading "!" disables it)
  public func ActButton(parent: ref<inkCompoundWidget>, i: Int32, n: Int32, label: String, on: Bool, width: Float, height: Float, size: Int32) -> ref<TKButton> {
    let off = StrBeginsWith(label, "!");
    let b = TKButton.Make(parent, off ? StrAfterFirst(label, "!") : label, "act_" + IntToString(i) + (n > 0 ? "_" + IntToString(n) : ""), width, height, size);
    b.SetDisabled(off || !on);
    b.RegisterToCallback(n"OnBtnClick", this, n"OnActClick");
    TKTheme.Paint(b.GetLabel(), this.m_theme, "value");
    ArrayPush(this.m_buttons, b);
    return b;
  }

  // a button that opens a page ("page" or "page~arg")
  public func LinkButton(parent: ref<inkCompoundWidget>, label: String, target: String, current: Bool, width: Float, height: Float, size: Int32) -> ref<TKButton> {
    let b = TKButton.Make(parent, label, "tab_" + target, width, height, size);
    b.SetDisabled(current);
    b.RegisterToCallback(n"OnBtnClick", this, n"OnTabClick");
    TKTheme.Paint(b.GetLabel(), this.m_theme, "value");
    ArrayPush(this.m_buttons, b);
    return b;
  }

  // ---- columns: the rows after a Column row go in a panel that share of the
  // page wide, beside the one before (Show puts the page's panel back) ----
  private func ColumnStart(share: Float) -> Void {
    if !IsDefined(this.m_split) {
      this.m_pageContent = this.m_content;
      this.m_pageWidth = this.m_width;
      this.m_split = TKInk.Strip(this.m_content, 0.0);
    }
    let col: ref<inkVerticalPanel> = new inkVerticalPanel();
    col.SetVAlign(inkEVerticalAlign.Top);
    col.SetMargin(inkMargin(0.0, 0.0, 40.0, 0.0));   // rows are 40 narrower than the column: the gap to the next
    col.Reparent(this.m_split);
    this.m_content = col;
    this.m_width = this.m_pageWidth * ClampF(share, 0.1, 1.0);
  }

  private func ColumnsEnd() -> Void {
    if IsDefined(this.m_split) {
      this.m_content = this.m_pageContent;
      this.m_width = this.m_pageWidth;
      this.m_split = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Text boxes
  // ---------------------------------------------------------------------------
  private func InputRow(r: ref<TKRow>) -> Void {
    let row: ref<inkCanvas> = new inkCanvas();
    row.SetSize(Vector2(this.RowWidth(), 96.0));
    row.SetMargin(inkMargin(0.0, TKScale.F("row.gap", 10.0), 0.0, 0.0));
    row.SetHAlign(inkEHorizontalAlign.Left);
    row.Reparent(this.m_content);
    this.grown += 106.0;
    let name = this.Text(row, r.text, TKScale.I("row.title", 32), n"Medium", "value", 0.0);
    name.SetMargin(inkMargin(0.0, 24.0, 0.0, 0.0));
    let box = HubTextInput.Create();
    box.SetName(StringToName("in_" + r.arg));
    box.SetText(r.value);
    box.SetLetterCase(textLetterCase.OriginalCase);
    box.SetMaxLength(300);
    box.Reparent(row);
    box.SetWidth(this.RowWidth() - 460.0);
    box.GetRootWidget().SetMargin(inkMargin(440.0, 0.0, 0.0, 0.0));
    ArrayPush(this.m_inputs, box);
    ArrayPush(this.m_inputKeys, r.arg);
  }

  // copy every text box into the action's page object
  private func Fields(act: ref<TKPage>) -> Void {
    let k = 0;
    while k < ArraySize(this.m_inputs) {
      ArrayPush(act.fieldKeys, this.m_inputKeys[k]);
      ArrayPush(act.fieldValues, this.m_inputs[k].GetText());
      k += 1;
    }
  }

  // true while the player is typing in a text box (the open key must not close the frame)
  public func IsTyping() -> Bool {
    for box in this.m_inputs {
      if box.IsFocused() {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Slider: a bar of segments, lit up to the value. Each segment sits in a
  // taller, gapless hit area, so a click anywhere on the bar lands on a value.
  // Pressing sets it at once, dragging follows the cursor, and every change is
  // applied as it happens; letting go refreshes the page.
  // ---------------------------------------------------------------------------
  private func SliderRow(i: Int32, r: ref<TKRow>) -> Void {
    let parts = StrSplit(r.label, "|");
    if ArraySize(parts) < 4 {
      return;
    }
    let sl: ref<TKSlider> = new TKSlider();
    sl.row = i;
    sl.min = StringToInt(parts[0]);
    let max = StringToInt(parts[1]);
    sl.step = Max(1, StringToInt(parts[2]));
    sl.value = StringToInt(parts[3]);
    sl.suffix = ArraySize(parts) > 4 ? parts[4] : "";
    let count = (max - sl.min) / sl.step + 1;
    let w = TKScale.F("slider.w", 612.0);
    let h = TKScale.F("slider.h", 26.0);
    let line = this.RowBox(this.RowWidth() - w - 160.0, r.text, r.value, r.color, r.tip);
    let group: ref<inkHorizontalPanel> = new inkHorizontalPanel();
    group.Reparent(line);
    this.PinRight(group);
    let track: ref<inkHorizontalPanel> = new inkHorizontalPanel();
    track.SetMargin(inkMargin(0.0, 4.0, 0.0, 0.0));
    track.Reparent(group);
    let cell = w / Cast<Float>(count);
    let gap = cell >= 6.0 ? 2.0 : 1.0;
    let id = ArraySize(this.m_sliders);
    let k = 0;
    while k < count {
      let name = StringToName("sl_" + IntToString(id) + "_" + IntToString(k));
      let hit: ref<inkCanvas> = new inkCanvas();
      hit.SetName(name);
      hit.SetSize(Vector2(cell, h + 28.0));
      hit.SetInteractive(true);
      hit.Reparent(track);
      hit.RegisterToCallback(n"OnPress", this, n"OnSlidePress");
      hit.RegisterToCallback(n"OnHoverOver", this, n"OnSlideHover");
      hit.RegisterToCallback(n"OnRelease", this, n"OnSlideRelease");
      let seg: ref<inkRectangle> = new inkRectangle();
      seg.SetName(name);
      seg.SetSize(Vector2(MaxF(1.0, cell - gap), h));
      seg.SetMargin(inkMargin(0.0, 14.0, 0.0, 0.0));
      seg.Reparent(hit);
      ArrayPush(sl.segs, seg);
      k += 1;
    }
    let readout = this.Text(group, "", TKScale.I("row.title", 32), n"Semi-Bold", "value", 0.0);
    readout.SetMargin(inkMargin(24.0, 6.0, 0.0, 0.0));
    readout.SetSize(Vector2(120.0, 40.0));
    sl.readout = readout;
    ArrayPush(this.m_sliders, sl);
    this.PaintSlider(sl);
  }

  private func PaintSlider(sl: ref<TKSlider>) -> Void {
    let k = 0;
    while k < ArraySize(sl.segs) {
      let lit = sl.min + k * sl.step <= sl.value;
      TKTheme.PaintNew(sl.segs[k], this.m_theme, lit ? "value" : "rule");
      sl.segs[k].SetOpacity(lit ? 1.0 : 0.55);
      k += 1;
    }
    sl.readout.SetText(IntToString(sl.value) + sl.suffix);
  }

  // "sl_<slider>_<segment>" -> slider index, value
  private func SlideTarget(e: ref<inkPointerEvent>, out slider: Int32, out value: Int32) -> Bool {
    let name = NameToString(e.GetTarget().GetName());
    if !StrBeginsWith(name, "sl_") {
      return false;
    }
    let rest = StrAfterFirst(name, "sl_");
    slider = StringToInt(StrBeforeFirst(rest, "_"), -1);
    if slider < 0 || slider >= ArraySize(this.m_sliders) {
      return false;
    }
    let sl = this.m_sliders[slider];
    value = sl.min + StringToInt(StrAfterFirst(rest, "_"), 0) * sl.step;
    return true;
  }

  // applies the slider's value (the page itself is refreshed when the drag ends)
  private func SlideCommit(sl: ref<TKSlider>) -> ref<TKPage> {
    let act: ref<TKPage> = new TKPage();
    act.content = this.m_provider;
    act.page = this.m_page;
    let row = this.m_data.Row(sl.row);
    act.Act(row.action, row.arg + ":" + IntToString(sl.value));
    return act;
  }

  private func SlideSet(s: Int32, v: Int32) -> Void {
    let sl = this.m_sliders[s];
    if sl.value != v {
      sl.value = v;
      this.PaintSlider(sl);
      this.SlideCommit(sl);
    }
  }

  protected cb func OnSlidePress(e: ref<inkPointerEvent>) -> Bool {
    let s: Int32;
    let v: Int32;
    if e.IsAction(n"click") && this.SlideTarget(e, s, v) {
      this.m_drag = s;
      this.m_sliders[s].value = v;
      this.PaintSlider(this.m_sliders[s]);
      this.SlideCommit(this.m_sliders[s]);
    }
    return true;
  }

  protected cb func OnSlideHover(e: ref<inkPointerEvent>) -> Bool {
    if this.m_drag < 0 {
      return true;
    }
    // the button came up somewhere off the bar: the drag is over
    if !RedFunc.MouseButton(1) {
      this.SlideEnd();
      return true;
    }
    let s: Int32;
    let v: Int32;
    if this.SlideTarget(e, s, v) && s == this.m_drag {
      this.SlideSet(s, v);
    }
    return true;
  }

  protected cb func OnSlideRelease(e: ref<inkPointerEvent>) -> Bool {
    if this.m_drag >= 0 && e.IsAction(n"click") {
      this.SlideEnd();
    }
    return true;
  }

  private func SlideEnd() -> Void {
    let sl = this.m_sliders[this.m_drag];
    this.m_drag = -1;
    let act = this.SlideCommit(sl);
    if act.rebuild && IsDefined(this.m_provider) {
      this.m_provider.Rebuild();
    }
    this.Show(StrLen(act.nextPage) > 0 ? act.nextPage : this.m_page, StrLen(act.nextPage) > 0 ? act.nextArg : this.m_arg, act.message);
  }
}
