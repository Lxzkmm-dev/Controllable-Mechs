# Python mirror of CMFlight 6-DOF, for tuning and stability checks.
# Body frame: X right, Y forward, Z up (the game's). Angular velocity in body frame:
# wx + = nose up, wy + = right side down, wz + = turn left. Quaternion (w,x,y,z) body->world.
import math

def qmul(a, b):
    aw, ax, ay, az = a; bw, bx, by, bz = b
    return (aw*bw-ax*bx-ay*by-az*bz, aw*bx+ax*bw+ay*bz-az*by, aw*by-ax*bz+ay*bw+az*bx, aw*bz+ax*by-ay*bx+az*bw)

def qrot(q, v):  # rotate v by q
    w, x, y, z = q; vx, vy, vz = v
    tx = 2*(y*vz - z*vy); ty = 2*(z*vx - x*vz); tz = 2*(x*vy - y*vx)
    return (vx + w*tx + (y*tz - z*ty), vy + w*ty + (z*tx - x*tz), vz + w*tz + (x*ty - y*tx))

def qinv_rot(q, v):
    w, x, y, z = q
    return qrot((w, -x, -y, -z), v)

def qnorm(q):
    n = math.sqrt(sum(c*c for c in q)); return tuple(c/n for c in q)

def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])

PROF = {
 'bombus': dict(mass=6, arm=0.2, thrust=30, spool=0.06, kq=0.02, agility=16, tilt=35, rate=220, cdh=0.30, cdv=0.45, flap=0.06, yawRate=200, climb=5, level=0.65),
 'griffin': dict(mass=40, arm=0.45, thrust=190, spool=0.10, kq=0.04, agility=9, tilt=22, rate=120, cdh=1.9, cdv=2.8, flap=0.35, yawRate=110, climb=4, level=0.85),
 'octant': dict(mass=180, arm=1.0, thrust=900, spool=0.14, kq=0.08, agility=4.5, tilt=20, rate=90, cdh=10.7, cdv=16, flap=2.0, yawRate=60, climb=3, level=0.95),
}
RHO = 1.2

