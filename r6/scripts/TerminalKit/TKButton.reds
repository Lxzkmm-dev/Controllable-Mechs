// =============================================================================
// TERMINAL KIT - CONTROLS' CLASSES
// TKButton: a vanilla-style button (Codeware SimpleButton) sized for a page.
// TKSlider: one slider's live state on the current page.
// =============================================================================
module TerminalKit

import Codeware.UI.*

public class TKButton extends SimpleButton {
  public func SetFontSize(size: Int32) -> Void { this.m_label.SetFontSize(size); }
  public func GetLabel() -> wref<inkText> { return this.m_label; }

  public static func Make(parent: ref<inkCompoundWidget>, text: String, name: String, width: Float, height: Float, size: Int32) -> ref<TKButton> {
    let b: ref<TKButton> = new TKButton();
    b.CreateInstance();
    let label = TKScale.T(text);
    b.SetText(label);
    b.SetFontSize(TKButton.FitSize(label, width, size));
    b.ToggleSounds(true);
    b.Reparent(parent);
    b.SetName(StringToName(name));
    let root = b.GetRootWidget();
    root.SetSize(Vector2(width, height));
    root.SetAnchorPoint(Vector2(0.0, 0.0));
    return b;
  }

  // Largest font size (down to 16) at which the label fits the button. Glyphs of
  // the game's condensed UI font are about 0.55 of the font size wide in caps.
  public static func FitSize(text: String, width: Float, size: Int32) -> Int32 {
    let room = width - 36.0;
    let chars = Cast<Float>(Max(1, StrLen(text)));
    let fit = Cast<Int32>(room / (chars * 0.55));
    return Max(16, Min(size, fit));
  }
}

public class TKSlider extends IScriptable {
  public let row: Int32;
  public let min: Int32;
  public let step: Int32;
  public let value: Int32;
  public let suffix: String;
  public let segs: array<wref<inkRectangle>>;
  public let readout: wref<inkText>;
}
