"""Piecewise SymPy arch equations; optional symbolic/numerical compatibility check.
Usage: python arch_symbolic.py Arch_Model.toml [--compatibility]
Python 3.11+, SymPy; compatibility fallback additionally uses SciPy.
"""
import argparse
import math
from pathlib import Path
import signal
import tomllib
import sympy as sp

x = sp.Symbol('x', real=True)
R = lambda v: sp.Rational(str(v))


def geometry(g):
    L, f = R(g['L']), R(g['f'])
    if g['kind'] == 'parabolic':
        y = 4*f*x*(L-x)/L**2
    elif g['kind'] == 'circular':
        radius = L**2/(8*f)+f/2
        y = f-radius+sp.sqrt(radius**2-(x-L/2)**2)
    else:
        pieces = []
        for a,b,ya,yb in zip(g['xs'],g['xs'][1:],g['ys'],g['ys'][1:]):
            pieces.append((R(ya)+(R(yb)-R(ya))*(x-R(a))/(R(b)-R(a)),x<R(b)))
        pieces[-1] = (pieces[-1][0],True)
        y = sp.Piecewise(*pieces)
    slope = sp.diff(y,x)
    c = 1/sp.sqrt(1+slope**2)
    return y,c,slope*c


def primitive_y(g):
    L,f=R(g['L']),R(g['f'])
    if g['kind']=='parabolic':
        y=4*f*x*(L-x)/L**2
        return sp.integrate(y,x),sp.integrate(x*y,x)
    radius=L**2/(8*f)+f/2
    u=x-L/2
    h=sp.sqrt(radius**2-u**2)
    z=(u*h+radius**2*sp.asin(u/radius))/2
    return (f-radius)*x+z,(f-radius)*x**2/2+L*z/2-h**3/3


def ramp_integral(primitive,a,b):
    a,b=R(a),R(b)
    part=primitive-primitive.subs(x,a)
    return sp.Piecewise((0,x<a),(part,x<b),(part.subs(x,b),True))


def equations(model):
    g=model['geometry'];y,c,s=geometry(g)
    fx=fy=T=sp.S.Zero
    for load in model['loads']:
        if load['kind']=='point':
            a=R(load['x']);h=sp.Piecewise((0,x<a),(1,True))
            px,py=R(load['fx']),R(load['fy'])
            fx+=h*px;fy+=h*py;T+=h*(a*py-y.subs(x,a)*px)
        elif load['kind']=='moment':
            T+=sp.Piecewise((0,x<R(load['x'])),(R(load['moment']),True))
        else:
            a,b=R(load['a']),R(load['b'])
            bx=(R(load['qxb'])-R(load['qxa']))/(b-a);by=(R(load['qyb'])-R(load['qya']))/(b-a)
            ax=R(load['qxa'])-bx*a;ay=R(load['qya'])-by*a
            fx+=ramp_integral(sp.integrate(ax+bx*x,x),a,b)
            fy+=ramp_integral(sp.integrate(ay+by*x,x),a,b)
            if g['kind']=='polyline':
                for lo,hi,ya,yb in zip(g['xs'],g['xs'][1:],g['ys'],g['ys'][1:]):
                    aa,bb=max(a,R(lo)),min(b,R(hi))
                    if aa>=bb:continue
                    yy=R(ya)+(R(yb)-R(ya))*(x-R(lo))/(R(hi)-R(lo))
                    T+=ramp_integral(sp.integrate(x*(ay+by*x)-yy*(ax+bx*x),x),aa,bb)
            else:
                Y,XY=primitive_y(g)
                T+=ramp_integral(ay*x**2/2+by*x**3/3-ax*Y-bx*XY,a,b)
    reactions=model.get('force_reactions',model.get('frame_reactions'))
    if reactions is None:raise ValueError('No solved reactions in model')
    H,V,M=(sp.Float(str(v),12) for v in reactions[:3])
    # General spring models use stiffness reactions plus their nodal springs.
    for spring in model.get('springs',[]):
        j=model['mesh_x'].index(spring['x']);d=model['frame_d']
        px=-R(spring['kx'])*R(d[3*j]);py=-R(spring['ky'])*R(d[3*j+1]);mm=-R(spring['kr'])*R(d[3*j+2])
        a=R(spring['x']);h=sp.Piecewise((0,x<a),(1,True))
        fx+=px*h;fy+=py*h;T+=h*(a*py-y.subs(x,a)*px+mm)
    expressions={'y(x)':y,'Fx_prefix(x)':fx,'Fy_prefix(x)':fy,'T_prefix(x)':T,
                 'M(x)':x*(V+fy)-y*(H+fx)-M-T,
                 'N(x)':-((H+fx)*c+(V+fy)*s),'Q(x)':(V+fy)*c-(H+fx)*s}
    return expressions,(fx,fy,T),(y,c,s)


class IntegrationTimeout(Exception):pass

