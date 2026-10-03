"""Original Kart Racer meshes. Run: blender --background --python art/build_assets.py
Blender uses X right, Y forward, Z up; FBX exports -Z forward, Y up.
One Blender unit is intended as one Roblox stud; verify Import 3D scaling.
"""
import bpy, math, random, json, pathlib, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parent
for folder in ('blend','fbx','previews'): (ROOT/folder).mkdir(exist_ok=True)
ONLY = set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
MANIFEST=json.loads((ROOT/'manifest.json').read_text()) if ONLY and (ROOT/'manifest.json').exists() else []

def material(name, color, metallic=0, roughness=.65):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metallic; p.inputs['Roughness'].default_value=roughness
    return m

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global bark, leaves, stone, paint, accent, rubber, chrome, dark
    bark=material('Bark',(.17,.09,.045)); leaves=[material('Foliage'+str(i),c) for i,c in enumerate([(.06,.19,.10),(.12,.30,.13),(.23,.40,.16)])]
    stone=material('Stone',(.34,.37,.39)); paint=material('Paint',(.45,.035,.025),.35,.25)
    accent=material('Accent',(.95,.60,.12),.3,.3); rubber=material('Rubber',(.025,.028,.035),0,.85)
    chrome=material('Metal',(.60,.65,.7),.8,.25); dark=material('DarkMetal',(.075,.09,.11),.65,.4)

def finish(obj,name,mat):
    obj.name=name; obj.data.materials.append(mat); return obj

def box(name,loc,size,mat,bevel=.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o=bpy.context.object; o.scale=size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod=o.modifiers.new('Edge rounding','BEVEL'); mod.width=bevel; mod.segments=1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,mat)

def cone(name,loc,r1,r2,height,mat,vertices=10):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=height,location=loc)
    return finish(bpy.context.object,name,mat)

def ico(name,loc,size,mat,sub=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object; o.scale=size; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o,name,mat)

def rod(name,start,end,r,mat,vertices=8):
    d=Vector(end)-Vector(start); o=cone(name,(Vector(start)+Vector(end))/2,r,r,d.length,mat,vertices)
    o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return o

def join(objs,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]; bpy.ops.object.join(); o=objs[0]; o.name=name
    bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o

def smooth(o):
    for face in o.data.polygons: face.use_smooth=True
    return o

def mesh(name,vertices,faces,mat):
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);return finish(o,name,mat)

def loft(name,sections,mat,x=0):
    # Eight-point rounded cross section, with changing width and height.
    vertices=[]
    for y,w,lo,hi in sections:
        corner=min(.12,(hi-lo)*.25)
        vertices.extend([(x-w*.8,y,lo),(x+w*.8,y,lo),(x+w,y,lo+corner),
                         (x+w,y,hi-corner),(x+w*.8,y,hi),(x-w*.8,y,hi),
                         (x-w,y,hi-corner),(x-w,y,lo+corner)])
    faces=[tuple(reversed(range(8)))]
    for j in range(len(sections)-1):
        for k in range(8):faces.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
    faces.append(tuple(range((len(sections)-1)*8,len(sections)*8)))
    return smooth(mesh(name,vertices,faces,mat))

def ring(name,loc,major,minor,mat,rotation=(0,0,0),segments=24):
    bpy.ops.mesh.primitive_torus_add(major_radius=major,minor_radius=minor,major_segments=segments,minor_segments=6,location=loc,rotation=rotation)
    return smooth(finish(bpy.context.object,name,mat))

