/*
 * KZ AutoJump - CS 1.6 KZ 全自动 DCJ/CJ 插件
 * 编译：amxxpc kz_autojump.sma -o kz_autojump.amxx
 * 安装：放入 cstrike/addons/amxmodx/plugins/，amx_plugins.ini 加入 kz_autojump.amxx
 * 单机用法：New Game -> Listen Server -> 控制台 kz_aj_mode 1 (DCJ) / 2 (CJ) / 3 (智能)
 */

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <engine>

#define PLUGIN_NAME "KZ AutoJump"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR "wobe"

// ================= 模式枚举 =================
#define MODE_OFF      0
#define MODE_DCJ      1
#define MODE_CJ       2
#define MODE_AutoDCJ  3

// ================= 配置常量 =================
#define TASK_THINK      9987
#define TASK_DCJ_SEQ    9988
#define TASK_CJ_SEQ     9989

// DCJ 时序（帧，1000fps 物理帧下 1帧=1ms；实测可微调）
#define DCJ_STRAFE_FRAMES     16   // W+A/D 持续帧数
#define DCJ_COUNTER_DELAY     1    // 反向键延迟帧
#define DCJ_COUNTER_HOLD      14   // 反向键持续帧
#define DCJ_JUMP_DELAY        2    // 跳跃延迟帧
#define DCJ_CYCLE_GAP         4    // 两轮间隙帧

// CJ 时序
#define CJ_STRAFE_FRAMES      18
#define CJ_JUMP_DELAY         3
#define CJ_CYCLE_GAP          6

// 物理常量（CS 1.6 默认）
#define GRAVITY               800.0
#define JUMP_HEIGHT           45.0
#define MAX_SPEED             320.0

// ================= 全局变量 =================
new g_iMode = MODE_OFF;
new g_iDCJStage = 0;        // 0=待机, 1=第一轮侧向, 2=第一轮反向, 3=第一轮跳跃, 4=间隙, 5=第二轮侧向...
new g_iCJStage = 0;         // CJ 阶段
new g_iDCJDirection = 1;    // 1=先左(A), -1=先右(D)
new g_iCJDirection = 1;     // CJ 交替方向
new g_iFrameCounter = 0;
new bool:g_bInDCJ = false;
new bool:g_bInCJ = false;
new Float:g_flLastSpeed = 0.0;
new g_iPlayer = 0;

// 前向句柄
new g_fwdDCJStart, g_fwdDCJEnd, g_fwdCJStart, g_fwdCJEnd;

// 玩家按键状态缓存
new g_iButtons;
new g_iOldButtons;

// ================= 前向声明 =================
public plugin_init();
public plugin_precache();
public client_putinserver(id);
public client_disconnected(id);
public Task_Think();
public Task_DCJ_Sequence();
public Task_CJ_Sequence();
public Cmd_Mode(id);
public Cmd_Status(id);
public Cmd_Config(id);

// ================= 插件入口 =================
public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
    
    // 注册 Ham 钩子
    RegisterHam(Ham_Player_PreThink, "player", "Ham_Player_PreThink");
    RegisterHam(Ham_Player_PostThink, "player", "Ham_Player_PostThink");
    
    // 指令
    register_clcmd("kz_aj_mode", "Cmd_Mode", ADMIN_CVAR, "<0|1|2|3> 0=关闭 1=DCJ 2=CJ 3=智能DCJ");
    register_clcmd("kz_aj_status", "Cmd_Status", ADMIN_CVAR, "显示当前状态");
    register_clcmd("kz_aj_config", "Cmd_Config", ADMIN_CVAR, "调整时序参数");
    
    // CVAR
    register_cvar("kz_aj_version", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
    register_cvar("kz_aj_dcj_strafe", "16", FCVAR_SERVER);
    register_cvar("kz_aj_dcj_counter_delay", "1", FCVAR_SERVER);
    register_cvar("kz_aj_dcj_counter_hold", "14", FCVAR_SERVER);
    register_cvar("kz_aj_dcj_jump_delay", "2", FCVAR_SERVER);
    register_cvar("kz_aj_dcj_cycle_gap", "4", FCVAR_SERVER);
    register_cvar("kz_aj_cj_strafe", "18", FCVAR_SERVER);
    register_cvar("kz_aj_cj_jump_delay", "3", FCVAR_SERVER);
    register_cvar("kz_aj_cj_cycle_gap", "6", FCVAR_SERVER);
}

public plugin_precache() {
    // 无需预缓存资源
}

