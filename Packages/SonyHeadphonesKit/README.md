# SonyHeadphonesKit

Vendored from Rui Martins' MIT-licensed XM6 Control (the sibling `xm6-control`
checkout). Only the protocol, models, and RFCOMM transport are included.

Notch adaptations: injectable per-attempt transport and deadlines, cancellation
and stale-session protection, read-only connection initialization, sandbox-local
opt-in logging, and coalescing queued custom EQ writes. No standalone app target.

Run `swift test` from this directory on macOS with Xcode selected via
`DEVELOPER_DIR` if necessary. Hardware-free tests use a fake transport.