def pine(i):
    rng=random.Random(100+i);h=[8.5,10,7.5,11][i]
    # Leaning tapered trunks, root flares, visible radial branches; no cone tiers.
    rod('Trunk',(0,0,.1),(.15*(i-1),.1,h*.87),.18,bark,9)
    for j in range(5):
        angle=j*math.tau/5;rod('Root',(0,0,.15),(math.cos(angle)*.65,math.sin(angle)*.65,.03),.085,bark,6)
    for level in range(7):
        z=1.4+level*(h-2)/7;reach=(h-z)*.29
        for j in range(5):
            angle=j*math.tau/5+level*.65+rng.uniform(-.15,.15)
            tip=(math.cos(angle)*reach,math.sin(angle)*reach,z-.12)
            rod('Branch',(0,0,z),tip,.045,bark,5)
            o=ico('NeedleCluster',(tip[0]*.7,tip[1]*.7,z+.25),(reach*.7,.40,.6),leaves[(j+level)%3],1)
            o.rotation_euler[2]=angle; smooth(o)
    smooth(ico('Leader',(.05,0,h-.45),(.42,.42,.85),leaves[0],1))

def leafy(i):
    rng=random.Random(300+i);h=[6.5,8,5.6][i]
    # Three different canopy silhouettes: rounded oak, tall crown, spreading tree.
    lean=[(.25,.0),(-.15,.25),(.4,-.1)][i]
    rod('Trunk',(0,0,.12),(lean[0],lean[1],h*.65),.24,bark,10)
    for j in range(5):
        a=j*math.tau/5;rod('Root',(0,0,.12),(math.cos(a)*.7,math.sin(a)*.7,.02),.10,bark,6)
    for j in range(10):
        a=j*2.399;reach=[1.5,1.1,2.0][i]*rng.uniform(.7,1.2)
        z=h*.63+rng.uniform(-.8,1.2);x,y=math.cos(a)*reach,math.sin(a)*reach
        rod('Branch',(lean[0],lean[1],h*.35),(x,y,z),.075,bark,7)
        size=[(1.4,1.15,1.3),(1.1,1.1,1.6),(1.55,1.1,1.0)][i]
        o=ico('Leaves',(x,y,z),size,leaves[j%3],2)
        # Irregular surfaces rather than identical balls.
        for v in o.data.vertices:v.co*=rng.uniform(.90,1.08)
        smooth(o)
    smooth(ico('Crown',(lean[0],lean[1],h-.5),(1.5,1.25,1.35),leaves[1],2))

def rock(i):
    rng=random.Random(500+i)
    sizes=[(2.4,1.4,1.2),(1.5,1.5,2),(2.7,1.1,.8),(1.7,1.5,1.4)]
    o=ico('WeatheredRock',(0,0,0),sizes[i],stone,3)
    for v in o.data.vertices:
        v.co*=rng.uniform(.93,1.08)
        if i==1 and v.co.z>.2:v.co.x+=v.co.z*.24
    low=min(v.co.z for v in o.data.vertices)
    for v in o.data.vertices:v.co.z-=low
    # Mineral patches, weathered darker crevices and moss on upper surfaces.
    mats=[material('Mineral',(.43,.45,.43)),material('Moss',(.16,.23,.10)),material('Crevice',(.20,.23,.25))]
    for m in mats:o.data.materials.append(m)
    for face in o.data.polygons:
        z=sum(o.data.vertices[k].co.z for k in face.vertices)/len(face.vertices)
        face.material_index=2 if z>sizes[i][2]*1.5 and rng.random()<.35 else (1 if rng.random()<.15 else (3 if rng.random()<.09 else 0))
    smooth(o)

def distant(i):
    cone('Trunk',(0,0,2),.2,.10,4,bark,7)
    if i==0:
        for j in range(3):cone('Crown',(0,0,3+j*1.2),2-j*.55,.06,2.5,leaves[j],9)
    else:
        for j in range(4):ico('Crown',(math.cos(j*1.7),math.sin(j*1.7),4+j*.25),(1.6,1.5,1.8),leaves[j%3],1)

