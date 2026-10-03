"""Original Kart Racer meshes. Run: blender --background --python art/build_assets.py
Blender uses X right, Y forward, Z up; FBX exports -Z forward, Y up.
One Blender unit is intended as one Roblox stud; verify Import 3D scaling.
"""
import bpy, math, random, json, pathlib
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parent
for folder in ('blend','fbx','previews'): (ROOT/folder).mkdir(exist_ok=True)
MANIFEST=[]

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
        mod=o.modifiers.new('Edge rounding','BEVEL'); mod.width=bevel; mod.segments=2
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
    bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR'); return o

def pine(i):
    rng=random.Random(100+i); h=[8,10,7,11][i]; cone('Trunk',(0,0,h*.4),.30,.14,h*.8,bark,8)
    for j in range(4+i%2):
        z=1.8+j*(h-2)/4; r=(h-z)*.37
        o=cone('Needles',(.15*math.sin(j+i),.12*math.cos(j),z+1),r,.04,2.7,leaves[j%3],10)
        o.rotation_euler[2]=rng.random()

def leafy(i):
    h=[6,7.2,5.5][i]; rod('Trunk',(0,0,0),(.2,0,h*.7),.32,bark)
    rng=random.Random(300+i)
    for j in range(6):
        a=j*math.tau/6; x,y=math.cos(a)*(1.1+i*.15),math.sin(a)*1.1; z=h*.65+rng.uniform(-.6,1)
        rod('Branch',(.1,0,h*.4),(x,y,z),.12,bark)
        ico('Canopy',(x,y,z),(1.6,1.45,1.6),leaves[j%3],2)
    ico('Crown',(0,0,h),(1.7,1.7,1.4),leaves[1],2)

def rock(i):
    o=ico('Rock',(0,0,1),(2+i*.25,1.4+i*.1,1.35),stone,2)
    rng=random.Random(500+i)
    for v in o.data.vertices:
        v.co*=rng.uniform(.82,1.15)
        if v.co.z < -.75:v.co.z=-1
    # Whole mesh stands on z=0; retain bottom-centre origin.
    low=min(v.co.z for v in o.data.vertices)
    for v in o.data.vertices:v.co.z-=low
    o.location=(0,0,0)

def distant(i):
    cone('Trunk',(0,0,2),.2,.12,4,bark,6)
    if i==0:cone('Crown',(0,0,4.8),2,.02,5,leaves[0],8)
    else:ico('Crown',(0,0,4.6),(2.2,1.8,2.8),leaves[1],1)

def wheel(name,x,y,r,width):
    parts=[]
    o=cone('Tyre',(x,y,r),r,r,width,rubber,24); o.rotation_euler[1]=math.pi/2; parts.append(o)
    for side in (-1,1):
        xx=x+side*(width/2+.015)
        o=cone('Rim',(xx,y,r),r*.62,r*.62,.06,chrome,16);o.rotation_euler[1]=math.pi/2;parts.append(o)
        o=cone('Hub',(xx+side*.035,y,r),r*.20,r*.20,.10,dark,12);o.rotation_euler[1]=math.pi/2;parts.append(o)
        for j in range(6):
            a=j*math.tau/6
            parts.append(rod('Spoke',(xx+side*.04,y+math.cos(a)*r*.2,r+math.sin(a)*r*.2),(xx+side*.04,y+math.cos(a)*r*.56,r+math.sin(a)*r*.56),.045,dark,6))
    return join(parts,name)

def engine(y,z,style):
    box('EngineBlock',(0,y,z),(1.6,1.3,.65),dark)
    for x in (-.65,.65):
        box('ValveCover',(x,y,z+.45),(.42,1.45,.25),chrome)
        for j in range(4):
            rod('Header',(x,y-.45+j*.3,z+.15),(x*1.6,y-.45+j*.3,z-.35),.09,chrome)
    o=box('EngineIntake',(0,y,z+.85),(1.05,1.05,.50),chrome);o['Anim']='engine'
    if style=='v12':
        for x in (-.35,.35):
            for j in range(6):cone('IntakeStack',(x,y-.5+j*.2,z+1.2),.07,.12,.35,chrome,8)['Anim']='engine'
    else:
        box('IntakeMouth',(0,y+.56,z+.85),(.80,.06,.25),dark,0)
        for x in (-.28,0,.28):cone('IntakeThrottle',(x,y,z+1.16),.11,.11,.14,dark,8)['Anim']='engine'

