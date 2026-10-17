# 经典画框品牌素材

这些标志用于在本地照片底栏中识别相机品牌。品牌名称和商标归各自所有者所有。

原始 SVG 固定保存在当前目录，下载日期为 2026-10-17；`manifest.json` 记录原始文件 SHA256、来源链接及转换后的图层数量。App 直接使用生成的 Core Graphics 路径，无需联网或安装相应字体。

| 标志 | 来源 | 转换说明 |
| --- | --- | --- |
| Nikon | [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/icons/nikon.svg) | 黑色字标，裁去空白视口 |
| Canon | [Canon 官网](https://global.canon/01cmn/img/common/logo.svg) | 保留红色 Canon 字标，不包含网站附带的文字 |
| SONY | [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/icons/sony.svg) | 黑色字标，裁去空白视口 |
| FUJIFILM | [富士官网](https://global.fujifilm.com/themes/custom/fujifilm_com_g2/common/img/fujifilm_corporate_logo.svg) | 保留字标及红色细节，不包含底部口号 |
| Leica | [徕卡官网](https://leica-camera.com/themes/custom/leica_redesign_theme/logo.svg) | 红色圆标和白色文字分别绘制 |
| Hasselblad | [哈苏官网](https://www.hasselblad.com/assets/icons/logo-white.svg) | 将反白字标转换为黑色，保留原始轮廓 |
| DJI | [Simple Icons](https://github.com/simple-icons/simple-icons/blob/develop/icons/dji.svg) | 黑色字标，裁去空白视口 |
| Insta360 | [影石官网](https://wassets.insta360.com/common/739ce316523b43ed953175d4d4f03c64/black-sc.svg) | 黑色品牌标志，保留内镂空轮廓，裁去空白视口 |

Simple Icons 项目以 [CC0-1.0](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md) 发布图形；官网来源的标志保留各品牌自身权利，不将其重新声明为 CC0。LUMIX、OLYMPUS、OM SYSTEM、PENTAX、RICOH 使用系统粗体文字呈现，未伪称为官方矢量标志。

更新素材后可运行 `scripts/generate-brand-marks.py`，需要开发环境安装 Python `fonttools`。转换器保留填充轮廓和分层颜色，并处理 SVG 曲线；生成文件为 `Sources/FrameCore/BrandVectors.swift`。正常构建及 App 运行不需要此 Python 依赖。
