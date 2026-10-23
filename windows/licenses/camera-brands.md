# 摄影品牌素材

摄影品牌名称与商标归各自权利人所有。映框与这些品牌无隶属、赞助或背书关系；项目的 MIT License 不授予商标使用权。

八个矢量标志沿用 macOS 映框中 2026-10-17 固定的 SVG 轮廓，经小程序渲染核心转换为离线 Canvas 路径。Windows 版复用 `src/core/brand-marks.ts` 的固定路径。来源记录见 [camera-brand-sources.json](camera-brand-sources.json)，正常构建和运行不联网获取品牌素材。

| 标志 | 来源 | 转换范围 |
| --- | --- | --- |
| Nikon、SONY、DJI | Simple Icons（CC0-1.0，商标权仍归权利人） | 保留字标，移除空白视口 |
| Canon | Canon 官网 | 保留红色字标，移除网页附带文字 |
| FUJIFILM | 富士官网 | 保留字标与红色细节，移除底部口号 |
| Leica | 徕卡官网 | 保留红色圆标和白色文字的分层 |
| Hasselblad | 哈苏官网 | 将反白字标转换为黑色 |
| Insta360 | 影石官网 | 保留原始镂空轮廓 |

官方 SVG 保留原权利人的权利，未重新声明为 MIT 或 CC0。LUMIX、OLYMPUS、OM SYSTEM、PENTAX、RICOH 使用系统文字，不宣称为官方矢量。Windows 版不附带商业字体文件。

Simple Icons 图形许可：[CC0-1.0](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md)。官网来源链接见随项目保存的来源记录；公开可访问不等同于开放商标授权。

Code 128 编码模式表来自 JsBarcode，许可见 [JsBarcode-MIT.txt](JsBarcode-MIT.txt)。其余复用渲染代码的许可见 [Frame-Studio-MIT.txt](Frame-Studio-MIT.txt)。
