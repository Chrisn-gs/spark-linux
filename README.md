# Spark for Linux

> Spark 的 Linux 移植版 — 基于 wofi 的 Hyprland 快速启动器

## 功能

- **多组合键分类启动** — Alt+C(code), Alt+B(browser), Alt+A(AI) 等
- **全局搜索** — Alt+Space 搜索所有类别的所有项目
- **最近使用** — Alt+R 查看启动历史
- **模糊搜索** — 输入关键词快速筛选
- **多种项目类型** — app / url / folder / script
- **自动扫描** — 扫描 .desktop 文件，一键导入已安装应用
- **Dark Red 主题** — 匹配 Hyprland #8B0000 配色

## 依赖

```
sudo pacman -S wofi jq
```

## 安装

```bash
git clone https://github.com/Chrisn-gs/spark-linux.git ~/spark-linux
chmod +x ~/spark-linux/scripts/*.sh
```

## 使用

```bash
# 显示分类列表
~/spark-linux/scripts/spark.sh

# 直接打开某个分类
~/spark-linux/scripts/spark.sh code

# 全局搜索
~/spark-linux/scripts/spark.sh --search

# 最近使用
~/spark-linux/scripts/spark.sh --recent

# 扫描导入已安装应用
~/spark-linux/scripts/spark.sh --scan
```

## 配置 Hyprland 快捷键

```bash
# 复制快捷键配置
cp ~/spark-linux/config/spark-binds.conf ~/.config/hypr/

# 在 hyprland.conf 中添加
source = ~/.config/hypr/spark-binds.conf
```

## 自定义配置

编辑 `config/config.json`：

```json
{
  "id": "my-category",
  "name": "My Category",
  "hotkey": "Alt+M",
  "icon": "",
  "items": [
    { "name": "My App", "type": "app", "command": "my-app" },
    { "name": "My Site", "type": "url", "command": "https://example.com" }
  ]
}
```

### 项目类型

| 类型 | 说明 | 示例 |
|------|------|------|
| `app` | 应用程序 | `firefox`, `code` |
| `url` | 网页链接 | `https://github.com` |
| `folder` | 文件夹 | `/home/chrisn/Downloads` |
| `script` | Shell 脚本 | `kitty -e btop` |

## 目录结构

```
spark-linux/
├── scripts/
│   ├── spark.sh          # 主启动脚本
│   └── scan-apps.sh      # .desktop 扫描导入
├── themes/
│   ├── wofi.conf          # wofi 配置
│   └── wofi.css           # Dark Red 主题样式
├── config/
│   ├── config.json        # 分类与项目配置
│   └── spark-binds.conf   # Hyprland 快捷键片段
└── README.md
```

## 快捷键

| 按键 | 功能 |
|------|------|
| `↑↓` | 上下导航 |
| `Enter` | 启动选中项目 |
| `Esc` | 关闭 |
| `Tab` | 补全 |
| 输入关键词 | 模糊搜索过滤 |

## 许可证

MIT License
