// UTF-8 BOM 标记确保中文注释正常显示
// ============================================================================
// 文件: utils.h
// 作用: 实用工具函数的头文件声明
// 功能:
//   1. 控制台创建和附加
//   2. UTF-16 到 UTF-8 字符串转换
//   3. 命令行参数解析
// ============================================================================

#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

/**
 * @brief 为进程创建控制台窗口并重定向标准输出/错误流
 * 
 * 这个函数会创建一个新的控制台窗口，并将 stdout 和 stderr 重定向到该控制台。
 * 这对于调试 Windows GUI 应用程序特别有用，因为默认情况下 GUI 应用没有控制台。
 * 
 * 功能细节:
 * - 调用 AllocConsole() 创建新控制台
 * - 设置控制台编码为 UTF-8，确保中文字符正常显示
 * - 重定向 stdout 和 stderr 到控制台
 * - 同步 C++ iostream 和 C stdio
 * - 调用 Flutter 的输出流重新同步函数
 * 
 * 使用场景:
 * - 开发调试时查看日志输出
 * - 在 'flutter run' 模式下显示实时日志
 * - 使用调试器时输出诊断信息
 */
void CreateAndAttachConsole();

/**
 * @brief 将 UTF-16 宽字符串转换为 UTF-8 字符串
 * 
 * Windows API 通常使用 UTF-16（wchar_t*）编码的字符串，
 * 而 Dart/Flutter 使用 UTF-8 编码。此函数执行必要的转换。
 * 
 * @param utf16_string 输入的 UTF-16 编码字符串（以 null 结尾）
 * @return std::string UTF-8 编码的字符串；如果转换失败则返回空字符串
 * 
 * 实现细节:
 * - 使用 Windows API WideCharToMultiByte() 进行转换
 * - 首先计算所需的缓冲区大小
 * - 然后执行实际转换
 * - 处理 nullptr 输入和转换错误
 * 
 * 使用示例:
 * ```cpp
 * wchar_t* wide_str = L"你好世界";
 * std::string utf8_str = Utf8FromUtf16(wide_str);
 * ```
 */
std::string Utf8FromUtf16(const wchar_t* utf16_string);

/**
 * @brief 获取命令行参数并转换为 UTF-8 编码的 vector
 * 
 * 解析 Windows 命令行参数并将其转换为 UTF-8 编码的字符串向量。
 * 第一个参数（程序名称）会被跳过，只返回实际的命令行参数。
 * 
 * @return std::vector<std::string> UTF-8 编码的命令行参数列表；
 *         如果失败则返回空 vector
 * 
 * 功能流程:
 * 1. 调用 CommandLineToArgvW() 获取 UTF-16 参数数组
 * 2. 跳过第一个参数（可执行文件路径）
 * 3. 将每个参数从 UTF-16 转换为 UTF-8
 * 4. 释放 Windows 分配的参数内存
 * 
 * 使用场景:
 * - 将命令行参数传递给 Dart 代码
 * - 支持启动时配置选项
 * - 处理文件路径等参数
 * 
 * 示例用法:
 * ```cpp
 * auto args = GetCommandLineArguments();
 * for (const auto& arg : args) {
 *     std::cout << "Argument: " << arg << std::endl;
 * }
 * ```
 */
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_