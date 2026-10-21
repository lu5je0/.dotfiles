# Dotfiles

个人 dotfiles 仓库，管理 shell、编辑器、终端与自动化环境配置。

## 目录结构
- `vim/`: Neovim 配置（有独立 `AGENTS.md`）
- `zsh/`, `zshrc`, `bashrc`: Shell 配置
- `ime/`: 输入法配置，fcitx5/Squirrel + Rime（有独立 `AGENTS.md`）
- `nix/`: NixOS / nix-darwin 配置与本地包定义（有独立 `AGENTS.md`）
- `scripts/`: 安装与环境初始化脚本（`setup.d/` 有独立 `AGENTS.md`）
- `skills/`: 本地 skills，清单见 `skills/INDEX.md`
- `module/`: 个人工具项目

## 目录协作
- 改子目录内容时，先读该目录下的 `AGENTS.md`（如果存在）。

## 注释与文档
- 注释和 `AGENTS.md` 只记录当前行为、必要的设计原因、仍生效的约束、兼容性与避坑信息。
- 不写与当前实现无关的历史背景、迁移经过、旧实现规模或提交次数、改动复盘及对话残留；历史由 Git 保存。
- 功能调整时同步删改过时说明；废弃代码直接删除，不整块注释保留。

## 提交约定
- 消息写短：默认**单行**，形如 `type(scope): 中文描述`。
- 确实需要解释时正文控制在几行内；不要把逐条改动、排查过程、验证清单都搬进提交消息
  （当前实现需要的设计原因、约束与验证方式写在代码注释或子目录 `AGENTS.md` 中）。
- 提交前先 `git diff --cached --name-only` 核对暂存内容，别把不相关的改动扫进来。
  （本仓库是多工作流共用的，历史上反复出现过误提交。）
