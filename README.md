# KZ AutoJump - CS 1.6 KZ 全自动 DCJ/CJ 插件

**AMX Mod X 服务端插件**，在本地 Listen Server（单机练图）运行，逐帧读取玩家物理状态（速度、旗标、坐标），实现**帧完美**的 DCJ/CJ 自动执行。

## 核心优势（vs AHK）
| 特性 | AHK | KZ AutoJump (AMX) |
|------|-----|-------------------|
| 读取游戏内存 | ❌ | ✅ `pev_velocity`/`pev_flags`/`pev_origin` |
| 帧完美时机 | ❌ 靠 Sleep 估算 | ✅ `Ham_Player_PreThink` 每帧精确控制 |
| 适应变速/高度 | ❌ 固定延迟 | ✅ 实时判断落地/起跳帧 |
| 服务端预测兼容 | ❌ 客户端按键冲突 | ✅ 直接写 `pev_button` |
| 单机/联机通用 | 仅单机 | ✅ Listen Server / 专用服均可 |

## 安装步骤

### 1. 编译
```bash
cd /home/wobe/test/kz_autojump
chmod +x compile.sh
./compile.sh          # 需安装 amxmodx-compiler
# 或指定编译器路径：./compile.sh /path/to/amxxpc
```
产出 `kz_autojump.amxx`。

### 2. 部署到 CS 1.6
```bash
# 假设 CS 安装在 ~/.steam/steam/steamapps/common/Half-Life/cstrike
CS_DIR="$HOME/.steam/steam/steamapps/common/Half-Life/cstrike"

cp kz_autojump.amxx "$CS_DIR/addons/amxmodx/plugins/"
echo "kz_autojump.amxx" >> "$CS_DIR/addons/amxmodx/configs/plugins.ini"
```

### 3. 启动单机练图
1. 启动 CS 1.6 → **New Game** → 选择 KZ 图（如 `kz_climb`）→ **Listen Server** → **Start**
2. 进入游戏后打开控制台（`~` 键）输入：
   ```
   kz_aj_mode 1   # DCJ 模式（按 E 触发一次完整 DCJ）
   kz_aj_mode 2   # CJ 模式（按 E 触发循环 CJ）
   kz_aj_mode 3   # 智能 DCJ（速度>250 且落地自动触发）
   kz_aj_mode 0   # 关闭
   ```

## 控制台指令
| 指令 | 权限 | 说明 |
|------|------|------|
| `kz_aj_mode <0-3>` | 管理员/单机 | 切换模式 |
| `kz_aj_status` | 管理员/单机 | 显示当前模式、速度、标志位 |
| `kz_aj_config` | 管理员/单机 | 显示所有时序参数 |

## 实时调参（无需重编译）
所有时序以 **物理帧** 为单位（1000fps 下 1帧=1ms），通过 cvar 修改即时生效：
```
kz_aj_dcj_strafe 16        # DCJ 侧向持续帧
kz_aj_dcj_counter_delay 1  # DCJ 反向延迟帧
kz_aj_dcj_counter_hold 14  # DCJ 反向持续帧
kz_aj_dcj_jump_delay 2     # DCJ 跳跃延迟帧
kz_aj_dcj_cycle_gap 4      # DCJ 两轮间隙帧

kz_aj_cj_strafe 18         # CJ 侧向持续帧
kz_aj_cj_jump_delay 3      # CJ 跳跃延迟帧
kz_aj_cj_cycle_gap 6       # CJ 循环间隙帧
```

建议调参流程：
```
sv_cheats 1
host_timescale 0.3    # 慢动作观察
developer 1           # 显示 HUD 调试信息（速度/模式/标志位）
```
观察 HUD 中的 `Speed` 与 `OnGround` 变化，微调上述 cvar 直到：
- DCJ：两次反向加速都生效，速度曲线呈锯齿上升
- CJ：每跳速度稳定增益，无卡顿

## 绑定触发键（可选）
默认用 `+use`（E 键）触发。想改键可在 `autoexec.cfg` 加：
```
alias +kz_dcj "kz_aj_mode 1; +use; wait; -use"
alias -kz_dcj "kz_aj_mode 0"
bind "MOUSE3" "+kz_dcj"   # 鼠标中键触发 DCJ
```

## 进阶：作为库被其它插件调用
包含 `kz_autojump.inc` 后可用股票函数：
```pawn
#include <kz_autojump>

public OnPluginStart() {
    KZAJ_SetMode(MODE_DCJ);           // 设置模式
    if (KZAJ_IsActive()) { ... }      // 判断是否运行中
}

// 监听事件
public KZAJ_OnDCJStart(client) { PrintToChat(client, "DCJ 开始"); }
public KZAJ_OnDCJEnd(client, success) { PrintToChat(client, success ? "成功" : "失败"); }
```

## 目录结构
```
/home/wobe/test/kz_autojump/
├── kz_autojump.sma       # 主源码
├── kz_autojump.inc       # API 头文件
├── compile.sh            # 编译脚本
├── kz_autojump.amxx      # 编译产物（运行后生成）
└── README.md             # 本文件
```

## 常见问题
**Q: 编译报错 `fatal error 100: cannot read from file: "fakemeta"`**  
A: 缺少 AMX Mod X 编译器包含目录。确保安装了 `amxmodx-compiler` 或指定正确的 `-i` 路径。

**Q: 进游戏插件不生效**  
A: 检查 `amx_plugins` 列表是否有 `kz_autojump`；确认 `liblist.gam` 的 `gamedll` 指向 `addons/metamod/dlls/metamod.so`（Linux）或 `metamod.dll`（Windows）。

**Q: 想在专用服跑**  
A: 直接把 `.amxx` 放进服务器 `plugins/`，`plugins.ini` 加载即可。注意：服务端插件会影响所有玩家，建议结合权限系统限制使用。

**Q: 物理帧率不是 1000fps**  
A: CS 1.6 默认 `sys_ticrate 1000`。若服务器修改过，时序参数需按比例缩放（如 100fps 下所有帧数 ÷10）。

## 许可
MIT License — 随意修改、分发、商用。