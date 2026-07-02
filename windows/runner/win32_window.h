// UTF-8 BOM 标记确保中文注释正常显示
// ============================================================================
// 文件: win32_window.h
// 作用: Win32 窗口抽象类的头文件声明
// 功能:
//   1. 提供高 DPI 感知的 Win32 窗口基类
//   2. 封装 Windows 窗口创建和管理的复杂性
//   3. 支持自定义渲染和输入处理
//   4. 管理窗口生命周期和主题
// ============================================================================

#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

/**
 * @brief 高 DPI 感知的 Win32 窗口抽象类
 * 
 * 这个类封装了创建和管理 Win32 窗口的复杂性，提供了：
 * - 自动 DPI 缩放支持
 * - 暗色模式主题支持
 * - 简化的窗口创建 API
 * - 子窗口内容管理
 * 
 * 设计模式:
 * - 使用模板方法模式：定义骨架，子类实现具体逻辑
 * - 使用单例注册器管理窗口类注册
 * 
 * 使用方法:
 * 继承此类并重写 OnCreate(), OnDestroy(), MessageHandler() 等虚函数
 * 来自定义窗口行为。
 */
class Win32Window {
 public:
  /**
   * @brief 窗口位置结构体
   * 
   * 表示窗口左上角的坐标（相对于屏幕）。
   * 坐标单位为逻辑像素，会根据 DPI 自动缩放。
   */
  struct Point {
    unsigned int x;  // X 坐标（从左到右）
    unsigned int y;  // Y 坐标（从上到下）
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  /**
   * @brief 窗口尺寸结构体
   * 
   * 表示窗口的宽度和高度。
   * 尺寸单位为逻辑像素，会根据 DPI 自动缩放。
   */
  struct Size {
    unsigned int width;   // 窗口宽度
    unsigned int height;  // 窗口高度
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  /**
   * @brief 构造函数
   * 
   * 创建 Win32Window 实例并增加活动窗口计数。
   * 注意：此时不创建实际的 Windows 窗口，需要调用 Create()。
   */
  Win32Window();
  
  /**
   * @brief 虚析构函数
   * 
   * 确保派生类的析构函数被正确调用。
   * 自动减少活动窗口计数并销毁窗口。
   */
  virtual ~Win32Window();

  /**
   * @brief 创建 Win32 窗口
   * 
   * 创建指定标题、位置和尺寸的窗口。新窗口在默认显示器上创建。
   * 
   * 重要特性:
   * - 自动 DPI 缩放：输入的宽度和高度会根据显示器 DPI 自动缩放
   * - 初始隐藏：窗口创建后是隐藏的，需要调用 Show() 显示
   * - 主题自动应用：根据系统设置应用暗色/亮色主题
   * 
   * @param title  窗口标题（宽字符串）
   * @param origin 窗口左上角位置（逻辑坐标）
   * @param size   窗口尺寸（逻辑尺寸）
   * @return bool  窗口创建成功返回 true，失败返回 false
   * 
   * 注意: 如果窗口已存在，会先销毁旧窗口再创建新窗口
   */
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  /**
   * @brief 显示窗口
   * 
   * 将隐藏的窗口显示为正常窗口（非最小化、非最大化）。
   * 
   * @return bool 窗口成功显示返回 true
   */
  bool Show();

  /**
   * @brief 释放窗口相关的操作系统资源
   * 
   * 销毁 Windows 窗口并清理相关资源。
   * 如果这是最后一个活动窗口，还会注销窗口类。
   * 
   * 注意: 析构函数会自动调用此方法，通常不需要手动调用
   */
  void Destroy();

  /**
   * @brief 将子窗口插入到窗口树中
   * 
   * 将指定的窗口句柄设置为当前窗口的子窗口，并调整其大小以填充客户区。
   * 
   * @param content 要插入的子窗口句柄
   * 
   * 使用场景:
   * - 嵌入 Flutter 渲染表面
   * - 嵌入其他控件或视图
   */
  void SetChildContent(HWND content);

  /**
   * @brief 获取窗口句柄
   * 
   * 返回底层的 Windows 窗口句柄（HWND），允许客户端设置图标、
   * 修改窗口属性等。
   * 
   * @return HWND 窗口句柄；如果窗口已销毁则返回 nullptr
   */
  HWND GetHandle();

