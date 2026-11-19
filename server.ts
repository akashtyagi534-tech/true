import express from 'express';
import fs from 'fs';
import path from 'path';
import JSZip from 'jszip';
import {createServer as createViteServer} from 'vite';

const PORT = 3000;
const MOBILE_REPO_ROOT = path.resolve(process.cwd(), 'truth-verify-app');
const V3_REPO_ROOT = path.resolve(process.cwd(), 'truth-lens-v3-pro');

interface RepoFile {
  path: string;
  content: string;
  size: number;
  lines: number;
  language: string;
}

function detectLanguage(filePath: string): string {
  if (filePath.endsWith('.py')) return 'python';
  if (filePath.endsWith('.dart')) return 'dart';
  if (filePath.endsWith('.html')) return 'html';
  if (filePath.endsWith('.js')) return 'javascript';
  if (filePath.endsWith('.css')) return 'css';
  if (filePath.endsWith('.yml') || filePath.endsWith('.yaml')) return 'yaml';
  if (filePath.endsWith('.json')) return 'json';
  if (filePath.endsWith('Dockerfile')) return 'dockerfile';
  if (filePath.endsWith('.txt')) return 'text';
  return 'plaintext';
}

function collectRepoFiles(dir: string, prefix = ''): RepoFile[] {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, {withFileTypes: true});
  entries.sort((a, b) => {
    if (a.isDirectory() && !b.isDirectory()) return -1;
    if (!a.isDirectory() && b.isDirectory()) return 1;
    return a.name.localeCompare(b.name);
  });

  const results: RepoFile[] = [];
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    const relPath = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      results.push(...collectRepoFiles(fullPath, relPath));
    } else {
      const content = fs.readFileSync(fullPath, 'utf-8');
      results.push({
        path: relPath,
        content,
        size: Buffer.byteLength(content, 'utf-8'),
        lines: content.split('\n').length,
        language: detectLanguage(relPath),
      });
    }
  }
  return results;
}

function sanitizeBaseUrl(raw?: string): string {
  if (!raw || typeof raw !== 'string') return '';
  const trimmed = raw.trim().replace(/\/+$/, '');
  if (trimmed === 'https://truth-verify-production.up.railway.app') return '';
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return '';
  }
  return trimmed;
}

function sanitizeRepoName(raw?: string, fallback = 'True-'): string {
  if (!raw || typeof raw !== 'string') return fallback;
  const cleaned = raw.trim().replace(/[^a-zA-Z0-9._-]/g, '');
  return cleaned || fallback;
}

function resolveBundle(raw?: string): {bundle: 'v3' | 'mobile'; rootDir: string; defaultRepo: string} {
  if (raw === 'v3') {
    return {bundle: 'v3', rootDir: V3_REPO_ROOT, defaultRepo: 'truth-lens-v3-pro'};
  }
  return {bundle: 'mobile', rootDir: MOBILE_REPO_ROOT, defaultRepo: 'True-'};
}

function applyRailwayUrl(files: RepoFile[], baseUrl: string): RepoFile[] {
  return files.map((file) => {
    if (file.path === 'flutter_app/lib/api_service.dart') {
      const updated = file.content.replace(
        /this\.baseUrl\s*=\s*'[^']*'/,
        `this.baseUrl = '${baseUrl}'`,
      );
      return {
        ...file,
        content: updated,
        size: Buffer.byteLength(updated, 'utf-8'),
        lines: updated.split('\n').length,
      };
    }
    return file;
  });
}

