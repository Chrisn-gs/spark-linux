-- ═══════════════════════════════════════════════════════
-- Spark for Linux — Hyprland keybindings (Lua)
-- ALT 全部让给 Spark，原功能已迁移到 SUPER
-- Source: require("spark-binds") from hyprland.lua
-- ═══════════════════════════════════════════════════════

local spark = os.getenv("HOME") .. "/spark-linux/scripts/spark.sh"

-- Category launchers (ALT + letter)
hl.bind("ALT + C",     hl.dsp.exec_cmd(spark .. " code"))
hl.bind("ALT + B",     hl.dsp.exec_cmd(spark .. " browser"))
hl.bind("ALT + A",     hl.dsp.exec_cmd(spark .. " ai"))
hl.bind("ALT + D",     hl.dsp.exec_cmd(spark .. " document"))
hl.bind("ALT + T",     hl.dsp.exec_cmd(spark .. " tools"))
hl.bind("ALT + S",     hl.dsp.exec_cmd(spark .. " social"))
hl.bind("ALT + E",     hl.dsp.exec_cmd(spark .. " folders"))
hl.bind("ALT + V",     hl.dsp.exec_cmd(spark .. " pin"))

-- Global search
hl.bind("ALT + SPACE", hl.dsp.exec_cmd(spark .. " --search"))

-- Recent launches
hl.bind("ALT + R",     hl.dsp.exec_cmd(spark .. " --recent"))
