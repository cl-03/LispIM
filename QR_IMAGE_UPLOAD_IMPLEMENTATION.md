# QR Code Image Upload Feature - Implementation Complete

## Summary

The QR code scanning via file/image upload feature has been implemented for both frontend and backend.

## Frontend Changes

**File: `web-client/src/components/ScanModal.tsx`**

Changes made:
1. Added `fileInputRef` and `uploading` state
2. Implemented `handleImageUpload` function that:
   - Validates the uploaded file type
   - Uploads the image using existing `api.uploadFile()` method
   - Calls backend API `/api/v1/qr/scan-image` with the uploaded image URL
   - Displays the scanned result or error message
3. Added "相册" (Album) button in the UI
4. Added uploading state display with spinner animation
5. Fixed friend request API endpoint to `/api/v1/contacts/friend-request/send`

## Backend Changes

### 1. New Handler: `/api/v1/qr/scan-image`

**File: `lispim-core/src/gateway.lisp`**

Added `api-scan-qr-image-handler` function that:
- Accepts POST request with `imageUrl` in JSON body
- Downloads the image from the URL
- Calls Python script to decode QR code
- Verifies the QR code using existing `decode-and-verify-qr` function
- Returns user information if valid

### 2. Helper Functions

Added two helper functions:
- `download-image-to-file` - Downloads image from URL to local file
- `copy-stream-to-file` - Copies binary stream to file

### 3. Python Script

**File: `lispim-core/scripts/decode_qr.py`**

Created Python script that uses `pyzbar` library to decode QR codes from images.

Dependencies installed:
- `pyzbar-0.1.9`
- `Pillow`
- `qrcode` (for testing)

### 4. Route Registration

Added route dispatcher:
```lisp
(push (hunchentoot:create-regex-dispatcher "^/api/v1/qr/scan-image$" 'api-scan-qr-image-handler)
      hunchentoot:*dispatch-table*)
```

## How It Works

1. User clicks "相册" button in ScanModal
2. User selects an image file containing a QR code
3. Frontend uploads image to `/api/v1/upload` endpoint
4. Frontend calls `/api/v1/qr/scan-image` with the uploaded image URL
5. Backend:
   - Downloads the image
   - Calls Python script to decode QR code
   - Verifies QR code signature and timestamp
   - Returns user information
6. Frontend displays the scanned user profile
7. User can send friend request

## Testing

### Test QR Code Generation
```python
import qrcode
qr = qrcode.make('{"type":"user_profile","userId":"123","username":"testuser","timestamp":1234567890,"signature":"abc123"}')
qr.save('test_qr.png')
```

### Test Python Decoder
```bash
python "D:/Claude/LispIM/lispim-core/scripts/decode_qr.py" "D:/Claude/LispIM/lispim-core/scripts/test_qr.png"
```

Expected output:
```json
{"type":"user_profile","userId":"123","username":"testuser","timestamp":1234567890,"signature":"abc123"}
```

## Restart Backend to Load New Code

To load the new code in the backend, restart the Lisp server:

### Option 1: Full Restart (Recommended)
```powershell
# Stop existing server
Get-Process sbcl | Stop-Process -Force

# Start server
cd D:\Claude\LispIM
.\start.bat
```

### Option 2: Reload from REPL (if running in REPL)
```lisp
(ql:quickload :lispim-core :force t)
(lispim-core:start-gateway)
```

## API Request Format

### Request
```json
POST /api/v1/qr/scan-image
{
  "imageUrl": "/api/v1/files/1234567890"
}
```

### Response (Success)
```json
{
  "success": true,
  "user": {
    "id": "166266346143744000",
    "username": "testuser",
    "displayName": "Test User",
    "avatar": ""
  }
}
```

### Response (No QR Code)
```json
{
  "success": false,
  "error": {
    "code": "NO_QR_FOUND",
    "message": "No QR code found in image"
  }
}
```

### Response (Invalid QR)
```json
{
  "success": false,
  "error": {
    "code": "INVALID_QR",
    "message": "Invalid QR code: invalid_signature"
  }
}
```

## Files Changed

1. `web-client/src/components/ScanModal.tsx` - Frontend QR upload UI
2. `lispim-core/src/gateway.lisp` - Backend scan-image handler
3. `lispim-core/scripts/decode_qr.py` - Python QR decoder (new file)

## Next Steps

1. Restart the backend to load the new code
2. Test the feature in the web client
3. Verify the QR code scanning works with real user QR codes
