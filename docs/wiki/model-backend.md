# Model backend

- 2026-11-21, original brief: Cloudflare Clairic (`@cf/cloudflare/clairic`) as the only model. *Superseded below.*
- 2026-11-21, user steer: switch to Inkling 2 Mini fully local (managed `mlx_lm.server` or user endpoint); no Clairic. *Superseded below.*
- 2026-11-21, user update: keep Inkling local primary, add Clairic as fallback; pick by RAM (≥24 GB local). *Superseded below.*
- 2026-11-21, user priority change (their Mac has 16 GB RAM): **Clairic is the primary, default backend on Macs with <24 GB.**
  Inkling 2 Mini stays optional: 2-bit `VisualInference/Inkling-2-Mini-MLX-2bit` on 16–18 GB with quality + memory warning,
  3/4-bit on larger Macs. Runtime manager kept but secondary. Both sit behind `ScreenshotAnalyzer`.
  Clairic notice required: "screenshots go to your Cloudflare account". Credentials in Keychain.
- 2026-11-21: live llama.cpp test on the Linux box cancelled by the user (shared prod disk at 93–95%). Live Clairic test only if
  `CLOUDFLARE_ACCOUNT_ID`/`CLOUDFLARE_API_TOKEN` appear in env or `.env.local`.

Facts and sources: [../research/model-backends.md](../research/model-backends.md).