def wheel(name,x,y,r,width):
    # Rounded tyre sidewalls and open centre; tread blocks on the outer belt.
    parts=[];verts=[];faces=[];segments=28
    profile=[(-.5,.58),(-.5,.83),(-.38,.97),(-.20,1),(.20,1),(.38,.97),(.5,.83),(.5,.58)]
    for xx,rr in profile:
        for j in range(segments):
            a=j*math.tau/segments;verts.append((x+xx*width,y+math.cos(a)*r*rr,r+math.sin(a)*r*rr))
    for k in range(len(profile)):
        for j in range(segments):faces.append((k*segments+j,k*segments+(j+1)%segments,((k+1)%len(profile))*segments+(j+1)%segments,((k+1)%len(profile))*segments+j))
    parts.append(smooth(mesh('Tyre',verts,faces,rubber)))
    outward=-1 if x<0 else 1;xx=x+outward*width*.48
    parts.append(ring('RimLip',(xx,y,r),r*.62,.065,chrome,(0,math.pi/2,0),24))
    o=cone('BrakeRotor',(xx-outward*.06,y,r),r*.5,r*.5,.04,dark,20);o.rotation_euler[1]=math.pi/2;parts.append(o)
    o=cone('Hub',(xx,y,r),r*.18,r*.18,.12,chrome,12);o.rotation_euler[1]=math.pi/2;parts.append(o)
    for j in range(6):
        a=j*math.tau/6
        parts.append(rod('Spoke',(xx,y+math.cos(a)*r*.18,r+math.sin(a)*r*.18),(xx,y+math.cos(a)*r*.56,r+math.sin(a)*r*.56),.065,chrome,6))
    for j in range(20):
        a=j*math.tau/20
        o=box('Tread',(x,y+math.cos(a)*r*.987,r+math.sin(a)*r*.987),(width*.60,.10,.035),rubber,0)
        o.rotation_euler[0]=a-math.pi/2;parts.append(o)
    return join(parts,name)

def engine(y,z,style):
    box('EngineBlock',(0,y,z),(1.45,1.4,.55),dark,.08)
    for x in (-.62,.62):
        box('ValveCover',(x,y,z+.37),(.38,1.55,.25),chrome,.10)
        for j in range(4):
            rod('Header',(x,y-.5+j*.32,z+.15),(x*1.7,y-.5+j*.32,z-.30),.075,chrome,7)
            box('CoolingFin',(x,y-.55+j*.35,z+.53),(.35,.045,.025),dark,0)
    intake=loft('EngineIntake',[(y-.55,.42,z+.62,z+1.02),(y+.4,.52,z+.62,z+1.12),(y+.65,.44,z+.70,z+1.04)],chrome);intake['Anim']='engine'
    box('IntakeMouth',(0,y+.66,z+.86),(.68,.03,.18),dark,.03)
    for x in (-.25,0,.25):
        o=cone('IntakeThrottle',(x,y+.45,z+1.13),.075,.10,.16,chrome,8);o['Anim']='engine'
    # Pulley drive, belt, coolant hoses and bolts make the motor readable.
    for zz,rr in [(z+.15,.20),(z+.75,.14)]:
        o=cone('Pulley',(0,y+.85,zz),rr,rr,.10,dark,12);o.rotation_euler[0]=math.pi/2
        ring('PulleyRim',(0,y+.91,zz),rr*.75,.025,chrome,(math.pi/2,0,0),12)
    for x in (-.15,.15):rod('DriveBelt',(x,y+.90,z+.12),(x,y+.90,z+.75),.025,rubber,5)
    rod('CoolantHose',(.7,y-.6,z+.2),(.9,y-.1,z-.25),.055,rubber)
    if style=='v12':
        for x in (-.32,.32):
            for j in range(6):cone('IntakeStack',(x,y-.55+j*.2,z+1.32),.055,.085,.32,chrome,7)['Anim']='engine'