class Drone:
    def __init__(s, p):
        s.p = p
        d = p['arm'] / math.sqrt(2)
        # FL, FR, BL, BR: (x, y, spin) ; spin +1 = its counter-torque turns the body left (+z)
        s.rotors = [(-d, d, 1), (d, d, -1), (-d, -d, -1), (d, -d, 1)]
        m = p['mass']; a = p['arm']
        s.I = (m*a*a*0.5, m*a*a*0.5, m*a*a*0.8)
        s.pos = [0, 0, 5]; s.vel = [0, 0, 0]; s.q = (1, 0, 0, 0); s.w = [0, 0, 0]
        hov = m*9.81/(4*p['thrust']); s.spool = [hov]*4; s.eff = [1]*4
        s.holdZ = 5; s.holding = True

    def up(s): return qrot(s.q, (0, 0, 1))
    def fwd(s): return qrot(s.q, (0, 1, 0))

    def step(s, dt, f, side, c, view):
        p = s.p; m = p['mass']; L = p['level']
        st = math.hypot(f, side)
        if st > 1: f /= st; side /= st
        up = s.up(); fw = s.fwd()
        heading = math.degrees(math.atan2(-fw[0], fw[1]))
        # --- desired body rates ---
        rate = math.radians(p['rate'])
        acro = (-f*rate, side*rate)   # (wx, wy): nose down for forward, right down for right
        # angle mode: desired up from target tilt about the current heading
        tp = math.radians(-f*p['tilt']); tr = math.radians(side*p['tilt'])
        hy = math.radians(heading)
        # desired attitude: yaw heading, pitch tp, roll tr -> desired up in world
        qd = qmul(qmul((math.cos(hy/2), 0, 0, math.sin(hy/2)), (math.cos(tp/2), math.sin(tp/2), 0, 0)), (math.cos(tr/2), 0, math.sin(tr/2), 0))
        upd = qrot(qd, (0, 0, 1))
        # error axis in body frame: current up -> desired up
        e = qinv_rot(s.q, cross(up, upd))
        ka = p['agility'] * 0.4
        ang = (e[0]*ka*1.0, e[1]*ka*1.0)
        wdx = acro[0] + (ang[0] - acro[0]) * L
        wdy = acro[1] + (ang[1] - acro[1]) * L
        dyaw = (view - heading + 180) % 360 - 180
        wdz = math.radians(max(-p['yawRate'], min(p['yawRate'], dyaw*5)))
        # --- rate loop: torques ---
        ag = p['agility']
        tx = s.I[0]*ag*(wdx - s.w[0]); ty = s.I[1]*ag*(wdy - s.w[1]); tz = s.I[2]*ag*0.5*(wdz - s.w[2])
        # --- collective: vertical speed / altitude hold ---
        if abs(c) > 0.05:
            s.holding = False; az = (c*p['climb'] - s.vel[2]) * 1.6
        else:
            if not s.holding: s.holding = True; s.holdZ = s.pos[2] + s.vel[2]*0.6
            az = (s.holdZ - s.pos[2])*0.8 - s.vel[2]*1.0
        uz = up[2]
        Tc = m*(9.81 + az)/uz if uz > 0.3 else m*9.81*0.6
        # --- mixer ---
        d = p['arm']/math.sqrt(2); kq = p['kq']
        cmd = []
        for (x, y, sp) in s.rotors:
            Ti = Tc/4 + (tx*(1 if y > 0 else -1))/(4*d) + (ty*(-1 if x > 0 else 1))/(4*d) + sp*tz/(4*kq)
            cmd.append(Ti / p['thrust'])
        # air mode: shift so the differentials fit in 0..1
        lo = min(cmd); hi = max(cmd)
        if hi - lo > 1: cmd = [(v - lo)/(hi - lo) for v in cmd]
        elif hi > 1: cmd = [v - (hi - 1) for v in cmd]
        elif lo < 0: cmd = [v - lo for v in cmd]
        k = min(1, dt/p['spool'])
        for i in range(4): s.spool[i] += (cmd[i] - s.spool[i])*k
        T = [s.spool[i]*s.eff[i]*p['thrust'] for i in range(4)]
        # --- body torques from the rotors ---
        Tx = sum(T[i]*s.rotors[i][1] for i in range(4))
        Ty = -sum(T[i]*s.rotors[i][0] for i in range(4))
        Tz = sum(T[i]*s.rotors[i][2]*kq for i in range(4))
        # airflow in the body frame
        vb = qinv_rot(s.q, s.vel)
        Tx += p['flap']*vb[1]; Ty -= p['flap']*vb[0]
        # angular damping
        Tx -= s.I[0]*1.5*s.w[0]; Ty -= s.I[1]*1.5*s.w[1]; Tz -= s.I[2]*1.0*s.w[2]
        # Euler's equation with the gyroscopic term
        Iw = (s.I[0]*s.w[0], s.I[1]*s.w[1], s.I[2]*s.w[2])
        g = cross(s.w, Iw)
        s.w[0] += (Tx - g[0])/s.I[0]*dt; s.w[1] += (Ty - g[1])/s.I[1]*dt; s.w[2] += (Tz - g[2])/s.I[2]*dt
        # orientation
        dq = qmul(s.q, (0, s.w[0], s.w[1], s.w[2]))
        s.q = qnorm(tuple(s.q[i] + 0.5*dq[i]*dt for i in range(4)))
        # --- forces ---
        tot = sum(T)
        F = list(qrot(s.q, (0, 0, tot)))
        sp = math.sqrt(sum(v*v for v in s.vel))
        # quadratic drag per body axis
        db = (-0.5*RHO*p['cdh']*vb[0]*abs(vb[0]), -0.5*RHO*p['cdh']*vb[1]*abs(vb[1]), -0.5*RHO*p['cdv']*vb[2]*abs(vb[2]))
        dw = qrot(s.q, db)
        for i in range(3): F[i] += dw[i] - 0.05*m*s.vel[i]
        F[2] -= m*9.81
        for i in range(3):
            s.vel[i] += F[i]/m*dt; s.pos[i] += s.vel[i]*dt

    def euler(s):
        fw = s.fwd(); rt = qrot(s.q, (1, 0, 0))
        return math.degrees(math.asin(max(-1, min(1, fw[2])))), math.degrees(math.asin(max(-1, min(1, -rt[2])))), math.degrees(math.atan2(-fw[0], fw[1]))

