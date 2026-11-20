# 动画素材

仓库内的 `demo.mp4` 是本项目用代码生成的原创几何演示动画，14.2 秒、640×360、H.264，无音轨，按项目 MIT 许可证提供。生成器为 `scripts/make-demo.py`，可选依赖 Python、Pillow 和 ffmpeg。

替换动画：把自己的 H.264/AAC MP4 放在这里，命名为 `intro.mp4`，启动器自动优先使用。支持最长 60 秒、最大 32 MiB 的视频，音量可配置。删除 intro.mp4 后回到演示视频。也可以在 config.local.json 中用 media 指定本目录内的其他文件名。

intro.mp4 被 Git 忽略，不会随代码提交。用户提供的原片、人物和音乐不包含在项目 MIT 授权中。