public client_putinserver(id) {
    if (is_user_hltv(id) || is_user_bot(id)) return;
    g_iPlayer = id;
    // 启动主思考任务（每帧）
    set_task(0.001, "Task_Think", TASK_THINK, _, _, "b");
}

public client_disconnected(id) {
    if (id == g_iPlayer) {
        remove_task(TASK_THINK);
        remove_task(TASK_DCJ_SEQ);
        remove_task(TASK_CJ_SEQ);
        g_iPlayer = 0;
        g_iMode = MODE_OFF;
        g_bInDCJ = g_bInCJ = false;
    }
}

// ================= 主思考循环（每帧） =================
public Task_Think() {
    if (!g_iPlayer || !is_user_alive(g_iPlayer)) return;
    
    // 读取 CVAR 实时生效
    new dcj_strafe = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_strafe"));
    new dcj_counter_delay = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_counter_delay"));
    new dcj_counter_hold = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_counter_hold"));
    new dcj_jump_delay = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_jump_delay"));
    new dcj_cycle_gap = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_cycle_gap"));
    new cj_strafe = get_pcvar_num(get_cvar_pointer("kz_aj_cj_strafe"));
    new cj_jump_delay = get_pcvar_num(get_cvar_pointer("kz_aj_cj_jump_delay"));
    new cj_cycle_gap = get_pcvar_num(get_cvar_pointer("kz_aj_cj_cycle_gap"));
    
    // 读取玩家状态
    new Float:velocity[3];
    pev(g_iPlayer, pev_velocity, velocity);
    new Float:speed = floatsqroot(velocity[0]*velocity[0] + velocity[1]*velocity[1]);
    new flags = pev(g_iPlayer, pev_flags);
    new buttons = pev(g_iPlayer, pev_button);
    new oldbuttons = pev(g_iPlayer, pev_oldbuttons);
    new Float:origin[3];
    pev(g_iPlayer, pev_origin, origin);
    new waterlevel = pev(g_iPlayer, pev_waterlevel);
    
    g_iButtons = buttons;
    g_iOldButtons = oldbuttons;
    g_flLastSpeed = speed;
    
    // 水中/梯子/观察者模式不执行
    if (waterlevel > 1 || (flags & FL_ONGROUND) == 0 && (flags & FL_INWATER)) return;
    
    // 智能模式：根据速度/高度自动切换
    if (g_iMode == MODE_AutoDCJ) {
        // 简单启发式：速度>250 且在地面 -> 启动 DCJ
        if ((flags & FL_ONGROUND) && speed > 250.0 && !g_bInDCJ && !g_bInCJ) {
            StartDCJ();
        }
    }
    
    // 手动模式下的触发检测（可绑定键触发）
    // 这里演示：按 USE 键(E) 触发一次 DCJ/CJ
    if ((buttons & IN_USE) && !(oldbuttons & IN_USE)) {
        if (g_iMode == MODE_DCJ && !g_bInDCJ && !g_bInCJ && (flags & FL_ONGROUND)) {
            StartDCJ();
        } else if (g_iMode == MODE_CJ && !g_bInCJ && !g_bInDCJ && (flags & FL_ONGROUND)) {
            StartCJ();
        }
    }
    
    // 显示调试信息
    if (get_pcvar_num(get_cvar_pointer("developer")) > 0) {
        new mode_str[16];
        switch (g_iMode) {
            case MODE_OFF: mode_str = "OFF";
            case MODE_DCJ: mode_str = "DCJ";
            case MODE_CJ: mode_str = "CJ";
            case MODE_AutoDCJ: mode_str = "AUTO";
        }
        set_hudmessage(0, 255, 100, 0.02, 0.85, 0, 0.01, 0.1, 0.01, 0.01, -1);
        show_hudmessage(g_iPlayer, "KZ AutoJump: %s | Speed: %.1f | OnGround: %s | Flags: %d", mode_str, speed, (flags & FL_ONGROUND) ? "YES" : "NO", flags);
    }
}

// ================= DCJ 启动 =================
StartDCJ() {
    if (g_bInDCJ || g_bInCJ) return;
    
    g_bInDCJ = true;
    g_iDCJStage = 1;
    g_iFrameCounter = 0;
    g_iDCJDirection = (random_num(0, 1) == 0) ? 1 : -1; // 随机首向
    
    // 通知前向
    ExecuteForward(g_fwdDCJStart, _, g_iPlayer);
    
    // 启动序列任务（每帧）
    set_task(0.001, "Task_DCJ_Sequence", TASK_DCJ_SEQ, _, _, "b");
    
    client_print(g_iPlayer, print_chat, "[KZ AutoJump] DCJ 已启动 (首向: %s)", g_iDCJDirection == 1 ? "左(A)" : "右(D)");
}

