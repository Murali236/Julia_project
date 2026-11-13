"""Independent FE verification of an exported Julia arch model using Pynite.
No Julia matrices or equivalent nodal load vectors are reused.
Usage: python verify_arch_pynite.py Arch_Model.toml [more models...]
"""
import argparse
import math
from pathlib import Path
import tomllib
import numpy as np
from Pynite import FEModel3D


def verify(path):
    model=tomllib.loads(path.read_text())
    xs,ys=model['mesh_x'],model['mesh_y'];n=len(xs)
    fe=FEModel3D()
    for j,(x,y) in enumerate(zip(xs,ys)):
        name=f'N{j}';fe.add_node(name,x,y,0)
        end=j in (0,n-1)
        fe.def_support(name,end,end,True,True,True,end and model['support']=='fixed')
    for j in range(n-1):
        a,b=xs[j:j+2];length=math.hypot(b-a,ys[j+1]-ys[j]);c=(b-a)/length
        p=next(p for p in model['sections'] if p['a']<=(a+b)/2<=p['b'])
        I=p['I']
        if p['law']=='secant':
            g=model['geometry'];mid=(a+b)/2
            if g['kind']=='parabolic':slope=4*g['f']*(g['L']-2*mid)/g['L']**2
            elif g['kind']=='circular':
                R=g['L']**2/(8*g['f'])+g['f']/2
                slope=-(mid-g['L']/2)/math.sqrt(R*R-(mid-g['L']/2)**2)
            else:slope=(ys[j+1]-ys[j])/(b-a)
            I*=math.hypot(1,slope)
        fe.add_material(f'E{j}',p['E'],p['E']/2.6,0.3,0)
        fe.add_section(f'S{j}',p['A'],I,I,2*I)
        fe.add_member(f'M{j}',f'N{j}',f'N{j+1}',f'E{j}',f'S{j}')
        if model['support']=='three_hinged' and b==model['hinge']:
            fe.def_releases(f'M{j}',Rzj=True)
        for l in model['loads']:
            if l['kind']=='line' and l['a']<=a and b<=l['b']:
                for direction,qa,qb in [('FX',l['qxa'],l['qxb']),('FY',l['qya'],l['qyb'])]:
                    wa=qa+(qb-qa)*(a-l['a'])/(l['b']-l['a'])
                    wb=qa+(qb-qa)*(b-l['a'])/(l['b']-l['a'])
                    if wa or wb:fe.add_member_dist_load(f'M{j}',direction,wa*c,wb*c)
    for l in model['loads']:
        if l['kind']=='point':
            node=f"N{xs.index(l['x'])}";fe.add_node_load(node,'FX',l['fx']);fe.add_node_load(node,'FY',l['fy'])
        elif l['kind']=='moment':fe.add_node_load(f"N{xs.index(l['x'])}",'MZ',l['moment'])
    for sp in model.get('springs',[]):
        for dof,k in [('DX',sp['kx']),('DY',sp['ky']),('RZ',sp['kr'])]:
            if k:fe.def_support_spring(f"N{xs.index(sp['x'])}",dof,k)
    fe.analyze_linear()
    combo='Combo 1'
    reactions=[]
    for j in (0,n-1):
        node=fe.nodes[f'N{j}']
        reactions.extend([node.RxnFX[combo],node.RxnFY[combo],node.RxnMZ[combo]])
    reference=np.asarray(model['frame_reactions'])
    np.testing.assert_allclose(reactions,reference,rtol=2e-7,atol=2e-3)
    displacements=[];expected=[]
    for j in range(n):
        node=fe.nodes[f'N{j}']
        displacements.extend([node.DX[combo],node.DY[combo],node.RZ[combo]])
        expected.extend(model['frame_d'][3*j:3*j+3])
        if model['support']=='three_hinged' and xs[j]==model['hinge']:
            expected[-1]=model['frame_d'][-1] # Pynite's retained rotation is on the right
    np.testing.assert_allclose(displacements,expected,rtol=2e-6,atol=2e-10)
    force_error=float(np.max(np.abs(np.asarray(reactions)-reference)))
    disp_error=float(np.max(np.abs(np.asarray(displacements)-expected)))
    line=f'{path.name}: PASS; {n-1} elements; max reaction difference={force_error:.6g} N/N-m; max DOF difference={disp_error:.6g} m/rad'
    print(line)
    path.with_name(path.stem+'_Pynite_Verification.txt').write_text(line+'\nPynite 3.2.0; independent frame assembly, transforms, member loads, and hinge releases.\n')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('models',type=Path,nargs='+')
    for path in parser.parse_args().models:verify(path)
