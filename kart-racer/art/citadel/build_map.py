"""Original Emberstone map, using exported playable road frames.
Run from kart-racer: lune run art/citadel/export_track
blender --background --python art/citadel/build_map.py
"""
import bpy,json,math,random,pathlib,numpy as np
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parent
for d in ('textures','exports','previews'): (ROOT/d).mkdir(exist_ok=True)
data=json.loads((ROOT/'track.json').read_text());F=data['frames'];N=len(F);HALF=data['width']/2
bpy.ops.wm.read_factory_settings(use_empty=True)
rng=random.Random(907);GROUPS={};ACTIVE='Landscape'

def texture(name,kind):
    # Original tileable 512px mineral grain, seams and roughness; no external files.
    size=512;yy,xx=np.mgrid[:size,:size];random=np.random.default_rng(32)
    grain=random.random((size,size))
    signal=(np.sin(xx*.12)+np.sin(yy*.065)+np.sin((xx+yy)*.023))*.018+grain*.055
    if kind=='stone':
        mortar=((yy%128<5)|((xx+((yy//128)%2)*64)%128<4));base=.32+signal;base[mortar]*=.42
        rgb=np.stack((base*1.04,base,base*.93),axis=-1)
    elif kind=='lava':
        veins=(np.sin(xx*.041+np.sin(yy*.02)*2)+np.sin(yy*.039+np.sin(xx*.03)*2))
        hot=np.clip((veins-.1)*1.4,0,1);rgb=np.stack((.16+.84*hot,.025+.38*hot,.008+.025*hot),axis=-1)
    else:
        base=.17+signal;rgb=np.stack((base*.92,base*.96,base),axis=-1)
    image=bpy.data.images.new(name,width=size,height=size,alpha=True)
    image.pixels.foreach_set(np.concatenate((rgb,np.ones((size,size,1))),axis=-1).astype(np.float32).ravel())
    image.filepath_raw=str(ROOT/'textures'/f'{name}.png');image.file_format='PNG';image.save();return image

def mat(name,color,rough=.8,metal=0,tex=None,emission=0):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    if tex:
        t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=tex;m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
        bump=m.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.22;bump.inputs['Distance'].default_value=.12
        m.node_tree.links.new(t.outputs['Color'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs['Normal'],p.inputs['Normal'])
    if emission:
        p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
        if tex:m.node_tree.links.new(t.outputs['Color'],p.inputs['Emission Color'])
    return m
stone=mat('CitadelStone',(.32,.3,.28),tex=texture('stone_color','stone'))
trim=mat('SandstoneTrim',(.46,.40,.30));basalt=mat('Basalt',(.11,.1,.12),tex=texture('basalt_color','basalt'))
lava=mat('Lava',(.9,.18,.02),tex=texture('lava_color','lava'),emission=2.7)
metal=mat('Iron',(.08,.085,.09),.43,.75);gold=mat('Gold',(.6,.32,.10),.32,.8)
wood=mat('Timber',(.19,.085,.035));fabric=mat('Burgundy',(.28,.035,.045));ash=mat('Ash',(.22,.19,.16))
roadmat=mat('RoadStone',(.22,.21,.20),tex=bpy.data.images['basalt_color']);line=mat('RoadMarking',(.68,.59,.39));flame=mat('Flame',(.95,.32,.035),emission=4)

def add(o,name,m):
    o.name=name;o.data.materials.append(m);GROUPS.setdefault(ACTIVE,[]).append(o)
    return o

def mesh(name,verts,faces,m,uv=True):
    d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);add(o,name,m)
    if uv:
        layer=d.uv_layers.new(name='UVMap')
        for face in d.polygons:
            # Planar projection aligned to each face's dominant axis, in studs.
            axis=max(range(3),key=lambda k:abs(face.normal[k]));axes=[k for k in range(3) if k!=axis]
            for li in face.loop_indices:
                v=d.vertices[d.loops[li].vertex_index].co;layer.data[li].uv=(v[axes[0]]/16,v[axes[1]]/16)
    return o

def box(name,loc,size,m,angle=0,bevel=.20):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size;o.rotation_euler[2]=angle
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('WornEdges','BEVEL');mod.width=bevel;mod.segments=1;bpy.ops.object.modifier_apply(modifier=mod.name)
    return add(o,name,m)

def rod(name,a,b,r,m,segments=8):
    a,b=Vector(a),Vector(b);d=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=r,depth=d.length,location=(a+b)/2)
    o=bpy.context.object;o.rotation_euler=d.to_track_quat('Z','Y').to_euler();return add(o,name,m)

def rock(name,loc,size,m,seed):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1,location=loc);o=bpy.context.object;o.scale=size
    rnd=random.Random(seed)
    for v in o.data.vertices:v.co*=rnd.uniform(.80,1.16)
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for face in o.data.polygons:face.use_smooth=True
    return add(o,name,m)

def point(i,lateral=0,lift=0):
    f=F[i%N];return Vector((f['x']+f['rx']*lateral,-f['z']-f['rz']*lateral,f['y']+lift))

def angle(i):
    a,b=point(i),point(i+1);return math.atan2(b.y-a.y,b.x-a.x)

def ribbon(name,l1,l2,lift,m,start=0,end=N):
    verts=[];faces=[]
    for i in range(start,end+1):verts.extend([point(i,l1,lift),point(i,l2,lift)])
    for i in range(end-start):faces.append((i*2,i*2+1,i*2+3,i*2+2))
    return mesh(name,verts,faces,m)

# Road geometry is for preview only: runtime road physics remain code-generated.
ACTIVE='PreviewRoad'
ribbon('Road',-HALF,HALF,0,roadmat)
for side in (-1,1):
    ribbon('EdgeLine',side*(HALF-2),side*(HALF-2.6),.07,line)
    ribbon('Curb',side*HALF,side*(HALF+3),.35,trim)
    for i in range(0,N,4):
        a,b=point(i,side*(HALF+5),2),point(i+4,side*(HALF+5),2)
        rod('SafetyRail',a,b,1.25,stone,6)
for i in range(0,N,3):
    if i%6==0:ribbon('CentreDash',-.35,.35,.08,line,i,i+1)
for k in range(14):
    box('StartingGrid',(k%7*7-21,0 if k<7 else -7,14.51),(5,5,.12),trim if k%2 else metal,bevel=0)

ACTIVE='Landscape'
box('BasaltBed',(300,50,-18),(1500,1450,20),basalt,bevel=0)
# Lava basin in the infield, kept well away from every road sample.
verts=[(320,80,-1)]+[(320+math.cos(j*math.tau/64)*230,80+math.sin(j*math.tau/64)*310,-1) for j in range(64)]
mesh('LavaLake',verts,[(0,j+1,(j+1)%64+1) for j in range(64)],lava)
for i in range(85):
    theta=i*math.tau/85;x=310+math.cos(theta)*620;y=20+math.sin(theta)*680
    h=rng.uniform(90,245);rock('Cliff',(x,y,h*.18-10),(rng.uniform(55,95),rng.uniform(50,90),h*.70),basalt,i)
for i in range(60):
    index=int(i*N/60);side=(-1 if i%2 else 1);pos=point(index,side*(HALF+70),-18)
    if .44<index/N<.60:continue
    rock('CausewayRock',pos,(42,40,26),basalt,100+i)
# Lava canals are continuous ribbons with thick stone banks outside the track.
for side in (-1,1):ribbon('LavaCanal',side*(HALF+14),side*(HALF+35),-7,lava)

# Chunked scenery meshes: 8 sections, preserving world-space track coordinates.
for sector in range(8):
    ACTIVE=f'Sector{sector+1}'
    for i in range(sector*N//8,(sector+1)*N//8,5):
        if .45<i/N<.61:continue
        for side in (-1,1):
            p=point(i,side*(HALF+12),1);a=angle(i)
            box('StoneParapet',p+Vector((0,0,1)),(25,5,4),stone,a)
            box('WallCap',p+Vector((0,0,3.4)),(25.6,5.7,.85),trim,a)
            for j in (-1,1):
                off=Vector((math.cos(a)*j*7,math.sin(a)*j*7,5.2));box('Crenel',p+off,(4,5,3),stone,a)
            if i%10==0:
                rod('TorchStem',p+Vector((0,0,4)),p+Vector((0,0,9)),.4,metal)
                rock('Flame',p+Vector((0,0,10)),(.7,.7,1.6),flame,10+i)
    # Cylindrical gate towers with genuinely curved stone arch openings.
    index=int([.055,.29,.72,.90][sector//2]*N)
    if sector%2==0:
        p=point(index);a=angle(index);right=Vector((F[index]['rx'],-F[index]['rz'],0));forward=Vector((math.cos(a),math.sin(a),0))
        for side in (-1,1):
            centre=p+right*side*(HALF+17)
            rod('GateTower',centre+Vector((0,0,-7)),centre+Vector((0,0,62)),13,stone,20)
            rod('TowerCornice',centre+Vector((0,0,56)),centre+Vector((0,0,60)),15,trim,20)
            for j in range(10):
                theta=j*math.tau/10;loc=centre+Vector((math.cos(theta)*12,math.sin(theta)*12,63));box('Battlement',loc,(4.4,4.4,5),stone,theta)
            for z in (15,30,45):
                box('ArrowSlit',centre-forward*13+Vector((0,0,z)),(.45,3,6),metal,a)
        radius=HALF+5;spring=15
        # Voussoirs form a half-circle with the crown high enough for the camera.
        for j in range(18):
            t1=j*math.pi/18;t2=(j+1)*math.pi/18;verts=[]
            for depth in (-4,4):
                for r,t in [(radius,t1),(radius+5,t1),(radius+5,t2),(radius,t2)]:
                    verts.append(p+right*(r*math.cos(t))+forward*depth+Vector((0,0,spring+r*math.sin(t))))
            mesh('ArchStone',verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],trim)
        for side in (-1,1):
            loc=p+right*side*(radius+2.5)+Vector((0,0,7));box('ArchPier',loc,(8,6,18),stone,a)
        box('GoldCrest',p+Vector((0,0,56))-forward*6,(2,8,9),gold,a)

ACTIVE='Bridge'
start,end=int(N*.45),int(N*.61)
for side in (-1,1):
    # Hangers follow the actual curved/elevated deck; main cable has a sag.
    cable=[]
    for j,i in enumerate(range(start,end+1)):
        t=j/(end-start);height=12+26*(2*t-1)**2
        base=point(i,side*(HALF+5),0);cable.append(base+Vector((0,0,height)))
        if j%2==0:rod('BridgeHanger',base+Vector((0,0,3)),cable[-1],.38,metal)
        if j:rod('MainCable',cable[-2],cable[-1],.75,wood)
    for i in (start,end):
        p=point(i,side*(HALF+10));box('BridgePylon',(p.x,p.y,(p.z+30)/2),(8,8,p.z+66),stone,angle(i))
        box('PylonCrown',p+Vector((0,0,48)),(12,12,3),trim)
    for i in range(start,end,3):rod('BridgeRail',point(i,side*(HALF+3),3),point(min(i+3,end),side*(HALF+3),3),1,wood)
for i in range(start,end,3):
    a,b=point(i),point(i+3);rod('DeckGirder',a+Vector((0,0,-3)),b+Vector((0,0,-3)),4,metal,6)
    rod('DeckCrossbeam',point(i,-HALF,-3),point(i,HALF,-3),1.2,metal,6)

# Natural enclosure: a steep volcanic cliff amphitheatre with jungle on ledges.
ACTIVE='Enclosure'
for i in range(54):
    t=i*math.tau/54;p=Vector((310+math.cos(t)*520,20+math.sin(t)*590,0))
    h=120+35*math.sin(t*3)+rng.uniform(-12,20)
    rock('JungleCliff',p+Vector((0,0,h*.32)),(62,70,h*.72),basalt,1200+i)
    if i%9==0:
        rod('RuinedLookout',p+Vector((0,0,h*.7)),p+Vector((0,0,h*.7+30)),10,stone,12)
        rod('LookoutCornice',p+Vector((0,0,h*.7+27)),p+Vector((0,0,h*.7+31)),12,trim,12)

# Original central volcano, wholly inside the road loop with a glowing crater.
ACTIVE='Volcano'
verts=[];rings=((132,-2),(112,32),(82,96),(48,166),(30,190),(23,183))
for k,(radius,z) in enumerate(rings):
    for j in range(40):
        t=j*math.tau/40;r=radius*(1+.075*math.sin(t*7+k*.3))
        verts.append((320+math.cos(t)*r,80+math.sin(t)*r,z+math.sin(t*5)*3))
faces=[(k*40+j,k*40+(j+1)%40,(k+1)*40+(j+1)%40,(k+1)*40+j) for k in range(len(rings)-1) for j in range(40)]
mesh('VolcanoSlopes',verts,faces,basalt)
crater=[(320,80,179)]+[(320+math.cos(j*math.tau/40)*23,80+math.sin(j*math.tau/40)*23,179) for j in range(40)]
mesh('CraterLava',crater,[(0,j+1,(j+1)%40+1) for j in range(40)],lava)
for theta in (0.4,2.7,4.4):
    verts=[]
    for radius,z in ((25,183),(44,165),(80,95),(112,32),(135,-1)):
        for shift in (-.025,.025):verts.append((320+math.cos(theta+shift)*radius,80+math.sin(theta+shift)*radius,z+.3))
    mesh('LavaFall',verts,[(j*2,j*2+1,j*2+3,j*2+2) for j in range(4)],lava)

# Two roofed galleries. Their inner arch profile is outside the road edges;
# the crown is over 50 studs above the deck for the chase camera.
ACTIVE='Galleries'
for start,end in ((int(N*.12),int(N*.22)),(int(N*.78),int(N*.86))):
    radius=HALF+17;spring=12
    def section(i,r):
        f=F[i];right=Vector((f['rx'],-f['rz'],0));p=point(i)
        return [p+right*(r*math.cos(j*math.pi/16))+Vector((0,0,spring+r*math.sin(j*math.pi/16))) for j in range(17)]
    for i in range(start,end):
        va,vb=section(i,radius),section(i+1,radius)
        mesh('VaultRoof',va+vb,[(j,j+1,j+18,j+17) for j in range(16)],basalt)
        for side in (-1,1):
            a,b=point(i,side*radius),point(i+1,side*radius);d=b-a
            box('GalleryWall',(a+b)/2+Vector((0,0,5)),(d.length+1,5,14),basalt,math.atan2(d.y,d.x))
        if (i-start)%4==0 or i==end-1:
            a=section(i,radius-1);b=section(i,radius+2)
            for j in range(16):
                rod('VaultRib',a[j],a[j+1],1.5,trim,6)
            for side in (-1,1):
                p=point(i,side*(radius-2),6);box('GalleryPillar',p,(5,5,18),trim,angle(i))
                rod('LampBracket',p+Vector((0,0,5)),p+Vector((0,0,10)),.4,metal)
                rod('GalleryFlame',p+Vector((0,0,10)),p+Vector((0,0,12)),.8,flame)

# Roadside workshops, supply piles, banners, braziers and forge machinery.
# All set dressing starts at least 16 studs beyond the driving surface.
ACTIVE='Props'
for i in range(0,N,9):
    if .45<i/N<.61:continue
    side=-1 if (i//9)%2 else 1;p=point(i,side*(HALF+49));a=angle(i)
    box('SupplyCrate',p+Vector((0,0,3)),(6,6,6),wood,a)
    for z in (1,5):box('CrateIronBand',p+Vector((0,0,z)),(6.3,6.3,.45),metal,a,bevel=0)
    box('StackedCrate',p+Vector((2,2,8)),(4,4,4),wood,a+.2)
    rod('Barrel',p+Vector((8,0,0)),p+Vector((8,0,6)),2.4,wood,12)
    for z in (1,5):rod('BarrelHoop',p+Vector((8,0,z)),p+Vector((8,0,z+.4)),2.5,metal,12)
    for j in range(3):rock('Rubble',p+Vector((-7+j*3,5,1)),(2.2,2,1.5),ash,400+i+j)
    if i%18==0:
        rod('BannerPole',p+Vector((-9,0,0)),p+Vector((-9,0,25)),.5,metal)
        box('HangingBanner',p+Vector((-6,0,19)),(6,.4,10),fabric,a,bevel=0)
        box('BannerEmblem',p+Vector((-6,-.3,19)),(2,.3,4),gold,a,bevel=0)
        rod('BrazierBase',p+Vector((12,5,0)),p+Vector((12,5,3)),3,stone)
        rod('BrazierBowl',p+Vector((12,5,3)),p+Vector((12,5,5)),3.8,metal,12)
        rod('BrazierFire',p+Vector((12,5,5)),p+Vector((12,5,7)),2,flame,10)

def clear_of_road(p,margin):
    return min(math.hypot(p.x-f['x'],p.y+f['z']) for f in F)>HALF+margin

# Infield forge district: vertical silhouettes and detailed industrial ruins.
ACTIVE='TempleDistrict'
for k,(x,y) in enumerate(((150,80),(430,220),(350,-140),(200,340))):
    p=Vector((x,y,0))
    if not clear_of_road(p,70):continue
    box('ForgeIsland',p+Vector((0,0,4)),(72,62,12),basalt)
    box('TempleBase',p+Vector((0,0,14)),(58,50,18),stone)
    box('TempleTerrace',p+Vector((0,0,29)),(46,40,12),stone)
    box('TempleHall',p+Vector((0,0,43)),(32,26,18),stone)
    box('TempleCornice',p+Vector((0,0,54)),(36,30,3),trim)
    for dx in (-14,14):
        rod('ForgeChimney',p+Vector((dx,0,40)),p+Vector((dx,0,68+k*4)),4,stone,12)
        rod('ChimneyCrown',p+Vector((dx,0,66+k*4)),p+Vector((dx,0,70+k*4)),6,trim,12)
    for dx in (-12,0,12):
        box('FurnaceOpening',p+Vector((dx,-17.5,22)),(7,1,12),metal,bevel=0)
        box('FurnaceGlow',p+Vector((dx,-18.2,21)),(4,.4,7),flame,bevel=0)
    for step in range(8):box('TempleStair',p+Vector((0,-31-step*2,20-step*2)),(20,3,3),trim)
    for j in range(6):
        pos=p+Vector((-30+j*12,27,10));box('ForgeStock',pos,(7,6,10),wood,.12*j)

# Overhead industrial gantries, well above both drivers and camera.
ACTIVE='Gantries'
for fraction in (.025,.35,.68,.94):
    i=int(N*fraction);p=point(i);a=angle(i)
    for side in (-1,1):rod('GantryColumn',point(i,side*(HALF+20)),point(i,side*(HALF+20),58),2,metal)
    rod('OverheadBeam',point(i,-HALF-20,58),point(i,HALF+20,58),2.3,metal)
    for offset in (-18,0,18):
        rod('HangingChain',point(i,offset,57),point(i,offset,48),.22,metal,6)
        box('SuspendedLantern',point(i,offset,46),(2,2,4),flame,a)

# Dense original tropical vegetation: palms, broadleaf trees, ferns and vines.
ACTIVE='Jungle'
leaf=mat('JungleLeaf',(.055,.19,.065));leaflight=mat('LeafTips',(.17,.30,.075))
def palm(p,height,seed):
    rnd=random.Random(seed);tip=p+Vector((rnd.uniform(-4,4),rnd.uniform(-4,4),height))
    mid=(p+tip)/2+Vector((2,-1,0));rod('PalmTrunk',p,mid,1.3,wood,8);rod('PalmTrunk',mid,tip,.95,wood,8)
    for j in range(8):
        t=j*math.tau/8;v=Vector((math.cos(t),math.sin(t),0));w=Vector((-v.y,v.x,0))
        points=[tip,tip+v*7+w*2+Vector((0,0,2)),tip+v*17+Vector((0,0,-6)),tip+v*7-w*2+Vector((0,0,2))]
        mesh('PalmFrond',points,[(0,1,2),(0,2,3)],leaf if j%2 else leaflight)
def leafy(p,height,seed):
    rod('JungleTrunk',p,p+Vector((0,0,height)),1.8,wood,8)
    for j in range(3):
        t=j*math.tau/3;loc=p+Vector((math.cos(t)*6,math.sin(t)*6,height-2+j))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=loc);o=bpy.context.object;o.scale=(10,9,7)
        for f in o.data.polygons:f.use_smooth=True
        add(o,'JungleCanopy',leaf if j%2 else leaflight)
for i in range(0,N,3):
    if .45<i/N<.61:continue
    for side in (-1,1):
        p=point(i,side*(HALF+rng.uniform(70,100)),-9)
        if not clear_of_road(p,45):continue
        if i%6==0:leafy(p,rng.uniform(22,38),i)
        else:palm(p,rng.uniform(24,40),i)
        # Ferns make the roadside feel dense at driver's-eye height.
        base=point(i,side*(HALF+27),-1)
        for j in range(7):
            t=j*math.tau/7;v=Vector((math.cos(t),math.sin(t),0));w=Vector((-v.y,v.x,0))
            mesh('Fern', [base,base+v*3+w+Vector((0,0,4)),base+v*6+Vector((0,0,1)),base+v*3-w+Vector((0,0,4))],[(0,1,2),(0,2,3)],leaflight)
for i in range(0,54,2):
    t=i*math.tau/54;p=Vector((310+math.cos(t)*510,20+math.sin(t)*575,90+25*math.sin(t*3)))
    palm(p,26,i+900)
# Hanging vines and moss along temple gate towers.
for fraction in (.055,.29,.72,.90):
    i=int(N*fraction)
    for side in (-1,1):
        for j in range(3):
            p=point(i,side*(HALF+17)+j*2,55)
            rod('HangingVine',p,p+Vector((2,-1,-32-j*3)),.3,leaf,6)
            for k in range(6):box('VineLeaf',p+Vector((2,-1,-k*5)),(2,.5,3),leaflight,.5*k,bevel=0)

# World-aligned UVs prevent stretched primitive UVs and missing rock UVs.
for o in bpy.context.scene.objects:
    if o.type!='MESH':continue
    d=o.data;d.update();uv=d.uv_layers.active or d.uv_layers.new(name='UVMap')
    material=o.data.materials[0].name
    for face in d.polygons:
        axis=max(range(3),key=lambda k:abs(face.normal[k]));axes=[k for k in range(3) if k!=axis]
        tile=120 if material=='Lava' else (24 if material=='CitadelStone' else 32)
        for li in face.loop_indices:
            v=o.matrix_world @ d.vertices[d.loops[li].vertex_index].co
            uv.data[li].uv=(v[axes[0]]/tile,v[axes[1]]/tile)

# Export scenery only. Roads/grid are left to Roblox's tested road/race builders.
manifest=[]
for group,objs in list(GROUPS.items()):
    if group=='PreviewRoad':continue
    # Join by material; split landscape into smaller original chunks for import.
    bins={}
    for o in objs:bins.setdefault(o.data.materials[0].name,[]).append(o)
    export_bins=[]
    for material_name,parts in bins.items():
        chunks=[];chunk=[];count=0
        for o in parts:
            o.data.calc_loop_triangles();n=len(o.data.loop_triangles)
            if chunk and count+n>9000:chunks.append(chunk);chunk=[];count=0
            chunk.append(o);count+=n
        if chunk:chunks.append(chunk)
        for j,chunk in enumerate(chunks):export_bins.append((material_name,chunk,j))
    for material_name,parts,batch in export_bins:
        bpy.ops.object.select_all(action='DESELECT')
        for o in parts:o.select_set(True)
        bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();o=parts[0];o.name=f'{group}_{material_name}_{batch+1}'
        bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        o.data.calc_loop_triangles();tri=len(o.data.loop_triangles)
        path=ROOT/'exports'/f'{o.name}.fbx'
        bpy.ops.export_scene.fbx(filepath=str(path),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',bake_space_transform=True,apply_unit_scale=False,bake_anim=False,path_mode='RELATIVE')
        bounds=[o.matrix_world @ Vector(v) for v in o.bound_box]
        low=[min(v[k] for v in bounds) for k in range(3)];high=[max(v[k] for v in bounds) for k in range(3)]
        assert tri<=9000,(o.name,tri)
        manifest.append({'center_roblox':[(low[0]+high[0])/2,(low[2]+high[2])/2,-(low[1]+high[1])/2],'size_roblox':[high[0]-low[0],high[2]-low[2],high[1]-low[1]],'name':o.name,'triangles':tri,'fbx':f'exports/{path.name}','material':material_name})
keep={r['fbx'] for r in manifest}
for path in (ROOT/'exports').glob('*.fbx'):
    if 'exports/'+path.name not in keep:path.unlink()
(ROOT/'manifest.json').write_text(json.dumps({'track_id':'emberfort','road_length':data['length'],'scenery_triangles':sum(r['triangles'] for r in manifest),'meshes':manifest,'lights':[{'position':[F[int(N*f)]['x'],F[int(N*f)]['y']+24,F[int(N*f)]['z']], 'range':45, 'brightness':2} for f in (.13,.16,.19,.21,.79,.82,.85)]},indent=2)+'\n')
import runpy
runpy.run_path(str(ROOT/'write_import_helper.py'))
for image in bpy.data.images:
    if image.source=='FILE' or image.name.endswith('_color'):image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'EmberstoneCitadel.blend'),compress=True)

runpy.run_path(str(ROOT/'render_previews.py'),run_name='__main__')
