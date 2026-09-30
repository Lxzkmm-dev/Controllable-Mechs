// =============================================================================
// TERMINAL KIT - THE PAGE MODEL
// A page is a list of rows a content provider (TKContent) fills in and TKView
// draws. Rows are data: a kind, texts, a colour, and for action rows a typed
// list of buttons (label, action, args) split once here, so the renderer never
// re-parses a packed string. The string builders below ("A|B" labels, "a|b"
// actions, "x|y" or "x\ny" args) stay for convenience; the typed builders take
// arrays. TerminalKit has no dependency on the mod using it: it needs only
// Codeware (buttons, text boxes) and RedFunctions (the mouse state).
// =============================================================================
module TerminalKit

import Codeware.UI.*

// row kinds
public abstract class TKKind {
  public static func Heading() -> Int32 = 1
  public static func Text() -> Int32 = 2
  public static func Pair() -> Int32 = 3
  public static func Meter() -> Int32 = 4
  public static func Button() -> Int32 = 5
  public static func Note() -> Int32 = 6
  public static func Gap() -> Int32 = 7
  public static func Item() -> Int32 = 8
  public static func Links() -> Int32 = 9
  public static func Buttons() -> Int32 = 12
  public static func Slider() -> Int32 = 13
  public static func Track() -> Int32 = 14
  public static func Section() -> Int32 = 15
  public static func Input() -> Int32 = 16
  public static func Entry() -> Int32 = 17
  public static func Dossier() -> Int32 = 18
  public static func Columns() -> Int32 = 19
  public static func Custom() -> Int32 = 20
  public static func Table() -> Int32 = 21
  public static func Card() -> Int32 = 22
  public static func Board() -> Int32 = 23
  public static func ColumnStart() -> Int32 = 24
  public static func ColumnsEnd() -> Int32 = 25
  public static func Ticker() -> Int32 = 26
  public static func Stat() -> Int32 = 27
  public static func Tile() -> Int32 = 28
}

public class TKRow extends IScriptable {
  public let kind: Int32;
  public let text: String;
  public let value: String;
  public let color: String;
  public let label: String;      // raw: labels, or a data field for data rows (see each builder)
  public let action: String;     // raw actions, or data
  public let arg: String;        // raw args, or data
  public let fraction: Float;
  public let on: Bool;
  public let extra: String;      // what a row needs beyond the rest (Levels: "level:max"; a custom row's payload)
  public let tip: String;        // shown when the cursor rests on the row's title
  // action rows only: the buttons, typed
  public let labels: array<String>;
  public let actions: array<String>;
  public let args: array<String>;

  public func IsAction() -> Bool = ArraySize(this.actions) > 0
}

// String helpers the kit needs (empty parts count, unlike StrSplit)
public abstract class TKStr {
  public static func Split(s: String, sep: String) -> array<String> {
    let parts: array<String>;
    let n = StrLen(sep);
    let at = n > 0 ? StrFindFirst(s, sep) : -1;
    while at >= 0 {
      ArrayPush(parts, StrLeft(s, at));
      s = StrMid(s, at + n, StrLen(s) - at - n);
      at = StrFindFirst(s, sep);
    }
    ArrayPush(parts, s);
    return parts;
  }

  public static func Part(s: String, sep: String, i: Int32) -> String {
    let parts = TKStr.Split(s, sep);
    return i < ArraySize(parts) ? parts[i] : "";
  }

  public static func Join(parts: array<String>, sep: String) -> String {
    let out = "";
    let i = 0;
    while i < ArraySize(parts) {
      out += (i > 0 ? sep : "") + parts[i];
      i += 1;
    }
    return out;
  }
}

public class TKPage extends IScriptable {
  public let page: String;
  public let answered: Bool;
  public let title: String;
  public let subtitle: String;
  public let message: String;
  public let nextPage: String;
  public let nextArg: String;
  public let theme: String;        // palette id (TKTheme), "" = keep the current one
  public let rebuild: Bool;        // an action changed the layout: rebuild the whole frame
  public let skipRedraw: Bool;     // an action handled everything itself: don't redraw
  public let section: String;      // sidebar tab to highlight ("" = the page itself)
  public let bare: Bool;           // hide the frame around the page (a page that needs the world in view)
  public let wheelReserved: Bool;  // a row on this page uses the mouse wheel itself: the page doesn't scroll
  public let rows: array<ref<TKRow>>;
  // text boxes on the page (Input rows), handed to Act with every action
  public let fieldKeys: array<String>;
  public let fieldValues: array<String>;
  public let content: ref<TKContent>;   // who fills and acts on it (set by the view)

