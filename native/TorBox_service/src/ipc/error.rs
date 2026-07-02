// IPC 错误类型定义

use thiserror::Error;

// IPC 错误类型
#[derive(Error, Debug)]
#[allow(dead_code)]
pub enum IpcError {
    // 连接错误
    #[error(
        "IPC 连接失败: {0}\n可能原因：\n  1. 服务未启动\n  2. 权限不足\n  3. IPC 路径错误\n提示: 请检查服务状态并确认权限"
    )]
    ConnectionFailed(String),

    // 超时错误
    #[error(
        "IPC 操作超时\n可能原因：\n  1. 服务无响应\n  2. 网络延迟过高\n  3. 服务处理超时\n提示: 请尝试重启服务"
    )]
    Timeout,

    // 序列化错误
    #[error("数据序列化失败: {0}\n提示: 请检查数据格式是否正确")]
    SerializationError(#[from] serde_json::Error),

    // IO 错误
    #[error("IO 错误: {0}")]
    IoError(#[from] std::io::Error),

    // 服务未运行
    #[error("服务未运行\n提示: 请先启动 TorBox Service")]
    ServiceNotRunning,

    // 服务返回错误
    #[error("服务返回错误 (错误代码: {0}): {1}")]
    ServiceError(i32, String),

    // 其他错误
    #[error("{0}")]
    Other(String),
}

// IPC Result 类型
pub type Result<T> = std::result::Result<T, IpcError>;