  /**
   * @brief 设置关闭窗口时是否退出应用程序
   * 
   * @param quit_on_close true 表示关闭窗口时退出应用，false 表示仅隐藏窗口
   * 
   * 使用场景:
   * - 主窗口通常设为 true
   * - 对话框或辅助窗口通常设为 false
   */
  void SetQuitOnClose(bool quit_on_close);

  /**
   * @brief 获取客户区矩形
   * 
   * 返回表示当前客户区边界的 RECT 结构（不包括边框和标题栏）。
   * 
   * @return RECT 客户区矩形，坐标相对于窗口左上角
   */
  RECT GetClientArea();

 protected:
  /**
   * @brief 处理和路由重要的窗口消息
   * 
   * 这是一个虚函数，子类可以重写来处理特定的窗口消息。
   * 
   * 处理的消息类型:
   * - 鼠标事件（移动、点击、滚轮）
   * - 窗口大小变化
   * - DPI 变化
   * - 主题变化
   * 
   * @param window  窗口句柄
   * @param message 消息类型（WM_* 常量）
   * @param wparam  消息参数 1
   * @param lparam  消息参数 2
   * @return LRESULT 消息处理结果
   * 
   * 注意: 必须使用 noexcept 以保证异常安全性（Windows 回调不能抛出异常）
   */
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  /**
   * @brief 窗口创建完成后的回调
   * 
   * 在 Create() 调用后被调用，允许子类执行窗口相关的设置。
   * 
   * @return bool 设置成功返回 true，失败返回 false
   * 
   * 注意: 如果返回 false，窗口创建会失败
   */
  virtual bool OnCreate();

  /**
   * @brief 窗口销毁时的回调
   * 
   * 在 Destroy() 调用时被调用，允许子类清理窗口相关资源。
   */
  virtual void OnDestroy();

 private:
  // ========================================================================
  // 友元类
  // ========================================================================
  /**
   * @brief 窗口类注册器友元类
   * 
   * 允许 WindowClassRegistrar 访问私有静态方法 WndProc
   */
  friend class WindowClassRegistrar;

  /**
   * @brief Windows 消息泵调用的操作系统回调
   * 
   * 这是 Windows 消息循环调用的静态回调函数。
   * 
   * 特殊处理:
   * - WM_NCCREATE: 启用自动 DPI 缩放，设置窗口实例指针
   * - 其他消息: 转发给对应 Win32Window 实例的 MessageHandler
   * 
   * @return LRESULT 消息处理结果
   */
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  /**
   * @brief 从窗口句柄获取 Win32Window 实例指针
   * 
   * 从窗口的用户数据中提取 Win32Window 指针。
   * 
   * @param window 窗口句柄
   * @return Win32Window* 窗口实例指针，如果不存在则返回 nullptr
   */
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  /**
   * @brief 更新窗口框架主题以匹配系统主题
   * 
   * 根据系统暗色/亮色模式设置更新窗口标题栏和边框的主题。
   * 
   * @param window 要更新的窗口句柄
   * 
   * 优先级:
   * 1. 使用未公开的暗色模式 API（Windows 10 1809+）
   * 2. 回退到官方 DWMWA_USE_IMMERSIVE_DARK_MODE API
   */
  static void UpdateTheme(HWND const window);

  // ========================================================================
  // 成员变量
  // ========================================================================
  
  /**
   * @brief 关闭窗口时是否退出应用程序
   * 
   * true: 发送 WM_QUIT 消息退出应用
   * false: 仅销毁窗口，应用继续运行
   */
  bool quit_on_close_ = false;

  /**
   * @brief 顶层窗口的窗口句柄
   * 
   * 指向实际的 Windows 窗口。
   * nullptr 表示窗口尚未创建或已被销毁。
   */
  HWND window_handle_ = nullptr;

  /**
   * @brief 托管内容的窗口句柄
   * 
   * 指向作为子窗口嵌入的内容窗口（如 Flutter 视图）。
   * nullptr 表示没有子内容。
   */
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_