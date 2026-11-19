import {useEffect, useState} from 'react';
import {Check, Copy, Download} from 'lucide-react';
import type {ProjectBundle, UiLanguage} from '../types/truthVerify';

interface DeployGuideViewProps {
  bundle: ProjectBundle;
  onChangeBundle: (bundle: ProjectBundle) => void;
  repoName: string;
  onChangeRepoName: (name: string) => void;
  githubUsername: string;
  onChangeGithubUsername: (username: string) => void;
  railwayUrl: string;
  onChangeRailwayUrl: (url: string) => void;
  onDownloadZip: () => void;
  onOpenFiles: () => void;
  language: UiLanguage;
  onChangeLanguage: (lang: UiLanguage) => void;
}

const STORAGE_KEY = 'truthverify_deploy_steps_v2';

export function DeployGuideView({
  bundle,
  onChangeBundle,
  repoName,
  onChangeRepoName,
  githubUsername,
  onChangeGithubUsername,
  railwayUrl,
  onChangeRailwayUrl,
  onDownloadZip,
  onOpenFiles,
  language,
  onChangeLanguage,
}: DeployGuideViewProps) {
  const [completedSteps, setCompletedSteps] = useState<Record<string, boolean>>(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      return saved ? (JSON.parse(saved) as Record<string, boolean>) : {};
    } catch {
      return {};
    }
  });
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(completedSteps));
    } catch {
      // ignore storage errors
    }
  }, [completedSteps]);

  const toggleStep = (id: string) => {
    setCompletedSteps((prev) => ({...prev, [id]: !prev[id]}));
  };

  const copySnippet = async (key: string, text: string) => {
    await navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 1600);
  };

  const doneCount = Object.values(completedSteps).filter(Boolean).length;
  const cleanRepo = repoName.trim().replace(/[^a-zA-Z0-9._-]/g, '') || 'True-';
  const cleanUser = githubUsername.trim().replace(/^@/, '') || 'akashtyagi534-tech';

  const v3EnvBlock = `# Railway PostgreSQL ke liye (agar MySQL add kiya hai to \${{MySQL.MYSQL_URL}} likhein)
DATABASE_URL=\${{Postgres.DATABASE_URL}}
DATA_DIR=/data
JWT_SECRET=truth-lens-pro-super-secret-9988776655
GOOGLE_CLIENT_ID=
ADMIN_EMAILS=akashtyagi534@gmail.com
ADMIN_PASSWORD=AkashAdmin@2026`;

  const gitCommands = `git init
git add .
git commit -m "Deploy ${bundle === 'v3' ? 'Truth Lens Pro v3' : 'TruthVerify Mobile'}"
git branch -M main
git remote add origin https://github.com/${cleanUser}/${cleanRepo}.git
git push -u origin main`;

  const cleanUrl = railwayUrl.trim().replace(/\/+$/, '') || 'https://truth-verify-production.up.railway.app';

  return (
    <section className="mx-auto max-w-[1160px] px-6 py-8">
      <div className="mb-8 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-6">
        <div className="max-w-2xl">
          <p className="font-mono text-xs text-slate-500 tabular-nums">
            GitHub ({cleanUser}/{cleanRepo}) + Railway + GitHub Actions · {doneCount} / 5 Steps Completed
          </p>
          <h1 className="mt-1.5 font-display text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">
            {bundle === 'v3'
              ? language === 'hi'
                ? 'Truth Lens Pro v3 — Railway + Volume + GitHub Actions गाइड'
                : 'Truth Lens Pro v3 — Railway + Volume + GitHub Actions Guide'
              : language === 'hi'
                ? `"${cleanRepo}" रिपॉजिटरी से Railway और Cloud APK सेटअप`
                : `Deploy "${cleanRepo}" to Railway & Build Cloud APK`}
          </h1>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div className="inline-flex items-center rounded-lg border border-slate-200 bg-slate-100 p-1">
            <button
              type="button"
              onClick={() => onChangeBundle('v3')}
              className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                bundle === 'v3'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Truth Lens Pro v3
            </button>
            <button
              type="button"
              onClick={() => onChangeBundle('mobile')}
              className={`rounded-md px-3 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                bundle === 'mobile'
                  ? 'bg-white text-slate-900 shadow-xs'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Flutter APK (True-)
            </button>
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
      </div>

      {bundle === 'v3' ? (
        <div className="space-y-6">
          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  01. truth-lens-v3-pro.zip डाउनलोड करें या फ़ाइलें कॉपी करें
                </h2>
                <p className="mt-1.5 text-sm leading-relaxed text-slate-600">
                  {language === 'hi'
                    ? 'इसमें app/ (Google Login, Wallet, Moderation, NLP, Scoring), static/ (index, admin, history, report + JS/CSS), tests/test_all.py, Dockerfile, और .github/workflows/deploy.yml सब शामिल हैं।'
                    : 'Includes app/ (auth, db, moderation, nlp, scoring, main), static/ (HTML, CSS, JS modules), tests/test_all.py, Dockerfile, and .github/workflows/deploy.yml.'}
                </p>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['v3_1'])}
                  onChange={() => toggleStep('v3_1')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>
            <div className="mt-4 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={onDownloadZip}
                className="inline-flex items-center gap-2 rounded-lg bg-slate-900 px-4 py-2 text-xs font-medium text-white hover:bg-slate-800 whitespace-nowrap shrink-0"
              >
                <Download className="h-3.5 w-3.5" aria-hidden="true" />
                <span>Download truth-lens-v3-pro.zip</span>
              </button>
              <button
                type="button"
                onClick={onOpenFiles}
                className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50 whitespace-nowrap shrink-0"
              >
                Inspect All Files (Copy Path & Code)
              </button>
            </div>
          </article>

          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  02. Railway पर Volume (/data) जोड़ें
                </h2>
                <p className="mt-1.5 text-sm text-slate-600">
                  {language === 'hi'
                    ? 'Railway → New Project → Deploy from GitHub repo चुनें। सर्विस खुलते ही Volumes → Add Volume पर जाकर Mount Path में /data सेट करें (ताकि SQLite DB और Flagged Videos सुरक्षित रहें)।'
                    : 'Deploy from GitHub repo on Railway, then attach a Volume with Mount Path /data so SQLite and flagged moderation clips persist across restarts.'}
                </p>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['v3_2'])}
                  onChange={() => toggleStep('v3_2')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>
          </article>

          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  03. Railway Variables सेट करें
                </h2>
                <p className="mt-1.5 text-sm text-slate-600">
                  {language === 'hi'
                    ? 'Railway Service → Variables → Raw Editor में नीचे दिए वेरिएबल्स पेस्ट करें (GOOGLE_CLIENT_ID खाली छोड़ने पर quick email login चलेगा):'
                    : 'Paste these environment variables in Railway Service → Variables → Raw Editor:'}
                </p>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['v3_3'])}
                  onChange={() => toggleStep('v3_3')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>
            <div className="mt-4 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
              <div className="flex items-center justify-between border-b border-slate-800 px-4 py-2">
                <span className="font-mono text-[11px] text-slate-400">Railway Variables (.env)</span>
                <button
                  type="button"
                  onClick={() => copySnippet('v3env', v3EnvBlock)}
                  className="inline-flex items-center gap-1.5 text-xs text-slate-300 hover:text-white"
                >
                  {copiedKey === 'v3env' ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
                  <span>{copiedKey === 'v3env' ? 'Copied' : 'Copy'}</span>
                </button>
              </div>
              <pre className="overflow-x-auto p-4 font-mono text-xs leading-6 text-slate-100">
                <code>{v3EnvBlock}</code>
              </pre>
            </div>
          </article>

          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  04. GitHub Actions CI/CD (Pytest + Auto Railway Deploy)
                </h2>
                <p className="mt-1.5 text-sm text-slate-600">
                  {language === 'hi'
                    ? 'GitHub Repo → Settings → Secrets and variables → Actions में RAILWAY_TOKEN जोड़ें। हर push पर पहले pytest चलेगा, और पास होने पर Railway पर अपने आप डिप्लॉय होगा।'
                    : 'Add RAILWAY_TOKEN in GitHub Repo → Settings → Secrets → Actions. Every push runs pytest first and deploys to Railway on success.'}
                </p>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['v3_4'])}
                  onChange={() => toggleStep('v3_4')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>
          </article>

          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  05. Admin Panel (/admin) खोलें और Pricing / UPI सेट करें
                </h2>
                <p className="mt-1.5 text-sm text-slate-600">
                  {language === 'hi'
                    ? 'अपनी ADMIN_EMAILS (akashtyagi534@gmail.com) व ADMIN_PASSWORD से लॉगिन करें, फिर /admin पर जाकर Flagged Videos, Recharge Approvals, Free Questions और UPI ID लाइव कंट्रोल करें।'
                    : 'Sign in with ADMIN_EMAILS and ADMIN_PASSWORD, then visit /admin to manage flagged videos, UPI recharge approvals, pricing, and users.'}
                </p>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['v3_5'])}
                  onChange={() => toggleStep('v3_5')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>
          </article>
        </div>
      ) : (
        <div className="space-y-6">
          {/* Mobile APK Guide */}
          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  {language === 'hi'
                    ? `01. मोबाइल ब्राउज़र से फ़ाइलें डालें (बिना लैपटॉप के)`
                    : `01. Add Files Directly from Mobile Browser (No Laptop Needed)`}
                </h2>
                <p className="mt-1.5 text-sm leading-relaxed text-slate-600">
                  {language === 'hi'
                    ? `फ़ोन में GitHub की "creating a new file" लिंक पर टैप करें, Project Files टैब से हर फ़ाइल का Path ("Copy Path") और कोड ("Copy Code") पेस्ट करके Commit करें।`
                    : `On Android Chrome, tap "creating a new file" on your empty GitHub repo, then use Copy Path and Copy Code from Project Files for each file.`}
                </p>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['step1'])}
                  onChange={() => toggleStep('step1')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>
            <div className="mt-4 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={onOpenFiles}
                className="rounded-lg bg-slate-900 px-4 py-2 text-xs font-medium text-white hover:bg-slate-800 whitespace-nowrap shrink-0"
              >
                Open Files (Copy Path & Code)
              </button>
              <button
                type="button"
                onClick={onDownloadZip}
                className="inline-flex items-center gap-2 rounded-lg border border-slate-300 bg-white px-4 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50 whitespace-nowrap shrink-0"
              >
                <Download className="h-3.5 w-3.5" aria-hidden="true" />
                <span>Download {cleanRepo}.zip</span>
              </button>
            </div>
          </article>

          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  02. Git CLI / Termux Commands ({cleanRepo})
                </h2>
              </div>
              <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
                <input
                  type="checkbox"
                  checked={Boolean(completedSteps['step2'])}
                  onChange={() => toggleStep('step2')}
                  className="h-4 w-4 rounded border-slate-300 text-blue-700"
                />
                <span>Done</span>
              </label>
            </div>

            <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div>
                <label htmlFor="guide-gh-user" className="block text-xs font-medium text-slate-700">
                  GitHub Username
                </label>
                <input
                  id="guide-gh-user"
                  type="text"
                  value={githubUsername}
                  onChange={(e) => onChangeGithubUsername(e.target.value)}
                  className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                />
              </div>
              <div>
                <label htmlFor="guide-repo-name" className="block text-xs font-medium text-slate-700">
                  Repository Name
                </label>
                <input
                  id="guide-repo-name"
                  type="text"
                  value={repoName}
                  onChange={(e) => onChangeRepoName(e.target.value)}
                  className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                />
              </div>
            </div>

            <div className="mt-4 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
              <div className="flex items-center justify-between border-b border-slate-800 px-4 py-2">
                <span className="font-mono text-[11px] text-slate-400">bash</span>
                <button
                  type="button"
                  onClick={() => copySnippet('git', gitCommands)}
                  className="inline-flex items-center gap-1.5 text-xs text-slate-300 hover:text-white"
                >
                  {copiedKey === 'git' ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
                  <span>{copiedKey === 'git' ? 'Copied' : 'Copy'}</span>
                </button>
              </div>
              <pre className="overflow-x-auto p-4 font-mono text-xs leading-6 text-slate-100">
                <code>{gitCommands}</code>
              </pre>
            </div>
          </article>

          <article className="rounded-xl border border-slate-200 bg-white p-6">
            <h2 className="font-display text-lg font-semibold text-slate-950">
              03. Railway SQL (PostgreSQL / MySQL) + Public Domain सेटअप
            </h2>
            <p className="mt-1.5 text-sm leading-relaxed text-slate-600">
              {language === 'hi'
                ? 'Railway प्रोजेक्ट में + New → GitHub Repo (True-) जोड़ें, Settings → Root Directory में /backend सेट करें, और Variables → Raw Editor में नीचे दिए वेरिएबल्स पेस्ट करें (PostgreSQL और MySQL दोनों ऑटो-सपोर्टेड हैं)। फिर Settings → Networking → Generate Domain से मिला https://....up.railway.app लिंक APK के Server आइकन में सेव करें।'
                : 'Add your True- GitHub repo in the same Railway project as your SQL database, set Root Directory to /backend, paste the variables below, and click Settings → Networking → Generate Domain to get your public https://....up.railway.app URL.'}
            </p>
            <div className="mt-4 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
              <div className="flex items-center justify-between border-b border-slate-800 px-4 py-2">
                <span className="font-mono text-[11px] text-slate-400">Railway Backend Variables (SQL Ready)</span>
                <button
                  type="button"
                  onClick={() => copySnippet('mobile_env', v3EnvBlock)}
                  className="inline-flex items-center gap-1.5 text-xs text-slate-300 hover:text-white"
                >
                  {copiedKey === 'mobile_env' ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
                  <span>{copiedKey === 'mobile_env' ? 'Copied' : 'Copy'}</span>
                </button>
              </div>
              <pre className="overflow-x-auto p-4 font-mono text-xs leading-6 text-slate-100">
                <code>{v3EnvBlock}</code>
              </pre>
            </div>
            <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
              <div>
                <label htmlFor="guide-railway-url" className="block text-xs font-medium text-slate-700">
                  Public Railway Backend URL (https://....up.railway.app)
                </label>
                <input
                  id="guide-railway-url"
                  type="url"
                  value={railwayUrl}
                  onChange={(e) => onChangeRailwayUrl(e.target.value)}
                  placeholder="https://your-service.up.railway.app"
                  className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                />
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-950 p-3.5 font-mono text-xs text-slate-100">
                <code>{`ApiService({this.baseUrl = '${cleanUrl}'});`}</code>
              </div>
            </div>
          </article>
        </div>
      )}
    </section>
  );
}
