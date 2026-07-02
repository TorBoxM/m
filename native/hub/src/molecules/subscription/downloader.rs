// 订阅下载器
// 处理订阅配置的 HTTP 下载，支持多种代理模式

use crate::molecules::ProxyMode;
use reqwest::{Client, Proxy};
use rinf::{DartSignal, RustSignal};
use serde::{Deserialize, Serialize};
use std::str::FromStr;
use std::time::Duration;

const AGE_ARMOR_HEADER: &str = "-----BEGIN AGE ENCRYPTED FILE-----";
const AGE_X25519_SECRET_KEY_PREFIX: &str = "AGE-SECRET-KEY-1";
const AGE_HYBRID_SECRET_KEY_PREFIX: &str = "AGE-SECRET-KEY-PQ-1";

// Dart → Rust：下载订阅请求
#[derive(Deserialize, DartSignal)]
pub struct DownloadSubscriptionRequest {
    pub request_id: String, // 请求标识符，用于响应匹配
    pub url: String,
    pub proxy_mode: ProxyMode,
    pub user_agent: String,
    pub timeout_seconds: u64,
    pub mixed_port: u16, // Clash 混合端口
    pub age_secret_key: Option<String>,
}

// Rust → Dart：下载订阅响应
#[derive(Serialize, RustSignal)]
pub struct DownloadSubscriptionResponse {
    pub request_id: String, // 请求标识符，用于请求匹配
    pub is_successful: bool,
    pub content: String,
    pub subscription_info: Option<SubscriptionInfoData>,
    pub error_message: Option<String>,
}

// 订阅信息
#[derive(Serialize, Deserialize, Clone, Debug, rinf::SignalPiece)]
pub struct SubscriptionInfoData {
    pub upload: Option<u64>,
    pub download: Option<u64>,
    pub total: Option<u64>,
    pub expire: Option<i64>,
}

impl DownloadSubscriptionRequest {
    pub async fn handle(self) {
        log::info!("收到下载订阅请求 [{}]：{}", self.request_id, self.url);

        let result = download_subscription(
            &self.url,
            self.proxy_mode,
            &self.user_agent,
            self.timeout_seconds,
            self.mixed_port,
            self.age_secret_key.as_deref(),
        )
        .await;

        let response = match result {
            Ok((content, info)) => {
                log::info!(
                    "订阅下载成功 [{}]，内容长度：{} 字节",
                    self.request_id,
                    content.len()
                );
                DownloadSubscriptionResponse {
                    request_id: self.request_id,
                    is_successful: true,
                    content,
                    subscription_info: info,
                    error_message: None,
                }
            }
            Err(e) => {
                log::error!("订阅下载失败 [{}]：{}", self.request_id, e);
                DownloadSubscriptionResponse {
                    request_id: self.request_id,
                    is_successful: false,
                    content: String::new(),
                    subscription_info: None,
                    error_message: Some(e.to_string()),
                }
            }
        };

        response.send_signal_to_dart();
    }
}

// 下载订阅配置并返回内容与订阅信息。
// 支持代理模式、超时与自定义 User-Agent。
pub async fn download_subscription(
    url: &str,
    proxy_mode: ProxyMode,
    user_agent: &str,
    timeout_seconds: u64,
    mixed_port: u16,
    age_secret_key: Option<&str>,
) -> Result<(String, Option<SubscriptionInfoData>), Box<dyn std::error::Error + Send + Sync>> {
    log::info!("开始下载订阅：{}", url);
    log::info!("代理模式：{:?}", proxy_mode);

    // 创建 HTTP 客户端
    let client = create_http_client(proxy_mode, timeout_seconds, mixed_port)?;

    // 发送 HTTP GET 请求
    let response = client
        .get(url)
        .header("User-Agent", user_agent)
        .send()
        .await?;

    // 检查 HTTP 状态码
    let status = response.status();
    if !status.is_success() {
        return Err(format!(
            "HTTP {}: {}",
            status.as_u16(),
            status.canonical_reason().unwrap_or("Unknown")
        )
        .into());
    }

    // 解析订阅信息头
    let subscription_info = parse_subscription_info(response.headers());

    // 读取响应体
    let content = response.text().await?;

    if content.is_empty() {
        return Err("订阅内容为空".into());
    }

    let content = decrypt_age_content_if_needed(&content, age_secret_key)?;
    if content.is_empty() {
        return Err("订阅内容为空".into());
    }

    log::info!("订阅下载成功，内容长度：{} 字节", content.len());

    Ok((content, subscription_info))
}

fn decrypt_age_content_if_needed(
    content: &str,
    age_secret_key: Option<&str>,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    if !content.starts_with(AGE_ARMOR_HEADER) {
        return Ok(content.to_string());
    }

    let Some(secret_key) = age_secret_key.map(str::trim).filter(|key| !key.is_empty()) else {
        return Err("订阅内容已使用 age 加密，请填写 age-secret-key".into());
    };

    let (identities, has_hybrid_secret_key) = parse_x25519_identities(secret_key)?;

    for identity in identities {
        match age::decrypt(&identity, content.as_bytes()) {
            Ok(bytes) => {
                let decrypted = String::from_utf8(bytes)
                    .map_err(|e| format!("age 解密结果不是有效 UTF-8：{}", e))?;
                log::info!("订阅 age 解密成功");
                return Ok(decrypted);
            }
            Err(e) => {
                log::debug!("当前 age-secret-key 无法解密订阅：{}", e);
            }
        }
    }

    if has_hybrid_secret_key {
        return Err(
            "当前内置解密仅支持 x25519 age-secret-key，暂不支持 mlkem768-x25519 key".into(),
        );
    }

    Err("age-secret-key 无法解密订阅内容".into())
}

