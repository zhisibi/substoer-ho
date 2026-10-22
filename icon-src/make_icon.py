"""SubStore HO icon: three stacked white subscription cards with a down arrow on Sub-Store's blue gradient
(#478EF2 -> #496AF2, the web UI's primary colors). Writes foreground.png / background.png (1024 layered),
app_icon.png (216), startIcon.png (288) and preview.png."""
from PIL import Image, ImageDraw

W, S = 1024, 4
c1 = (0x5B, 0xA0, 0xF6); c2 = (0x45, 0x5F, 0xE8)
g = Image.new('L', (256, 256))
g.putdata([min(255, int((x * 0.4 + y * 0.8) / 1.2)) for y in range(256) for x in range(256)])
g = g.resize((W, W), Image.BICUBIC)
bgimg = Image.merge('RGB', [g.point(lambda v, i=i: int(c1[i] + (c2[i] - c1[i]) * v / 255)) for i in range(3)]).convert('RGBA')

F = Image.new('RGBA', (W * S, W * S), (0, 0, 0, 0))
d = ImageDraw.Draw(F)
def R(*v):
    return [int(c * S) for c in v]
# three stacked cards (back ones lighter), each with a dot and a line
cards = [(352, 280, 0.55), (332, 360, 0.78), (312, 440, 1.0)]
for i, (x0, y0, a) in enumerate(cards):
    w = 400 - (len(cards) - 1 - i) * 0
    col = (255, 255, 255, int(255 * a))
    d.rounded_rectangle(R(x0, y0, x0 + 360, y0 + 120), radius=34 * S, fill=col)
    d.ellipse(R(x0 + 36, y0 + 42, x0 + 72, y0 + 78), fill=(0x47, 0x8E, 0xF2, int(255 * a)))
    d.rounded_rectangle(R(x0 + 100, y0 + 48, x0 + 300, y0 + 72), radius=12 * S, fill=(0x9F, 0xB8, 0xF5, int(255 * a)))
# down arrow under the stack (subscription download)
cx = 512
d.rounded_rectangle(R(cx - 22, 590, cx + 22, 680), radius=14 * S, fill=(255, 255, 255, 255))
d.polygon(R(cx - 80, 662, cx + 80, 662, cx, 742), fill=(255, 255, 255, 255))
fg = F.resize((W, W), Image.LANCZOS)
fg.save('foreground.png'); bgimg.save('background.png')
full = bgimg.copy(); full.alpha_composite(fg)
m = Image.new('L', (W, W), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, W, W), radius=230, fill=255)
icon = Image.new('RGBA', (W, W), (0, 0, 0, 0)); icon.paste(full, (0, 0), m)
full.convert('RGB').resize((216, 216), Image.LANCZOS).save('app_icon.png')
icon.resize((288, 288), Image.LANCZOS).save('startIcon.png')
icon.save('preview.png')