def integrate_checked(expr,a,b):
    """Attempt a closed form for two seconds; preserve the same integrand on fallback."""
    def timeout(*_):raise IntegrationTimeout()
    signal.signal(signal.SIGALRM,timeout)
    try:
        signal.setitimer(signal.ITIMER_REAL,2)
        value=sp.integrate(expr,(x,R(a),R(b)))
        if value.has(sp.Integral):raise IntegrationTimeout()
        result=float(value.evalf())
        if not math.isfinite(result):raise IntegrationTimeout()
        return result,'symbolic'
    except (IntegrationTimeout,TypeError,ValueError):
        pass
    finally:
        signal.setitimer(signal.ITIMER_REAL,0)
    from scipy.integrate import quad
    fn=sp.lambdify(x,expr,'math')
    value,error=quad(fn,float(a),float(b),epsabs=1e-12,epsrel=1e-9,limit=200)
    if error>max(1e-11,abs(value)*1e-6):raise ArithmeticError('Quadrature failed requested tolerance')
    return value,'numerical fallback'


def on_interval(expr,a,b):
    mid=R((a+b)/2)
    def choose(e):
        for value,cond in e.args:
            if cond==True or cond.subs(x,mid)==True:return value
        raise ValueError('Uncovered piecewise interval')
    return expr.replace(lambda e:isinstance(e,sp.Piecewise),choose)


def compatibility(model,prefix,geom):
    import numpy as np
    if model['support']=='three_hinged' or model.get('springs'):
        return 'Compatibility re-integration applies to two-hinged/fixed models without springs.\n'
    y,c,s=geom;fx,fy,T=prefix;L=R(model['geometry']['L'])
    VA=-fy.subs(x,L)+T.subs(x,L)/L
    R0=[0,VA,0] if model['support']=='two_hinged' else [0,0,0]
    M0=x*(R0[1]+fy)-y*fx-T
    N0=-(fx*c+(R0[1]+fy)*s)
    us=[(-y,-c)] if model['support']=='two_hinged' else [(-y,-c),(x,-s),(-sp.S.One,sp.S.Zero)]
    n=len(us);F=np.zeros((n,n));D=np.zeros(n);backends=set()
    cuts={0.,float(L),*model['geometry'].get('xs',[])}
    for load in model['loads']:
        cuts.update([load['a'],load['b']] if load['kind']=='line' else [load['x']])
    for p in model['sections']:cuts.update([p['a'],p['b']])
    cuts=sorted(cuts)
    for a,b in zip(cuts,cuts[1:]):
        p=next(p for p in model['sections'] if p['a']<=(a+b)/2<=p['b'])
        EI=R(p['E'])*R(p['I'])/(c if p['law']=='secant' else 1)
        EA=R(p['E'])*R(p['A']);axial=int(model['axial'])
        for i,(mi,ni) in enumerate(us):
            expr=on_interval((mi*M0/EI+axial*ni*N0/EA)/c,a,b)
            value,backend=integrate_checked(expr,a,b);D[i]+=value;backends.add(backend)
            for j in range(i,n):
                mj,nj=us[j]
                expr=on_interval((mi*mj/EI+axial*ni*nj/EA)/c,a,b)
                value,backend=integrate_checked(expr,a,b);F[i,j]+=value;backends.add(backend)
                if i!=j:F[j,i]+=value
    X=np.linalg.solve(F,-D)
    RA=np.array(R0,dtype=float)
    if n==1:RA[0]+=X[0]
    else:RA+=X
    reference=np.array(model['force_reactions'][:3])
    if not np.allclose(RA,reference,rtol=2e-7,atol=1e-5):
        raise AssertionError(f'Symbolic/quadrature compatibility differs: {RA} vs {reference}')
    return f'Compatibility backends: {sorted(backends)}\nF (support-A redundant basis):\n{F}\nDelta0={D}\nRA={RA}\nJulia comparison: PASS\n'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('model',type=Path);parser.add_argument('--compatibility',action='store_true')
    args=parser.parse_args();model=tomllib.loads(args.model.read_text())
    expr,prefix,geom=equations(model)
    output=args.model.with_name('Arch_Symbolic_Equations.txt' if args.model.stem=='Arch_Model' else args.model.stem+'_Symbolic_Equations.txt')
    text=['SymPy PIECEWISE ARCH EQUATIONS','SI units: N, m, N-m. Reaction coefficients are numerical (12 significant digits).',
          'Expressions hold inside the arch; at point events these use the right-hand side.',
          'Use one-sided limits for end values and jumps. All distributed load moments were integrated symbolically.']
    text.extend(f'\n{name} = {value}' for name,value in expr.items())
    if args.compatibility:text.append('\n'+compatibility(model,prefix,geom))
    output.write_text('\n'.join(text)+'\n')
    print(f'Symbolic equations saved to {output}')


if __name__=='__main__':main()
