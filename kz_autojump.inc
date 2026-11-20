// kz_autojump.inc - 常量与股票函数声明
#if defined _kz_autojump_included
  #endinput
#endif
#define _kz_autojump_included

// 模式枚举
#define MODE_OFF     0
#define MODE_DCJ     1
#define MODE_CJ      2
#define MODE_AutoDCJ 3  // 智能 DCJ：按速度/高度自动判断单/双反向

// 全局变量股票
stock KZAJ_GetMode() { return g_iMode; }
stock KZAJ_SetMode(mode) { g_iMode = mode; }
stock bool:KZAJ_IsActive() { return g_iMode != MODE_OFF; }

// 供其它插件调用的 API
public KZAJ_OnDCJStart(client)
public KZAJ_OnDCJEnd(client, success)
public KZAJ_OnCJStart(client)
public KZAJ_OnCJEnd(client, success)