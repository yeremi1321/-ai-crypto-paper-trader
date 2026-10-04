"""Render the saved scene; optionally pass -- starting_gate bridge etc."""
import bpy,json,pathlib,sys,math
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parent
data=json.loads((ROOT/'track.json').read_text());F=data['frames'];N=len(F);HALF=data['width']/2
manifest=json.loads((ROOT/'manifest.json').read_text())['meshes']
requested=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
def point(i,lateral=0,lift=0):
    f=F[i%N];return Vector((f['x']+f['rx']*lateral,-f['z']-f['rz']*lateral,f['y']+lift))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'EmberstoneCitadel.blend'))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False
scene.render.resolution_x=1920;scene.render.resolution_y=1080;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('VolcanicDusk');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.16,.23,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
bpy.ops.object.light_add(type='SUN',location=(0,0,500));sun=bpy.context.object;sun.rotation_euler=(.45,-.6,-.5);sun.data.energy=3.0;sun.data.angle=.18
# Lava reflection and torch accents are local to landmarks, not a screen-wide glow.
for i in (int(N*.055),int(N*.14),int(N*.29),int(N*.72),int(N*.82)):
    p=point(i,HALF+14,14);bpy.ops.object.light_add(type='AREA',location=p);l=bpy.context.object;l.data.energy=14000;l.data.color=(1,.25,.025);l.data.size=25
# Warm tunnel fill matches the optional Studio lamp nodes in the manifest.
for fraction in (.13,.16,.19,.21,.79,.82,.85):
    p=point(int(N*fraction),0,24);bpy.ops.object.light_add(type='AREA',location=p)
    light=bpy.context.object;light.data.energy=45000;light.data.color=(1,.72,.45);light.data.size=32
bpy.ops.object.camera_add();camera=bpy.context.object;scene.camera=camera;camera.data.lens=38;camera.data.clip_end=5000
for name,loc,target in [('overview',(1120,-960,800),(270,65,20)),('starting_gate',tuple(point(2,0,12)),tuple(point(15,0,24))),('bridge',(740,15,125),(560,30,55)),('jungle_gallery',tuple(point(int(N*.11),0,14)),tuple(point(int(N*.15),0,18)))]:
    if requested and name not in requested:continue
    camera.location=loc;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=94;scene.render.filepath=str(ROOT/'previews'/f'{name}.jpg');bpy.ops.render.render(write_still=True)
    print('RENDERED',name,flush=True)
print('MAP COMPLETE',sum(r['triangles'] for r in manifest),len(manifest),'scenery meshes',flush=True)
