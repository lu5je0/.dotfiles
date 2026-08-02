#!/usr/bin/env bash
# 生成候选框背景图 panel.png（9-patch）。
#
# 为什么圆角和边框都得烘进图里：
#   fcitx5 主题没有 BorderRadius；而 BorderWidth/BorderColor 只在背景图缺失时才生效
#   （theme.cpp 的 ThemeImage 构造函数里是 `if (!image_) { ...画边框... }`），
#   配了 Image= 就走不到那个分支。所以两者只能画进 PNG。
#
# 为什么是「两层填充圆角矩形 + 4x 超采样 + Box 缩放」而不是直接 -stroke：
#   -strokewidth 1 描边会被抗锯齿摊到相邻像素上，实测边框只剩 67% 不透明度，发虚；
#   Box 滤镜做整数倍降采样是精确均值，1px 边框能拿到准确颜色和 alpha=1。
#   （Lanczos 会振铃，颜色会偏，别换。）
#
# 改 SIZE/RADIUS 后要同步 theme.conf 的 Background/Margin —— 必须 >= RADIUS，
# 否则 9-patch 的拉伸区会切进圆角，四角变形。
set -euo pipefail

SIZE=32
RADIUS=10
BORDER=1
SS=4 # 超采样倍数

gen() { # <输出路径> <填充色> <边框色>
  local out=$1 fill=$2 border=$3
  local n=$((SIZE * SS)) r=$((RADIUS * SS)) b=$((BORDER * SS))
  magick -size "${n}x${n}" xc:none \
    -fill "$border" -draw "roundrectangle 0,0 $((n - 1)),$((n - 1)) $r,$r" \
    -fill "$fill" -draw "roundrectangle $b,$b $((n - 1 - b)),$((n - 1 - b)) $((r - b)),$((r - b))" \
    -filter Box -resize "${SIZE}x${SIZE}" "$out"
  echo "generated $out"
}

cd "$(dirname "$0")"

# 边框色取自微信输入法面板截图的像素测量：白底 #ffffff 上是 1px #dadada。
# 深色没有官方参照，按同等明度差反推：255-218=37，所以 (37,41,46)+37 = (74,78,83)。
#      输出                    背景色（对应 theme.conf 的 Background/Color）  边框色
gen wechat/panel.png      '#ffffff' '#dadada'
gen wechat-dark/panel.png '#25292e' '#4a4e53'
