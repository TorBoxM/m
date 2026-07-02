// UTF-8 BOM
#include "dark_mode_utils.h"

namespace DarkMode {
    // 未公开的 API 函数指针
    fnSetPreferredAppMode SetPreferredAppMode = nullptr;
    fnFlushMenuThemes FlushMenuThemes = nullptr;
    fnRefreshImmersiveColorPolicyState RefreshImmersiveColorPolicyState = nullptr;
    fnShouldAppsUseDarkMode ShouldAppsUseDarkMode = nullptr;
    fnAllowDarkModeForWindow AllowDarkModeForWindow = nullptr;

    bool g_darkModeSupported = false;
    DWORD g_buildNumber = 0;

    bool IsDarkModeSupported() {
        return g_darkModeSupported;
    }

    bool IsHighContrast() {
        HIGHCONTRASTW highContrast = { sizeof(highContrast) };
        if (SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(highContrast), &highContrast, FALSE))
            return highContrast.dwFlags & HCF_HIGHCONTRASTON;
        return false;
    }

    void Initialize() {
        // 获取 Windows 版本
        fnRtlGetNtVersionNumbers RtlGetNtVersionNumbers = reinterpret_cast<fnRtlGetNtVersionNumbers>(
            GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetNtVersionNumbers"));

        if (!RtlGetNtVersionNumbers) return;

        DWORD major, minor;
        RtlGetNtVersionNumbers(&major, &minor, &g_buildNumber);
        g_buildNumber &= ~0xF0000000;

        // 需要 Windows 10 1809+ (build 17763+)
        if (major != 10 || minor != 0 || g_buildNumber < 17763) {
            return;
        }

        // 加载 uxtheme.dll
        HMODULE hUxtheme = LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (!hUxtheme) return;

        // 通过序号获取未公开的 API
        RefreshImmersiveColorPolicyState = reinterpret_cast<fnRefreshImmersiveColorPolicyState>(
            GetProcAddress(hUxtheme, MAKEINTRESOURCEA(104)));
        
        ShouldAppsUseDarkMode = reinterpret_cast<fnShouldAppsUseDarkMode>(
            GetProcAddress(hUxtheme, MAKEINTRESOURCEA(132)));
        
        AllowDarkModeForWindow = reinterpret_cast<fnAllowDarkModeForWindow>(
            GetProcAddress(hUxtheme, MAKEINTRESOURCEA(133)));

        SetPreferredAppMode = reinterpret_cast<fnSetPreferredAppMode>(
            GetProcAddress(hUxtheme, MAKEINTRESOURCEA(135)));

        FlushMenuThemes = reinterpret_cast<fnFlushMenuThemes>(
            GetProcAddress(hUxtheme, MAKEINTRESOURCEA(136)));

        // 验证所有必需的函数是否加载成功
        if (RefreshImmersiveColorPolicyState &&
            ShouldAppsUseDarkMode &&
            AllowDarkModeForWindow &&
            SetPreferredAppMode &&
            FlushMenuThemes) {
            g_darkModeSupported = true;
        }
    }

    void EnableForApp() {
        if (!g_darkModeSupported) return;

        if (SetPreferredAppMode) {
            SetPreferredAppMode(PreferredAppMode::AllowDark);
        }

        if (RefreshImmersiveColorPolicyState) {
            RefreshImmersiveColorPolicyState();
        }

        // 关键：刷新菜单主题以应用暗色模式到托盘菜单
        if (FlushMenuThemes) {
            FlushMenuThemes();
        }
    }

    void EnableForWindow(HWND hWnd) {
        if (!g_darkModeSupported || !hWnd) return;

        bool shouldUseDark = ShouldAppsUseDarkMode && ShouldAppsUseDarkMode() && !IsHighContrast();

        if (AllowDarkModeForWindow) {
            AllowDarkModeForWindow(hWnd, shouldUseDark);
        }

        // 设置标题栏暗色模式
        BOOL dark = shouldUseDark ? TRUE : FALSE;
        #ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
        #define DWMWA_USE_IMMERSIVE_DARK_MODE 20
        #endif
        DwmSetWindowAttribute(hWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
    }

    bool HandleThemeChange(LPARAM lParam) {
        if (!g_darkModeSupported) return false;

        // 检查是否是配色方案改变
        bool isColorSchemeChange = false;
        if (lParam) {
            const wchar_t* setting = reinterpret_cast<const wchar_t*>(lParam);
            if (wcscmp(setting, L"ImmersiveColorSet") == 0) {
                isColorSchemeChange = true;
            }
        }

        if (RefreshImmersiveColorPolicyState) {
            RefreshImmersiveColorPolicyState();
        }

        if (isColorSchemeChange && FlushMenuThemes) {
            FlushMenuThemes();
        }

        return isColorSchemeChange;
    }
}