async function startServer() {
  const app = express();
  app.use(express.json({limit: '2mb'}));

  app.get('/api/project/files', (req, res) => {
    try {
      const {bundle, rootDir, defaultRepo} = resolveBundle(req.query.bundle as string | undefined);
      const baseUrl = sanitizeBaseUrl(req.query.baseUrl as string | undefined);
      const repoName = sanitizeRepoName(req.query.repoName as string | undefined, defaultRepo);
      const files = applyRailwayUrl(collectRepoFiles(rootDir), baseUrl);
      res.json({
        bundle,
        rootName: repoName,
        baseUrl,
        totalFiles: files.length,
        files,
      });
    } catch (err) {
      res.status(500).json({error: err instanceof Error ? err.message : 'Failed to read repository files'});
    }
  });

  app.get('/api/project/download', async (req, res) => {
    try {
      const {rootDir, defaultRepo} = resolveBundle(req.query.bundle as string | undefined);
      const baseUrl = sanitizeBaseUrl(req.query.baseUrl as string | undefined);
      const repoName = sanitizeRepoName(req.query.repoName as string | undefined, defaultRepo);
      const files = applyRailwayUrl(collectRepoFiles(rootDir), baseUrl);

      const zip = new JSZip();
      const rootFolder = zip.folder(repoName);
      if (!rootFolder) {
        throw new Error('Could not initialize zip archive');
      }

      for (const file of files) {
        rootFolder.file(file.path, file.content);
      }

      const buffer = await zip.generateAsync({
        type: 'nodebuffer',
        compression: 'DEFLATE',
        compressionOptions: {level: 6},
      });

      res.setHeader('Content-Type', 'application/zip');
      res.setHeader('Content-Disposition', `attachment; filename="${repoName}.zip"`);
      res.send(buffer);
    } catch (err) {
      res.status(500).json({error: err instanceof Error ? err.message : 'Failed to generate ZIP'});
    }
  });

  app.post('/api/railway/health', async (req, res) => {
    const rawUrl = typeof req.body?.baseUrl === 'string' ? req.body.baseUrl.trim().replace(/\/+$/, '') : '';
    if (!rawUrl || (!rawUrl.startsWith('https://') && !rawUrl.startsWith('http://'))) {
      res.status(400).json({ok: false, error: 'Enter a valid http:// or https:// Railway URL.'});
      return;
    }
    if (rawUrl.includes('railway.com/project/') || rawUrl.includes('railway.app/project/')) {
      res.status(400).json({
        ok: false,
        error:
          'Yeh Railway Dashboard ka private link hai. Apni backend service ke Settings -> Networking -> Generate Domain se mila public URL (https://....up.railway.app) dalein.',
      });
      return;
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 7000);
    const start = Date.now();

    try {
      const response = await fetch(`${rawUrl}/health`, {
        method: 'GET',
        signal: controller.signal,
      });
      const latencyMs = Date.now() - start;
      const text = await response.text();
      let payload: unknown = text;
      try {
        payload = JSON.parse(text);
      } catch {
        // leave as plain text
      }
      res.json({
        ok: response.ok,
        status: response.status,
        latencyMs,
        payload,
      });
    } catch (err) {
      const latencyMs = Date.now() - start;
      res.json({
        ok: false,
        status: 0,
        latencyMs,
        error: err instanceof Error ? err.message : 'Connection failed',
      });
    } finally {
      clearTimeout(timer);
    }
  });

  app.post('/api/admin/proxy', async (req, res) => {
    const rawBase = typeof req.body?.baseUrl === 'string' ? req.body.baseUrl.trim().replace(/\/+$/, '') : '';
    const endpoint = typeof req.body?.endpoint === 'string' ? req.body.endpoint.trim() : '';
    const method = typeof req.body?.method === 'string' ? req.body.method.toUpperCase() : 'GET';
    const token = typeof req.body?.token === 'string' ? req.body.token.trim() : '';
    const payload = req.body?.body;

    if (!rawBase || (!rawBase.startsWith('https://') && !rawBase.startsWith('http://'))) {
      res.status(400).json({error: 'Valid Railway backend URL (https://....up.railway.app) required.'});
      return;
    }
    if (rawBase.includes('railway.com/project/') || rawBase.includes('railway.app/project/')) {
      res.status(400).json({
        error:
          'Yeh Railway Dashboard ka private link hai. Backend service → Settings → Networking → Generate Domain se mila https://....up.railway.app URL dalein.',
      });
      return;
    }
    if (!endpoint.startsWith('/api/') && endpoint !== '/health') {
      res.status(400).json({error: 'Invalid admin endpoint.'});
      return;
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);
    try {
      const headers: Record<string, string> = {};
      if (token) headers['Authorization'] = `Bearer ${token}`;
      if (method !== 'GET' && payload !== undefined) {
        headers['Content-Type'] = 'application/json';
      }
      const upstream = await fetch(`${rawBase}${endpoint}`, {
        method,
        headers,
        body: method !== 'GET' && payload !== undefined ? JSON.stringify(payload) : undefined,
        signal: controller.signal,
      });
      const text = await upstream.text();
      let data: unknown = {detail: text};
      try {
        data = JSON.parse(text);
      } catch {
        // leave wrapped text
      }
      res.status(upstream.status).json(data);
    } catch (err) {
      res.status(502).json({
        error: err instanceof Error ? err.message : 'Could not reach Railway backend.',
      });
    } finally {
      clearTimeout(timer);
    }
  });

  app.get('/api/admin/video-proxy', async (req, res) => {
    const rawBase = typeof req.query.baseUrl === 'string' ? req.query.baseUrl.trim().replace(/\/+$/, '') : '';
    const videoPath = typeof req.query.path === 'string' ? req.query.path.trim() : '';
    if (
      !rawBase ||
      (!rawBase.startsWith('https://') && !rawBase.startsWith('http://')) ||
      !videoPath.startsWith('/api/admin/videos/')
    ) {
      res.status(400).send('Invalid video proxy request');
      return;
    }
    try {
      const upstream = await fetch(`${rawBase}${videoPath}`);
      if (!upstream.ok) {
        res.status(upstream.status).send('Video unavailable');
        return;
      }
      const contentType = upstream.headers.get('content-type') || 'video/mp4';
      const arrayBuf = await upstream.arrayBuffer();
      res.setHeader('Content-Type', contentType);
      res.send(Buffer.from(arrayBuf));
    } catch {
      res.status(502).send('Failed to stream video');
    }
  });

  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: {middlewareMode: true},
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distDir = path.resolve(process.cwd(), 'dist');
    app.use(express.static(distDir));
    app.get('*', (_req, res) => {
      res.sendFile(path.join(distDir, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`TruthVerify Studio server listening on http://localhost:${PORT}`);
  });
}

startServer();
