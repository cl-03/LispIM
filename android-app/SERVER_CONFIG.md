# Android Client Server Configuration

## Server URL Configuration

### Default Configuration (Android Emulator)

The Android client is configured to use `10.0.2.2:8443` as the default server address, which is the Android emulator's special address to access the host machine's loopback interface.

- **Default HTTP URL**: `http://10.0.2.2:8443`
- **Default WebSocket URL**: `ws://10.0.2.2:8443/ws`

### Running on Different Environments

#### Android Emulator
The default configuration works out-of-the-box with the Android emulator:
- `10.0.2.2` maps to your host machine's `127.0.0.1` (localhost)
- No configuration changes needed

#### Physical Android Device
When running on a physical device, you need to configure the server URL:

1. **Same Local Network**: Use your development machine's local IP address
   - Example: `http://192.168.1.100:8443`
   - Make sure your Lisp server is listening on `0.0.0.0` (not just `127.0.0.1`)

2. **Production Server**: Use your production server's domain or IP
   - Example: `https://api.lispim.example.com`
   - Ensure SSL/TLS is properly configured

#### iOS Simulator (if applicable)
For iOS Simulator, use `localhost:8443` as it maps directly to the host machine.

### Server Configuration

Make sure your Lisp server is configured to accept connections:

```lisp
;; In server.lisp or configuration
:host "0.0.0.0"  ;; Listen on all interfaces, not just localhost
:port 8443
```

### Changing Server URL in the App

The server URL can be changed in the login screen:
1. Open the app
2. On the login screen, tap the "Server URL" field
3. Enter your server URL (e.g., `http://192.168.1.100:8443`)
4. The WebSocket URL will be automatically derived
5. Login with your credentials

### Troubleshooting

#### "Connection refused" error
- Verify the Lisp server is running: `ps aux | grep sbcl`
- Check server is listening: `netstat -tlnp | grep 8443`
- Ensure firewall allows connections on port 8443

#### "Unable to connect to server" on physical device
- Verify device and development machine are on the same network
- Check server is listening on `0.0.0.0` not `127.0.0.1`
- Try pinging your development machine from the device

#### WebSocket connection fails
- Ensure the WebSocket endpoint is available at `/ws`
- Check for proxy/firewall blocking WebSocket connections
- Verify the server supports WebSocket upgrades

### Security Notes

- **Development**: HTTP is acceptable for local development
- **Production**: Always use HTTPS/WSS with valid SSL certificates
- **Cleartext Traffic**: The app currently allows cleartext traffic (`android:usesCleartextTraffic="true"`) for development. For production, this should be disabled and all connections should use TLS.