public Task_DCJ_Sequence() {
    if (!g_iPlayer || !is_user_alive(g_iPlayer) || !g_bInDCJ) {
        EndDCJ(false);
        return;
    }
    
    new flags = pev(g_iPlayer, pev_flags);
    new Float:velocity[3];
    pev(g_iPlayer, pev_velocity, velocity);
    new Float:speed = floatsqroot(velocity[0]*velocity[0] + velocity[1]*velocity[1]);
    
    // 读取配置
    new dcj_strafe = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_strafe"));
    new dcj_counter_delay = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_counter_delay"));
    new dcj_counter_hold = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_counter_hold"));
    new dcj_jump_delay = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_jump_delay"));
    new dcj_cycle_gap = get_pcvar_num(get_cvar_pointer("kz_aj_dcj_cycle_gap"));
    
    g_iFrameCounter++;
    
    // 状态机
    switch (g_iDCJStage) {
        case 1: { // 第一轮侧向 (W + A/D)
            SetPlayerButtons(g_iPlayer, IN_FORWARD | (g_iDCJDirection == 1 ? IN_MOVELEFT : IN_MOVERIGHT));
            if (g_iFrameCounter >= dcj_strafe) {
                g_iDCJStage = 2;
                g_iFrameCounter = 0;
            }
        }
        case 2: { // 反向延迟
            SetPlayerButtons(g_iPlayer, IN_FORWARD);
            if (g_iFrameCounter >= dcj_counter_delay) {
                g_iDCJStage = 3;
                g_iFrameCounter = 0;
            }
        }
        case 3: { // 反向键按住
            SetPlayerButtons(g_iPlayer, IN_FORWARD | (g_iDCJDirection == 1 ? IN_MOVERIGHT : IN_MOVELEFT));
            if (g_iFrameCounter >= dcj_counter_hold) {
                g_iDCJStage = 4;
                g_iFrameCounter = 0;
            }
        }
        case 4: { // 跳跃延迟
            SetPlayerButtons(g_iPlayer, IN_FORWARD);
            if (g_iFrameCounter >= dcj_jump_delay) {
                g_iDCJStage = 5;
                g_iFrameCounter = 0;
            }
        }
        case 5: { // 跳跃
            SetPlayerButtons(g_iPlayer, IN_FORWARD | IN_JUMP);
            g_iDCJStage = 6;
            g_iFrameCounter = 0;
        }
        case 6: { // 松开跳跃
            SetPlayerButtons(g_iPlayer, IN_FORWARD);
            g_iDCJStage = 7;
            g_iFrameCounter = 0;
        }
        case 7: { // 循环间隙
            SetPlayerButtons(g_iPlayer, 0);
            if (g_iFrameCounter >= dcj_cycle_gap) {
                // 准备第二轮（反向）
                g_iDCJDirection *= -1;
                g_iDCJStage = 8;
                g_iFrameCounter = 0;
            }
        }
        case 8: { // 第二轮侧向
            SetPlayerButtons(g_iPlayer, IN_FORWARD | (g_iDCJDirection == 1 ? IN_MOVELEFT : IN_MOVERIGHT));
            if (g_iFrameCounter >= dcj_strafe) {
                g_iDCJStage = 9;
                g_iFrameCounter = 0;
            }
        }
        case 9: { // 第二轮反向延迟
            SetPlayerButtons(g_iPlayer, IN_FORWARD);
            if (g_iFrameCounter >= dcj_counter_delay) {
                g_iDCJStage = 10;
                g_iFrameCounter = 0;
            }
        }
        case 10: { // 第二轮反向键
            SetPlayerButtons(g_iPlayer, IN_FORWARD | (g_iDCJDirection == 1 ? IN_MOVERIGHT : IN_MOVELEFT));
            if (g_iFrameCounter >= dcj_counter_hold) {
                g_iDCJStage = 11;
                g_iFrameCounter = 0;
            }
        }
        case 11: { // 第二轮跳跃延迟
            SetPlayerButtons(g_iPlayer, IN_FORWARD);
            if (g_iFrameCounter >= dcj_jump_delay) {
                g_iDCJStage = 12;
                g_iFrameCounter = 0;
            }
        }
        case 12: { // 第二轮跳跃
            SetPlayerButtons(g_iPlayer, IN_FORWARD | IN_JUMP);
            g_iDCJStage = 13;
            g_iFrameCounter = 0;
        }
        case 13: { // 第二轮松开跳跃
            SetPlayerButtons(g_iPlayer, IN_FORWARD);
            g_iDCJStage = 14;
            g_iFrameCounter = 0;
        }
        case 14: { // 结束
            ExecuteForward(g_iPlayer, 0);
            EndDCJ(true);
        }
    }
    
    // 安全检测：如果意外落地且未在跳跃阶段，终止
    if ((flags & FL_ONGROUND) && g_iDCJStage > 5 && g_iDCJStage < 14) {
        EndDCJ(false);
    }
}

