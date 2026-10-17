# 第三方素材与品牌

映框与 Nikon、Canon、Sony、FUJIFILM、Leica、Hasselblad、DJI、Insta360 及其他摄影品牌无隶属、赞助或背书关系。品牌名称和商标归各自权利人所有，本项目的 MIT License 不授予商标使用权。

`Assets/BrandSources/` 保存用于识别相机品牌的固定版本 SVG，`Sources/FrameCore/BrandVectors.swift` 是其轮廓转换结果。来源 URL 和转换范围见该目录的 [README](Assets/BrandSources/README.md)、`sources.json` 与 `manifest.json`。官网可访问不代表这些标志采用开源许可，相关品牌标志保留原权利人的权利；修改、再分发或商业使用时应自行核对对应许可与品牌规范。

Nikon、Sony、DJI 的源图形来自采用 CC0-1.0 的 Simple Icons；商标权仍属于相应权利人。其余官方 SVG 未被重新声明为 MIT 或 CC0。未提供矢量素材的品牌使用系统文字。

运行和正常构建仅使用 Apple 系统框架，无第三方运行库。品牌转换脚本可选使用 Python fonttools，开发者需自行安装；该库及其源码未打包进入 App。App 不附带微软雅黑或其他商业字体文件，缺失字体由 macOS 字体回退机制处理。

`Assets/Sample.jpg` 是由 `scripts/GenerateSample.swift` 绘制的原创演示图，不是个人摄影作品，不包含真实拍摄元数据。
