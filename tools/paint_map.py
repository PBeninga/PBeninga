"""Authoring aid for data/frontier.txt. The text file is the source of truth
once written; this script records how the layout was blocked out."""
W, H = 72, 64
g = [['.' for _ in range(W)] for _ in range(H)]

def put(x, y, c):
    if 0 <= x < W and 0 <= y < H: g[y][x] = c
def rect(x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1): put(x, y, c)
def frame(x0, y0, x1, y1, c):
    for x in range(x0, x1 + 1): put(x, y0, c); put(x, y1, c)
    for y in range(y0, y1 + 1): put(x0, y, c); put(x1, y, c)
def blob(cx, cy, rx, ry, c, only=None):
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            if ((x - cx) / (rx + .5)) ** 2 + ((y - cy) / (ry + .5)) ** 2 <= 1:
                if only is None or g[y][x] in only: put(x, y, c)
def line(pts, c, w=0):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n); y = round(y0 + (y1 - y0) * i / n)
            rect(x - w, y - w, x + w, y + w, c)
def dots(c, pts):
    for x, y in pts: put(x, y, c)

# Outer cliffs frame the region.
frame(0, 0, W - 1, H - 1, '#'); frame(1, 1, W - 2, H - 2, '#')
for x in range(2, W - 2):
    if (x * 7) % 5 == 0: put(x, 2, '#')
    if (x * 3) % 4 == 0: put(x, H - 3, '#')

# Forest: the whole west half is woodland floor.
blob(15, 26, 14, 24, ',')
blob(10, 10, 9, 8, ',')
blob(14, 50, 12, 10, ',')

# River runs north to south east of the camp.
line([(47, 2), (46, 12), (48, 22), (47, 32), (49, 42), (47, 52), (48, 61)], '~', 1)
rect(45, 30, 50, 31, '=')   # east bridge to the mine
# Mine: rock mass with a carved cave floor.
rect(51, 3, 69, 40, '#')
blob(58, 30, 6, 7, '_', only='#')
blob(60, 18, 6, 6, '_', only='#')
blob(62, 8, 4, 3, '_', only='#')
line([(51, 31), (55, 31)], '_', 1)
line([(58, 24), (59, 22)], '_', 1)
line([(61, 12), (62, 10)], '_', 0)

# A south bridge links the pass to the meadow.
for x in range(44, 54):
    if g[41][x] == '~': put(x, 41, '=')
    if g[42][x] == '~': put(x, 42, '=')
# South-east meadow past the mine.
blob(60, 53, 9, 7, ',')
dots('P', [(55, 50), (60, 56), (64, 48), (57, 58), (66, 55)])
dots('2', [(62, 52)])
dots('r', [(52, 47), (67, 60)])

# Camp: palisade, plank floor, gates on west, east and south.
rect(28, 22, 42, 36, '+')
frame(27, 21, 43, 37, '|')
for gx, gy in [(27, 29), (27, 30), (43, 30), (43, 31), (34, 37), (35, 37), (35, 21)]: put(gx, gy, '+')
# Paths.
line([(35, 20), (35, 12), (30, 6)], ':')
line([(26, 29), (18, 28), (10, 22)], ':')
line([(18, 28), (14, 40), (10, 48)], ':')
line([(44, 30), (45, 30)], ':')
line([(35, 38), (35, 46), (33, 50)], ':')

# Ashen pass south to the Warden's hollow.
blob(34, 47, 7, 4, '%')
line([(35, 38), (35, 44), (34, 50)], ':')
rect(21, 43, 25, 50, '#'); rect(43, 43, 47, 50, '#')
rect(21, 51, 47, 61, '#')
rect(23, 51, 45, 61, '^')
rect(24, 52, 44, 60, 'o')
put(34, 51, 'G')

# Buildings in camp (h = timber hall footprint).
rect(29, 23, 32, 25, 'h')
rect(38, 23, 41, 25, 'h')
rect(29, 33, 31, 35, 'h')
# Stations.
dots('B', [(34, 25)]); dots('A', [(39, 33)]); dots('F', [(36, 33)]); dots('R', [(35, 28)]); dots('H', [(33, 30)])
dots('l', [(30, 28), (40, 28), (30, 31), (40, 31)])
dots('@', [(35, 31)])

# Trees.
dots('P', [(22, 26), (24, 31), (21, 33), (23, 22), (20, 29), (25, 35), (19, 24), (22, 37)])
dots('O', [(12, 32), (15, 36), (10, 38), (13, 42), (16, 44), (9, 34)])
dots('M', [(8, 14), (12, 10), (15, 14), (6, 18), (11, 18)])
dots('I', [(5, 45), (8, 50), (4, 53), (12, 55), (16, 52)])
dots('E', [(4, 5)])
# Rocks.
dots('c', [(53, 30), (54, 33), (56, 27), (55, 35)])
dots('i', [(60, 34), (62, 29), (63, 32), (57, 36)])
dots('d', [(57, 16), (62, 15), (64, 19), (58, 21)])
dots('e', [(61, 7), (63, 8), (60, 9)])
dots('s', [(65, 8)])
# Creatures.
dots('1', [(21, 30), (23, 25), (24, 34)])
dots('2', [(11, 36), (14, 40), (7, 48), (10, 52)])
dots('3', [(57, 29), (61, 32), (59, 26)])
dots('4', [(60, 17), (62, 20), (60, 10)])
dots('5', [(30, 47), (38, 48), (34, 44)])
dots('W', [(33, 55)])
# Decoration: boulders and braziers.
dots('r', [(27, 12), (40, 9), (44, 18), (20, 58), (37, 40), (31, 42), (6, 28), (18, 8)])
dots('b', [(26, 53), (42, 53), (26, 59), (42, 59)])

open('data/frontier.txt', 'w').write('\n'.join(''.join(r) for r in g) + '\n')
print('\n'.join(''.join(r) for r in g))
