// IPC 通信模块
//
// 提供客户端和服务端的 IPC 通信能力

pub mod client;
pub mod error;
pub mod protocol;
pub mod server;

pub use client::IpcClient;
pub use error::{IpcError, Result};
pub use protocol::{IpcCommand, IpcResponse};
pub use server::IpcServer;