EndDCJ(success) {
    if (!g_bInDCJ) return;
    g_bInDCJ = false;
    remove_task(TASK_DCJ_SEQ);
    ExecuteForward(g_iPlayer, 0); // 释放所有键
    ExecuteForward(g_fwdDCJEnd, _, g_iPlayer, success);
    client_print(g_iPlayer, print_chat, "[KZ AutoJump] DCJ %s", success ? "完成" : "中断");
}

// ================= CJ 启动 =================
StartCJ() {
    if (g_bInCJ || g_bInDCJ) return;
    
    g_bInCJ = true;
    g_iCJStage = 1;
    g_iFrameCounter = 0;
    g_iCJDirection = (random_num(0, 1) == 0) ? 1 : -1;
    
    ExecuteForward(g_fwdCJStart, _, g_iPlayer);
    set_task(0.001, "Task_CJ_Sequence", TASK_CJ_SEQ, _, _, "b");
    
    client_print(g_iPlayer, print_chat, "[KZ AutoJump] CJ 已启动 (首向: %s)", g_iCJDirection == 1 ? "左(A)" : "右(D)");
}

public Task_CJ_Sequence() {
    if (!g_iPlayer || !is_user_alive(g_iPlayer) || !g_bInCJ) {
        EndCJ(false);
        return;
    }
    
    new flags = pev(g_iPlayer, pev_flags);
    
    new cj_strafe = get_pcvar_num(get_cvar_pointer("kz_aj_cj_strafe"));
    new cj_jump_delay = get_pcvar_num(get_cvar_pointer("kz_aj_cj_jump_delay"));
    new cj_cycle_gap = get_pcvar_num(get_cvar_pointer("kz_aj_cj_cycle_gap"));
    
    g_iFrameCounter++;
    
    switch (g_iCJStage) {
        case 1: { // 侧向
            ExecuteForward(g_iPlayer, IN_FORWARD | (g_iCJDirection == 1 ? IN_MOVELEFT : IN_MOVERIGHT));
            if (g_iFrameCounter >= cj_strafe) {
                g_iCJStage = 2;
                g_iFrameCounter = 0;
            }
        }
        case 2: { // 跳跃延迟
            ExecuteForward(g_iPlayer, IN_FORWARD);
            if (g_iFrameCounter >= cj_jump_delay) {
                g_iCJStage = 3;
                g_iFrameCounter = 0;
            }
        }
        case 3: { // 跳跃
            ExecuteForward(g_iPlayer, IN_FORWARD | IN_JUMP);
            g_iCJStage = 4;
            g_iFrameCounter = 0;
        }
        case 4: { // 松开跳跃
            ExecuteForward(g_iPlayer, IN_FORWARD);
            g_iCJStage = 5;
            g_iFrameCounter = 0;
        }
        case 5: { // 循环间隙
            ExecuteForward(g_iPlayer, 0);
            if (g_iFrameCounter >= cj_cycle_gap) {
                g_iCJDirection *= -1; // 交替方向
                g_iCJStage = 1;
                g_iFrameCounter = 0;
            }
        }
    }
    
    // 安全检测
    if ((flags & FL_ONGROUND) && g_iCJStage > 3 && g_iCJStage < 5) {
        EndCJ(false);
    }
}

EndCJ(success) {
    if (!g_bInCJ) return;
    g_bInCJ = false;
    remove_task(TASK_CJ_SEQ);
    ExecuteForward(g_iPlayer, 0);
    ExecuteForward(g_fwdCJEnd, _, g_iPlayer, success);
    client_print(g_iPlayer, print_chat, "[KZ AutoJump] CJ %s", success ? "完成" : "中断");
}

