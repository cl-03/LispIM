// WebSocket 模块 for LispIM
use log::{info, error};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::{Mutex, broadcast};
use futures::{SinkExt, StreamExt};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use url::Url;
use tauri::Manager;

// WebSocket 消息类型
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WSMessage {
    pub r#type: String,
    pub payload: serde_json::Value,
    pub timestamp: i64,
}

// WebSocket 连接状态
#[derive(Debug, Clone, PartialEq)]
pub enum WSState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
}

// WebSocket 客户端
pub type WSSplitSink = futures::stream::SplitSink<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    Message
>;

pub struct WSClient {
    pub url: String,
    pub token: String,
    pub state: Arc<Mutex<WSState>>,
    pub tx: Arc<Mutex<Option<WSSplitSink>>>,
    pub rx_handle: Arc<Mutex<Option<tokio::task::JoinHandle<()>>>>,
    pub broadcast_tx: broadcast::Sender<WSMessage>,
}

impl WSClient {
    pub fn new(url: String, token: String) -> Self {
        let (broadcast_tx, _) = broadcast::channel(100);
        Self {
            url,
            token,
            state: Arc::new(Mutex::new(WSState::Disconnected)),
            tx: Arc::new(Mutex::new(None)),
            rx_handle: Arc::new(Mutex::new(None)),
            broadcast_tx,
        }
    }

    pub async fn connect(&self) -> Result<(), String> {
        let mut state = self.state.lock().await;
        *state = WSState::Connecting;
        drop(state);

        info!("Connecting to WebSocket: {}", self.url);

        // 构建 WebSocket URL with auth
        let ws_url = format!("{}?token={}", self.url, self.token);

        match connect_async(Url::parse(&ws_url).map_err(|e| e.to_string())?).await {
            Ok((ws_stream, _response)) => {
                info!("WebSocket connected");

                let (write, mut read) = ws_stream.split();

                // 保存写入端
                {
                    let mut tx_guard = self.tx.lock().await;
                    *tx_guard = Some(write);
                }

                // 设置状态为已连接
                {
                    let mut state = self.state.lock().await;
                    *state = WSState::Connected;
                }

                // 启动读取任务
                let rx_handle = {
                    let broadcast_tx = self.broadcast_tx.clone();
                    let state = self.state.clone();
                    tokio::spawn(async move {
                        while let Some(result) = read.next().await {
                            match result {
                                Ok(Message::Text(text)) => {
                                    info!("Received: {}", text);
                                    // 解析消息
                                    if let Ok(msg) = serde_json::from_str::<WSMessage>(&text) {
                                        let _ = broadcast_tx.send(msg);
                                    }
                                }
                                Ok(Message::Binary(data)) => {
                                    info!("Received binary: {} bytes", data.len());
                                }
                                Ok(Message::Ping(_data)) => {
                                    info!("Ping received");
                                    // Pong 会在 WebSocket 层自动处理
                                }
                                Ok(Message::Pong(_)) => {
                                    info!("Pong received");
                                }
                                Ok(Message::Close(_)) => {
                                    info!("Close received");
                                    let mut state = state.lock().await;
                                    *state = WSState::Disconnected;
                                    break;
                                }
                                Ok(Message::Frame(_)) => {}
                                Err(e) => {
                                    error!("WebSocket error: {}", e);
                                    let mut state = state.lock().await;
                                    *state = WSState::Disconnected;
                                    break;
                                }
                            }
                        }
                    })
                };

                {
                    let mut rx_handle_guard = self.rx_handle.lock().await;
                    *rx_handle_guard = Some(rx_handle);
                }

                Ok(())
            }
            Err(e) => {
                error!("Failed to connect: {}", e);
                let mut state = self.state.lock().await;
                *state = WSState::Disconnected;
                Err(e.to_string())
            }
        }
    }

    pub async fn disconnect(&self) {
        info!("Disconnecting WebSocket...");

        // 取消读取任务
        if let Some(handle) = self.rx_handle.lock().await.take() {
            handle.abort();
        }

        // 关闭写入端
        if let Some(mut tx) = self.tx.lock().await.take() {
            let _ = tx.send(Message::Close(None)).await;
        }

        let mut state = self.state.lock().await;
        *state = WSState::Disconnected;

        info!("WebSocket disconnected");
    }

