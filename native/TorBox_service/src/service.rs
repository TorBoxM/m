// 服务模块

pub mod handler;
pub mod installer;
pub mod runner;

// Re-export 常用项
#[cfg(any(windows, target_os = "linux", target_os = "macos"))]
pub use installer::*;

// Re-export runner 的函数
#[cfg(windows)]
pub use runner::run_as_service;
#[cfg(target_os = "linux")]
pub use runner::run_service;
