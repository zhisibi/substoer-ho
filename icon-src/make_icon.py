"""MimiSubStore icon (from the MimiSub icon): the 咪咪 orange tabby (from the MimiSSH v2 icon, ">_" removed) peeking over a card with a
striped shop awning over three stacked subscription cards and the word STORE, on the same soft warm near-white background. Writes foreground.png / background.png
(1024 layered), app_icon.png (216), startIcon.png (288), preview_full.png, preview_masked.png."""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
from scipy import ndimage

W = 1024
src = np.array(Image.open('source_mimissh_v2.png').convert('RGB').resize((W, W))).astype(float)
y, x = np.mgrid[0:W, 0:W] / W
t = np.clip((x * 0.5 + y * 0.7) / 1.2, 0, 1)[..., None]
c1 = np.array([255., 251., 245.]); c2 = np.array([252., 239., 225.])
colb = c1 + (c2 - c1) * t
dd = np.sqrt((x - 0.32) ** 2 + (y - 0.25) ** 2)
colb = np.clip(colb + (np.clip(1 - dd / 0.6, 0, 1) ** 2 * 4)[..., None], 0, 255)
Y, X = np.mgrid[0:W, 0:W]

# cat head = pixels that differ clearly from the background, above the old server stack
diff = np.abs(src - colb).max(axis=2)
head = (diff > 40) & (Y < 600) & (X > 250) & (X < 780)
head = ndimage.binary_fill_holes(ndimage.binary_closing(head, iterations=3))
lab, n = ndimage.label(head)
sizes = ndimage.sum(head, lab, range(1, n + 1))
head = lab == (np.argmax(sizes) + 1)

cat = src.copy()
# remove ">_" on the cheek: replace with smoothed surrounding orange
box = (X > 606) & (X < 700) & (Y > 458) & (Y < 532)
L = cat.mean(axis=2)
orange_ok = head & ~box & (cat[..., 0] > 200) & (cat[..., 2] < 140)
w = ndimage.gaussian_filter(orange_ok.astype(float), 22)
sm = np.stack([ndimage.gaussian_filter(cat[..., c] * orange_ok, 22) for c in range(3)], -1) / np.maximum(w, 1e-3)[..., None]
bw = ndimage.gaussian_filter(box.astype(float), 4)[..., None]
cat = cat * (1 - bw) + sm * bw

# alpha with the soft anti-aliased edge
alpha = ndimage.gaussian_filter(head.astype(float), 1.0)
fg = np.zeros((W, W, 4))
fg[..., :3] = cat
fg[..., 3] = alpha * 255
fgimg = Image.fromarray(np.clip(fg, 0, 255).astype('uint8'), 'RGBA')

# ---- tunnel card (drawn at 4x then reduced for smooth edges)
S = 3
F = Image.new('RGBA', (W * S, W * S), (0, 0, 0, 0))
d = ImageDraw.Draw(F)
navy = (33, 28, 72, 255)
def R(v):
    return [int(c * S) for c in v]
ol = 17
CT, CB = 540, 812  # card top / bottom
d.rounded_rectangle(R((300, CT, 724, CB)), radius=46 * S, fill=navy)
F = F.resize((W, W), Image.LANCZOS)
front = np.zeros((W, W, 4))
fy = np.clip((Y - CT) / (CB - CT), 0, 1)[..., None]
top = np.array([246., 244., 255.]); bot = np.array([206., 202., 234.])
front[..., :3] = top + (bot - top) * fy
m = Image.new('L', (W * S, W * S), 0)
ImageDraw.Draw(m).rounded_rectangle(R((300 + ol, CT + ol, 724 - ol, CB - ol)), radius=32 * S, fill=255)
m = m.resize((W, W), Image.LANCZOS)
front[..., 3] = np.array(m)
F.alpha_composite(Image.fromarray(np.clip(front, 0, 255).astype('uint8'), 'RGBA'))

