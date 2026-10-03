"""Optional contact sheets: python art/make_review.py (requires Pillow)."""
import json,pathlib,math
from PIL import Image, ImageDraw, ImageFont
root=pathlib.Path(__file__).resolve().parent
rows=json.loads((root/'manifest.json').read_text())
try:font=ImageFont.truetype('DejaVuSans.ttf',20)
except OSError:font=ImageFont.load_default()
for name,items,cols in [('nature_review',[r for r in rows if r['folder']!='Bodies'],4),('cars_review',[r for r in rows if r['folder']=='Bodies'],3)]:
    w,h=360,410
    sheet=Image.new('RGB',(cols*w,math.ceil(len(items)/cols)*h),(30,36,44));d=ImageDraw.Draw(sheet)
    for i,row in enumerate(items):
        x,y=(i%cols)*w,(i//cols)*h
        img=Image.open(root/row['preview']);img.thumbnail((w-12,w-12));sheet.paste(img,(x+6,y+6))
        d.text((x+12,y+360),row['name'],font=font,fill='white')
        d.text((x+12,y+385),f"{row['triangles']:,} triangles",font=font,fill=(180,195,205))
    sheet.save(root/'previews'/f'{name}.jpg',quality=94)
print('Review sheets written')