def run(kind, L=None, script=None):
    p = dict(PROF[kind])
    if L is not None: p['level'] = L
    d = Drone(p); dt = 0.004; out = []
    for i in range(int(9/dt)):
        t = i*dt
        f, side, c, view = script(t)
        d.step(dt, f, side, c, view)
        if i % int(0.5/dt) == 0:
            pi, ro, ya = d.euler(); sp = math.hypot(d.vel[0], d.vel[1])
            out.append('t%.1f p%6.1f r%6.1f y%6.1f v%5.1f z%5.2f' % (t, pi, ro, ya, sp, d.pos[2]))
    print(kind, 'L=', p['level']); print('\n'.join(out))

def fwd_then_release(t):
    return (1.0 if 1 <= t < 4 else 0.0, 0.0, 0.0, 0.0)

def diag_turn(t):
    return (1.0 if 1 <= t < 5 else 0.0, -1.0 if 2 <= t < 4 else 0.0, 1.0 if 6 <= t < 7 else 0.0, 90.0 if t >= 3 else 0.0)

def acro_flip(t):
    return (1.0 if 1 <= t < 2.6 else 0.0, 0.0, 0.0, 0.0)

if __name__ == '__main__':
    for k in PROF: run(k, script=fwd_then_release)
    run('bombus', script=diag_turn)
    run('bombus', L=0.0, script=acro_flip)

def contact(s, n, r, bounce, grip):
    wW = qrot(s.q, tuple(s.w))
    cr = cross(wW, r)
    vc = [s.vel[i] + cr[i] for i in range(3)]
    vn = sum(vc[i]*n[i] for i in range(3))
    if vn >= 0: return 0.0
    m = s.p['mass']; ix, _, iz = s.I
    rn = qinv_rot(s.q, cross(r, n))
    irn = qrot(s.q, (rn[0]/ix, rn[1]/ix, rn[2]/iz))
    k = 1/m + sum(a*b for a, b in zip(cross(irn, r), n))
    j = -(1+bounce)*vn/max(1e-4, k)
    vt = [vc[i] - n[i]*vn for i in range(3)]
    sl = math.sqrt(sum(v*v for v in vt))
    imp = [n[i]*j for i in range(3)]
    if sl > 1e-3:
        tdir = [vt[i]/sl for i in range(3)]
        rt = qinv_rot(s.q, cross(r, tdir)); irt = qrot(s.q, (rt[0]/ix, rt[1]/ix, rt[2]/iz))
        kt = 1/m + sum(a*b for a, b in zip(cross(irt, r), tdir))
        ft = min(grip*j, sl/max(1e-4, kt))
        imp = [imp[i] - vt[i]/sl*ft for i in range(3)]
    for i in range(3): s.vel[i] += imp[i]/m
    ang = qinv_rot(s.q, cross(r, imp))
    s.w[0] += ang[0]/ix; s.w[1] += ang[1]/ix; s.w[2] += ang[2]/iz
    return -vn

def crash_test(kind):
    p = dict(PROF[kind]); d = Drone(p); d.pos = [0, 0, 1.5]; d.holdZ = 1.5; dt = 0.004; out = []; hits = []
    for i in range(int(6/dt)):
        t = i*dt
        f = 1.0 if t < 3 else 0.0
        c = -1.0 if 1 < t < 2 else 0.0
        frame_from = list(d.pos)
        d.step(dt, f, 0.0, c, 0.0)
        r = 0.3
        if d.pos[2] < r:  # ground
            d.pos[2] = r; v = contact(d, (0, 0, 1), (0, 0, -r), 0.0, GRIP)
            if v > 0.5: hits.append(('ground', round(t, 2), round(v, 1)))
        if d.pos[1] > 25 - r:  # wall facing -y
            d.pos[1] = 25 - r; v = contact(d, (0, -1, 0), (0, r, 0), 0.25, 0.3)
            if v > 0.5: hits.append(('wall', round(t, 2), round(v, 1)))
        if i % int(0.5/dt) == 0:
            pi, ro, ya = d.euler()
            out.append('t%.1f p%6.1f r%6.1f y%6.1f vy%5.1f z%5.2f w%5.1f' % (t, pi, ro, ya, d.vel[1], d.pos[2], math.degrees(math.sqrt(sum(x*x for x in d.w)))))
    print(kind, 'crash test'); print('\n'.join(out)); print(hits[:8])

for GRIP in (0.5, 0.25, 0.15):
    print('GRIP', GRIP); crash_test('bombus')