def car(style):
    # Front is Blender +Y, exported Roblox -Z. Four distinct silhouette families.
    truck=style=='dunehauler'; drag=style=='dragster'; mid=style=='v12'; hot=style=='blowerrod'
    paint.diffuse_color=(*{'thunder':(.48,.025,.035),'v12':(.025,.16,.45),'blowerrod':(.7,.16,.025),'dragster':(.32,.04,.42),'dunehauler':(.08,.34,.20)}[style],1)
    paint.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=paint.diffuse_color
    box('Chassis',(0,0,.75),(3.45,9.2,.35),dark)
    # Cockpit at middle: a clear 2.0-wide, 2.4-long opening.
    for x in (-1.65,1.65):box('PaintSidePod',(x,0,1.35),(.70,6.9,.85 if not truck else 1.3),paint,.16)
    nose_width=2 if drag or hot else 3.5
    box('PaintNose',(0,2.95,1.3),(nose_width,2.9,.8),paint,.18)
    box('AccentSplitter',(0,4.35,.7),(3.9,.30,.16),accent,.04)
    box('PaintRearDeck',(0,-3.15,1.35),(3.4,2.25,.7),paint,.15)
    box('Seat',(0,-.1,1.08),(1.55,1.65,.25),rubber)
    box('SeatBack',(0,-1,1.7),(1.6,.25,1.4),rubber,.1)
    rod('SteeringColumn',(0,.8,1.1),(0,.65,1.9),.09,dark)
    bpy.ops.mesh.primitive_torus_add(major_radius=.43,minor_radius=.06,major_segments=16,minor_segments=6,location=(0,.65,1.9),rotation=(math.pi/3,0,0));finish(bpy.context.object,'SteeringWheel',rubber)
    engine(-2.7 if mid or drag else 2.45,1.85,style)
    for x in (-1.9,1.9):
        rod('Exhaust',(x,-3.9,.95),(x,-1.4,.95),.15,chrome,12)
        for y in (-2.75,2.75):
            if not hot and not drag:box('PaintFender',(x,y,2.15),(.5,1.95,.20),paint,.1)
    for name,x,y in [('WheelFL',-1.9,2.75),('WheelFR',1.9,2.75),('WheelRL',-1.9,-2.75),('WheelRR',1.9,-2.75)]:
        wheel(name,x,y,1.12 if truck or (name.startswith('WheelR') and (drag or hot)) else .95,.95)
    for x in (-1.25,1.25):
        box('Headlamp',(x,4.42,1.5),(.5,.07,.23),chrome,.04)
        box('TailLamp',(x,-4.3,1.4),(.45,.07,.20),accent,.025)
    if truck:
        for x in (-1.5,1.5):
            rod('Cage',(x,-1.5,1.6),(x,-1.5,3.7),.10,dark)
            rod('Cage',(x,-1.5,3.7),(x,1.35,3.25),.10,dark)
        rod('CageCross',(-1.5,-1.5,3.7),(1.5,-1.5,3.7),.10,dark)
        for j in range(5):box('RoofLamp',(-1+j*.5,-1.5,3.9),(.3,.24,.3),chrome)
    elif drag or mid:
        for x in (-1.25,1.25):box('WingSupport',(x,-3.7,2.1),(.12,.20,1.1),dark,.025)
        box('AccentWing',(0,-3.7,2.7),(4.2,.8,.15),accent,.06)
    for x in (-.48,.48):box('AccentNoseStripe',(x,3.3,1.715),(.14,2,.025),accent,0)

def save_asset(name,folder,limit,iscar=False):
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    if not iscar:meshes=[join(meshes,name)]
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
    scene=bpy.context.scene; scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False
    scene.render.resolution_x=768;scene.render.resolution_y=768;scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.18,.21,.26,1)
    centre=(low+high)/2; extent=max(high-low)
    box('RenderGround',(0,0,-.07),(extent*5,extent*5,.12),material('Ground',(.12,.15,.18)),0)
    bpy.ops.object.camera_add(location=centre+Vector((extent*1.05,extent*1.45,extent*.95)))
    cam=bpy.context.object;cam.rotation_euler=(centre-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=extent*1.38;scene.camera=cam
    for loc,power,size in [(Vector((extent,extent,extent*1.6)),2200,extent), (Vector((-extent,0,extent)),1500,extent*.8)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(centre-o.location).to_track_quat('-Z','Y').to_euler()
    scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=92;scene.render.filepath=str(ROOT/'previews'/f'{name}.jpg');bpy.ops.render.render(write_still=True)
    MANIFEST.append({'name':name,'folder':folder,'triangles':count,'limit':limit,'dimensions_blender':list(high-low),'fbx':f'fbx/{name}.fbx','blend':f'blend/{name}.blend','preview':f'previews/{name}.jpg','engine_parts':[o.name for o in meshes if o.get('Anim')=='engine']})
    print('ASSET',name,count,flush=True)

for i in range(4):reset();pine(i);save_asset(f'pine_{i+1}','Pines',2000)
for i in range(3):reset();leafy(i);save_asset(f'leafy_{i+1}','Trees',2000)
for i in range(4):reset();rock(i);save_asset(f'rock_{i+1}','Rocks',1000)
for i in range(2):reset();distant(i);save_asset(f'far_tree_{i+1}','FarTrees',300)
for name in ('thunder','v12','blowerrod','dragster','dunehauler'):reset();car(name);save_asset(name,'Bodies',10000,True)
(ROOT/'manifest.json').write_text(json.dumps(MANIFEST,indent=2)+'\n')
