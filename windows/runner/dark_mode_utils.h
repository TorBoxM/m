// UTF-8 BOM
#pragma once
#include <windows.h>
#include <dwmapi.h>

// 应用主题模式 (Windows 10 1903+)
enum class PreferredAppMode
{
    Default,
    AllowDark,
    ForceDark,
    ForceLight,
    Max
};

// 未公开的 Windows API 函数指针类型
using fnSetPreferredAppMode = PreferredAppMode (WINAPI *)(PreferredAppMode appMode);
using fnFlushMenuThemes = void (WINAPI *)();
using fnRefreshImmersiveColorPolicyState = void (WINAPI *)();
using fnShouldAppsUseDarkMode = bool (WINAPI *)();
using fnAllowDarkModeForWindow = bool (WINAPI *)(HWND hWnd, bool allow);
using fnRtlGetNtVersionNumbers = void (WINAPI *)(LPDWORD major, LPDWORD minor, LPDWORD build);

namespace DarkMode {
    // 全局函数指针（由 Initialize() 填充）
    extern fnSetPreferredAppMode SetPreferredAppMode;
    extern fnFlushMenuThemes FlushMenuThemes;
    extern fnRefreshImmersiveColorPolicyState RefreshImmersiveColorPolicyState;
    extern fnShouldAppsUseDarkMode ShouldAppsUseDarkMode;
    extern fnAllowDarkModeForWindow AllowDarkModeForWindow;

    extern bool g_darkModeSupported;
    extern DWORD g_buildNumber;

    // 检查是否支持暗色模式 (Windows 10 1809+)
    bool IsDarkModeSupported();

    // 检查是否启用了高对比度模式
    bool IsHighContrast();

    // 初始化暗色模式支持
    void Initialize();

    // 为整个应用启用暗色模式
    void EnableForApp();

    // 为特定窗口启用暗色模式
    void EnableForWindow(HWND hWnd);

    // 处理系统主题更改事件
    bool HandleThemeChange(LPARAM lParam);
}