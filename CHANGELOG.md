# Changelog

## [0.5.0] - 2026-07-15

### 初始版本发布
- 基于 wofi 的 Hyprland 快速启动器
- 多组合键分类启动：ALT+C/B/A/D/T/S/E/V/SPACE/R
- 支持 app / url / folder / script 四种项目类型
- 全局搜索（ALT+SPACE）
- 最近使用记录（ALT+R）
- .desktop 文件扫描导入
- Dark Red 主题（#8B0000）
- Hyprland 快捷键配置（冲突键迁移到 SUPER）

## [0.5.1] - 2026-07-15

### Bug Fixes
- **修复 wofi 不显示条目**：`$@` 传多行字符串时换行丢失，改用临时文件
- **修复 `||` 显示**：`|` 做分隔符跟显示内容冲突，改用 tab 分隔

## [0.5.2] - 2026-07-15

### Features
- **添加 GTK 图标**：从 .desktop 文件查找 Icon=，用 `img:/path` 格式显示

### Bug Fixes
- **修复图标显示乱码**：wofi dmenu 需要 `img:/实际文件路径`，不是 `icon:名称`
- **修复引号嵌套错误**：`icon_for()` case 语句引号不匹配导致脚本崩溃

## [0.5.3] - 2026-07-15

### Revert
- **回退图标功能**：图标导致 wofi 不显示条目，回退到纯文本可用版本

## [0.5.4] - 2026-07-15

### Performance
- **移除 gtk-launch**：每次都失败浪费时间，直接用 setsid
- **异步 log_recent**：jq 写最近记录改为后台执行，不阻塞启动

## [0.5.5] - 2026-07-15

### Bug Fixes
- **修复多面板残留**：切换分类时旧面板不关闭
  - 原因：`pkill -f "wofi.*Spark"` 匹配不到（prompt 是分类名不是 Spark）
  - 修复：改为匹配配置路径 `pkill -f "wofi.*spark-linux"`

## [0.5.6] - 2026-07-15

### Bug Fixes
- **修复 fcitx5 候选窗口空白**：wofi 弹出时输入法在中文模式会右侧出现空白窗口
  - 修复：`GTK_IM_MODULE=xim` 禁用 wofi 的输入法支持
- **回滚数字键快速选择**：功能导致面板不显示，暂不实现

## Hyprland 配置变更

### 冲突键迁移（dotfiles-arch 97ea70d）
| 原绑定 | 新绑定 | 功能 |
|--------|--------|------|
| ALT+T | SUPER+T | 终端 |
| ALT+E | SUPER+E | 文件管理器 |
| ALT+SPACE | SUPER+SPACE | 浮动切换 |
| ALT+R | SUPER+R | wofi 菜单 |
| ALT+S | SUPER+S | 特殊工作区 |

### Spark 占用的 ALT 键
| 快捷键 | 功能 |
|--------|------|
| ALT+C | Code 分类 |
| ALT+B | Browser 分类 |
| ALT+A | AI 分类 |
| ALT+D | Document 分类 |
| ALT+T | Tools 分类 |
| ALT+S | Social 分类 |
| ALT+E | Folders 分类 |
| ALT+V | Pin 分类 |
| ALT+SPACE | 全局搜索 |
| ALT+R | 最近使用 |
