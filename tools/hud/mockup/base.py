# Makes shots/wyv_base.png and shots/grf_base.png: the raw in-game screenshots with the old
# HUD strokes inpainted away inside the listed boxes (boxes match the original screenshots).
import os, cv2, numpy as np
from PIL import Image
from kit import SHOTS
def clean(src, size, boxes, out):
    im = Image.open(os.path.join(SHOTS, src)).convert("RGB").resize(size, Image.LANCZOS)
    a = cv2.cvtColor(np.array(im), cv2.COLOR_RGB2BGR)
    m = np.zeros(a.shape[:2], np.uint8)
    for (x0,y0,x1,y1) in boxes:
        m[y0:y1, x0:x1] = 255
    # only inpaint HUD-coloured strokes inside boxes (bright/saturated thin lines), widen a little
    hsv = cv2.cvtColor(a, cv2.COLOR_BGR2HSV)
    bright = ((hsv[...,2] > 150) & ((hsv[...,1] > 90) | (hsv[...,1] < 40))).astype(np.uint8)*255
    mm = cv2.bitwise_and(m, bright)
    mm = cv2.dilate(mm, np.ones((5,5),np.uint8), iterations=2)
    r = cv2.inpaint(a, mm, 5, cv2.INPAINT_TELEA)
    Image.fromarray(cv2.cvtColor(r, cv2.COLOR_BGR2RGB)).save(os.path.join(SHOTS, out))
# Wyvern (scout)
clean("wyv_raw.png", (2000,838), [
 (318,38,548,92),(950,48,1052,88),(1543,38,1690,92),(608,395,720,445),(955,378,1045,478),
 (893,485,1108,550),(1283,395,1398,450),(315,692,602,780),(1590,652,1690,812)], "wyv_base.png")
# Griffin (assault)
clean("grf_raw.png", (2000,809), [
 (322,38,548,95),(875,48,1135,98),(1548,38,1695,92),(920,170,1260,250),(610,395,722,445),
 (958,380,1050,485),(1287,395,1398,450),(318,688,602,780),(1572,652,1695,812)], "grf_base.png")
