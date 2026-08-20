# 英见 · YingSee GitHub 宣传图 Prompt

推荐尺寸：`1600 × 900 px`，比例 `16:9`。生成时将 `Resources/AppIcon.png` 作为参考图上传，并要求模型保持图标本身不变形。

## 可直接使用的 Prompt

```text
为一款名为“英见 · YingSee”的原生 macOS 菜单栏应用制作一张高级、克制、产品功能清晰的 GitHub README Hero 宣传图，横版 16:9，1600×900，高分辨率，适合深色与浅色 GitHub 页面展示。

产品定位：用户按 Command + Shift + T，系统立刻冻结当前屏幕，鼠标拖拽框选任何英文软件界面、网页、系统弹窗、右键菜单或 hover 提示，应用通过 OCR 识别英文并翻译成简体中文，在原区域附近显示轻量双语浮层。核心卖点是“hover 提示和临时菜单即使在真实应用中消失，也会被保留在冻结截图中供用户框选翻译”。

画面构图：
1. 使用附带的英见 App Icon 作为真实产品图标，放在左上区域，保持原图标的深海军蓝、Apple blue 发光边框、取景框与双气泡元素，不重绘、不变形。
2. 背景是一张干净、真实但无第三方品牌标识的 macOS 桌面软件界面，使用浅灰白窗口、细腻阴影、圆角和顶部菜单栏，画面简洁，不能像网页后台或手机界面。
3. 中央展示一个刚被 hover 唤起的英文提示气泡，气泡内容严格为两行：
   “Rename project”
   “Change the name shown in your workspace”
4. 整个桌面被轻微压暗约 24%，但 hover 气泡被一个清晰的 macOS 蓝色截图选区矩形框住，选区内部保持明亮锐利，四周是冻结状态，表达“Freeze the screen, then select”。
5. 在选区右下方显示一个紧凑的原生 macOS 翻译浮层：顶部中文主译文“重命名项目”，下方灰色英文原文“Rename project”，底部只有朗读、复制、关闭三个简洁 SF Symbols 风格按钮。浮层使用半透明冷灰背景、18px 圆角、自然阴影，不能做成大窗口。
6. 右上或左侧留出充足留白放品牌文案，所有文字必须准确，不得产生乱码。主标题严格为：
   “YingSee”
   副标题严格为：
   “See it. Translate it.”
   再显示一个紧凑快捷键胶囊：“⌘ ⇧ T”
7. 视觉重点依次为：品牌名、被冻结的 hover 提示与选区、中文翻译浮层。让用户不用阅读说明就能理解“快捷键截图框选，原地翻译”。

视觉风格：Apple Human Interface Guidelines 感、原生 macOS 产品截图质感、克制、轻量、可信、隐私友好；以 #0A84FF 电光蓝、#0B1F3A 深海军蓝、冷白和中性灰为主色；细腻玻璃材质只用于浮层，避免大面积毛玻璃；使用真实 UI 比例、精准 1px 描边、自然环境光和柔和阴影；整体像 Apple Design Award 候选应用的发布页头图，而不是泛化 AI 海报。

输出要求：所有核心元素距离画布边缘至少 100px，兼容 GitHub README 缩放；画面锐利，文字可读；不出现人物、手机、键盘、MacBook 外壳、3D 漂浮设备、第三方品牌 Logo、浏览器 Logo、机器人、魔法粒子、AI 大脑、霓虹赛博朋克、紫色渐变背景、夸张光效、水印或多余按钮；不要把产品做成聊天软件，不要加入历史记录、账号、云同步或多语言切换等不存在的功能。
```

## 建议导出

- 文件名：`yingjian-yingsee-hero.png`
- 放置路径：`docs/assets/yingjian-yingsee-hero.png`
- PNG，sRGB，尽量控制在 2 MB 以内
- 生成后检查英文与中文是否准确；若生成模型文字不稳定，先生成无文字版本，再在 Figma 中覆盖标题和界面文案

将图片加入 README 时，可以放在标题区徽章之后：

```html
<p align="center">
  <img src="docs/assets/yingjian-yingsee-hero.png" alt="YingSee screenshot translation workflow">
</p>
```
