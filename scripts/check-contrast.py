#!/usr/bin/env python3
"""WCAG contrast audit for entry/src/main/ets/common/Theme.ets (AppGallery 上架自检 checks color contrast).

Parses the Palette defaults, darkPalette() overrides and every AccentDef, mirrors applyAccent(), and checks
text tokens (>= 4.5:1) and icon/control tokens (>= 3:1) against the surfaces they are drawn on.
Exit code 1 on any failure. Usage: python3 scripts/check-contrast.py [-v]
"""
# 中文说明：主题颜色对比度（WCAG）自检脚本
#
# 用途：AppGallery 上架审核会检查颜色对比度。本脚本解析 entry/src/main/ets/common/Theme.ets 中的
#   - Palette 类的浅色默认值、darkPalette() 中的深色覆盖值；
#   - 每个 AccentDef 强调色（浅 / 深两套 AccentTone），并模拟 applyAccent() 的赋值逻辑；
#   - 每个 BackdropDef 背景渐变预设；
# 然后检查：文字类颜色对比度 >= 4.5:1，图标 / 控件类颜色 >= 3:1。
# 用法：python3 scripts/check-contrast.py [-v]   （-v 打印全部检查结果，默认只打印失败项）
# 有任何失败时退出码为 1。
# 注意：脚本依赖 Theme.ets 中的书写格式（正则解析），修改主题文件格式时需同步调整这里。
import os
import re
import sys

# 读取主题源码；-v 输出全部检查项
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = open(os.path.join(ROOT, 'entry/src/main/ets/common/Theme.ets'), encoding='utf-8').read()
VERBOSE = '-v' in sys.argv


def rgb(h):
    """十六进制颜色转 (r, g, b) 元组；8 位 #AARRGGBB 时丢弃前两位 alpha。"""
    h = h.lstrip('#')
    if len(h) == 8:
        h = h[2:]
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(h):
    """计算 WCAG 2.x 定义的相对亮度（先做 sRGB 伽马解码，再按 0.2126/0.7152/0.0722 加权）。"""
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def cr(a, b):
    """两种颜色的对比度：(较亮亮度 + 0.05) / (较暗亮度 + 0.05)，范围 1 ~ 21。"""
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def over(fg, alpha, bg):
    """把前景色按 alpha 不透明度叠加到背景色上，返回合成后的不透明颜色（用于半透明 tint / 卡片）。"""
    f, b = rgb(fg), rgb(bg)
    return '#' + ''.join('%02X' % round(b[i] + (f[i] - b[i]) * alpha) for i in range(3))


# 解析浅色 Palette 的默认值：形如  name: string = '#RRGGBB'
block = re.search(r'export class Palette \{(.*?)\n\}', SRC, re.S).group(1)
LIGHT = dict(re.findall(r"(\w+): string = '(#[0-9A-Fa-f]{6,8})'", block))
# 深色色板 = 浅色默认值 + darkPalette() 中 p.xxx = '#RRGGBB' 的覆盖
dblock = re.search(r'export function darkPalette\(\).*?\{(.*?)\n\}', SRC, re.S).group(1)
DARK = dict(LIGHT)
DARK.update(dict(re.findall(r"p\.(\w+) = '(#[0-9A-Fa-f]{6})'", dblock)))
# 解析强调色：key、名称、默认色，以及浅色 / 深色两组 AccentTone(ui, text, fill, on)
H = r"'(#[0-9A-Fa-f]{6})'"
TONE = r"new AccentTone\(%s, %s, %s, %s\)" % (H, H, H, H)
ACC = re.findall(r"new AccentDef\('(\w+)', '([^']+)', %s,\s*%s,\s*%s\)" % (H, TONE, TONE), SRC)
assert ACC, 'no accents parsed'