def car(style):
    truck=style=='dunehauler';drag=style=='dragster';mid=style=='v12';hot=style=='blowerrod'
    colors={'thunder':(.40,.018,.03),'v12':(.015,.11,.38),'blowerrod':(.60,.095,.01),'dragster':(.26,.025,.38),'dunehauler':(.045,.25,.12)}
    paint.diffuse_color=(*colors[style],1);paint.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=paint.diffuse_color
    glass=material('LampGlass',(.62,.83,.92),.25,.12);red=material('TailGlass',(.5,.015,.025),.1,.22)
    box('Chassis',(0,0,.70),(3.0,9.4,.25),dark,.10)
    for x in (-1.50,1.50):
        sections=[(-4.3,.27,.8,1.18),(-3.0,.46,.8,1.7),(-1,.28,.8,1.6),(1,.27,.8,1.45),(3,.39,.8,1.8),(4.3,.22,.8,1.1)]
        if hot or drag:sections=[(y,w*.65,lo,hi-.1) for y,w,lo,hi in sections]
        loft('PaintSculptedSill',sections,paint,x)
        box('AccentSill',(x,0,.88),(.06,4.2,.10),accent,.025)
    front_width=.88 if hot or drag else (1.65 if truck else 1.60)
    loft('PaintNose',[(1.35,front_width,.83,1.65),(2.5,front_width, .83,1.65),(3.65,front_width*.90,.72,1.35),(4.55,front_width*.72,.70,1.10)],paint)
    loft('PaintTail',[(-4.55,1.3,.8,1.12),(-3.3,1.55,.8,1.6),(-1.55,1.30,.8,1.5)],paint)
    box('AccentFrontSplitter',(0,4.58,.61),(3.6,.25,.15),dark,.05)
    # Cockpit is still open for a Roblox driver; no untested glass canopy.
    box('SeatCushion',(0,-.1,1.05),(1.5,1.55,.20),rubber,.12)
    seat=loft('SeatBack',[(-1.1,.68,1.05,2.1),(-.90,.72,1.05,2.1)],rubber)
    for x in (-.35,.35):box('SeatStitch',(x,-.87,1.58),(.025,.02,.65),accent,0)
    box('Dashboard',(0,1.1,1.6),(1.5,.38,.25),dark,.10)
    for x in (-.35,0,.35):
        o=cone('InstrumentDial',(x,.88,1.70),.11,.11,.025,chrome,12);o.rotation_euler[0]=math.pi/2
    rod('SteeringColumn',(0,.8,1.1),(0,.65,1.8),.075,dark)
    ring('SteeringWheel',(0,.65,1.8),.40,.055,rubber,(math.pi/3,0,0),16)
    for a in (0,2.1,4.2):rod('SteeringSpoke',(0,.65,1.8),(.32*math.cos(a),.65,1.8+.32*math.sin(a)),.03,chrome,5)
    engine(-2.7 if mid or drag else 2.35,1.70,style)
    # Front grille, inset lamp housings, four vents and sculpted fender arches.
    box('GrilleRecess',(0,4.58,.92),(1.7,.04,.30),dark,.04)
    for j in range(7):box('GrilleSlat',(-.66+j*.22,4.61,.92),(.045,.025,.22),chrome,0)
    for x in (-1.05,1.05):
        box('LampHousing',(x,4.28,1.12),(.65,.12,.28),dark,.08)
        box('HeadlampLens',(x,4.35,1.12),(.53,.025,.17),glass,.05)
        box('TailLampHousing',(x,-4.45,1.23),(.66,.06,.27),dark,.05)
        box('TailLampLens',(x,-4.49,1.23),(.55,.025,.17),red,.04)
    for side in (-1,1):
        for j in range(4):box('CoolingVent',(side*1.71,.1+j*.28,1.46),(.03,.16,.15),dark,0)
        rod('MirrorArm',(side*1.4,1.2,1.7),(side*1.9,1.15,1.9),.045,dark,6)
        box('PaintMirrorHousing',(side*1.9,1.15,1.92),(.30,.32,.16),paint,.06)
        # Side pipes; open end treatment.
        rod('Exhaust',(side*1.8,-3.9,.85),(side*1.8,-1.5,.85),.11,chrome,10)
        o=cone('ExhaustOpening',(side*1.8,-3.92,.85),.085,.085,.03,dark,10);o.rotation_euler[0]=math.pi/2
    radius=1.02 if truck else .9
    for name,x,y in [('WheelFL',-1.95,2.8),('WheelFR',1.95,2.8),('WheelRL',-1.95,-2.8),('WheelRR',1.95,-2.8)]:
        r=1.07 if name.startswith('WheelR') and (drag or hot) else radius
        wheel(name,x,y,r,.86)
        # Eight-section arch covers the upper tyre, not a flat plank.
        if not hot and not drag:
            verts=[];faces=[]
            for j in range(9):
                a=.05+j*(math.pi-.10)/8
                for xx,rr in [(x-.43,r+.11),(x+.43,r+.11),(x+.43,r+.20),(x-.43,r+.20)]:verts.append((xx,y+math.cos(a)*rr,r+math.sin(a)*rr))
            for j in range(8):
                for k in range(4):faces.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
            smooth(mesh('PaintWheelArch',verts,faces,paint))
        box('BrakeCaliper',(x+(.32 if x>0 else -.32),y+.26,r),(.09,.22,.34),accent,.04)
    if truck:
        for x in (-1.35,1.35):
            rod('Cage',(x,-1.5,1.55),(x,-1.4,3.4),.085,dark)
            rod('Cage',(x,-1.4,3.4),(x,1.15,2.9),.085,dark)
            rod('Cage',(x,1.15,2.9),(x,1.5,1.6),.085,dark)
        rod('CageCross',(-1.35,-1.4,3.4),(1.35,-1.4,3.4),.085,dark)
        rod('CageBrace',(-1.35,-1.4,3.4),(1.35,-2.2,1.6),.06,dark)
        for j in range(5):box('RoofLamp',(-.9+j*.45,-1.4,3.55),(.30,.22,.16),glass,.04)
        rod('FrontSkid',(-1.5,4.5,.9),(1.5,4.5,.9),.09,chrome)
    elif drag or mid:
        for x in (-1.25,1.25):box('WingSupport',(x,-3.8,2),(.10,.25,1.1),dark,.025)
        loft('AccentAeroWing',[(-4.15,2.0,2.45,2.61),(-3.5,2.0,2.49,2.68)],accent)
        for x in (-2,2):box('AccentWingEndplate',(x,-3.85,2.6),(.06,.80,.4),accent,.03)
    elif hot:
        for x in (-1.35,1.35):rod('RearHoop',(x,-1.5,1.5),(x,-1.5,2.45),.065,chrome)
        rod('RearHoopTop',(-1.35,-1.5,2.45),(1.35,-1.5,2.45),.065,chrome)
    for x in (-.44,.44):
        stripe=box('AccentNoseStripe',(x,3.83,1.325),(.12,1.45,.02),accent,0);stripe.rotation_euler[0]=-.29
    # Rear diffuser fins, towing eye and small fuel cap.
    for x in (-.7,0,.7):box('DiffuserFin',(x,-4.45,.67),(.06,.6,.25),dark,.015)
    ring('TowEye',(0,4.7,.75),.13,.025,accent,(math.pi/2,0,0),12)
    cap=cone('FuelCap',(1.42,-1.8,1.63),.12,.12,.035,chrome,12)

