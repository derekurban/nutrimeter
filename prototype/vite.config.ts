import react from '@vitejs/plugin-react'
import { defineConfig, type ProxyOptions } from 'vite'

// search.openfoodfacts.org does not send CORS headers, so the browser talks to it through
// this proxy. OpenFoodFacts asks API clients to identify themselves with a User-Agent.
const proxy: Record<string, ProxyOptions> = {
  '/off-search': {
    target: 'https://search.openfoodfacts.org',
    changeOrigin: true,
    rewrite: (path) => path.replace(/^\/off-search/, ''),
    headers: { 'User-Agent': 'Nutrimeter-Prototype/0.1 (local dev)' },
  },
}

// The dev server stays on localhost; `tailscale serve` fronts it with HTTPS on the tailnet
// (phones only allow camera access for barcode scanning on secure origins).
const allowedHosts = ['.ts.net']

export default defineConfig({
  plugins: [react()],
  // IPv4 loopback: `tailscale serve` proxies to 127.0.0.1, and this keeps the server off the LAN.
  server: { host: '127.0.0.1', proxy, allowedHosts },
  preview: { proxy, allowedHosts },
})
