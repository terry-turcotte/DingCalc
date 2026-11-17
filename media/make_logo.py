# Generates media/logo.svg. The "DING!" lettering is Cinzel Black (SIL Open Font
# License 1.1, https://github.com/NDISCOVER/Cinzel), converted to outlines so the
# SVG needs no font installed.
#
# Usage: pip install fonttools brotli
#        python3 media/make_logo.py path/to/cinzel-latin-900-normal.woff media/logo.svg
# Then render the PNGs (512/256/64) from the SVG with any SVG renderer.
import math, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

font = TTFont(sys.argv[1]); out = sys.argv[2]
gs = font.getGlyphSet(); cmap = font.getBestCmap(); upem = font['head'].unitsPerEm

def text_path(s, size, cx, baseline, tracking=0):
    scale = size / upem
    names = [cmap[ord(c)] for c in s]
    width = sum(gs[n].width for n in names) + tracking * (len(names) - 1)
    x = cx / scale - width / 2
    pen = SVGPathPen(gs)
    for n in names:
        tp = TransformPen(pen, (scale, 0, 0, -scale, x * scale, baseline))
        gs[n].draw(tp)
        x += gs[n].width + tracking
    return pen.getCommands()

W = 512
# light rays behind the medallion
cx, cy = 256, 200
rays = []
for i in range(16):
    a = i * 2 * math.pi / 16
    a1, a2 = a - 0.09, a + 0.09
    R = 300
    rays.append(f"M{cx},{cy} L{cx+R*math.cos(a1):.1f},{cy+R*math.sin(a1):.1f} L{cx+R*math.cos(a2):.1f},{cy+R*math.sin(a2):.1f}Z")

ding = text_path("DING!", 104, 256, 392, tracking=20)

# XP bar
bx, by, bw, bh = 76, 420, 360, 34
fill = 0.82
segs = "".join(f'<line x1="{bx+bw*i/10:.1f}" y1="{by+3}" x2="{bx+bw*i/10:.1f}" y2="{by+bh-3}"/>' for i in range(1, 10))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">
  <defs>
    <radialGradient id="bg" cx="50%" cy="40%" r="70%">
      <stop offset="0" stop-color="#3b1d5c"/>
      <stop offset="0.6" stop-color="#1c0f2e"/>
      <stop offset="1" stop-color="#0b0612"/>
    </radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff2b0"/>
      <stop offset="0.45" stop-color="#f2c94c"/>
      <stop offset="1" stop-color="#a86b12"/>
    </linearGradient>
    <linearGradient id="goldEdge" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#ffe9a0"/>
      <stop offset="0.5" stop-color="#c9932b"/>
      <stop offset="1" stop-color="#7a4b0c"/>
    </linearGradient>
    <radialGradient id="rayFade" cx="{cx}" cy="{cy}" r="260" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffe08a" stop-opacity="0.75"/>
      <stop offset="1" stop-color="#ffe08a" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glow" cx="{cx}" cy="{cy}" r="150" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#ffd76a" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#ffd76a" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="medal" cx="50%" cy="35%" r="65%">
      <stop offset="0" stop-color="#4a2672"/>
      <stop offset="1" stop-color="#170b26"/>
    </radialGradient>
    <linearGradient id="xp" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#d48bff"/>
      <stop offset="0.5" stop-color="#9431e0"/>
      <stop offset="1" stop-color="#5a168f"/>
    </linearGradient>
    <clipPath id="frame"><rect x="8" y="8" width="496" height="496" rx="88"/></clipPath>
  </defs>

  <g clip-path="url(#frame)">
    <rect width="{W}" height="{W}" fill="url(#bg)"/>
    <path d="{' '.join(rays)}" fill="url(#rayFade)"/>
    <circle cx="{cx}" cy="{cy}" r="150" fill="url(#glow)"/>
  </g>
  <rect x="8" y="8" width="496" height="496" rx="88" fill="none" stroke="url(#goldEdge)" stroke-width="10"/>
  <rect x="22" y="22" width="468" height="468" rx="76" fill="none" stroke="#c9932b" stroke-opacity="0.45" stroke-width="2"/>

  <!-- medallion with level-up arrow -->
  <circle cx="{cx}" cy="{cy}" r="104" fill="url(#medal)" stroke="url(#goldEdge)" stroke-width="12"/>
  <circle cx="{cx}" cy="{cy}" r="88" fill="none" stroke="#f2c94c" stroke-opacity="0.5" stroke-width="2"/>
  <path d="M{cx},{cy-70} L{cx+62},{cy-4} L{cx+26},{cy-4} L{cx+26},{cy+62} L{cx-26},{cy+62} L{cx-26},{cy-4} L{cx-62},{cy-4} Z"
        fill="url(#gold)" stroke="#5c3a08" stroke-width="5" stroke-linejoin="round"/>

  <!-- DING! -->
  <path d="{ding}" fill="#1a0d06" transform="translate(0,5)" opacity="0.7"/>
  <path d="{ding}" fill="url(#gold)" stroke="#4a2c06" stroke-width="4" stroke-linejoin="round" paint-order="stroke"/>

  <!-- XP bar -->
  <rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="6" fill="#120a1c"/>
  <rect x="{bx+3}" y="{by+3}" width="{(bw-6)*fill:.1f}" height="{bh-6}" rx="4" fill="url(#xp)"/>
  <rect x="{bx+3}" y="{by+3}" width="{(bw-6)*fill:.1f}" height="{(bh-6)/2:.1f}" rx="4" fill="#ffffff" opacity="0.18"/>
  <g stroke="#120a1c" stroke-opacity="0.7" stroke-width="2">{segs}</g>
  <rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="6" fill="none" stroke="url(#goldEdge)" stroke-width="5"/>
</svg>
'''
open(out, 'w').write(svg)
print("wrote", out)
