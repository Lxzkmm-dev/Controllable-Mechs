module ThermalVision.Localization

import Codeware.Localization.*

public class English extends ModLocalizationPackage {
  protected func DefineTexts() -> Void {
    this.Text("ThermalVision-Optics-Description", "Enables <Rich color=\"TooltipText.cyberwareDescriptionHighlightColor\" style=\"Semi-Bold\">Kiroshi Optics Thermal Vision</> with multiple spectral imaging modes.");
    this.Text("ThermalVision-Settings-Input", "Input");
    this.Text("ThermalVision-Settings-KeyboardActivationPrimary", "Keyboard Activation Button");
    this.Text("ThermalVision-Settings-KeyboardActivationPrimary-Description", "Turns Kiroshi Optics Thermal Vision on or off without changing the selected imaging mode.");
    this.Text("ThermalVision-Settings-KeyboardActivationModifier", "Keyboard Activation Modifier");
    this.Text("ThermalVision-Settings-KeyboardActivationModifier-Description", "Hold this key while pressing the keyboard activation button. Set to None for a single-key binding.");
    this.Text("ThermalVision-Settings-KeyboardCyclePrimary", "Keyboard Cycle Button");
    this.Text("ThermalVision-Settings-KeyboardCyclePrimary-Description", "Cycles Normal Thermal, Red/Black Hot, and White Hot while Kiroshi Optics Thermal Vision is active.");
    this.Text("ThermalVision-Settings-KeyboardCycleModifier", "Keyboard Cycle Modifier");
    this.Text("ThermalVision-Settings-KeyboardCycleModifier-Description", "Hold this key while pressing the keyboard cycle button. Set to None for a single-key binding.");
    this.Text("ThermalVision-Settings-ControllerActivationPrimary", "Controller Activation Button");
    this.Text("ThermalVision-Settings-ControllerActivationPrimary-Description", "Turns Kiroshi Optics Thermal Vision on or off without changing the selected imaging mode. Unbound by default.");
    this.Text("ThermalVision-Settings-ControllerActivationModifier", "Controller Activation Modifier");
    this.Text("ThermalVision-Settings-ControllerActivationModifier-Description", "Hold this button while pressing the controller activation button. Set to None for a single-button binding.");
    this.Text("ThermalVision-Settings-ControllerCyclePrimary", "Controller Cycle Button");
    this.Text("ThermalVision-Settings-ControllerCyclePrimary-Description", "Cycles Normal Thermal, Red/Black Hot, and White Hot while Kiroshi Optics Thermal Vision is active. Unbound by default.");
    this.Text("ThermalVision-Settings-ControllerCycleModifier", "Controller Cycle Modifier");
    this.Text("ThermalVision-Settings-ControllerCycleModifier-Description", "Hold this button while pressing the controller cycle button. Set to None for a single-button binding.");
    this.Text("ThermalVision-Settings-Integration", "Integration");
    this.Text("ThermalVision-Settings-NightVisionProvider", "Night Vision Integration");
    this.Text("ThermalVision-Settings-NightVisionProvider-Description", "Selects which compatible Night Vision system joins the activation cycle. Automatic favors Kiroshi Optics Night Vision when both are available.");
    this.Text("ThermalVision-Settings-NightVisionProvider-Automatic", "Automatic");
    this.Text("ThermalVision-Settings-NightVisionProvider-KiroshiOptics", "Kiroshi Optics Night Vision");
    this.Text("ThermalVision-Settings-NightVisionProvider-TrueNightVision", "True Night Vision");
    this.Text("ThermalVision-Settings-NightVisionProvider-Disabled", "Disabled");
    this.Text("ThermalVision-Mode-Normal", "Normal Thermal");
    this.Text("ThermalVision-Mode-RedHot", "Red/Black Hot");
    this.Text("ThermalVision-Mode-WhiteHot", "White Hot");
  }
}
