# Kimpanel 候选面板

- `wechat.css` 控制面板的边框、阴影、间距和选中项配色。候选序号的相对字号由上一级的 `candidate-label.patch` 设置。
- GNOME 51 在分数缩放下使用 `candidateText.js` 按屏幕实际倍率栅格化文字，并将字形对齐到物理像素。弹窗和标签需要允许直接绘制，否则文字会先进入整数倍率的离屏纹理，再被缩放一次。
