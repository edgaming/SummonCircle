import math, subprocess
CX = CY = 256

def defs(p):
    return f'''<defs>
    <radialGradient id="bg" cx="50%" cy="45%" r="70%">
      <stop offset="0%" stop-color="{p['bg1']}"/><stop offset="60%" stop-color="{p['bg2']}"/><stop offset="100%" stop-color="{p['bg3']}"/>
    </radialGradient>
    <radialGradient id="portal" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#ffffff"/><stop offset="18%" stop-color="{p['light']}"/>
      <stop offset="55%" stop-color="{p['main']}"/><stop offset="100%" stop-color="{p['deep']}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="shard" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{p['shard1']}"/><stop offset="50%" stop-color="{p['shard2']}"/><stop offset="100%" stop-color="{p['shard3']}"/>
    </linearGradient>
    <linearGradient id="hood" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{p['hood1']}"/><stop offset="100%" stop-color="{p['hood2']}"/>
    </linearGradient>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <filter id="glowSmall" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>'''

def frame(p, body):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">{defs(p)}
  <rect width="512" height="512" rx="88" fill="url(#bg)"/>{body}
  <rect x="4" y="4" width="504" height="504" rx="86" fill="none" stroke="{p['border']}" stroke-width="6"/></svg>'''

def shard(angle, r=168, s=46, stroke="#f2e6ff"):
    a = math.radians(angle); x, y = CX + r*math.cos(a), CY + r*math.sin(a)
    return f'''<g transform="translate({x:.1f},{y:.1f}) rotate({angle+90:.1f})">
      <polygon points="0,{-s} {s*0.55:.1f},0 0,{s} {-s*0.55:.1f},0" fill="url(#shard)" stroke="{stroke}" stroke-width="3" filter="url(#glowSmall)"/>
      <polygon points="0,{-s} {s*0.55:.1f},0 0,0" fill="#ffffff" opacity="0.35"/></g>'''

def ticks(color, r1=198, r2=214):
    out = []
    for i in range(36):
        a = math.radians(i*10); big = i % 3 == 0
        a1, a2 = (r1, r2) if big else (r1+4, r2-4)
        out.append(f'<line x1="{CX+a1*math.cos(a):.1f}" y1="{CY+a1*math.sin(a):.1f}" x2="{CX+a2*math.cos(a):.1f}" y2="{CY+a2*math.sin(a):.1f}" stroke="{color}" stroke-width="{4 if big else 2}" stroke-linecap="round" opacity="0.8"/>')
    return "".join(out)

def swirl(color, width=7, scale=0.92, turns=3.0):
    out = []
    for k in range(3):
        pts = []
        for t in range(101):
            th = math.radians(k*120 + t*turns); rr = 8 + t*scale
            pts.append(f'{CX+rr*math.cos(th):.1f},{CY+rr*math.sin(th):.1f}')
        out.append(f'<polyline points="{" ".join(pts)}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" opacity="0.8" filter="url(#glowSmall)"/>')
    return "".join(out)

def ring(p, r=168):
    return (f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="none" stroke="{p["main"]}" stroke-width="16" opacity="0.55" filter="url(#glow)"/>'
            f'<circle cx="{CX}" cy="{CY}" r="{r}" fill="none" stroke="{p["light"]}" stroke-width="5"/>')

ARCANE = dict(bg1="#2e1145", bg2="#150a22", bg3="#07040c", light="#d7b8ff", main="#7a2cf0", deep="#2a0b52",
              shard1="#e2c9ff", shard2="#9a5cff", shard3="#4a1590", hood1="#3a1a5c", hood2="#12081d", border="#5b2f8c", tick="#b48cff", swirl="#e9dcff")
FEL = dict(bg1="#123a14", bg2="#081a0a", bg3="#030803", light="#c6ff9e", main="#3fd61f", deep="#0b3d05",
           shard1="#efe0ff", shard2="#a066ff", shard3="#4a1590", hood1="#1d3a14", hood2="#071007", border="#2f6b1f", tick="#8ef06a", swirl="#eaffd9")

def v1():  # Arcane Portal
    p = ARCANE
    return frame(p, f'<circle cx="{CX}" cy="{CY}" r="150" fill="url(#portal)"/>' + swirl(p["swirl"]) + ring(p) + ticks(p["tick"]) + shard(-90) + shard(30) + shard(150))

def v2():  # Fel Portal (green circle, purple shards)
    p = FEL
    return frame(p, f'<circle cx="{CX}" cy="{CY}" r="150" fill="url(#portal)"/>' + swirl(p["swirl"]) + ring(p) + ticks(p["tick"]) + shard(-90) + shard(30) + shard(150))

def hood(angle, r=170, s=1.0):
    a = math.radians(angle); x, y = CX + r*math.cos(a), CY + r*math.sin(a)
    rot = 0  # figures stand upright around the circle
    return f'''<g transform="translate({x:.1f},{y:.1f}) rotate({rot:.1f}) scale({s})">
      <path d="M0,-58 C26,-58 40,-26 44,8 C47,30 50,44 56,58 L-56,58 C-50,44 -47,30 -44,8 C-40,-26 -26,-58 0,-58 Z"
            fill="url(#hood)" stroke="#d7b8ff" stroke-width="3" filter="url(#glowSmall)"/>
      <ellipse cx="0" cy="-10" rx="20" ry="25" fill="#05020a"/>
      <circle cx="-8" cy="-12" r="4" fill="#c6ff9e"/><circle cx="8" cy="-12" r="4" fill="#c6ff9e"/></g>'''

def v3():  # Three Hoods around the portal
    p = ARCANE
    return frame(p, f'<circle cx="{CX}" cy="{CY}" r="125" fill="url(#portal)"/>' + swirl(p["swirl"], width=6, scale=0.78)
                 + f'<circle cx="{CX}" cy="{CY}" r="128" fill="none" stroke="{p["light"]}" stroke-width="4" opacity="0.9"/>'
                 + hood(90, r=168, s=0.82) + hood(210, r=172, s=0.82) + hood(330, r=172, s=0.82))

def v4():  # Soul Shard in the circle
    p = ARCANE
    big = '''<g transform="translate(256,262)" filter="url(#glowSmall)">
      <polygon points="0,-150 78,-40 52,120 0,150 -52,120 -78,-40" fill="url(#shard)" stroke="#f2e6ff" stroke-width="5"/>
      <polygon points="0,-150 78,-40 0,-10" fill="#ffffff" opacity="0.30"/>
      <polygon points="0,-150 -78,-40 0,-10" fill="#ffffff" opacity="0.12"/>
      <polygon points="-78,-40 0,-10 -52,120" fill="#000000" opacity="0.15"/>
      <polygon points="78,-40 0,-10 52,120" fill="#000000" opacity="0.28"/>
      <polygon points="-52,120 0,-10 52,120 0,150" fill="#000000" opacity="0.10"/></g>'''
    return frame(p, ring(p, r=200) + ticks(p["tick"], 218, 232) + big
                 + "".join(f'<circle cx="{CX+200*math.cos(math.radians(a)):.1f}" cy="{CY+200*math.sin(math.radians(a)):.1f}" r="14" fill="#efe0ff" filter="url(#glowSmall)"/>' for a in (-90, 30, 150)))

def v5():  # Flat minimal
    p = dict(ARCANE, bg1="#6a2ad6", bg2="#4b1aa6", bg3="#2e0e6e", border="#2e0e6e")
    dots = "".join(f'<circle cx="{CX+160*math.cos(math.radians(a)):.1f}" cy="{CY+160*math.sin(math.radians(a)):.1f}" r="34" fill="#ffffff"/>' for a in (-90, 30, 150))
    arcs = []
    for k in range(3):
        a0 = math.radians(k*120 - 90 + 18); a1 = math.radians(k*120 - 90 + 102)
        arcs.append(f'<path d="M{CX+160*math.cos(a0):.1f},{CY+160*math.sin(a0):.1f} A160,160 0 0,1 {CX+160*math.cos(a1):.1f},{CY+160*math.sin(a1):.1f}" fill="none" stroke="#ffffff" stroke-width="22" stroke-linecap="round"/>')
    spiral = []
    pts = []
    for t in range(0, 181):
        th = math.radians(t*3.2 - 90); rr = 6 + t*0.48
        pts.append(f'{CX+rr*math.cos(th):.1f},{CY+rr*math.sin(th):.1f}')
    spiral = f'<polyline points="{" ".join(pts)}" fill="none" stroke="#ffffff" stroke-width="20" stroke-linecap="round" opacity="0.95"/>'
    return frame(p, "".join(arcs) + dots + spiral)

VARIANTS = [("1-arcane-portal", "1. Arcane Portal", v1), ("2-fel-portal", "2. Fel Portal", v2),
            ("3-three-hoods", "3. Three Hoods", v3), ("4-soul-shard", "4. Soul Shard", v4), ("5-flat", "5. Flat Minimal", v5)]
for slug, _, fn in VARIANTS:
    open(f"{slug}.svg", "w").write(fn())
    for size in (512, 64, 32):
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), f"{slug}.svg", "-o", f"{slug}-{size}.png"], check=True)

# Contact sheet: each design big, plus 64px and 32px (in-game sizes) beside it.
from PIL import Image, ImageDraw, ImageFont
font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
try:
    font = ImageFont.truetype(font_path, 26); small = ImageFont.truetype(font_path.replace("-Bold", ""), 16)
except OSError:
    font = small = ImageFont.load_default()
cell_w, cell_h = 360, 400
sheet = Image.new("RGB", (cell_w * len(VARIANTS) + 20, cell_h + 20), "#1c1c22")
d = ImageDraw.Draw(sheet)
for i, (slug, label, _) in enumerate(VARIANTS):
    x0 = 20 + i * cell_w
    big = Image.open(f"{slug}-512.png").convert("RGBA").resize((256, 256), Image.LANCZOS)
    sheet.paste(big, (x0, 60), big)
    d.text((x0, 18), label, fill="#ffffff", font=font)
    s64 = Image.open(f"{slug}-64.png").convert("RGBA"); s32 = Image.open(f"{slug}-32.png").convert("RGBA")
    sheet.paste(s64, (x0 + 270, 60), s64); sheet.paste(s32, (x0 + 286, 140), s32)
    d.text((x0 + 268, 128), "64", fill="#9a9aa6", font=small); d.text((x0 + 268, 176), "32", fill="#9a9aa6", font=small)
    d.text((x0, 330), "in-game list size →", fill="#9a9aa6", font=small)
    s20 = Image.open(f"{slug}-32.png").convert("RGBA").resize((20, 20), Image.LANCZOS)
    sheet.paste(s20, (x0 + 170, 328), s20)
sheet.save("icon-options.png")
print("ok")