def batch_static():
    # Keep wheels and animated engine pieces separate; batch static geometry
    # by material to limit imported MeshParts and preserve paint prefixes.
    groups={}
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH' or o.name.startswith('Wheel') or o.get('Anim'):continue
        mat=o.data.materials[0]
        groups.setdefault(mat.name,[]).append(o)
    names={'Paint':'PaintBody','Accent':'AccentTrim','Rubber':'Interior',
           'Metal':'MetalDetails','DarkMetal':'DarkDetails','LampGlass':'HeadlampLenses',
           'TailGlass':'TailLampLenses'}
    for mat,objects in groups.items():join(objects,names.get(mat,mat+'Details'))

def save_asset(name,folder,limit,iscar=False):
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    if not iscar:
        meshes=[join(meshes,name)]
        bottom=min(v.co.z for v in meshes[0].data.vertices)
        for v in meshes[0].data.vertices:v.co.z-=bottom
    # Triangulated geometry is counted after bevels and joins, before export.
    count=0; positions=[]
    for o in meshes:
        o.data.calc_loop_triangles();count+=len(o.data.loop_triangles)
        positions += [o.matrix_world @ Vector(v) for v in o.bound_box]
    assert count<limit,(name,count,limit)
    low=Vector(tuple(min(v[k] for v in positions) for k in range(3)))
    high=Vector(tuple(max(v[k] for v in positions) for k in range(3)))
    if iscar:
        assert all(any(o.name==n for o in meshes) for n in ('WheelFL','WheelFR','WheelRL','WheelRR'))
        assert high.x-low.x <= 5.1 and 9 <= high.y-low.y <= 10.1, (name, list(high-low))
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.export_scene.fbx(filepath=str(ROOT/'fbx'/f'{name}.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',bake_space_transform=True,apply_unit_scale=False,use_custom_props=True,bake_anim=False)
    # Save source geometry only. Studio lights/ground are render-only.
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blend'/f'{name}.blend'),compress=True)
    scene=bpy.context.scene; scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False
    scene.render.resolution_x=1080;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.21,.26,1)
    centre=(low+high)/2; extent=max(high-low)
    box('RenderGround',(0,0,-.07),(extent*5,extent*5,.12),material('Ground',(.12,.15,.18)),0)
    bpy.ops.object.camera_add(location=centre+Vector((extent*1.05,extent*1.45,extent*.95)))
    cam=bpy.context.object;cam.rotation_euler=(centre-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=extent*1.38;scene.camera=cam
    for loc,power,size in [(Vector((extent,extent,extent*1.6)),2200,extent), (Vector((-extent,0,extent)),1500,extent*.8)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(centre-o.location).to_track_quat('-Z','Y').to_euler()
    scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=92;scene.render.filepath=str(ROOT/'previews'/f'{name}.jpg');bpy.ops.render.render(write_still=True)
    MANIFEST[:]=[r for r in MANIFEST if r['name']!=name]
    MANIFEST.append({'name':name,'folder':folder,'triangles':count,'mesh_objects':len(meshes),'limit':limit,'dimensions_blender':list(high-low),'fbx':f'fbx/{name}.fbx','blend':f'blend/{name}.blend','preview':f'previews/{name}.jpg','engine_parts':[o.name for o in meshes if o.get('Anim')=='engine']})
    print('ASSET',name,count,flush=True)

def main():
    specs=[]
    for i in range(4):specs.append((f'pine_{i+1}','Pines',2000,lambda i=i:pine(i)))
    for i in range(3):specs.append((f'leafy_{i+1}','Trees',2000,lambda i=i:leafy(i)))
    for i in range(4):specs.append((f'rock_{i+1}','Rocks',1000,lambda i=i:rock(i)))
    for i in range(2):specs.append((f'far_tree_{i+1}','FarTrees',300,lambda i=i:distant(i)))
    for name in ('thunder','v12','blowerrod','dragster','dunehauler'):specs.append((name,'Bodies',10000,lambda name=name:car(name)))
    for name,folder,limit,builder in specs:
        if ONLY and name not in ONLY:continue
        reset();builder()
        if folder=='Bodies':batch_static()
        save_asset(name,folder,limit,folder=='Bodies')
        (ROOT/'manifest.json').write_text(json.dumps(MANIFEST,indent=2)+'\n')

if __name__=='__main__':main()
