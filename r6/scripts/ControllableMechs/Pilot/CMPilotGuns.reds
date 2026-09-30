// =============================================================================
// CONTROLLABLE MECHS - PILOT GUNS (the two MK.31 HMGs)
//
// Finds the mech's left and right weapons and fires them through the game's own
// NPC firing call (AIWeapon.Fire) at the point the reticle is on, with the mech
// as owner: the one call that deals damage (the damage pipeline hook in
// CMCHits credits the hits to V).
//
// Fire modes (CMFireMode):
//   Stagger  - LMB fires both, barrels alternate at double cadence (default)
//   Together - LMB fires both at once
//   Split    - LMB fires the left gun, RMB the right
//
// Heat per gun: each shot adds heat, it bleeds off when the trigger is released,
// at 100% the gun locks until it has cooled to 35%. The unit calls Update()
// every frame while piloting and never otherwise.
// =============================================================================
module ControllableMechs

public abstract class CMFireMode {
  public static func Stagger() -> Int32 = 0
  public static func Together() -> Int32 = 1
  public static func Split() -> Int32 = 2

  public static func Name(mode: Int32) -> String {
    if mode == CMFireMode.Together() { return "LINKED SALVO"; }
    if mode == CMFireMode.Split() { return "SPLIT L/R"; }
    return "STAGGERED";
  }

  public static func Next(mode: Int32) -> Int32 = (mode + 1) % 3
}

public class CMGun {
  public let weapon: wref<WeaponObject>;
  public let heat: Float;          // 0..1
  public let locked: Bool;         // overheated, cooling down
  public let nextShot: Float;      // sim time
  public let lastShot: Float;      // sim time
  public let flash: Float;         // seconds of muzzle-flash on the HUD marker
  public let offAim: Bool;         // the barrel is too far off the reticle to fire (the unit's fire gate)

  public func Ready() -> Bool = IsDefined(this.weapon)
}

public class CMPilotGuns {
  public let left: ref<CMGun>;
  public let right: ref<CMGun>;
  private let m_cycle: Float;       // seconds between shots of one gun
  private let m_turnLeft: Bool;     // stagger: which barrel is next
  private let m_names: String;      // what was found, for the log
  public let rate: Float = 1.0;     // spin-up: fraction of the full rate of fire (1 = full)

  private let HEAT_PER_SHOT: Float = 0.022;
  private let COOL_RATE: Float = 0.30;   // per second
  private let COOL_DELAY: Float = 0.35;  // seconds after the last shot
  private let UNLOCK_AT: Float = 0.35;

  public func Init(mech: ref<NPCPuppet>) -> Void {
    this.left = new CMGun();
    this.right = new CMGun();
    let game = mech.GetGame();
    let ts = GameInstance.GetTransactionSystem(game);
    let r = ScriptedPuppet.GetWeaponRight(mech);
    let l = ScriptedPuppet.GetWeaponLeft(mech);
    if !IsDefined(r) {
      r = ts.GetItemInSlot(mech, t"AttachmentSlots.WeaponRight") as WeaponObject;
    }
    if !IsDefined(l) {
      l = ts.GetItemInSlot(mech, t"AttachmentSlots.WeaponLeft") as WeaponObject;
    }
    this.right.weapon = r;
    this.left.weapon = l;
    // one weapon object for both arms: both triggers drive it
    if !IsDefined(this.left.weapon) && IsDefined(r) { this.left.weapon = r; }
    if !IsDefined(this.right.weapon) && IsDefined(l) { this.right.weapon = l; }

    this.m_cycle = 0.1;
    if IsDefined(r) {
      let c = GameInstance.GetStatsSystem(game).GetStatValue(Cast<StatsObjectID>(r.GetEntityID()), gamedataStatType.CycleTime);
      if c > 0.03 && c < 1.0 {
        this.m_cycle = c;
      }
    }
    this.m_turnLeft = true;
    this.m_names = "L " + CMPilotGuns.ItemName(this.left.weapon) + "  R " + CMPilotGuns.ItemName(this.right.weapon);
  }

  public func Describe() -> String = this.m_names

