"""压缩预设图标并生成应用启动图标。"""
import os
from PIL import Image, ImageDraw

ROOT = r"D:\dev\my_calendar_app"
ICONS = os.path.join(ROOT, "assets", "icons")

# 卡片宽高比 2.2，图片按这个比例预裁，避免运行时再裁掉两边
TARGET_W, TARGET_H = 1200, 545

total_before = 0
total_after = 0
for name in sorted(os.listdir(ICONS)):
    if not name.endswith(".png"):
        continue
    src = os.path.join(ICONS, name)
    total_before += os.path.getsize(src)
    img = Image.open(src).convert("RGB")
    w, h = img.size
    target_ratio = TARGET_W / TARGET_H
    ratio = w / h
    if ratio > target_ratio:
        new_w = int(h * target_ratio)
        left = (w - new_w) // 2
        img = img.crop((left, 0, left + new_w, h))
    else:
        new_h = int(w / target_ratio)
        top = (h - new_h) // 2
        img = img.crop((0, top, w, top + new_h))
    img = img.resize((TARGET_W, TARGET_H), Image.LANCZOS)
    out = os.path.join(ICONS, name[:-4] + ".webp")
    img.save(out, "WEBP", quality=82, method=6)
    total_after += os.path.getsize(out)
    print(f"{name:18} -> {name[:-4]}.webp  {os.path.getsize(out)/1024:7.1f} KB")
    os.remove(src)

print(f"\n预设图标：{total_before/1024/1024:.1f} MB -> {total_after/1024/1024:.2f} MB")


def teal_gradient(size, top=(38, 166, 154), bottom=(0, 105, 92)):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=color)
    return img


S = 1024
icon = teal_gradient(S)
d = ImageDraw.Draw(icon)

# 日历主体
d.rounded_rectangle([196, 250, 828, 812], radius=72, fill=(255, 255, 255))
# 顶部色条
d.rounded_rectangle([196, 250, 828, 412], radius=72, fill=(0, 137, 123))
d.rectangle([196, 340, 828, 412], fill=(0, 137, 123))
# 两个装订环
for cx in (356, 668):
    d.rounded_rectangle([cx - 34, 196, cx + 34, 300], radius=34, fill=(0, 105, 92))
# 打勾
d.line([(372, 596), (486, 712), (700, 452)], fill=(0, 150, 136), width=64, joint="curve")
for p in ((372, 596), (486, 712), (700, 452)):
    d.ellipse([p[0] - 32, p[1] - 32, p[0] + 32, p[1] + 32], fill=(0, 150, 136))

icon = icon.resize((512, 512), Image.LANCZOS)
icon.save(os.path.join(ROOT, "assets", "app_icon.png"), "PNG", optimize=True)
print("app_icon.png 512x512 已生成")

for density, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    out = os.path.join(ROOT, "android", "app", "src", "main", "res", f"mipmap-{density}", "ic_launcher.png")
    icon.resize((px, px), Image.LANCZOS).save(out, "PNG", optimize=True)
    print(f"mipmap-{density}/ic_launcher.png {px}x{px}")
