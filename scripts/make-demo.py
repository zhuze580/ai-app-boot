"""Optional asset generator: Python + Pillow + ffmpeg. Not needed to run the launcher."""
import math
import random
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
ffmpeg = sys.argv[1] if len(sys.argv) > 1 else 'ffmpeg'
width, height, fps, frames = 640, 360, 30, 426
random.seed(23)
particles = [(random.uniform(0, math.tau), random.uniform(80, 180), random.uniform(.1, 1)) for _ in range(70)]
font = ImageFont.load_default()
process = subprocess.Popen([
    ffmpeg, '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
    '-s', f'{width}x{height}', '-r', str(fps), '-i', '-', '-an',
    '-c:v', 'libx264', '-crf', '21', '-preset', 'fast', '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart', str(root / 'assets' / 'demo.mp4')
], stdin=subprocess.PIPE)
for frame in range(frames):
    t = frame / fps
    image = Image.new('RGB', (width, height), (6, 6, 13))
    draw = ImageDraw.Draw(image)
    fade = min(1, t / 1.2)
    for radius in (57, 72, 90):
        angle = int((t * 28 + radius) % 360)
        draw.arc((320-radius, 158-radius, 320+radius, 158+radius), angle, angle+260,
                 fill=(int(83*fade), int(71*fade), int(155*fade)), width=2)
    for angle, radius, speed in particles:
        a = angle + t * speed * .15
        r = radius * (.85 + .15 * math.sin(t + angle))
        x, y = 320 + math.cos(a)*r, 158 + math.sin(a)*r*.7
        value = int((100+90*math.sin(t*speed+angle)**2)*fade)
        draw.ellipse((x-1, y-1, x+1, y+1), fill=(value, value//2, value))
    draw.text((303, 154), 'AI', fill=(225, 215, 255), font=font)
    draw.text((285, 278), 'AI APP BOOT', fill=(205, 195, 235), font=font)
    draw.text((225, 298), 'CODEX  /  WORKBUDDY', fill=(130, 120, 160), font=font)
    draw.rectangle((140, 326, 500, 328), fill=(29, 25, 45))
    draw.rectangle((140, 326, 140+int(360*frame/(frames-1)), 328), fill=(157, 124, 215))
    process.stdin.write(image.tobytes())
process.stdin.close()
if process.wait() != 0:
    raise SystemExit('ffmpeg failed')
print('Generated assets/demo.mp4: 14.2 seconds, 640x360, original project artwork.')
