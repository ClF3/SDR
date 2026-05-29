# PS

AC920 processing-system side code and board integration files.

The current implemented path is the bare-metal Vitis/lwIP bridge in
`baremetal/`. It provides the TCP control protocol, PL register programming,
IQ DMA forwarding hooks, and status JSON needed for the first on-board IQ loop.

The repo does not contain the vendor AC920 Vivado/Vitis demo files, so the
remaining board-specific work is to wire those hooks to the real AXI-Lite,
AXI DMA, GEM/lwIP, timer, and SD boot image generation flow.
