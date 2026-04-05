const WebSocket = require('ws');

const API_BASE = 'http://localhost:3000/api/v1';

async function login(username, password) {
    const response = await fetch(`${API_BASE}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password })
    });
    const data = await response.json();
    return data.data;
}

async function getConversations(token) {
    const response = await fetch(`${API_BASE}/chat/conversations`, {
        headers: { 'Authorization': `Bearer ${token}` }
    });
    const data = await response.json();
    return data.data;
}

async function sendMessageViaWS(ws, conversationId, content) {
    return new Promise((resolve, reject) => {
        const msgId = Date.now();
        const message = {
            type: 'message',
            'message-id': msgId,
            'ack-required': true,
            payload: {
                'conversation-id': conversationId,
                content: content,
                type: 'text'
            }
        };

        const timeout = setTimeout(() => {
            reject(new Error('Timeout waiting for message response'));
        }, 5000);

        const handler = (data) => {
            const str = typeof data === 'string' ? data : data.toString();
            let msg;
            try {
                msg = JSON.parse(str);
            } catch (e) {
                // Already parsed
                msg = data;
            }
            if (msg.type === 'message' && msg.payload?.content === content) {
                clearTimeout(timeout);
                ws.removeEventListener('message', handler);
                resolve(msg);
            } else if (msg.type === 'error') {
                clearTimeout(timeout);
                ws.removeEventListener('message', handler);
                reject(new Error(msg.payload?.message || 'Send error'));
            }
        };

        ws.addEventListener('message', handler);
        ws.send(JSON.stringify(message));
    });
}

async function testWebSocket() {
    console.log('[Test] Logging in...');
    const { userid, token } = await login('test', 'test123');
    console.log(`[Test] Logged in as ${userid}, token: ${token}`);

    const ws = new WebSocket(`ws://localhost:3000/websocket?token=${token}`);

    ws.on('open', () => {
        console.log('[Test] WebSocket connected');
    });

    let messageCount = 0;
    ws.on('message', (data) => {
        const str = typeof data === 'string' ? data : data.toString();
        let msg;
        try {
            msg = JSON.parse(str);
        } catch (e) {
            // Already parsed
            msg = data;
        }
        const raw = str;
        console.log(`[Test] Raw message: ${raw}`);
        messageCount++;
        console.log(`[Test] Received message #${messageCount}:`, msg.type);
        if (msg.type === 'authResponse') {
            console.log('[Test] Auth response:', JSON.stringify(msg.payload, null, 2));
        } else if (msg.type === 'message') {
            console.log('[Test] Chat message received:', JSON.stringify(msg.payload, null, 2));
        } else if (msg.type === 'ping') {
            console.log('[Test] Ping received');
        } else if (msg.type === 'pong') {
            console.log('[Test] Pong received');
        } else {
            console.log('[Test] Other message:', JSON.stringify(msg, null, 2));
        }
    });

    ws.on('error', (err) => {
        console.error('[Test] WebSocket error:', err.message);
    });

    ws.on('close', (code, reason) => {
        console.log(`[Test] WebSocket closed: code=${code}, reason=${reason}`);
    });

    // Wait for auth response
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Get conversations
    const conversations = await getConversations(token);
    console.log('[Test] Conversations:', conversations.length);
    if (conversations.length > 0) {
        console.log('[Test] First conversation:', conversations[0]);
    }

    // Try to send a message via WebSocket
    if (conversations.length > 0) {
        const convId = conversations[0].id;
        console.log(`[Test] Sending message to conversation ${convId} via WebSocket...`);

        try {
            const response = await sendMessageViaWS(ws, convId, 'Hello from WebSocket!');
            console.log('[Test] Message sent successfully via WebSocket:', response);
        } catch (err) {
            console.error('[Test] Failed to send via WebSocket:', err.message);
        }
    }

    // Keep connection open longer
    console.log('[Test] Keeping connection open for 10 seconds...');
    await new Promise(resolve => setTimeout(resolve, 10000));

    ws.close();
    console.log('[Test] Test complete');
}

testWebSocket().catch(console.error);