// ================= 按键注入辅助 =================
// 直接修改玩家的 pev_button 实现按键注入（服务端预测兼容）
SetPlayerButtons(id, buttons) {
    if (!is_user_alive(id)) return;
    set_pev(id, pev_button, buttons);
}

// ================= 指令处理 =================
public Cmd_Mode(id, level, cid) {
    if (!cmd_access(id, level, cid, 2)) return PLUGIN_HANDLED;
    
    new arg[4];
    read_argv(1, arg, 3);
    new mode = str_to_num(arg);
    
    if (mode < 0 || mode > 3) {
        console_print(id, "[KZ AutoJump] 模式范围 0-3");
        return PLUGIN_HANDLED;
    }
    
    // 停止当前进行的序列
    if (g_bInDCJ) EndDCJ(false);
    if (g_bInCJ) EndCJ(false);
    
    g_iMode = mode;
    
    new mode_str[16];
    switch (mode) {
        case MODE_OFF: mode_str = "关闭";
        case MODE_DCJ: mode_str = "DCJ (按E触发)";
        case MODE_CJ: mode_str = "CJ (按E触发)";
        case MODE_AutoDCJ: mode_str = "智能DCJ (自动检测)";
    }
    
    console_print(id, "[KZ AutoJump] 模式已设为: %s", mode_str);
    if (id != 0) client_print(id, print_chat, "[KZ AutoJump] 模式: %s", mode_str);
    
    return PLUGIN_HANDLED;
}

public Cmd_Status(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    
    new mode_str[16];
    switch (g_iMode) {
        case MODE_OFF: mode_str = "OFF";
        case MODE_DCJ: mode_str = "DCJ";
        case MODE_CJ: mode_str = "CJ";
        case MODE_AutoDCJ: mode_str = "AUTO";
    }
    
    console_print(id, "[KZ AutoJump] 状态: Mode=%s | DCJ=%s | CJ=%s | Player=%d", 
        mode_str, g_bInDCJ ? "运行中" : "空闲", g_bInCJ ? "运行中" : "空闲", g_iPlayer);
    
    if (g_iPlayer) {
        new Float:vel[3];
        pev(g_iPlayer, pev_velocity, vel);
        new Float:spd = floatsqroot(vel[0]*vel[0] + vel[1]*vel[1]);
        console_print(id, "  Speed: %.1f | Flags: %d", spd, pev(g_iPlayer, pev_flags));
    }
    
    return PLUGIN_HANDLED;
}

public Cmd_Config(id, level, cid) {
    if (!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED;
    
    console_print(id, "[KZ AutoJump] 当前时序参数 (帧):");
    console_print(id, "  DCJ: strafe=%d counter_delay=%d counter_hold=%d jump_delay=%d cycle_gap=%d",
        get_pcvar_num(get_cvar_pointer("kz_aj_dcj_strafe")),
        get_pcvar_num(get_cvar_pointer("kz_aj_dcj_counter_delay")),
        get_pcvar_num(get_cvar_pointer("kz_aj_dcj_counter_hold")),
        get_pcvar_num(get_cvar_pointer("kz_aj_dcj_jump_delay")),
        get_pcvar_num(get_cvar_pointer("kz_aj_dcj_cycle_gap")));
    console_print(id, "  CJ:  strafe=%d jump_delay=%d cycle_gap=%d",
        get_pcvar_num(get_cvar_pointer("kz_aj_cj_strafe")),
        get_pcvar_num(get_cvar_pointer("kz_aj_cj_jump_delay")),
        get_pcvar_num(get_cvar_pointer("kz_aj_cj_cycle_gap")));
    console_print(id, "用法: kz_aj_dcj_strafe 18 等直接修改 cvar 即时生效");
    
    return PLUGIN_HANDLED;
}

// ================= 前向声明实现 =================
forward KZAJ_OnDCJStart(client);
forward KZAJ_OnDCJEnd(client, success);
forward KZAJ_OnCJStart(client);
forward KZAJ_OnCJEnd(client, success);

public plugin_natives() {
    g_fwdDCJStart = CreateMultiForward("KZAJ_OnDCJStart", ET_CONTINUE, FP_CELL);
    g_fwdDCJEnd = CreateMultiForward("KZAJ_OnDCJEnd", ET_CONTINUE, FP_CELL, FP_CELL);
    g_fwdCJStart = CreateMultiForward("KZAJ_OnCJStart", ET_CONTINUE, FP_CELL);
    g_fwdCJEnd = CreateMultiForward("KZAJ_OnCJEnd", ET_CONTINUE, FP_CELL, FP_CELL);
}