# shop awning (Sub-"Store") over three stacked subscription cards, word "STORE" under them
A = Image.new('RGBA', (W * S, W * S), (0, 0, 0, 0))
da = ImageDraw.Draw(A)
AX0, AX1, AY0, AY1 = 300 + ol, 724 - ol, CT + ol, CT + ol + 64
n = 6
sw = (AX1 - AX0) / n
cols = [(224, 84, 120, 255), (255, 250, 246, 255)]
for i in range(n):
    x0 = AX0 + i * sw
    da.rectangle([x0 * S, AY0 * S, (x0 + sw) * S, AY1 * S], fill=cols[i % 2])
    da.ellipse([x0 * S, (AY1 - sw / 2) * S, (x0 + sw) * S, (AY1 + sw / 2) * S], fill=cols[i % 2])
# clip awning to the card's rounded top
cm = Image.new('L', (W * S, W * S), 0)
ImageDraw.Draw(cm).rounded_rectangle(R((300 + ol, CT + ol, 724 - ol, CB - ol)), radius=32 * S, fill=255)
from PIL import ImageChops
A.putalpha(ImageChops.multiply(A.split()[3], cm))
del cm
da = ImageDraw.Draw(A)
# outline under the scallops
for i in range(n):
    x0 = AX0 + i * sw
    da.arc([x0 * S, (AY1 - sw / 2) * S, (x0 + sw) * S, (AY1 + sw / 2) * S], 0, 180, fill=navy, width=int(7 * S))
# stacked cards
for k, (col, dy) in enumerate([((102, 178, 255, 255), 0), ((76, 199, 106, 255), 1), ((255, 166, 77, 255), 2)]):
    x0, y0 = 404 + dy * 16, 648 + dy * 24
    da.rounded_rectangle([x0 * S, y0 * S, (x0 + 200) * S, (y0 + 44) * S], radius=12 * S, fill=navy)
    da.rounded_rectangle([(x0 + 6) * S, (y0 + 6) * S, (x0 + 194) * S, (y0 + 38) * S], radius=8 * S, fill=col)
    da.ellipse([(x0 + 18) * S, (y0 + 15) * S, (x0 + 32) * S, (y0 + 29) * S], fill=navy)
    da.rounded_rectangle([(x0 + 44) * S, (y0 + 18) * S, (x0 + 150) * S, (y0 + 26) * S], radius=4 * S, fill=(255, 255, 255, 230))
from PIL import ImageFont
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 46 * S)
word = 'STORE'; track = 8 * S
widths = [da.textlength(ch, font=font) for ch in word]
total = sum(widths) + track * (len(word) - 1)
tx = 512 * S - total / 2; ty = 790 * S
for ch, wch in zip(word, widths):
    da.text((tx, ty), ch, font=font, fill=navy, anchor='ls')
    tx += wch + track
A = A.resize((W, W), Image.LANCZOS)
F.alpha_composite(A)

comp = Image.new('RGBA', (W, W), (0, 0, 0, 0))
comp.alpha_composite(fgimg)
comp.alpha_composite(F)
# shift the group so it is centred (cat top ~210, folder bottom 812 -> centre at 511)
bb = comp.getbbox()
cy = (bb[1] + bb[3]) / 2
comp2 = Image.new('RGBA', (W, W), (0, 0, 0, 0))
comp2.alpha_composite(comp, (0, int(round(W / 2 - cy))))
comp = comp2
al = comp.split()[3]
sh_a = al.point(lambda v: int(v * 0.22)).filter(ImageFilter.GaussianBlur(20))
shadow = Image.new('RGBA', (W, W), (120, 70, 40, 0)); shadow.putalpha(sh_a)
fgf = Image.new('RGBA', (W, W), (0, 0, 0, 0)); fgf.alpha_composite(shadow, (0, 16)); fgf.alpha_composite(comp)
fgf.save('foreground.png')
bg = Image.fromarray(colb.astype('uint8'), 'RGB').convert('RGBA'); bg.save('background.png')
full = bg.copy(); full.alpha_composite(fgf); full.convert('RGB').save('preview_full.png')
mask = Image.new('L', (W, W), 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, W - 1), radius=230, fill=255)
p = Image.new('RGBA', (W, W), (0, 0, 0, 0)); p.paste(full, (0, 0), mask); p.save('preview_masked.png')
full.convert('RGB').resize((216, 216), Image.LANCZOS).save('app_icon.png')
p.resize((288, 288), Image.LANCZOS).save('startIcon.png')
print('ok', bb)
