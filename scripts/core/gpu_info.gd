class_name GpuInfo
extends RefCounted
## Hardware heuristics shared by the quality presets (dev_hud.gd) and effect fallbacks (katana.gd).


## True for integrated GPUs. The type check alone isn't enough: Godot's D3D12 backend reports
## Intel iGPUs as *discrete* (seen on UHD G1), so Intel iGPUs are also matched by name.
static func is_integrated() -> bool:
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU \
			or is_intel_integrated()


## Intel UHD / Iris / HD Graphics: anything from Intel that isn't a discrete Arc card.
static func is_intel_integrated() -> bool:
	return RenderingServer.get_video_adapter_vendor().containsn("intel") \
			and not RenderingServer.get_video_adapter_name().containsn("arc")
