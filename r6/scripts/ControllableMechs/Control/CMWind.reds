// =============================================================================
// MECHS OF NIGHT CITY - WIND
//
// The air over Night City, for anything that flies (the drones' flight model asks it each
// frame) and for anything else that wants it: CMWind.Get(game).At(position, height).
//   - The mean wind follows the game's weather: still in fog and smog, a breeze when it's
//     clear, stronger under cloud and in rain, hard in a storm and a sandstorm. When the
//     weather turns, the wind eases to the new strength over about twenty seconds.
//   - Its direction wanders slowly through the day (two slow swings on a heading picked
//     when the game loads).
//   - Gusts come and go every few seconds, veering a little as they blow.
//   - Turbulence: small eddies that change over a few metres and fractions of a second,
//     sideways and a little up and down.
//   - Height: the wind near the ground is slowed by it (the boundary layer); it is
//     stronger the higher up (a power law, 10 m as the reference).
//   - Shelter (Exposure): a wall or a building close upwind breaks the wind behind it.
// Nothing ticks: the wind is worked out when it is asked for, from the engine clock.
// =============================================================================
module ControllableMechs.Control

import ControllableMechs.*

public class CMWind extends ScriptableSystem {
  private let m_seed: Float;
  private let m_speed: Float;       // the mean wind now (m/s), easing toward the weather's
  private let m_gust: Float;        // gust strength now, a fraction of the mean
  private let m_turb: Float;        // turbulence now, a fraction of the mean
  private let m_toSpeed: Float;     // the weather's
  private let m_toGust: Float;
  private let m_toTurb: Float;
  private let m_weather: String;
  private let m_last: Float;
  private let m_checkAt: Float;
  private let m_ready: Bool;

  public static func Get(game: GameInstance) -> ref<CMWind> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"ControllableMechs.Control.CMWind") as CMWind;
  }

  private func OnAttach() -> Void {
    this.m_seed = RandRangeF(0.0, 1000.0);
    this.m_ready = false;
  }

  private func Clock() -> Float = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGameInstance()))

  // the weather now (every two seconds) and the wind easing toward its strength
  private func Update() -> Void {
    let now = this.Clock();
    if !this.m_ready || now >= this.m_checkAt {
      this.m_checkAt = now + 2.0;
      this.ReadWeather();
    }
    if !this.m_ready {
      this.m_ready = true;
      this.m_speed = this.m_toSpeed;
      this.m_gust = this.m_toGust;
      this.m_turb = this.m_toTurb;
      this.m_last = now;
      return;
    }
    let dt = ClampF(now - this.m_last, 0.0, 5.0);
    this.m_last = now;
    let k = 1.0 - ExpF(-dt / 20.0);
    this.m_speed += (this.m_toSpeed - this.m_speed) * k;
    this.m_gust += (this.m_toGust - this.m_gust) * k;
    this.m_turb += (this.m_toTurb - this.m_turb) * k;
  }

  private func ReadWeather() -> Void {
    let name = "";
    let ws = GameInstance.GetWeatherSystem(this.GetGameInstance());
    if IsDefined(ws) {
      let st = ws.GetWeatherState();
      if IsDefined(st) {
        name = StrLower(NameToString(st.name));
      }
    }
    this.m_weather = name;
    // mean m/s at 10 m, gusts and turbulence as fractions of it
    if StrContains(name, "sandstorm") {
      this.Want(14.0, 0.6, 0.4);
    } else if StrContains(name, "storm") {
      this.Want(12.0, 0.7, 0.4);
    } else if StrContains(name, "rain") {
      this.Want(7.0, 0.45, 0.25);
    } else if StrContains(name, "pollution") || StrContains(name, "toxic") || StrContains(name, "fog") {
      this.Want(1.5, 0.2, 0.1);
    } else if StrContains(name, "heavy_cloud") {
      this.Want(6.0, 0.4, 0.2);
    } else if StrContains(name, "cloud") {
      this.Want(5.0, 0.35, 0.18);
    } else {
      this.Want(3.5, 0.3, 0.15);
    }
  }

  private func Want(speed: Float, gust: Float, turb: Float) -> Void {
    this.m_toSpeed = speed;
    this.m_toGust = gust;
    this.m_toTurb = turb;
  }

  // ---- what others read ----------------------------------------------------------
  // the game's weather state's name, as the wind last read it
  public func Weather() -> String {
    this.Update();
    return this.m_weather;
  }

  // the heading the wind blows toward (deg, the mod's yaw)
  public func Heading() -> Float {
    let t = this.Clock();
    let s = this.m_seed;
    return CMPilotRig.Wrap(s * 0.36 + 35.0 * SinF(t / 170.0 + s) + 12.0 * SinF(t / 41.0 + s * 2.0));
  }

  // the gust factor now, 0 (lull) to about 1 (a full gust)
  public func Gust() -> Float {
    let t = this.Clock();
    let s = this.m_seed;
    let g = 0.55 * SinF(t * 0.71 + s) + 0.35 * SinF(t * 1.93 + s * 2.0) + 0.25 * SinF(t * 0.29 + s * 3.0) - 0.25;
    return ClampF(g / 0.9, 0.0, 1.0);
  }

  // The wind at `p` (m/s, world), `h` metres above the ground (below 0: not known, taken as
  // 10 m). Without shelter: multiply by Exposure() for that.
  public func At(p: Vector4, h: Float) -> Vector4 {
    this.Update();
    let t = this.Clock();
    let s = this.m_seed;
    let mean = this.m_speed;
    if mean <= 0.01 {
      return new Vector4(0.0, 0.0, 0.0, 0.0);
    }
    // the boundary layer: slower near the ground, stronger higher up
    let z = h < 0.0 ? 10.0 : MaxF(1.0, h);
    let prof = ClampF(PowF(z / 10.0, 0.25), 0.55, 1.6);
    let g = this.Gust();
    let speed = mean * prof * (1.0 + this.m_gust * 2.0 * g);
    let yaw = this.Heading() + 15.0 * SinF(t * 0.5 + s) * g;
    let d = CMPilotRig.Dir(yaw, 0.0);
    // eddies over a few metres
    let a = mean * prof * this.m_turb;
    let ex = SinF(p.X * 0.21 + t * 1.7 + s) * SinF(p.Y * 0.17 - t * 1.3);
    let ey = SinF(p.Y * 0.23 + t * 1.1 + s) * CosF(p.X * 0.19 + t * 0.9);
    let ez = 0.5 * SinF((p.X + p.Y) * 0.15 + t * 2.1) * SinF(p.Z * 0.3 + t + s);
    return new Vector4(d.X * speed + ex * a, d.Y * speed + ey * a, ez * a, 0.0);
  }

  // How open `p` is to the wind, 0.25 (right behind a wall or building upwind) to 1 (open):
  // a ray 30 m upwind and one 3 m above it. Rays: ask it a few times a second, not every
  // frame.
  public func Exposure(p: Vector4) -> Float {
    let d = CMPilotRig.Dir(this.Heading() + 180.0, 0.0);
    let sq = GameInstance.GetSpatialQueriesSystem(this.GetGameInstance());
    let best = 1.0;
    let i = 0;
    while i < 2 {
      let from = p + new Vector4(0.0, 0.0, 3.0 * Cast<Float>(i), 0.0);
      let to = from + d * 30.0;
      let hit: TraceResult;
      if sq.SyncRaycastByCollisionGroup(from, to, n"Static", hit, true, false) {
        best = MinF(best, 0.25 + 0.75 * Vector4.Distance(from, Cast<Vector4>(hit.position)) / 30.0);
      }
      i += 1;
    }
    return best;
  }
}