fn parse_x25519_identities(
    secret_key: &str,
) -> Result<(Vec<age::x25519::Identity>, bool), Box<dyn std::error::Error + Send + Sync>> {
    let mut identities = Vec::new();
    let mut has_hybrid_secret_key = false;

    for line in secret_key.lines().map(str::trim) {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        if line.starts_with(AGE_HYBRID_SECRET_KEY_PREFIX) {
            has_hybrid_secret_key = true;
            continue;
        }

        if !line.starts_with(AGE_X25519_SECRET_KEY_PREFIX) {
            return Err(format!("age-secret-key 类型无效：{}", line).into());
        }

        let identity = age::x25519::Identity::from_str(line)
            .map_err(|e| format!("age-secret-key 格式无效：{}", e))?;
        identities.push(identity);
    }

    if identities.is_empty() && has_hybrid_secret_key {
        return Err(
            "当前内置解密仅支持 x25519 age-secret-key，暂不支持 mlkem768-x25519 key".into(),
        );
    }

    if identities.is_empty() {
        return Err("age-secret-key 未包含有效私钥".into());
    }

    Ok((identities, has_hybrid_secret_key))
}

// 创建 HTTP 客户端
fn create_http_client(
    proxy_mode: ProxyMode,
    timeout_seconds: u64,
    mixed_port: u16,
) -> Result<Client, Box<dyn std::error::Error + Send + Sync>> {
    let mut builder = Client::builder()
        .timeout(Duration::from_secs(timeout_seconds))
        .connect_timeout(Duration::from_secs(10)) // 连接超时
        .danger_accept_invalid_certs(false); // 验证 SSL 证书

    // 根据代理模式配置客户端
    match proxy_mode {
        ProxyMode::Direct => {
            log::debug!("使用直连模式");
            // 不设置代理
        }
        ProxyMode::System => {
            log::debug!("使用系统代理模式");
            // reqwest 默认会读取系统环境变量（HTTP_PROXY, HTTPS_PROXY）
            // 无需额外配置
        }
        ProxyMode::Core => {
            log::debug!("使用核心代理模式：127.0.0.1:{}", mixed_port);
            let proxy_url = format!("http://127.0.0.1:{}", mixed_port);
            let proxy = Proxy::all(&proxy_url)?;
            builder = builder.proxy(proxy);
        }
    }

    Ok(builder.build()?)
}

// 解析订阅信息头（subscription-userinfo）。
// 示例：upload=0; download=123; total=1073741824; expire=1735689600
fn parse_subscription_info(headers: &reqwest::header::HeaderMap) -> Option<SubscriptionInfoData> {
    let header_value = headers.get("subscription-userinfo")?.to_str().ok()?;

    log::debug!("解析订阅信息头：{}", header_value);

    let mut upload = None;
    let mut download = None;
    let mut total = None;
    let mut expire = None;

    // 解析键值对
    for pair in header_value.split(';') {
        let pair = pair.trim();
        if let Some((key, value)) = pair.split_once('=') {
            let key = key.trim();
            let value = value.trim();

            match key {
                "upload" => upload = value.parse::<u64>().ok(),
                "download" => download = value.parse::<u64>().ok(),
                "total" => total = value.parse::<u64>().ok(),
                "expire" => expire = value.parse::<i64>().ok(),
                _ => {}
            }
        }
    }

    // 如果至少有一个字段有值，则返回订阅信息
    if upload.is_some() || download.is_some() || total.is_some() || expire.is_some() {
        Some(SubscriptionInfoData {
            upload,
            download,
            total,
            expire,
        })
    } else {
        None
    }
}

// 初始化 Dart 信号监听器
pub fn init() {
    use tokio::spawn;

    // 订阅下载请求监听器
    spawn(async {
        let receiver = DownloadSubscriptionRequest::get_dart_signal_receiver();
        while let Some(dart_signal) = receiver.recv().await {
            tokio::spawn(async move {
                dart_signal.message.handle().await;
            });
        }
    });
}

#[cfg(test)]
mod tests {
    use super::decrypt_age_content_if_needed;
    use age::secrecy::ExposeSecret;

    #[test]
    fn decrypt_age_content_with_x25519_secret_key()
    -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let identity = age::x25519::Identity::generate();
        let recipient = identity.to_public();
        let plaintext = "proxies:\n  - name: test\nproxy-groups:\n  - name: PROXY\n";
        let encrypted = age::encrypt_and_armor(&recipient, plaintext.as_bytes())?;
        let secret_key = identity.to_string();

        let decrypted =
            decrypt_age_content_if_needed(&encrypted, Some(secret_key.expose_secret()))?;

        assert_eq!(decrypted, plaintext);
        Ok(())
    }

    #[test]
    fn reject_hybrid_secret_key_with_clear_error()
    -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let identity = age::x25519::Identity::generate();
        let recipient = identity.to_public();
        let encrypted = age::encrypt_and_armor(&recipient, b"proxies: []")?;

        let err =
            match decrypt_age_content_if_needed(&encrypted, Some("AGE-SECRET-KEY-PQ-1INVALID")) {
                Ok(_) => return Err("预期 PQ key 会被当前内置解密拒绝".into()),
                Err(e) => e,
            };

        assert!(err.to_string().contains("mlkem768-x25519"));
        Ok(())
    }
}
