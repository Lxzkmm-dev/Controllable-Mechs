// =============================================================================
// CONTROLLABLE MECHS - PILOT GUNS (the two MK.31 HMGs)
//
// Finds the mech's left and right weapons and fires them through the game's own
// NPC firing call (AIWeapon.Fire) at a world point, so the rounds leave the real
// muzzles and converge on what the reticle is on.
//
// Fire modes (CMFireMode):
//   Stagger  - LMB fires both, barrels alternate at double cadence (default)
//   Together - LMB fires both at once
//   Split    - LMB fires the left gun, RMB the right
//
// Heat per gun: each shot adds heat, it bleeds off when the trigger is released,
// at 100% the gun locks until it has cooled to 35%. The pilot tick calls
// Update() every frame while piloting and never otherwise.
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

  public func Ready() -> Bool = IsDefined(this.weapon)
}

public class CMPilotGuns {
  public let left: ref<CMGun>;
  public let right: ref<CMGun>;
  private let m_cycle: Float;       // seconds between shots of one gun
  private let m_turnLeft: Bool;     // stagger: which barrel is next
  private let m_names: String;      // what was found, for the HUD / diagnostics

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
  public func HasAny() -> Bool = this.left.Ready() || this.right.Ready()
  public func Cycle() -> Float = this.m_cycle

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
      if lmb && this.TryFire(mech, this.left, now, this.m_cycle, aim, spreadDeg, camPos) { shots += 1; }
      if rmb && this.TryFire(mech, this.right, now, this.m_cycle, aim, spreadDeg, camPos) { shots += 1; }
      return shots;
    }
    if !lmb {
      return 0;
    }
    if mode == CMFireMode.Together() {
      if this.TryFire(mech, this.left, now, this.m_cycle, aim, spreadDeg, camPos) { shots += 1; }
      if this.right.weapon != this.left.weapon {
        if this.TryFire(mech, this.right, now, this.m_cycle, aim, spreadDeg, camPos) { shots += 1; }
      }
      return shots;
    }
    // stagger: one barrel every half cycle, alternating; a hot or missing barrel yields to the other
    let first = this.m_turnLeft ? this.left : this.right;
    let second = this.m_turnLeft ? this.right : this.left;
    let half = this.m_cycle * 0.5;
    if this.CanFire(first, now) && this.TryFire(mech, first, now, this.m_cycle, aim, spreadDeg, camPos) {
      second.nextShot = MaxF(second.nextShot, now + half);
      this.m_turnLeft = !this.m_turnLeft;
      return 1;
    }
    if !this.CanFire(first, now) && (first.locked || !first.Ready()) && this.TryFire(mech, second, now, this.m_cycle, aim, spreadDeg, camPos) {
      return 1;
    }
    return 0;
  }

  private func CanFire(g: ref<CMGun>, now: Float) -> Bool {
    return g.Ready() && !g.locked && now >= g.nextShot;
  }

  private func TryFire(mech: ref<NPCPuppet>, g: ref<CMGun>, now: Float, cycle: Float, aim: Vector4, spreadDeg: Float, camPos: Vector4) -> Bool {
    if !this.CanFire(g, now) {
      return false;
    }
    // spread grows with heat: a cone around the aim point
    let dist = Vector4.Distance(camPos, aim);
    let cone = Deg2Rad(spreadDeg * (1.0 + g.heat * 1.5));
    let r = dist * cone;
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