    pub async fn send(&self, message: WSMessage) -> Result<(), String> {
        let state = self.state.lock().await;
        if *state != WSState::Connected {
            return Err("WebSocket not connected".to_string());
        }
        drop(state);

        let json = serde_json::to_string(&message).map_err(|e| e.to_string())?;

        let mut tx_opt = self.tx.lock().await;
        if let Some(tx) = tx_opt.as_mut() {
            tx.send(Message::Text(json)).await.map_err(|e| e.to_string())?;
            Ok(())
        } else {
            Err("WebSocket sender not initialized".to_string())
        }
    }

    pub async fn send_message(&self, conversation_id: i64, content: String) -> Result<(), String> {
        let message = WSMessage {
            r#type: "message:send".to_string(),
            payload: serde_json::json!({
                "conversation_id": conversation_id,
                "content": content,
                "message_type": "text"
            }),
            timestamp: chrono::Utc::now().timestamp_millis(),
        };
        self.send(message).await
    }

    pub async fn send_read_receipt(&self, message_id: i64) -> Result<(), String> {
        let message = WSMessage {
            r#type: "message:read".to_string(),
            payload: serde_json::json!({
                "message_id": message_id,
                "timestamp": chrono::Utc::now().timestamp_millis(),
            }),
            timestamp: chrono::Utc::now().timestamp_millis(),
        };
        self.send(message).await
    }

    pub async fn subscribe_conversation(&self, conversation_id: i64) -> Result<(), String> {
        let message = WSMessage {
            r#type: "conversation:subscribe".to_string(),
            payload: serde_json::json!({
                "conversation_id": conversation_id,
            }),
            timestamp: chrono::Utc::now().timestamp_millis(),
        };
        self.send(message).await
    }

    pub fn subscribe_messages(&self) -> broadcast::Receiver<WSMessage> {
        self.broadcast_tx.subscribe()
    }

    pub async fn get_state(&self) -> WSState {
        self.state.lock().await.clone()
    }

    pub async fn send_heartbeat(&self) -> Result<(), String> {
        let message = WSMessage {
            r#type: "heartbeat".to_string(),
            payload: serde_json::json!({
                "timestamp": chrono::Utc::now().timestamp_millis(),
            }),
            timestamp: chrono::Utc::now().timestamp_millis(),
        };
        self.send(message).await
    }
}

// 创建 WebSocket 连接
#[tauri::command]
pub async fn ws_connect(
    url: String,
    token: String,
    window: tauri::Window,
) -> Result<(), String> {
    info!("WS Connect command called: {}", url);

    let ws_client = Arc::new(WSClient::new(url, token));

    // 连接到 WebSocket
    ws_client.connect().await?;

    // 设置消息监听器，转发到前端
    let window_clone = window.clone();
    let mut rx = ws_client.subscribe_messages();

    tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            // 转发消息到前端
            let _ = window_clone.emit("ws-message", msg);
        }
    });

    // 存储客户端到 window state
    window.manage(ws_client);

    Ok(())
}

#[tauri::command]
pub async fn ws_disconnect(window: tauri::Window) -> Result<(), String> {
    if let Some(client) = window.try_state::<Arc<WSClient>>() {
        client.disconnect().await;
        Ok(())
    } else {
        Err("WebSocket client not found".to_string())
    }
}

#[tauri::command]
pub async fn ws_send_message(
    conversation_id: i64,
    content: String,
    window: tauri::Window,
) -> Result<(), String> {
    if let Some(client) = window.try_state::<Arc<WSClient>>() {
        client.send_message(conversation_id, content).await
    } else {
        Err("WebSocket client not found".to_string())
    }
}

#[tauri::command]
pub async fn ws_send_read_receipt(
    message_id: i64,
    window: tauri::Window,
) -> Result<(), String> {
    if let Some(client) = window.try_state::<Arc<WSClient>>() {
        client.send_read_receipt(message_id).await
    } else {
        Err("WebSocket client not found".to_string())
    }
}

#[tauri::command]
pub async fn ws_get_state(window: tauri::Window) -> Result<String, String> {
    if let Some(client) = window.try_state::<Arc<WSClient>>() {
        let state = client.get_state().await;
        Ok(format!("{:?}", state))
    } else {
        Err("WebSocket client not found".to_string())
    }
}
