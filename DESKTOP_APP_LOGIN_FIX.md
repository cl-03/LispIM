# LispIM Desktop App Login Fix

## Problem Summary

The desktop app was receiving HTML instead of JSON when trying to login, causing the error:
```
Login error: SyntaxError: Unexpected token '<', "<html><hea"... is not valid JSON
```

## Root Cause

The desktop app (Tauri client) was making requests to `/api/auth/login` but the backend only has `/api/v1/auth/login` endpoint (with the `/v1` version prefix).

Server logs showed:
```
POST /api/api/v1/auth/login HTTP/1.1" 404
```

This indicates the request path was being doubled because:
1. The Tauri backend had a hardcoded base URL that included `/api`
2. The endpoint path also included `/api`, resulting in `/api/api/v1/auth/login`

## What Was Fixed

### 1. Tauri Backend API Endpoints (`tauri-client/src-tauri/src/main.rs`)

Updated all API endpoint paths to use `/api/v1`:

- `login`: Changed from `/api/auth/login` to `/api/v1/auth/login`
- `get_user_info`: Changed from `/api/users/{userId}` to `/api/v1/users/{userId}`
- `get_conversations`: Changed from `/api/conversations` to `/api/v1/conversations`
- `get_history`: Changed from `/api/conversations/{id}/messages` to `/api/v1/conversations/{id}/messages`

### 2. Tauri Frontend Login Component (`tauri-client/src/components/Login.tsx`)

Updated the login component to call the actual Tauri login command instead of using mock data:

```typescript
import { login as tauriLogin } from '@/utils/tauri-api'

const handleSubmit = async (e: React.FormEvent) => {
  e.preventDefault()
  setLoading(true)
  setError('')

  try {
    const response = await tauriLogin(username, password)
    // ... handle response
  } catch (err) {
    setError(err.message)
  }
}
```

### 3. Created Tauri API Client (`tauri-client/src/utils/tauri-api.ts`)

New utility file for calling Tauri backend commands:

```typescript
export async function login(username: string, password: string): Promise<AuthResponse>
export async function logout(): Promise<void>
export async function getWsUrl(): Promise<string | null>
export async function getUserInfo(userId: string): Promise<User>
export async function getConversations(): Promise<Conversation[]>
export async function getHistory(conversationId: number, limit?: number): Promise<Message[]>
```

## Build Output

The desktop app has been successfully rebuilt with the fixed API endpoints.

**Built executables:**
- Standalone: `D:\Claude\LispIM\tauri-client\src-tauri\target\release\LispIM Enterprise.exe`
- MSI Installer: `D:\Claude\LispIM\tauri-client\src-tauri\target\release\bundle\msi\LispIM Enterprise_0.1.0_x64_en-US.msi`
- NSIS Installer: `D:\Claude\LispIM\tauri-client\src-tauri\target\release\bundle\nsis\LispIM Enterprise_0.1.0_x64-setup.exe`

## How to Run

1. Make sure the backend server is running on `http://localhost:3000`
2. Run the desktop app: `D:\Claude\LispIM\tauri-client\src-tauri\target\release\LispIM Enterprise.exe`
3. Login with test credentials:
   - Username: `newtest`
   - Password: `test123`

## Additional Fixes Applied

### Conflicting Tauri Config

Found and fixed a conflicting Tauri v2 config file (`tauri-client/tauri.conf.json`) that was causing build failures. The v2 config was renamed to `tauri.conf.json.v2.bak`.

### Duplicate Function Definition

Removed duplicate `ws_send` function in `src-tauri/src/websocket.rs` that was causing compilation errors.

## Files Changed

1. `tauri-client/src-tauri/src/main.rs` - Fixed API endpoint paths
2. `tauri-client/src/components/Login.tsx` - Updated to use real API calls
3. `tauri-client/src/utils/tauri-api.ts` - New Tauri API client
4. `tauri-client/src/utils/index.ts` - Export tauri-api module
5. `tauri-client/src-tauri/src/websocket.rs` - Removed duplicate ws_send function
6. `tauri-client/src-tauri/tauri.conf.json` - Fixed schema reference
7. `tauri-client/tauri.conf.json` - Renamed to .v2.bak (was conflicting v2 format)

## Verification

The backend API is confirmed working:
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"newtest","password":"test123"}'
```

Returns:
```json
{
  "success": true,
  "data": {
    "userid": "166266346143744000",
    "username": "newtest",
    "token": "..."
  }
}
```

## Web Frontend Status

The web frontend at `http://localhost:3001` should work correctly through the Vite proxy. No changes needed there.
