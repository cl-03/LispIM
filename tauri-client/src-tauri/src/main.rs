#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

pub mod websocket;

use log::{info, warn, error};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;
use reqwest::Client;
use tauri::Manager;

// LispIM API 客户端
struct LispIMClient {
    http_client: Client,
    base_url: String,
    token: Arc<Mutex<Option<String>>>,
    ws_url: Arc<Mutex<Option<String>>>,
}

impl LispIMClient {
    fn new(base_url: String) -> Self {
        Self {
            http_client: Client::new(),
            base_url,
            token: Arc::new(Mutex::new(None)),
            ws_url: Arc::new(Mutex::new(None)),
        }
    }

    async fn set_token(&self, token: Option<String>) {
        *self.token.lock().await = token;
    }

    async fn get_token(&self) -> Option<String> {
        self.token.lock().await.clone()
    }

    async fn set_ws_url(&self, url: Option<String>) {
        *self.ws_url.lock().await = url;
    }

    async fn get_ws_url(&self) -> Option<String> {
        self.ws_url.lock().await.clone()
    }
}

// 认证相关结构
#[derive(Debug, Serialize, Deserialize)]
pub struct AuthRequest {
    pub username: String,
    pub password: String,
}

// 后端 API 返回的原始响应格式
#[derive(Debug, Serialize, Deserialize)]
pub struct BackendAuthResponse {
    pub success: bool,
    pub data: Option<BackendAuthData>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BackendAuthData {
    pub userid: String,
    pub username: String,
    pub token: String,
}

// 前端期望的响应格式
#[derive(Debug, Serialize, Deserialize)]
pub struct AuthResponse {
    pub success: bool,
    pub user_id: Option<String>,
    pub username: Option<String>,
    pub token: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub username: String,
    pub display_name: String,
    pub email: Option<String>,
    pub avatar: Option<String>,
    pub status: String,
}

// 消息相关结构
#[derive(Debug, Serialize, Deserialize)]
pub struct SendMessageRequest {
    pub conversation_id: i64,
    pub content: String,
    pub message_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Message {
    pub id: i64,
    pub sequence: i64,
    pub conversation_id: i64,
    pub sender_id: String,
    pub message_type: String,
    pub content: Option<String>,
    pub created_at: i64,
    pub edited_at: Option<i64>,
    pub read_by: Option<Vec<ReadReceipt>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReadReceipt {
    pub user_id: String,
    pub timestamp: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Conversation {
    pub id: i64,
    pub r#type: String,
    pub name: Option<String>,
    pub participants: Vec<String>,
    pub last_message: Option<Message>,
    pub last_activity: i64,
}

// Tauri 应用状态
struct AppState {
    client: LispIMClient,
}

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! Welcome to LispIM Enterprise!", name)
}

#[tauri::command]
fn get_app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[tauri::command]
fn log_message(level: String, message: String) {
    match level.as_str() {
        "info" => info!("[Frontend] {}", message),
        "warn" => log::warn!("[Frontend] {}", message),
        "error" => log::error!("[Frontend] {}", message),
        _ => info!("[Frontend] {}", message),
    }
}

// 认证命令
#[tauri::command]
async fn login(
    username: String,
    password: String,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<AuthResponse, String> {
    info!("Login attempt for user: {}", username);

    let client = &state.client;
    let auth_url = format!("{}/api/v1/auth/login", client.base_url);

    let auth_request = AuthRequest {
        username: username.clone(),
        password,
    };

    match client.http_client
        .post(&auth_url)
        .json(&auth_request)
        .send()
        .await
    {
        Ok(response) => {
            // 解析后端返回的原始响应
            match response.json::<BackendAuthResponse>().await {
                Ok(backend_response) => {
                    // 转换为前端期望的格式
                    let auth_response = AuthResponse {
                        success: backend_response.success,
                        user_id: backend_response.data.as_ref().map(|d| d.userid.clone()),
                        username: backend_response.data.as_ref().map(|d| d.username.clone()),
                        token: backend_response.data.as_ref().map(|d| d.token.clone()),
                        error: backend_response.error,
                    };

                    if auth_response.success {
                        if let Some(ref token) = auth_response.token {
                            client.set_token(Some(token.clone())).await;
                            info!("User {} logged in successfully", username);
                        }
                    } else {
                        warn!("Login failed for user {}: {:?}", username, auth_response.error);
                    }
                    Ok(auth_response)
                }
                Err(e) => {
                    error!("Failed to parse auth response: {}", e);
                    Err(format!("服务器响应异常：{}", e))
                }
            }
        }
        Err(e) => {
            error!("Login request failed: {}", e);
            Err(format!("Network error: {}", e))
        }
    }
}

// 登出命令
#[tauri::command]
async fn logout(state: tauri::State<'_, Arc<AppState>>) -> Result<(), String> {
    let client = &state.client;
    client.set_token(None).await;
    client.set_ws_url(None).await;
    info!("User logged out");
    Ok(())
}

// 获取 WebSocket URL 命令
#[tauri::command]
async fn get_ws_url(state: tauri::State<'_, Arc<AppState>>) -> Result<Option<String>, String> {
    let client = &state.client;
    let ws_url = client.get_ws_url().await;

    if ws_url.is_none() {
        // 从 HTTP URL 推导 WebSocket URL
        let http_url = &client.base_url;
        let ws = http_url
            .replace("http://", "ws://")
            .replace("https://", "wss://");
        let ws_url = format!("{}/ws", ws);
        client.set_ws_url(Some(ws_url.clone())).await;
        Ok(Some(ws_url))
    } else {
        Ok(ws_url)
    }
}

// 获取用户信息命令
#[tauri::command]
async fn get_user_info(
    user_id: String,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<User, String> {
    let client = &state.client;
    let token = client.get_token().await.ok_or("Not authenticated")?;

    let url = format!("{}/api/v1/users/{}", client.base_url, user_id);

    match client.http_client
        .get(&url)
        .header("Authorization", format!("Bearer {}", token))
        .send()
        .await
    {
        Ok(response) => {
            match response.json::<User>().await {
                Ok(user) => Ok(user),
                Err(e) => Err(format!("Failed to parse user info: {}", e)),
            }
        }
        Err(e) => Err(format!("Network error: {}", e)),
    }
}

// 获取会话列表命令
#[tauri::command]
async fn get_conversations(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<Vec<Conversation>, String> {
    let client = &state.client;
    let token = client.get_token().await.ok_or("Not authenticated")?;

    let url = format!("{}/api/v1/conversations", client.base_url);

    match client.http_client
        .get(&url)
        .header("Authorization", format!("Bearer {}", token))
        .send()
        .await
    {
        Ok(response) => {
            match response.json::<Vec<Conversation>>().await {
                Ok(conversations) => Ok(conversations),
                Err(e) => Err(format!("Failed to parse conversations: {}", e)),
            }
        }
        Err(e) => Err(format!("Network error: {}", e)),
    }
}

// 获取历史消息命令
#[tauri::command]
async fn get_history(
    conversation_id: i64,
    limit: Option<i32>,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<Vec<Message>, String> {
    let client = &state.client;
    let token = client.get_token().await.ok_or("Not authenticated")?;

    let limit = limit.unwrap_or(50);
    let url = format!("{}/api/v1/conversations/{}/messages?limit={}",
                      client.base_url, conversation_id, limit);

    match client.http_client
        .get(&url)
        .header("Authorization", format!("Bearer {}", token))
        .send()
        .await
    {
        Ok(response) => {
            match response.json::<Vec<Message>>().await {
                Ok(messages) => Ok(messages),
                Err(e) => Err(format!("Failed to parse messages: {}", e)),
            }
        }
        Err(e) => Err(format!("Network error: {}", e)),
    }
}

/// 检查应用更新
#[tauri::command]
async fn check_for_updates(_app: tauri::AppHandle) -> Result<Option<String>, String> {
    // 自动更新将通过 Tauri 内置机制处理
    // 这里仅提供手动检查入口
    // 注意：实际更新检查由 Tauri updater 插件自动处理
    Ok(Some("Auto-update is enabled. Updates will be checked on startup.".to_string()))
}

fn main() {
    // 初始化日志
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    info!("Starting LispIM Enterprise Desktop Client");

    // 创建 API 客户端
    let base_url = std::env::var("LISPIM_API_URL").unwrap_or_else(|_| "http://localhost:3000".to_string());
    let client = LispIMClient::new(base_url);
    let app_state = Arc::new(AppState { client });

    // 创建系统托盘
    let tray_icon = tauri::SystemTray::new();

    tauri::Builder::default()
        .system_tray(tray_icon)
        .on_system_tray_event(|app, event| match event {
            tauri::SystemTrayEvent::LeftClick { .. } => {
                let window = app.get_window("main").unwrap();
                window.show().unwrap();
                window.set_focus().unwrap();
            }
            tauri::SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
                "show" => {
                    let window = app.get_window("main").unwrap();
                    window.show().unwrap();
                    window.set_focus().unwrap();
                }
                "quit" => {
                    std::process::exit(0);
                }
                _ => {}
            },
            _ => {}
        })
        .manage(app_state)
        .invoke_handler(tauri::generate_handler![
            greet,
            get_app_version,
            log_message,
            login,
            logout,
            get_ws_url,
            get_user_info,
            get_conversations,
            get_history,
            check_for_updates,
            websocket::ws_connect,
            websocket::ws_disconnect,
            websocket::ws_send,
            websocket::ws_get_state
        ])
        .setup(|app| {
            info!("Application setup complete");

            // 注册全局快捷键
            #[cfg(any(windows, target_os = "macos"))]
            {
                use tauri::GlobalShortcutManager;
                let mut manager = app.handle().global_shortcut_manager();
                let app_handle = app.handle().clone();

                // Ctrl+Shift+L 快速显示/隐藏窗口
                #[cfg(target_os = "windows")]
                manager
                    .register("ctrl+shift+l", move || {
                        if let Some(window) = app_handle.get_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                window.hide().unwrap();
                            } else {
                                window.show().unwrap();
                                window.set_focus().unwrap();
                            }
                        }
                    })
                    .expect("Failed to register global shortcut");
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
