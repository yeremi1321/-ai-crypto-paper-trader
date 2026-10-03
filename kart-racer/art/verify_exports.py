"""Run headless AFTER build_assets.py to verify FBX names and triangle counts."""
import bpy,json,pathlib
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parent
for row in json.loads((root/'manifest.json').read_text()):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(root/row['fbx']))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    triangles=0
    for o in meshes:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
    assert triangles==row['triangles'], (row['name'],triangles,row['triangles'])
    if row['folder']=='Bodies':
        for n in ('WheelFL','WheelFR','WheelRL','WheelRR'):assert sum(o.name==n for o in meshes)==1
        assert any(o.name.startswith('Paint') for o in meshes)
        assert any(o.name.startswith('Accent') for o in meshes)
        assert any(o.get('Anim')=='engine' for o in meshes)
    else:
        assert len(meshes)==1
        assert meshes[0].location.length < .001, row['name']
    vertices=[o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    assert abs(min(v.z for v in vertices))<.05, (row['name'],'bottom origin')
    print('VERIFIED',row['name'],triangles,flush=True)
print('All 18 FBX exports verified')
