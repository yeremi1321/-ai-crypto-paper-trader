"""Reimport all exported scenery and verify budgets, bounds, and UVs."""
import bpy,json,pathlib
from mathutils import Vector
root=pathlib.Path(__file__).resolve().parent
manifest=json.loads((root/'manifest.json').read_text())
count=0
for row in manifest['meshes']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(root/row['fbx']))
    objects=[o for o in bpy.context.scene.objects if o.type=='MESH'];assert len(objects)==1
    o=objects[0];o.data.calc_loop_triangles();n=len(o.data.loop_triangles)
    assert n==row['triangles'] and n<=9000,(row['name'],n)
    assert o.data.uv_layers, row['name']
    verts=[o.matrix_world @ v.co for v in o.data.vertices]
    low=[min(v[k] for v in verts) for k in range(3)];high=[max(v[k] for v in verts) for k in range(3)]
    centre=[(low[0]+high[0])/2,(low[2]+high[2])/2,-(low[1]+high[1])/2]
    size=[high[0]-low[0],high[2]-low[2],high[1]-low[1]]
    assert max(abs(a-b) for a,b in zip(centre,row['center_roblox']))<.02,(row['name'],'centre')
    assert max(abs(a-b) for a,b in zip(size,row['size_roblox']))<.02,(row['name'],'size')
    count+=n;print('VERIFIED',row['name'],n,flush=True)
assert count==manifest['scenery_triangles']
print('MAP VERIFIED',count,'triangles in',len(manifest['meshes']),'meshes')