  public func Request(page: String, arg: String) -> Void {
    if IsDefined(this.content) {
      this.content.Request(this, page, arg);
    }
  }

  public func Act(action: String, arg: String) -> Void {
    if IsDefined(this.content) {
      this.content.Act(this, action, arg);
    }
  }

  public func SetTitle(title: String, subtitle: String) -> Void {
    this.title = title;
    this.subtitle = subtitle;
    this.answered = true;
  }
  public func SetMessage(text: String) -> Void { this.message = text; this.answered = true; }
  public func GoTo(page: String, arg: String) -> Void { this.nextPage = page; this.nextArg = arg; }
  public func SetTheme(id: String) -> Void { this.theme = id; }
  public func Rebuild() -> Void { this.rebuild = true; }
  public func SetSection(id: String) -> Void { this.section = id; }
  public func Bare() -> Void { this.bare = true; }
  public func GetField(key: String) -> String {
    let i = 0;
    while i < ArraySize(this.fieldKeys) {
      if Equals(this.fieldKeys[i], key) {
        return this.fieldValues[i];
      }
      i += 1;
    }
    return "";
  }

  public func Row(i: Int32) -> ref<TKRow> = i >= 0 && i < ArraySize(this.rows) ? this.rows[i] : new TKRow()
  public func Count() -> Int32 = ArraySize(this.rows)

  // ---- raw rows: data in label / action / arg ----
  private func Push(kind: Int32, text: String, value: String, color: String, label: String, action: String, arg: String, fraction: Float, on: Bool) -> ref<TKRow> {
    let r = new TKRow();
    r.kind = kind; r.text = text; r.value = value; r.color = color;
    r.label = label; r.action = action; r.arg = arg;
    r.fraction = fraction; r.on = on;
    ArrayPush(this.rows, r);
    this.answered = true;
    return r;
  }

  // ---- action rows: the buttons split once, typed ----
  // labels "A|B" (a leading "!" = disabled), actions "a|b", args "x|y" or
  // "x\ny" (when an arg itself holds "|"). A row with one action keeps its
  // whole arg string, "|" and all.
  private func PushAct(kind: Int32, text: String, value: String, color: String, labels: String, actions: String, args: String, fraction: Float, on: Bool) -> ref<TKRow> {
    let r = this.Push(kind, text, value, color, labels, actions, args, fraction, on);
    let names = TKStr.Split(labels, "|");
    let acts = TKStr.Split(actions, "|");
    let vals = ArraySize(acts) > 1 ? (StrContains(args, "\n") ? TKStr.Split(args, "\n") : TKStr.Split(args, "|")) : [args];
    let k = 0;
    while k < ArraySize(acts) {
      ArrayPush(r.labels, k < ArraySize(names) ? names[k] : "");
      ArrayPush(r.actions, acts[k]);
      ArrayPush(r.args, k < ArraySize(vals) ? vals[k] : "");
      k += 1;
    }
    return r;
  }

  // the typed builder: one entry per button
  public func Actions(kind: Int32, text: String, value: String, color: String, labels: array<String>, actions: array<String>, args: array<String>, fraction: Float, on: Bool) -> ref<TKRow> {
    let r = this.Push(kind, text, value, color, TKStr.Join(labels, "|"), TKStr.Join(actions, "|"), TKStr.Join(args, "\n"), fraction, on);
    r.labels = labels; r.actions = actions; r.args = args;
    return r;
  }