  // A gun whose weapon object has gone (the game removed or re-created the item): look the
  // slots up again, keeping each gun's heat. True when a gun got its weapon back.
  public func Refresh(mech: ref<NPCPuppet>) -> Bool {
    if this.left.Ready() && this.right.Ready() {
      return false;
    }
    let ts = GameInstance.GetTransactionSystem(mech.GetGame());
    let r = ScriptedPuppet.GetWeaponRight(mech);
    let l = ScriptedPuppet.GetWeaponLeft(mech);
    if !IsDefined(r) {
      r = ts.GetItemInSlot(mech, t"AttachmentSlots.WeaponRight") as WeaponObject;
    }
    if !IsDefined(l) {
      l = ts.GetItemInSlot(mech, t"AttachmentSlots.WeaponLeft") as WeaponObject;
    }
    let back = false;
    if !this.right.Ready() && IsDefined(r) {
      this.right.weapon = r;
      back = true;
    }
    if !this.left.Ready() && IsDefined(l) {
      this.left.weapon = l;
      back = true;
    }
    // one weapon left: both triggers drive it
    if !this.left.Ready() && this.right.Ready() {
      this.left.weapon = this.right.weapon;
      back = true;
    }
    if !this.right.Ready() && this.left.Ready() {
      this.right.weapon = this.left.weapon;
      back = true;
    }
    this.m_names = "L " + CMPilotGuns.ItemName(this.left.weapon) + "  R " + CMPilotGuns.ItemName(this.right.weapon);
    return back;
  }

  // ---- round speed: the MK.31s are smart guns, whose rounds are slow homing
  // projectiles; their speed is a stat on the weapon. A multiplier while piloting,
  // removed on exit. Returns the velocity before and after, for the log.
  private let m_speedMods: array<ref<gameStatModifierData>>;
  private let m_speedIDs: array<StatsObjectID>;

  public func SpeedUp(game: GameInstance, mult: Float) -> String {
    this.SlowDown(game);
    let stats = GameInstance.GetStatsSystem(game);
    let note = "";
    let weapons: array<wref<WeaponObject>> = [this.left.weapon];
    if this.right.weapon != this.left.weapon {
      ArrayPush(weapons, this.right.weapon);
    }
    for w in weapons {
      if IsDefined(w) {
        let id = Cast<StatsObjectID>(w.GetEntityID());
        let before = stats.GetStatValue(id, gamedataStatType.SmartGunNPCProjectileVelocity);
        for t in [gamedataStatType.SmartGunNPCProjectileVelocity, gamedataStatType.SmartGunPlayerProjectileVelocity] {
          let mod = RPGManager.CreateStatModifier(t, gameStatModifierType.Multiplier, mult);
          stats.AddModifier(id, mod);
          ArrayPush(this.m_speedMods, mod);
          ArrayPush(this.m_speedIDs, id);
        }
        note += (StrLen(note) > 0 ? "  " : "") + "NPC round velocity " + FloatToStringPrec(before, 1) + " -> " + FloatToStringPrec(stats.GetStatValue(id, gamedataStatType.SmartGunNPCProjectileVelocity), 1);
      }
    }
    return note;
  }

  public func SlowDown(game: GameInstance) -> Void {
    let stats = GameInstance.GetStatsSystem(game);
    let i = 0;
    while i < ArraySize(this.m_speedMods) {
      stats.RemoveModifier(this.m_speedIDs[i], this.m_speedMods[i]);
      i += 1;
    }
    ArrayClear(this.m_speedMods);
    ArrayClear(this.m_speedIDs);
  }

  // seconds between shots of one gun, stretched while the barrels spin up
  public func Cycle() -> Float = this.m_cycle / MaxF(0.2, this.rate)

  public static func ItemName(w: wref<WeaponObject>) -> String {
    if !IsDefined(w) {
      return "NONE";
    }
    return TDBID.ToStringDEBUG(w.GetItemID().GetTDBID());
  }

