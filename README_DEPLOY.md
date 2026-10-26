# CS203 DLD — Fault-Resilient Secure FSM Interactive Website Deployment Bundle

This folder is a complete, zero-dependency static web application bundle for the **Fault-Resilient Secure Finite State Machine (CS203 Digital Logic Design)** project.

## Included Files
- `index.html`: Self-contained interactive hardware simulator (all 8 Verilog RTL modules, live gate-level schematic SVG, GTKWave timing waveform analyzer, 202-fault exhaustive benchmark explorer, and interactive C++ checker runner).
- `vercel.json`: One-click Vercel configuration.
- `netlify.toml`: One-click Netlify configuration.

## 3 Ways to Host Live in Under 60 Seconds

### 1. GitHub Pages (Recommended — Host directly from your `fsm-security-dld` repo)
1. Copy `index.html` into the root of your `fsm-security-dld` repository.
2. Commit and push:
   ```bash
   git add index.html
   git commit -m "Host interactive FSM security simulator website"
   git push origin main
   ```
3. On GitHub, go to **Settings → Pages**, set **Source** to `Deploy from a branch`, select `main` and `/ (root)`, and click **Save**.

### 2. Netlify Drop (Instant Drag & Drop — No Account/CLI Needed)
1. Go to https://app.netlify.com/drop
2. Drag and drop this zip archive (`fsm_security_website_deploy.zip`) or unzipped folder onto the page.
3. Your interactive simulator will be live on a public HTTPS URL immediately.

### 3. Local Demo Server
```bash
python3 -m http.server 8080
```
Then open `http://localhost:8080` in any browser.
