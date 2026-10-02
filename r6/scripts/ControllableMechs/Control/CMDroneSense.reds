// =============================================================================
// MECHS OF NIGHT CITY - A DRONE'S SENSOR SWEEP (0.7.1)
//
// Fills the display's picture of the world round the drone (CMDroneTrack, Pilot):
//   the search   twice a second, the targeting system's search round the drone (the drone
//                as its instigator: the quickhack mods' NPC-centred query) for the living
//                puppets within RANGE: their kind (V's attitude to them, civilians and the
//                crowd), armed (a weapon in hand), in combat (their high-level state), a
//                machine (drones, mechs, androids); V is always contact C-01
//   each frame   each contact's place, speed, distance and spot on the display (through the
//                camera as it is drawn: CMUDrone.ScreenAt)
//   the lock     the contact the reticle's ray is on, held LOCK_HOLD after it leaves; its
//                lead pip for a round at ROUND_SPEED
//   tags         (the Wyvern) the reticle held on an untagged contact for SCAN_TIME tags it;
//                the ping (G) tags everything within PING_RANGE, every PING_COOLDOWN
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMDroneSense {
  public let track: ref<CMDroneTrack>;
  private let m_scanAt: Float;
  private let m_nextTag: Int32;
  private let m_scanEnt: EntityID;
  private let m_scanT: Float;
  private let m_lockT: Float;
  private let m_pingReady: Float;
  private let m_tagging: Bool;
  private let m_logAt: Float;

  private let RANGE: Float = 120.0;
  private let SCAN_EVERY: Float = 0.5;
  private let SCAN_TIME: Float = 1.2;
  private let LOCK_HOLD: Float = 1.5;
  private let PING_RANGE: Float = 60.0;
  private let PING_COOLDOWN: Float = 20.0;
  private let ROUND_SPEED: Float = 320.0;
  private let NEAR: Float = 80.0;

  public static func Make(tagging: Bool) -> ref<CMDroneSense> {
    let s = new CMDroneSense();
    s.track = new CMDroneTrack();
    s.m_tagging = tagging;
    s.m_nextTag = 2;
    s.track.scan = -1.0;
    return s;
  }

  public func Tick(s: ref<CMCSession>, unit: ref<CMUDrone>, me: ref<GameObject>, pos: Vector4, now: Float, dt: Float) -> Void {
    let t = this.track;
    t.now = now;
    t.pos = pos;
    t.aim = s.aim;
    t.aimOk = s.aimDist > 0.0;
    t.yaw = s.rig.yaw;
    t.camPitch = s.rig.pitch;
    t.fov = s.rig.fov;
    t.pingLeft = MaxF(0.0, this.m_pingReady - now);
    if now >= this.m_scanAt {
      this.m_scanAt = now + this.SCAN_EVERY;
      this.Search(me, pos, now);
    }
    // whatever the reticle's ray is on is a contact, search or not (a55)
    let onRay = s.aimEntity as NPCPuppet;
    if IsDefined(onRay) && !onRay.IsDead() && (!IsDefined(me) || !Equals(onRay.GetEntityID(), me.GetEntityID())) && Vector4.Distance(onRay.GetWorldPosition(), pos) <= this.RANGE {
      this.Note(onRay, GetPlayer(GetGameInstance()), now + this.SCAN_EVERY);
    }
    // each contact this frame
    let lockNow: ref<CMDroneContact>;
    let aimId: EntityID;
    if IsDefined(s.aimEntity) {
      aimId = s.aimEntity.GetEntityID();
    }
    t.tagged = 0;
    t.hostiles = 0;
    t.detected = 0;
    for c in t.contacts {
      let e = c.ent;
      if IsDefined(e) {
        let p = e.GetWorldPosition();
        p.Z += c.kind == 0 ? 1.0 : 1.1;
        if dt > 0.0 && c.pos.W > 0.5 {
          let v = (p - c.pos) * (1.0 / dt);
          c.vel = c.vel + (v - c.vel) * MinF(1.0, dt * 6.0);
        }
        c.pos = p;
        c.pos.W = 1.0;
      }
      c.dist = Vector4.Distance(pos, c.pos);
      c.scr = unit.ScreenAt(s, c.pos);
      if c.tag > 0 {
        t.tagged += 1;
      }
      if c.kind == 2 && c.dist <= this.NEAR {
        t.hostiles += 1;
        if c.combat {
          t.detected += 1;
        }
      }
      if c.kind != 0 && EntityID.IsDefined(aimId) && Equals(c.id, aimId) {
        lockNow = c;
      }
    }
    // the lock: what the reticle is on, held a moment after it leaves
    if IsDefined(lockNow) {
      t.lock = lockNow;
      this.m_lockT = this.LOCK_HOLD;
    } else {
      this.m_lockT -= dt;
      if this.m_lockT <= 0.0 || !IsDefined(t.lock) || !IsDefined(t.lock.ent) || t.lock.hp <= 0.0 {
        t.lock = null;
      }
    }
    t.leadOn = false;
    if IsDefined(t.lock) && Vector4.Length(t.lock.vel) > 0.5 {
      let at = t.lock.pos + t.lock.vel * (t.lock.dist / this.ROUND_SPEED);
      t.lead = unit.ScreenAt(s, at);
      t.leadOn = AbsF(t.lead.X) < 1880.0 && AbsF(t.lead.Y) < 1040.0;
    }
    // the Wyvern's tags: hold the reticle on a contact
    t.scan = -1.0;
    if this.m_tagging && IsDefined(lockNow) {
      if lockNow.tag > 0 {
        t.scan = 1.0;
      } else {
        if !Equals(this.m_scanEnt, lockNow.id) {
          this.m_scanEnt = lockNow.id;
          this.m_scanT = 0.0;
        }
        this.m_scanT += dt;
        t.scan = ClampF(this.m_scanT / this.SCAN_TIME, 0.0, 1.0);
        if this.m_scanT >= this.SCAN_TIME {
          this.TagIt(lockNow);
        }
      }
    } else {
      this.m_scanT = 0.0;
    }
  }

  // G on the Wyvern: everything near is tagged at once
  public func Ping(me: ref<GameObject>, now: Float) -> Bool {
    if !this.m_tagging || now < this.m_pingReady {
      return false;
    }
    this.m_pingReady = now + this.PING_COOLDOWN;
    for c in this.track.contacts {
      if c.tag <= 0 && c.dist <= this.PING_RANGE {
        this.TagIt(c);
      }
    }
    if IsDefined(me) {
      GameObject.PlaySoundEvent(me, n"ui_hacking_access_granted");
    }
    return true;
  }

  private func TagIt(c: ref<CMDroneContact>) -> Void {
    c.tag = this.m_nextTag;
    this.m_nextTag += 1;
    let pl = GetPlayer(GetGameInstance());
    if IsDefined(pl) {
      GameObject.PlaySoundEvent(pl, n"ui_menu_onpress");
    }
  }

  // the search round the drone: new contacts in, the gone and the dead out
  private func Search(me: ref<GameObject>, pos: Vector4, now: Float) -> Void {
    let game = GetGameInstance();
    let t = this.track;
    // V first, always
    let pl = GetPlayer(game);
    if ArraySize(t.contacts) == 0 || t.contacts[0].kind != 0 {
      let v = new CMDroneContact();
      v.kind = 0;
      v.tag = 1;
      v.hp = 1.0;
      ArrayInsert(t.contacts, 0, v);
    }
    let vc = t.contacts[0];
    vc.ent = pl;
    vc.seen = now;
    if IsDefined(pl) {
      vc.id = pl.GetEntityID();
      vc.hp = GameInstance.GetStatPoolsSystem(game).GetStatPoolValue(Cast<StatsObjectID>(pl.GetEntityID()), gamedataStatPoolType.Health, true) / 100.0;
    }
    if !IsDefined(me) {
      return;
    }
    let q: TargetSearchQuery;
    q.testedSet = TargetingSet.Complete;
    q.searchFilter = TSF_All(TSFMV.Obj_Puppet | TSFMV.St_AliveAndActive);
    q.maxDistance = this.RANGE;
    q.filterObjectByDistance = true;
    q.includeSecondaryTargets = false;
    q.ignoreInstigator = true;
    let parts: array<TS_TargetPartInfo>;
    GameInstance.GetTargetingSystem(game).GetTargetParts(me, q, parts);
    let fromDrone = ArraySize(parts);
    // a55: in game the search round the drone found nobody (Omar: the contacts list, radar
    // and ping empty), so V's search runs too, out far enough to take in the drone's ground;
    // both are kept to the drone's RANGE below
    let fromV = 0;
    if IsDefined(pl) {
      let qv = q;
      qv.maxDistance = MinF(400.0, this.RANGE + Vector4.Distance(pl.GetWorldPosition(), pos));
      let vparts: array<TS_TargetPartInfo>;
      GameInstance.GetTargetingSystem(game).GetTargetParts(pl, qv, vparts);
      fromV = ArraySize(vparts);
      for vp in vparts {
        ArrayPush(parts, vp);
      }
    }
    for p in parts {
      let comp = TS_TargetPartInfo.GetComponent(p);
      let npc: ref<NPCPuppet>;
      if IsDefined(comp) {
        npc = comp.GetEntity() as NPCPuppet;
      }
      if IsDefined(npc) && !npc.IsDead() && !Equals(npc.GetEntityID(), me.GetEntityID()) && Vector4.Distance(npc.GetWorldPosition(), pos) <= this.RANGE {
        this.Note(npc, pl, now);
      }
    }
    if now >= this.m_logAt {
      this.m_logAt = now + 5.0;
      CMCSession.Log("sweep: " + IntToString(fromDrone) + " found round the drone, " + IntToString(fromV) + " round V; " + IntToString(ArraySize(t.contacts) - 1) + " contacts in range");
    }
    // the gone (not found this time) and the dead out; V stays
    let i = ArraySize(t.contacts) - 1;
    while i >= 1 {
      let c = t.contacts[i];
      let npc = c.ent as NPCPuppet;
      if c.seen < now - 0.01 || !IsDefined(npc) || npc.IsDead() {
        ArrayErase(t.contacts, i);
      }
      i -= 1;
    }
  }

  // one NPC the search found: in, or its state again
  private func Note(npc: ref<NPCPuppet>, pl: ref<PlayerPuppet>, now: Float) -> Void {
    let t = this.track;
    let c = this.Find(npc.GetEntityID());
    if !IsDefined(c) {
      if ArraySize(t.contacts) >= 32 {
        return;
      }
      c = new CMDroneContact();
      c.id = npc.GetEntityID();
      c.ent = npc;
      ArrayPush(t.contacts, c);
    }
    c.seen = now;
    if npc.IsCivilian() || npc.IsCrowd() {
      c.kind = 1;
    } else {
      let att = IsDefined(pl) ? GameObject.GetAttitudeBetween(npc, pl) : EAIAttitude.AIA_Neutral;
      c.kind = Equals(att, EAIAttitude.AIA_Hostile) ? 2 : (Equals(att, EAIAttitude.AIA_Friendly) ? 4 : 3);
    }
    let ty = npc.GetNPCType();
    c.machine = Equals(ty, gamedataNPCType.Drone) || Equals(ty, gamedataNPCType.Mech) || Equals(ty, gamedataNPCType.Android);
    c.armed = IsDefined(ScriptedPuppet.GetWeaponRight(npc));
    c.combat = Equals(npc.GetHighLevelStateFromBlackboard(), gamedataNPCHighLevelState.Combat);
    c.hp = GameInstance.GetStatPoolsSystem(npc.GetGame()).GetStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, true) / 100.0;
  }

  private func Find(id: EntityID) -> ref<CMDroneContact> {
    for c in this.track.contacts {
      if Equals(c.id, id) {
        return c;
      }
    }
    return null;
  }
}