  // Called every frame while piloting. Returns how many rounds left the guns (for recoil).
  public func Update(mech: ref<NPCPuppet>, now: Float, dt: Float, lmb: Bool, rmb: Bool, mode: Int32, aim: Vector4, spreadDeg: Float, camPos: Vector4) -> Int32 {
    this.Cool(this.left, now, dt);
    this.Cool(this.right, now, dt);
    let shots = 0;
    if mode == CMFireMode.Split() {
      if lmb && this.TryFire(mech, this.left, now, this.Cycle(), aim, spreadDeg, camPos) { shots += 1; }
      if rmb && this.TryFire(mech, this.right, now, this.Cycle(), aim, spreadDeg, camPos) { shots += 1; }
      return shots;
    }
    if !lmb {
      return 0;
    }
    if mode == CMFireMode.Together() {
      if this.TryFire(mech, this.left, now, this.Cycle(), aim, spreadDeg, camPos) { shots += 1; }
      if this.right.weapon != this.left.weapon {
        if this.TryFire(mech, this.right, now, this.Cycle(), aim, spreadDeg, camPos) { shots += 1; }
      }
      return shots;
    }
    // stagger: one barrel every half cycle, alternating; a hot or missing barrel yields to the other
    let first = this.m_turnLeft ? this.left : this.right;
    let second = this.m_turnLeft ? this.right : this.left;
    let half = this.Cycle() * 0.5;
    if this.CanFire(first, now) && this.TryFire(mech, first, now, this.Cycle(), aim, spreadDeg, camPos) {
      second.nextShot = MaxF(second.nextShot, now + half);
      this.m_turnLeft = !this.m_turnLeft;
      return 1;
    }
    if !this.CanFire(first, now) && (first.locked || !first.Ready()) && this.TryFire(mech, second, now, this.Cycle(), aim, spreadDeg, camPos) {
      return 1;
    }
    return 0;
  }

  // where gun `g`'s barrel points, `dist` metres out (its reticle on the HUD)
  public func BarrelPoint(g: ref<CMGun>, dist: Float) -> Vector4 {
    if !g.Ready() {
      return new Vector4(0.0, 0.0, 0.0, 1.0);
    }
    let o = g.weapon.GetWorldPosition();
    let f = g.weapon.GetWorldForward();
    let d = ClampF(dist, 5.0, 400.0);
    return new Vector4(o.X + f.X * d, o.Y + f.Y * d, o.Z + f.Z * d, 1.0);
  }

  private func CanFire(g: ref<CMGun>, now: Float) -> Bool {
    return g.Ready() && !g.locked && !g.offAim && now >= g.nextShot;
  }

  // One round at the reticle point, with a spread cone that grows with heat. The target
  // must be the reticle point itself: a point projected along the barrel never did damage.
  private func TryFire(mech: ref<NPCPuppet>, g: ref<CMGun>, now: Float, cycle: Float, aim: Vector4, spreadDeg: Float, camPos: Vector4) -> Bool {
    if !this.CanFire(g, now) {
      return false;
    }
    let dist = Vector4.Distance(camPos, aim);
    let r = dist * Deg2Rad(spreadDeg * (1.0 + g.heat * 1.5));
    let target = new Vector4(aim.X + RandRangeF(-r, r), aim.Y + RandRangeF(-r, r), aim.Z + RandRangeF(-r, r) * 0.6, 1.0);
    AIWeapon.Fire(mech, g.weapon, now, 0.0, gamedataTriggerMode.FullAuto, target);
    g.nextShot = now + cycle;
    g.lastShot = now;
    g.flash = 0.06;
    g.heat = MinF(1.0, g.heat + this.HEAT_PER_SHOT);
    if g.heat >= 1.0 {
      g.locked = true;
    }
    return true;
  }

  private func Cool(g: ref<CMGun>, now: Float, dt: Float) -> Void {
    if g.flash > 0.0 {
      g.flash = MaxF(0.0, g.flash - dt);
    }
    if now - g.lastShot < this.COOL_DELAY && !g.locked {
      return;
    }
    g.heat = MaxF(0.0, g.heat - this.COOL_RATE * dt);
    if g.locked && g.heat <= this.UNLOCK_AT {
      g.locked = false;
    }
  }
}
