"""Pack existing scene textures without changing geometry or exports."""
import bpy,pathlib
root=pathlib.Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(root/'EmberstoneCitadel.blend'))
for image in bpy.data.images:
    if image.source=='FILE' or image.name.endswith('_color'):image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(root/'EmberstoneCitadel.blend'),compress=True)
