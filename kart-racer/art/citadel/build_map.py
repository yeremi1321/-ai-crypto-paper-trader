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
        if j:rod('MainCable',cable[-2],cable[-1],.75,metal)
    for i in (start,end):
        p=point(i,side*(HALF+10));box('BridgePylon',(p.x,p.y,(p.z+30)/2),(8,8,p.z+66),stone,angle(i))
        box('PylonCrown',p+Vector((0,0,48)),(12,12,3),trim)
    for i in range(start,end,3):rod('BridgeRail',point(i,side*(HALF+3),3),point(min(i+3,end),side*(HALF+3),3),1,metal)
for i in range(start,end,3):
    a,b=point(i),point(i+3);rod('DeckGirder',a+Vector((0,0,-3)),b+Vector((0,0,-3)),4,metal,6)
    rod('DeckCrossbeam',point(i,-HALF,-3),point(i,HALF,-3),1.2,metal,6)

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
(ROOT/'manifest.json').write_text(json.dumps({'track_id':'emberfort','road_length':data['length'],'scenery_triangles':sum(r['triangles'] for r in manifest),'meshes':manifest},indent=2)+'\n')
import runpy
runpy.run_path(str(ROOT/'write_import_helper.py'))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'EmberstoneCitadel.blend'),compress=True)

scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False
scene.render.resolution_x=1920;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('VolcanicDusk');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.16,.23,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
bpy.ops.object.light_add(type='SUN',location=(0,0,500));sun=bpy.context.object;sun.rotation_euler=(.45,-.6,-.5);sun.data.energy=3.0;sun.data.angle=.18
# Lava reflection and torch accents are local to landmarks, not a screen-wide glow.
for i in (int(N*.055),int(N*.29),int(N*.72)):
    p=point(i,HALF+14,14);bpy.ops.object.light_add(type='AREA',location=p);l=bpy.context.object;l.data.energy=14000;l.data.color=(1,.25,.025);l.data.size=25
bpy.ops.object.camera_add();camera=bpy.context.object;scene.camera=camera;camera.data.lens=38;camera.data.clip_end=5000
for name,loc,target in [('overview',(1120,-960,800),(270,65,20)),('starting_gate',(-105,-240,65),(10,150,44)),('bridge',(870,15,160),(560,30,55))]:
    camera.location=loc;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=94;scene.render.filepath=str(ROOT/'previews'/f'{name}.jpg');bpy.ops.render.render(write_still=True)
    print('RENDERED',name,flush=True)
print('MAP COMPLETE',sum(r['triangles'] for r in manifest),len(manifest),'scenery meshes',flush=True)
