# iOS MVP Notes

## Current status

The app builds as a minimal iPhone-first SwiftUI client and covers this path:

1. enter a host and port
2. check `GET /health` and `GET /host/info`
3. start pairing and display the returned pairing code
4. paste and validate a bearer token
5. save hosts and tokens locally
6. list authenticated sessions
7. attach to a session over WebSocket
8. observe live terminal output
9. request and release control
10. send terminal input
11. send terminal resize updates
12. show disconnected and exited states

## Intentional limitations

- Pairing completion is manual for now.
  - The current daemon contract exposes `POST /pairing/request` and host-admin approval, but it does not expose a remote client endpoint for the requester to poll or claim the approved token.
  - The app therefore shows the pairing code and expects the token returned by the host admin UI to be pasted into the iPhone client.
- Terminal rendering uses a narrow native abstraction.
  - PTY bytes are base64-decoded and rendered as lossy UTF-8 text.
  - Basic ANSI CSI escape sequences are stripped instead of fully interpreted.
  - This keeps the transport contract correct while leaving the rendering layer easy to replace later.
- Input is a plain text field, not a full mobile terminal keyboard.
- Session creation, file views, git views, discovery, and settings polish are intentionally omitted from this first slice.

## Replacement seams

- `HostClient` isolates REST calls.
- `SessionSocket` isolates WebSocket attach/events/commands.
- `TerminalEngine` isolates terminal decoding/rendering so a better renderer can replace it later.
- `SavedHostsStore` and `KeychainTokenStore` keep persistence out of the UI layer.
