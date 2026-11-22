"""Depth Anything V2 (Raw): depth maps with their scale kept, for a depth-of-field step done outside ComfyUI.

kijai's ComfyUI-DepthAnythingV2 'Depth Anything V2' node rescales every map to 0-1 per image, the metric
models included, so a metric map loses its metres. This node takes the model from kijai's loader
(DownloadAndLoadDepthAnythingV2Model) and runs it without that rescaling:
  metric model:   depth in metres divided by the model's max_depth (hypersim: 20 m), so value x max_depth = metres
  relative model: the model's relative inverse depth (disparity) divided by its own maximum (1 = nearest)
Output: a one-channel IMAGE at the input's size, meant for 'Save Image (Advanced)' as a 16-bit PNG
(0.3 mm steps for the 20 m metric model). The value scale is also returned as a FLOAT.
input_size: the short side the model sees, rounded to a multiple of 14, aspect kept (518 is the size both
model families were trained and published at); 0 runs the image at its own size, as kijai's node does.
Single file, loaded by ComfyUI from custom_nodes/; needs ComfyUI-DepthAnythingV2 for the loader.
"""
from contextlib import nullcontext

import torch
import torch.nn.functional as F
from torchvision import transforms

import comfy.model_management as mm


class DepthAnythingV2Raw:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "da_model": ("DAMODEL",),
            "images": ("IMAGE",),
            "input_size": ("INT", {"default": 518, "min": 0, "max": 8190, "step": 14,
                                   "tooltip": "short side the model sees (multiple of 14); 0 = the image's own size"}),
        }}

    RETURN_TYPES = ("IMAGE", "FLOAT")
    RETURN_NAMES = ("depth", "scale")
    FUNCTION = "process"
    CATEGORY = "DepthAnythingV2"

    def process(self, da_model, images, input_size):
        device = mm.get_torch_device()
        model, dtype, metric = da_model["model"], da_model["dtype"], da_model["is_metric"]
        B, H, W, _ = images.shape
        if input_size > 0:
            k = input_size / min(H, W)
            h, w = max(14, round(H * k / 14) * 14), max(14, round(W * k / 14) * 14)
        else:
            h, w = max(14, H - H % 14), max(14, W - W % 14)
        x = images[..., :3].permute(0, 3, 1, 2).float()
        if (h, w) != (H, W):
            x = F.interpolate(x, size=(h, w), mode="bicubic", align_corners=False, antialias=True).clamp(0, 1)
        x = transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])(x)
        model.to(device)
        auto = dtype != torch.float32 and not mm.is_device_mps(device)
        out = []
        with torch.no_grad(), (torch.autocast(mm.get_autocast_device(device), dtype=dtype) if auto else nullcontext()):
            for img in x:
                d = model(img.unsqueeze(0).to(device)).float()                     # 1 x h x w
                d = F.interpolate(d.unsqueeze(1), size=(H, W), mode="bilinear", align_corners=True)[:, 0]
                if metric:
                    d = d / float(model.max_depth)
                else:
                    d = d / d.max().clamp(min=1e-6)
                out.append(d.clamp(0, 1).cpu())
        model.to(mm.unet_offload_device())
        mm.soft_empty_cache()
        scale = float(model.max_depth) if metric else 1.0
        return (torch.cat(out, 0).unsqueeze(-1), scale)


NODE_CLASS_MAPPINGS = {"DepthAnythingV2Raw": DepthAnythingV2Raw}
NODE_DISPLAY_NAME_MAPPINGS = {"DepthAnythingV2Raw": "Depth Anything V2 (Raw)"}
