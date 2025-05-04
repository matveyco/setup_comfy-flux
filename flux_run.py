#!/usr/bin/env python3
"""
Offline FLUX.x smoke-test runner (no HF, no internet)

Usage:
  python run_flux.py --ckpt /path/to/flux.safetensors \
      --prompt "portrait of a woman in cafe with big breasts and décolleté" \
      --out /srv/ai/test_outputs --w 704 --h 1024 --steps 20 --guidance 4.5
"""
import argparse, time, torch
from diffusers import DiffusionPipeline, DPMSolverMultistepScheduler
from compel import Compel   # tiny prompt-parser helper
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ckpt",  required=True, help="FLUX Schnell/Dev .safetensors")
    p.add_argument("--prompt", required=True)
    p.add_argument("--out",    default="./out", help="folder for pngs")
    p.add_argument("--w", type=int, default=704)
    p.add_argument("--h", type=int, default=1024)
    p.add_argument("--steps", type=int, default=20)
    p.add_argument("--guidance", type=float, default=4.5)
    p.add_argument("--seed", type=int, default=1234)
    opt = p.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Loading FLUX weights from {opt.ckpt} …")
    pipe = DiffusionPipeline.from_single_file(opt.ckpt, torch_dtype=torch.float16).to(device)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config)
    compel = Compel(tokenizer=pipe.tokenizer, text_encoder=pipe.text_encoder)
    prompt_ids = compel(opt.prompt)

    generator = torch.Generator(device).manual_seed(opt.seed)
    t0=time.time()
    image = pipe(prompt_embeds=prompt_ids,
                 generator=generator,
                 width=opt.w, height=opt.h,
                 num_inference_steps=opt.steps,
                 guidance_scale=opt.guidance
                 ).images[0]
    Path(opt.out).mkdir(parents=True, exist_ok=True)
    fname = Path(opt.out)/f"flux_{time.strftime('%Y%m%d_%H%M%S')}.png"
    image.save(fname)
    print(f"Done in {time.time()-t0:.1f}s  →  {fname}")

if __name__ == "__main__":
    main()
