# Jomo

ZMK firmware config for the Jomo, a wireless 36-key split keyboard used with
macOS.

## Halves and links

**Central**:
The left half; it holds the BLE connection to the host and forwards the
peripheral's key events.
_Avoid_: master, main half

**Peripheral**:
The right half; it reaches the host only through the central, so its key events
travel two BLE hops.
_Avoid_: slave, secondary half

**Host link**:
The connection between the central and the Mac, over USB or BLE.
_Avoid_: hop, connection

**Split link**:
The BLE connection between the peripheral and the central.
_Avoid_: hop, connection

## Faults

**Spurious repeat**:
An extra character caused by host autorepeat because one physical press's
release arrived late.
_Avoid_: double press, double tap, ghosting

**Chatter**:
A switch producing more than one press/release pair for a single physical
press.
_Avoid_: double press, bounce

## Tmux layer

**Tmux layer**:
Layer 1, held on the Backspace thumb; its right hand drives tmux in kitty. Here
"window" always means a tmux window, never a macOS window.
_Avoid_: tmux cockpit

**Summoning key**:
A tmux-layer key that brings kitty to the front (⌥T) before sending its tmux
command, so it works from any app.

**In-place key**:
A tmux-layer key that acts on whatever has focus, without summoning kitty; the
pane arrows.
_Avoid_: plain key

## Nav layer

**Move-paste**:
The Finder paste that moves the copied files instead of duplicating them (⌥⌘V);
Finder's stand-in for cutting files, which ⌘X does not do.
_Avoid_: cut-paste, file cut
