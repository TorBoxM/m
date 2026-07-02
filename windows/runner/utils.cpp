// UTF-8 BOM 标记确保中文注释正常显示
// ============================================================================
// 文件: utils.cpp
// 作用: 实用工具函数的实现
// 功能: 实现 utils.h 中声明的所有工具函数
// ============================================================================

#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

/**
 * @brief 创建控制台窗口并重定向标准输出流
 * 
 * 实现步骤:
 * 1. 分配新的控制台窗口
 * 2. 设置控制台为 UTF-8 编码（支持中文显示）
 * 3. 重定向 stdout 和 stderr 到控制台
 * 4. 同步 C++ iostream 和 Flutter 输出流
 */
void CreateAndAttachConsole() {
  // 尝试分配新的控制台窗口
  if (::AllocConsole()) {
    // ======================================================================
    // 设置控制台编码为 UTF-8
    // ======================================================================
    // CP_UTF8 = 65001，UTF-8 代码页
    // 这样可以避免中文等非 ASCII 字符在控制台中显示为乱码
    
    // 设置控制台输出编码（显示到屏幕）
    ::SetConsoleOutputCP(CP_UTF8);
    // 设置控制台输入编码（从键盘输入）
    ::SetConsoleCP(CP_UTF8);

    // ======================================================================
    // 重定向标准输出流
    // ======================================================================
    FILE *unused;
    
    // 重定向 stdout（标准输出）到控制台
    // "CONOUT$" 是 Windows 控制台输出的特殊设备名称
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      // 如果 freopen_s 失败，使用 _dup2 作为备用方案
      // _fileno(stdout) 获取 stdout 的文件描述符
      // 1 是标准输出的文件描述符编号
      _dup2(_fileno(stdout), 1);
    }
    
    // 重定向 stderr（标准错误）到控制台
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      // 备用方案：文件描述符 2 代表标准错误
      _dup2(_fileno(stdout), 2);
    }
    
    // ======================================================================
    // 同步 C++ iostream
    // ======================================================================
    // 同步 C++ 标准流（std::cout, std::cerr）与 C 标准流（stdout, stderr）
    // 确保 std::cout 和 printf 等函数的输出顺序正确
    std::ios::sync_with_stdio();
    
    // 通知 Flutter 引擎重新同步输出流
    // 这样 Flutter 的日志也会输出到控制台
    FlutterDesktopResyncOutputStreams();
  }
}

/**
 * @brief 获取并转换命令行参数
 * 
 * 实现流程:
 * 1. 调用 Windows API 获取 UTF-16 格式的参数
 * 2. 跳过第一个参数（可执行文件路径）
 * 3. 将剩余参数转换为 UTF-8
 * 4. 释放 Windows 分配的内存
 * 
 * @return std::vector<std::string> UTF-8 编码的参数列表
 */
std::vector<std::string> GetCommandLineArguments() {
  // ========================================================================
  // 步骤 1: 获取命令行参数
  // ========================================================================
  // 将 UTF-16 命令行字符串解析为参数数组
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  
  // 检查是否成功获取参数
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  // ========================================================================
  // 步骤 2: 转换参数编码
  // ========================================================================
  std::vector<std::string> command_line_arguments;

  // 从索引 1 开始，跳过第一个参数（可执行文件的完整路径）
  // 例如: argv[0] = "C:\Program Files\MyApp\app.exe"
  //      argv[1] = "--some-flag"  <-- 从这里开始处理
  for (int i = 1; i < argc; i++) {
    // 将每个 UTF-16 参数转换为 UTF-8 并添加到结果向量
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  // ========================================================================
  // 步骤 3: 清理资源
  // ========================================================================
  // 释放 CommandLineToArgvW 分配的内存
  // 必须使用 LocalFree，不能用 delete 或 free
  ::LocalFree(argv);

  return command_line_arguments;
}

/**
 * @brief UTF-16 到 UTF-8 字符串转换
 * 
 * 使用 Windows API WideCharToMultiByte 执行转换。
 * 这个函数需要调用两次：第一次计算所需缓冲区大小，第二次执行实际转换。
 * 
 * @param utf16_string 输入的 UTF-16 字符串（wchar_t*）
 * @return std::string 转换后的 UTF-8 字符串
 */
std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  // ========================================================================
  // 边界检查
  // ========================================================================
  if (utf16_string == nullptr) {
    return std::string();
  }
  
  // ========================================================================
  // 步骤 1: 计算目标字符串长度
  // ========================================================================
  // CP_UTF8: 使用 UTF-8 代码页
  // WC_ERR_INVALID_CHARS: 如果遇到无效字符则失败（而不是替换为默认字符）
  // -1: 源字符串以 null 结尾，自动计算长度
  // nullptr, 0: 不执行实际转换，只计算所需缓冲区大小
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // 减去尾随的 null 字符
  
  // 获取输入字符串长度
  int input_length = (int)wcslen(utf16_string);
  
  // 准备输出字符串
  std::string utf8_string;
  
  // 检查长度是否有效
  // target_length == 0 表示转换失败
  // target_length > max_size() 表示长度溢出
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  
  // ========================================================================
  // 步骤 2: 分配缓冲区
  // ========================================================================
  utf8_string.resize(target_length);
  
  // ========================================================================
  // 步骤 3: 执行实际转换
  // ========================================================================
  // 这次提供实际的缓冲区来接收转换结果
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  
  // ========================================================================
  // 步骤 4: 验证转换结果
  // ========================================================================
  // converted_length == 0 表示转换失败
  if (converted_length == 0) {
    return std::string();
  }
  
  return utf8_string;
}