# 逐个强调色、浅 / 深两种模式检查
fails = 0
checks = 0
for dark in (False, True):
    for a in ACC:
        key = a[0]
        # 元组下标：a[3:7] 为浅色 tone，a[7:11] 为深色 tone；顺序为 ui、text、fill、on
        ui, text, fill, on = a[7:11] if dark else a[3:7]
        p = dict(DARK if dark else LIGHT)
        # 模拟 applyAccent()：把强调色写入色板的 accent / accentUi / primary / onPrimary
        p.update(accent=text, accentUi=ui, primary=fill, onPrimary=on)
        # accentSoft 背景：accentUi 以 12%（深色 22%）叠加在卡片上
        soft = over(ui, 0.22 if dark else 0.12, p['card'])
        surfaces = {'bg': p['bg'], 'card': p['card'], 'chip': p['chip'], 'soft': soft}
        rules = []
        # 文字类颜色在 bg / card / chip 三种表面上都需要 >= 4.5:1
        for t in ('text', 'subtle', 'accent', 'good', 'warn', 'bad', 'info'):
            for s in ('bg', 'card', 'chip'):
                rules.append((t, p[t], s, surfaces[s], 4.5))
        rules.append(('accent', p['accent'], 'soft', soft, 4.5))
        rules.append(('text', p['text'], 'soft', soft, 4.5))
        for s in ('bg', 'card', 'chip'):
            rules.append(('tertiary', p['tertiary'], s, surfaces[s], 4.5))
            rules.append(('disabled', p['disabled'], s, surfaces[s], 3.0))
        rules.append(('codeText', p['codeText'], 'codeBg', p['codeBg'], 4.5))
        rules.append(('onPrimary', p['onPrimary'], 'primary', p['primary'], 4.5))
        # 图标 / 控件颜色（非文字）按 WCAG 1.4.11 只需 >= 3:1
        for s in ('bg', 'card', 'chip'):
            rules.append(('accentUi', p['accentUi'], s, surfaces[s], 3.0))
        # 标签（Tag）：彩色文字画在自身 12% 透明度的底色上（再叠加到卡片）
        # Tag: colored text on its own 12% tint over the card
        for t in ('good', 'warn', 'bad', 'info', 'subtle', 'accent'):
            tint = over(p[t], 0.12, p['card'])
            rules.append(('tag ' + t, p[t], 'tint', tint, 4.5))
        # 逐条计算并统计；默认只打印失败项
        for name, fg, sname, bg, need in rules:
            checks += 1
            v = cr(fg, bg)
            ok = v >= need
            if not ok:
                fails += 1
            if VERBOSE or not ok:
                print('%s %-6s %-5s %-10s on %-6s %5.2f (need %.1f)' % (
                    'OK  ' if ok else 'FAIL', key, 'dark' if dark else 'light', name, sname, v, need))
# 背景预设：文字颜色在每个渐变色阶上、以及叠加在其上的半透明卡片上都要 >= 4.5:1
# Background presets: text tokens on every gradient stop, and on translucent cards composited over it
BD = re.findall(r"new BackdropDef\('(\w+)', '[^']+', \[([^\]]+)\], \[([^\]]+)\]\)", SRC)
assert BD, 'no backdrops parsed'
for dark in (False, True):
    p = DARK if dark else LIGHT
    for key, lt, dk in BD:
        stops = re.findall(r"#[0-9A-Fa-f]{6}", dk if dark else lt)
        for st in stops:
            # 每个色阶检查三种表面：色阶本身、约 88%（深色 86%）不透明的卡片、约 66%（深色 62%）的毛玻璃卡片
            surfaces = {'stop': st,
                        'card88': over(p['card'], 0.86 if dark else 0.88, st),
                        'glass': over(p['card'], 0.62 if dark else 0.66, st)}
            toks = [(t, p[t]) for t in ('text', 'subtle', 'tertiary', 'good', 'warn', 'bad', 'info')]
            # 各强调色的文字色也要检查（a[4] 为浅色 text，a[8] 为深色 text）
            toks += [('accent:' + a[0], a[8] if dark else a[4]) for a in ACC]
            for t, fg in toks:
                for sname, bg in surfaces.items():
                    checks += 1
                    v = cr(fg, bg)
                    ok = v >= 4.5
                    if not ok:
                        fails += 1
                    if VERBOSE or not ok:
                        print('%s bg:%-7s %-5s %-8s on %-6s %5.2f' % ('OK  ' if ok else 'FAIL', key,
                                                                    'dark' if dark else 'light', t, sname, v))
# 汇总输出；有失败则以 1 退出，便于 CI 拦截
print('%d checks, %d failures' % (checks, fails))
sys.exit(1 if fails else 0)
