module ThermalVision

public class ThermalVisionEquipmentCallback extends AttachmentSlotsScriptCallback {
  private let m_system: wref<ThermalVisionSystem>;

  public func OnItemEquipped(slot: TweakDBID, item: ItemID) -> Void {
    if IsDefined(this.m_system) {
      this.m_system.OnEquipmentChanged();
    }
  }

  public func OnItemUnequippedComplete(slot: TweakDBID, item: ItemID) -> Void {
    if IsDefined(this.m_system) {
      this.m_system.OnEquipmentChanged();
    }
  }

  public static func Create(system: ref<ThermalVisionSystem>) -> ref<ThermalVisionEquipmentCallback> {
    let callback: ref<ThermalVisionEquipmentCallback> = new ThermalVisionEquipmentCallback();
    callback.m_system = system;
    return callback;
  }
}

