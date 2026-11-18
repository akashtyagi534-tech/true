import {useMemo, useState} from 'react';
import {Check, Copy, Download, FileCode2, Folder, RefreshCw} from 'lucide-react';
import type {RepoFile, UiLanguage} from '../types/truthVerify';

interface ProjectFilesStudioProps {
  files: RepoFile[];
  isLoading: boolean;
  repoName: string;
  railwayUrl: string;
  onChangeRailwayUrl: (url: string) => void;
  onDownloadZip: () => void;
  isDownloading: boolean;
  language: UiLanguage;
  onChangeLanguage: (lang: UiLanguage) => void;
}

interface HealthResult {
  ok: boolean;
  status: number;
  latencyMs: number;
  payload?: unknown;
  error?: string;
}

export function ProjectFilesStudio({
  files,
  isLoading,
  repoName,
  railwayUrl,
  onChangeRailwayUrl,
  onDownloadZip,
  isDownloading,
  language,
  onChangeLanguage,
}: ProjectFilesStudioProps) {
  const [selectedPath, setSelectedPath] = useState<string>('backend/Dockerfile');
  const [copiedPath, setCopiedPath] = useState<string | null>(null);
  const [copiedNamePath, setCopiedNamePath] = useState<string | null>(null);
  const [testingHealth, setTestingHealth] = useState(false);
  const [healthResult, setHealthResult] = useState<HealthResult | null>(null);

  const activeFile = useMemo(() => {
    return files.find((f) => f.path === selectedPath) ?? files[0] ?? null;
  }, [files, selectedPath]);

  const groupedFiles = useMemo(() => {
    const groups: Record<string, RepoFile[]> = {
      '.github/workflows': [],
      backend: [],
      flutter_app: [],
    };
    for (const file of files) {
      if (file.path.startsWith('.github/')) {
        groups['.github/workflows'].push(file);
      } else if (file.path.startsWith('backend/')) {
        groups.backend.push(file);
      } else {
        groups.flutter_app.push(file);
      }
    }
    return groups;
  }, [files]);

  const handleCopy = async (file: RepoFile) => {
    await navigator.clipboard.writeText(file.content);
    setCopiedPath(file.path);
    setTimeout(() => setCopiedPath(null), 1800);
  };

  const handleCopyFilePath = async (file: RepoFile) => {
    await navigator.clipboard.writeText(file.path);
    setCopiedNamePath(file.path);
    setTimeout(() => setCopiedNamePath(null), 1800);
  };

  const handleTestRailway = async () => {
    setTestingHealth(true);
    setHealthResult(null);
    try {
      const resp = await fetch('/api/railway/health', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({baseUrl: railwayUrl}),
      });
      const data = (await resp.json()) as HealthResult;
      setHealthResult(data);
    } catch (err) {
      setHealthResult({
        ok: false,
        status: 0,
        latencyMs: 0,
        error: err instanceof Error ? err.message : 'Health probe failed',
      });
    } finally {
      setTestingHealth(false);
    }
  };

  return (
    <section className="mx-auto max-w-[1360px] px-6 py-8">
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-6">
        <div className="max-w-2xl">
          <p className="text-xs font-medium text-slate-500">
            Repository Bundle · {repoName} · {files.length} Files Ready
          </p>
          <h1 className="mt-1.5 font-display text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">
            {language === 'hi'
              ? 'पूर्ण GitHub रिपॉजिटरी और Railway कॉन्फ़िगरेशन'
              : 'Complete GitHub Repository & Railway Configurator'}
          </h1>
          <p className="mt-2 text-sm text-slate-600">
            {language === 'hi'
              ? 'नीचे अपना लाइव Railway URL पेस्ट करें — यह स्वतः flutter_app/lib/api_service.dart में जुड़ जाएगा और Download ZIP में शामिल होगा।'
              : 'Set your live Railway domain below to automatically bind it inside flutter_app/lib/api_service.dart and include it in your ZIP export.'}
          </p>
        </div>

        <div className="inline-flex items-center rounded-lg border border-slate-200 bg-slate-100 p-1">
          <button
            type="button"
            onClick={() => onChangeLanguage('hi')}
            className={`rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
              language === 'hi'
                ? 'bg-white text-slate-900 shadow-xs'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            हिन्दी
          </button>
          <button
            type="button"
            onClick={() => onChangeLanguage('en')}
            className={`rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
              language === 'en'
                ? 'bg-white text-slate-900 shadow-xs'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            English
          </button>
        </div>
      </div>

      {/* Railway URL Live Binding Bar */}
      <div className="mb-6 rounded-xl border border-slate-200 bg-white p-5">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end">
          <div className="flex-1">
            <label
              htmlFor="railway-url-input"
              className="block text-xs font-semibold text-slate-800"
            >
              {language === 'hi'
                ? 'Railway लाइव पब्लिक URL (अंत में "/" न लगाएं)'
                : 'Railway Public Domain URL (no trailing "/")'}
            </label>
            <input
              id="railway-url-input"
              type="url"
              value={railwayUrl}
              onChange={(e) => onChangeRailwayUrl(e.target.value)}
              placeholder="https://truth-verify-production.up.railway.app"
              className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
            />
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <button
              type="button"
              onClick={handleTestRailway}
              disabled={testingHealth}
              className="inline-flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-4 py-2 text-xs font-medium text-slate-800 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
            >
              <RefreshCw className={`h-3.5 w-3.5 ${testingHealth ? 'animate-spin' : ''}`} aria-hidden="true" />
              <span>{testingHealth ? 'Checking...' : 'Test /health'}</span>
            </button>

            <button
              type="button"
              onClick={onDownloadZip}
              disabled={isDownloading}
              className="inline-flex items-center gap-2 rounded-lg bg-blue-700 px-4 py-2 text-xs font-medium text-white transition-colors hover:bg-blue-800 whitespace-nowrap shrink-0"
            >
              <Download className="h-3.5 w-3.5" aria-hidden="true" />
              <span>{isDownloading ? 'Generating...' : 'Download Configured ZIP'}</span>
            </button>
          </div>
        </div>

        {healthResult && (
          <div
            className={`mt-4 flex flex-wrap items-center justify-between gap-2 rounded-lg border px-4 py-2.5 text-xs ${
              healthResult.ok
                ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
                : 'border-amber-200 bg-amber-50 text-amber-900'
            }`}
          >
            <span className="font-medium">
              {healthResult.ok
                ? `Connected · HTTP ${healthResult.status} OK`
                : `Unreachable · ${healthResult.error ?? `HTTP ${healthResult.status}`}`}
            </span>
            <span className="font-mono tabular-nums">
              Latency: {healthResult.latencyMs} ms
            </span>
          </div>
        )}
      </div>

      {/* File Explorer Split */}
      <div className="grid grid-cols-1 overflow-hidden rounded-xl border border-slate-200 bg-white lg:grid-cols-12">
        <aside className="border-b border-slate-200 bg-slate-50/70 p-4 lg:col-span-4 lg:border-r lg:border-b-0 xl:col-span-3">
          {isLoading ? (
            <div className="space-y-2 py-4">
              <div className="h-6 rounded bg-slate-200" />
              <div className="h-6 rounded bg-slate-200" />
              <div className="h-6 rounded bg-slate-200" />
            </div>
          ) : (
            <div className="space-y-5">
              {Object.entries(groupedFiles).map(([folderName, items]) => (
                <div key={folderName}>
                  <div className="mb-1.5 flex items-center gap-2 px-2 text-xs font-semibold text-slate-600">
                    <Folder className="h-3.5 w-3.5 text-slate-400" aria-hidden="true" />
                    <span className="font-mono">{folderName}/</span>
                  </div>
                  <div className="space-y-0.5">
                    {items.map((file) => {
                      const active = activeFile?.path === file.path;
                      const displayPath = file.path.replace(`${folderName}/`, '');
                      return (
                        <button
                          key={file.path}
                          type="button"
                          onClick={() => setSelectedPath(file.path)}
                          className={`flex w-full items-center justify-between gap-2 rounded-lg px-2.5 py-2 text-left text-xs transition-colors ${
                            active
                              ? 'bg-white font-medium text-blue-700 shadow-xs'
                              : 'text-slate-700 hover:bg-slate-100'
                          }`}
                        >
                          <span className="flex min-w-0 items-center gap-2">
                            <FileCode2 className="h-3.5 w-3.5 shrink-0 text-slate-400" aria-hidden="true" />
                            <span className="truncate font-mono">{displayPath}</span>
                          </span>
                          <span className="shrink-0 font-mono text-[11px] text-slate-400 tabular-nums">
                            {file.lines}L
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          )}
        </aside>

        <div className="flex min-w-0 flex-col lg:col-span-8 xl:col-span-9">
          {activeFile ? (
            <>
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-3.5">
                <div className="min-w-0">
                  <p className="truncate font-mono text-xs font-semibold text-slate-900">
                    {repoName}/{activeFile.path}
                  </p>
                  <p className="mt-0.5 font-mono text-[11px] text-slate-500 tabular-nums">
                    {activeFile.language} · {activeFile.lines} lines · {activeFile.size} bytes
                  </p>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    onClick={() => handleCopyFilePath(activeFile)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-700 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
                  >
                    {copiedNamePath === activeFile.path ? (
                      <>
                        <Check className="h-3.5 w-3.5 text-emerald-600" aria-hidden="true" />
                        <span>Path Copied</span>
                      </>
                    ) : (
                      <>
                        <Copy className="h-3.5 w-3.5" aria-hidden="true" />
                        <span>Copy Path</span>
                      </>
                    )}
                  </button>
                  <button
                    type="button"
                    onClick={() => handleCopy(activeFile)}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-medium text-slate-700 transition-colors hover:bg-slate-50 whitespace-nowrap shrink-0"
                  >
                    {copiedPath === activeFile.path ? (
                      <>
                        <Check className="h-3.5 w-3.5 text-emerald-600" aria-hidden="true" />
                        <span>Code Copied</span>
                      </>
                    ) : (
                      <>
                        <Copy className="h-3.5 w-3.5" aria-hidden="true" />
                        <span>Copy Code</span>
                      </>
                    )}
                  </button>
                </div>
              </div>
              <div className="max-h-[620px] overflow-auto bg-slate-950 p-5">
                <pre className="font-mono text-xs leading-6 text-slate-100">
                  <code>{activeFile.content}</code>
                </pre>
              </div>
            </>
          ) : (
            <div className="p-10 text-center text-sm text-slate-500">
              Select a file from the repository tree to inspect its contents.
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
