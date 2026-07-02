// Unix Socket 权限工具
// 将 root 服务创建的 socket 交还给桌面用户访问。

#[cfg(unix)]
use std::ffi::CString;
#[cfg(unix)]
use std::os::unix::ffi::OsStrExt;
#[cfg(unix)]
use std::os::unix::fs::FileTypeExt;
#[cfg(unix)]
use std::path::Path;

#[cfg(unix)]
pub const SERVICE_USER_UID_ENV: &str = "TorBox_SERVICE_USER_UID";
#[cfg(unix)]
pub const SERVICE_USER_GID_ENV: &str = "TorBox_SERVICE_USER_GID";

#[cfg(unix)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct UnixSocketOwner {
    pub uid: u32,
    pub gid: u32,
}

#[cfg(unix)]
impl UnixSocketOwner {
    pub fn new(uid: u32, gid: u32) -> Self {
        Self { uid, gid }
    }
}

#[cfg(unix)]
pub fn resolve_invoking_user() -> Option<UnixSocketOwner> {
    owner_from_uid_env("PKEXEC_UID")
        .or_else(|| owner_from_env_pair("SUDO_UID", "SUDO_GID"))
        .or_else(current_non_root_owner)
}

#[cfg(unix)]
pub fn resolve_configured_owner() -> Option<UnixSocketOwner> {
    owner_from_env_pair(SERVICE_USER_UID_ENV, SERVICE_USER_GID_ENV)
}

#[cfg(unix)]
pub fn apply_socket_permissions<P: AsRef<Path>>(path: P, mode: u32) -> Result<(), String> {
    let path = path.as_ref();
    ensure_unix_socket(path)?;

    if let Some(owner) = resolve_configured_owner() {
        chown_path(path, owner)?;
        log::info!(
            "Unix Socket 所有者已设置为 UID={}, GID={}：{}",
            owner.uid,
            owner.gid,
            path.display()
        );
    } else {
        log::debug!(
            "未配置桌面用户，保持 Unix Socket 当前所有者：{}",
            path.display()
        );
    }

    chmod_path(path, mode)?;
    log::info!("Unix Socket 权限已设置为 {:o}：{}", mode, path.display());
    Ok(())
}

#[cfg(unix)]
fn ensure_unix_socket(path: &Path) -> Result<(), String> {
    let meta = std::fs::symlink_metadata(path)
        .map_err(|e| format!("读取 Unix Socket 元数据失败：{}：{}", path.display(), e))?;
    let file_type = meta.file_type();

    if file_type.is_socket() {
        return Ok(());
    }

    Err(format!("目标不是 Unix Socket：{}", path.display()))
}

#[cfg(unix)]
fn owner_from_env_pair(uid_env: &str, gid_env: &str) -> Option<UnixSocketOwner> {
    let uid = env_u32(uid_env)?;
    let gid = env_u32(gid_env)?;
    Some(UnixSocketOwner::new(uid, gid))
}

#[cfg(unix)]
fn owner_from_uid_env(uid_env: &str) -> Option<UnixSocketOwner> {
    let uid = env_u32(uid_env)?;
    let gid = primary_gid_for_uid(uid)?;
    Some(UnixSocketOwner::new(uid, gid))
}

#[cfg(unix)]
fn current_non_root_owner() -> Option<UnixSocketOwner> {
    let uid = unsafe { libc::getuid() };
    if uid == 0 {
        return None;
    }

    let gid = unsafe { libc::getgid() };
    Some(UnixSocketOwner::new(uid, gid))
}

#[cfg(unix)]
fn env_u32(name: &str) -> Option<u32> {
    std::env::var(name).ok()?.parse::<u32>().ok()
}

#[cfg(unix)]
fn primary_gid_for_uid(uid: u32) -> Option<u32> {
    let passwd = unsafe { libc::getpwuid(uid as libc::uid_t) };
    if passwd.is_null() {
        return None;
    }

    Some(unsafe { (*passwd).pw_gid as u32 })
}

#[cfg(unix)]
fn chown_path(path: &Path, owner: UnixSocketOwner) -> Result<(), String> {
    let c_path = path_to_cstring(path)?;
    let result = unsafe {
        libc::chown(
            c_path.as_ptr(),
            owner.uid as libc::uid_t,
            owner.gid as libc::gid_t,
        )
    };

    if result == 0 {
        return Ok(());
    }

    Err(format!(
        "设置 Unix Socket 所有者失败：{}：{}",
        path.display(),
        std::io::Error::last_os_error()
    ))
}

#[cfg(unix)]
fn chmod_path(path: &Path, mode: u32) -> Result<(), String> {
    let c_path = path_to_cstring(path)?;
    let result = unsafe { libc::chmod(c_path.as_ptr(), mode as libc::mode_t) };

    if result == 0 {
        return Ok(());
    }

    Err(format!(
        "设置 Unix Socket 权限失败：{}：{}",
        path.display(),
        std::io::Error::last_os_error()
    ))
}

#[cfg(unix)]
fn path_to_cstring(path: &Path) -> Result<CString, String> {
    CString::new(path.as_os_str().as_bytes())
        .map_err(|_| format!("路径包含空字符：{}", path.display()))
}