  public func Heading(text: String) -> Void { this.Push(TKKind.Heading(), text, "", "red", "", "", "", 0.0, false); }
  public func Text(text: String, color: String) -> Void { this.Push(TKKind.Text(), text, "", color, "", "", "", 0.0, false); }
  public func Pair(label: String, value: String, color: String) -> Void { this.Push(TKKind.Pair(), label, value, color, "", "", "", 0.0, false); }
  public func Meter(label: String, value: String, fraction: Float) -> Void { this.Push(TKKind.Meter(), label, value, "yellow", "", "", "", fraction, false); }
  public func Button(label: String, action: String, arg: String, on: Bool) -> Void { this.PushAct(TKKind.Button(), "", "", "", label, action, arg, 0.0, on); }
  public func Note(text: String) -> Void { this.Push(TKKind.Note(), text, "", "dim", "", "", "", 0.0, false); }
  // A note under an item row, wrapped at the row's text width (clear of its button)
  public func ItemNote(text: String) -> Void { this.Push(TKKind.Note(), text, "item", "dim", "", "", "", 0.0, false); }
  public func Gap() -> Void { this.Push(TKKind.Gap(), "", "", "", "", "", "", 0.0, false); }
  public func Item(text: String, value: String, color: String, label: String, action: String, arg: String, on: Bool) -> Void {
    this.PushAct(TKKind.Item(), text, value, color, label, action, arg, 0.0, on);
  }
  // An item with a level track left of its button: boxes I, II, III... up to
  // `max`, the first `level` filled
  public func Levels(text: String, value: String, color: String, level: Int32, max: Int32, label: String, action: String, arg: String, on: Bool) -> Void {
    this.PushAct(TKKind.Item(), text, value, color, label, action, arg, 0.0, on).extra = IntToString(level) + ":" + IntToString(max);
  }
  // A table line: cells "a|b|c" across the columns `cols` ("L50|R25|R25": each
  // cell left or right aligned in its share of the row's width, in %). Styles:
  // "head" column titles, "group" a small heading inside the table, "line"
  // (every other one shaded), "total" (a rule above), "net" (larger, a double
  // rule under). Amounts starting with "+" show green, with "-" red, a lone "-"
  // dim; a cell starting with "!" shows red (the "!" isn't shown).
  public func Ledger(style: String, cells: String, cols: String) -> Void {
    this.Push(TKKind.Table(), cells, cols, style, "", "", "", 0.0, true);
  }
  // A listing card. Cards sit side by side and wrap to a new line when the row
  // is full. head "tag|title|sub|price": the tag in `color` over a dark strip,
  // the price large; details "a|b|c", a line each. In both, a leading "!" shows
  // red and "*" green (neither is shown), "+" amounts green. Buttons along the
  // bottom as in Buttons; `bright` false dims the card; a "*colour" frames it.
  public func Card(head: String, details: String, color: String, labels: String, actions: String, args: String, bright: Bool) -> Void {
    this.PushAct(TKKind.Card(), head, details, color, labels, actions, args, 0.0, bright);
  }
  // A departures board line: cells across the columns `cols` (as Ledger) on dark
  // split-flap tiles in amber; style "title" (large, no tiles, a rule under it),
  // "head" (column titles) or "line". A cell mark "!" shows red, "*" green, "^"
  // bright yellow, "~" grey. A button on the right when `label` isn't empty.
  public func Board(style: String, cells: String, cols: String, label: String, action: String, arg: String, on: Bool) -> Void {
    this.PushAct(TKKind.Board(), cells, cols, style, label, action, arg, 0.0, on);
  }
  // A market tile, laid out in a grid like cards: the name, today's value large,
  // the change ("*UP 6%" green, "!DOWN 9%" red), a line through `series`
  // ("0.92,1.04,..." oldest first) with a faint mark at 1.00, and a note under it
  public func Ticker(name: String, value: String, change: String, series: String, note: String) -> Void {
    this.Push(TKKind.Ticker(), name + "|" + value + "|" + change + "|" + note, series, "", "", "", "", 0.0, true);
  }
  // A stat tile in a grid (like cards): the name, the value large, a line under
  // it (card marks: "!" red, "*" green) and a bar filled to `fraction` (below 0: none)
  public func Stat(name: String, value: String, sub: String, fraction: Float) -> Void {
    this.Push(TKKind.Stat(), name + "|" + value + "|" + sub, "", "", "", "", "", fraction, true);
  }
  // A small tile in a grid (like cards) that opens something: a bar and the name in
  // `color`, the value large, a line under it (card marks), a button along the bottom
  public func Tile(name: String, value: String, sub: String, color: String, label: String, action: String, arg: String, on: Bool) -> Void {
    this.PushAct(TKKind.Tile(), name + "|" + value + "|" + sub, "", color, label, action, arg, 0.0, on);
  }
  // The rows after this go in a column `share` (0..1) of the page's width, to the
  // right of the column before it; EndColumns goes back to the full width
  public func Column(share: Float) -> Void { this.Push(TKKind.ColumnStart(), "", "", "", "", "", "", share, true); }
  public func EndColumns() -> Void { this.Push(TKKind.ColumnsEnd(), "", "", "", "", "", "", 0.0, true); }
  // Item with several buttons on the right: labels "A|B", actions "a|b", args
  // "x|y" (same order). A label starting with "!" is shown disabled.
  public func Buttons(text: String, value: String, color: String, labels: String, actions: String, args: String) -> Void {
    this.PushAct(TKKind.Buttons(), text, value, color, labels, actions, args, 0.0, true);
  }
  // A slider: spec "min|max|step|value|suffix" (e.g. "0|50|1|25|%"). Click or drag
  // on the bar; letting go calls Act(action, arg + ":" + value).
  public func Slider(text: String, value: String, color: String, spec: String, action: String, arg: String) -> Void {
    this.PushAct(TKKind.Slider(), text, value, color, spec, action, arg, 0.0, true);
  }
  // A meter with named marks under it: names "A|B|C", marks "0|0.2|0.4" (0..1, same order)
  public func Track(text: String, value: String, fraction: Float, names: String, marks: String) -> Void {
    this.Push(TKKind.Track(), text, value, "", names, marks, "", fraction, true);
  }
  // A text box: label on the left, the box starts with `value`; its text reaches
  // the provider as GetField(field) when any button on the page is pressed
  public func Input(label: String, value: String, field: String) -> Void {
    this.Push(TKKind.Input(), label, value, "", "", "", field, 0.0, true);
  }
  // A collapsible section heading: clicking it (or its button) runs action / arg
  public func Section(text: String, value: String, open: Bool, action: String, arg: String) -> Void {
    this.PushAct(TKKind.Section(), text, value, "", open ? "CLOSE" : "OPEN", action, arg, 0.0, open);
  }
  // A feed entry: time, status, tag, headline (coloured), details "a|b|c" set
  // apart by separator bars, and a quoted report under it
  public func Entry(time: String, status: String, tag: String, head: String, details: String, quote: String, color: String) -> Void {
    this.Push(TKKind.Entry(), head, details, color, time + "|" + status + "|" + tag, quote, "", 0.0, true);
  }
  // A dossier header: name, the line under it, a status stamp in `color`
  public func Dossier(name: String, line: String, stamp: String, color: String) -> Void {
    this.Push(TKKind.Dossier(), name, line, color, stamp, "", "", 0.0, true);
  }
  // Two columns of label / value pairs ("A|B", "1|2" per side); a label starting
  // with "#" is a small heading
  public func Columns(leftLabels: String, leftValues: String, rightLabels: String, rightValues: String) -> Void {
    this.Push(TKKind.Columns(), leftLabels, leftValues, "", rightLabels, rightValues, "", 0.0, true);
  }
  // labels "A|B|C", targets "page|page~arg|..." (same order), current = the target shown as selected
  public func Links(labels: String, targets: String, current: String) -> Void {
    this.Push(TKKind.Links(), labels, targets, "", current, "", "", 0.0, true);
  }
  // A row the content provider draws itself (TKContent.Custom): `tag` says what,
  // the rest is its data; `wheel` true when it takes the mouse wheel
  public func Custom(tag: String, a: String, b: String, c: String, d: String, wheel: Bool) -> Void {
    this.Push(TKKind.Custom(), tag, a, b, c, d, "", 0.0, true);
    if wheel {
      this.wheelReserved = true;
    }
  }
  // a tooltip on the row just added: shown when the cursor rests on its title
  public func SetTip(tip: String) -> Void {
    if ArraySize(this.rows) > 0 {
      this.rows[ArraySize(this.rows) - 1].tip = tip;
    }
  }
  // extra data on the row just added
  public func SetExtra(extra: String) -> Void {
    if ArraySize(this.rows) > 0 {
      this.rows[ArraySize(this.rows) - 1].extra = extra;
    }
  }
}

// What the kit needs from the mod: pages and actions, custom rows, and a word
// when the layout has to be rebuilt
public abstract class TKContent extends IScriptable {
  public func Request(p: ref<TKPage>, page: String, arg: String) -> Void {}
  public func Act(p: ref<TKPage>, action: String, arg: String) -> Void {}
  // draws a Custom row into `parent`; what it returns is stopped when the page goes away
  public func Custom(v: ref<TKView>, parent: ref<inkCompoundWidget>, p: ref<TKPage>, r: ref<TKRow>) -> ref<TKCustom> { return null; }
  // the layout changed under an open frame: rebuild it once the current callback is done
  public func Rebuild() -> Void {}
}

// a custom row's live object (a map, a chart...): told when its page is left
public abstract class TKCustom extends IScriptable {
  public func Stop() -> Void {}
}

// The frame around a view: the owner for global input, and whether the frame
// can hide itself around a bare page
public abstract class TKFrame extends IScriptable {
  public func Owner() -> ref<inkCustomController> { return null; }
  public func SetBare(bare: Bool) -> Void {}
}
