import {useEffect, useState} from 'react';
import {Check, Copy, Download} from 'lucide-react';
import type {UiLanguage} from '../types/truthVerify';

interface DeployGuideViewProps {
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

const STORAGE_KEY = 'truthverify_deploy_steps_v1';

export function DeployGuideView({
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

  const gitCommands = `git init
git add .
git commit -m "Initial TruthVerify backend, Flutter app, and APK workflow"
git branch -M main
git remote add origin https://github.com/${cleanUser}/${cleanRepo}.git
git push -u origin main`;

  const cleanUrl = railwayUrl.trim().replace(/\/+$/, '') || 'https://truth-verify-production.up.railway.app';

  return (
    <section className="mx-auto max-w-[1160px] px-6 py-8">
      <div className="mb-8 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-6">
        <div className="max-w-2xl">
          <p className="font-mono text-xs text-slate-500 tabular-nums">
            GitHub ({cleanUser}/{cleanRepo}) + Railway + GitHub Actions APK · {doneCount} / 5 Steps Completed
          </p>
          <h1 className="mt-1.5 font-display text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">
            {language === 'hi'
              ? `"${cleanRepo}" रिपॉजिटरी से Railway और Cloud APK सेटअप`
              : `Deploy "${cleanRepo}" to Railway & Build Cloud APK`}
          </h1>
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

      <div className="space-y-6">
        {/* Step 1 */}
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
                  ? `फ़ोन में GitHub की "creating a new file" लिंक पर टैप करें, Project Files टैब से हर फ़ाइल का Path ("Copy Path") और कोड ("Copy Code") पेस्ट करके Commit करें। यह Android पर ZIP अपलोड से ज़्यादा आसान और बिना एरर के काम करता है।`
                  : `On Android Chrome, tap "creating a new file" on your empty GitHub repo, then use Copy Path and Copy Code from the Project Files tab for each of the 13 files. Or download ${cleanRepo}.zip if using Git CLI.`}
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
              Open 13 Files (Copy Path & Code)
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

        {/* Step 2 */}
        <article className="rounded-xl border border-slate-200 bg-white p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="font-display text-lg font-semibold text-slate-950">
                {language === 'hi'
                  ? `02. वैकल्पिक: Termux / Git CLI से "${cleanRepo}" में पुश करें`
                  : `02. Optional: Push to "${cleanRepo}" via Git CLI / Termux`}
              </h2>
              <p className="mt-1.5 text-sm leading-relaxed text-slate-600">
                {language === 'hi'
                  ? `यदि आप Termux या लैपटॉप से push कर रहे हैं, तो ये कमांड "${cleanRepo}/" फ़ोल्डर के अंदर चलाएं:`
                  : `If pushing via Git CLI or Termux, run these commands inside the extracted "${cleanRepo}/" folder:`}
              </p>
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
                {language === 'hi' ? 'आपका GitHub Username' : 'Your GitHub Username'}
              </label>
              <input
                id="guide-gh-user"
                type="text"
                value={githubUsername}
                onChange={(e) => onChangeGithubUsername(e.target.value)}
                placeholder="e.g. akashtyagi534"
                className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
              />
            </div>
            <div>
              <label htmlFor="guide-repo-name" className="block text-xs font-medium text-slate-700">
                {language === 'hi' ? 'GitHub Repository का नाम' : 'GitHub Repository Name'}
              </label>
              <input
                id="guide-repo-name"
                type="text"
                value={repoName}
                onChange={(e) => onChangeRepoName(e.target.value)}
                placeholder="true"
                className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
              />
            </div>
          </div>

          <div className="mt-4 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
            <div className="flex items-center justify-between border-b border-slate-800 px-4 py-2">
              <span className="font-mono text-[11px] text-slate-400">bash (run inside {cleanRepo}/ folder)</span>
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

        {/* Step 3 */}
        <article className="rounded-xl border border-slate-200 bg-white p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="font-display text-lg font-semibold text-slate-950">
                {language === 'hi'
                  ? '03. Railway.app पर बैकएंड लाइव करें'
                  : '03. Deploy Python + ffmpeg Backend on Railway'}
              </h2>
            </div>
            <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
              <input
                type="checkbox"
                checked={Boolean(completedSteps['step3'])}
                onChange={() => toggleStep('step3')}
                className="h-4 w-4 rounded border-slate-300 text-blue-700"
              />
              <span>Done</span>
            </label>
          </div>
          <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
            <li>
              {language === 'hi'
                ? `Railway.app पर लॉगिन करें और New Project → Deploy from GitHub repo चुनकर "${cleanRepo}" रिपॉजिटरी सिलेक्ट करें।`
                : `Sign in to Railway.app and select New Project → Deploy from GitHub repo → choose "${cleanRepo}".`}
            </li>
            <li>
              {language === 'hi'
                ? 'Settings टैब में जाकर Root Directory में /backend सेट करें (ताकि Railway backend/Dockerfile चलाए)।'
                : 'Open Settings → set Root Directory to /backend so Railway builds backend/Dockerfile.'}
            </li>
            <li>
              {language === 'hi'
                ? 'Networking → Generate Domain पर क्लिक करें और मिला हुआ पब्लिक URL नीचे स्टेप 04 में पेस्ट करें।'
                : 'Click Networking → Generate Domain and paste the generated public URL in Step 04 below.'}
            </li>
          </ol>
        </article>

        {/* Step 4 */}
        <article className="rounded-xl border border-slate-200 bg-white p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="font-display text-lg font-semibold text-slate-950">
                {language === 'hi'
                  ? '04. Flutter ऐप में Railway का URL जोड़ें'
                  : '04. Bind Railway URL in flutter_app/lib/api_service.dart'}
              </h2>
              <p className="mt-1.5 text-sm text-slate-600">
                {language === 'hi'
                  ? 'यहाँ URL बदलने पर api_service.dart अपने आप अपडेट हो जाएगा (अंत में "/" न लगाएं)। अपडेट के बाद ZIP दोबारा डाउनलोड करके push करें या GitHub पर api_service.dart एडिट करें।'
                  : 'Updating this field automatically rewrites baseUrl inside api_service.dart (omit trailing "/"). Re-download ZIP or edit api_service.dart on GitHub before building the APK.'}
              </p>
            </div>
            <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
              <input
                type="checkbox"
                checked={Boolean(completedSteps['step4'])}
                onChange={() => toggleStep('step4')}
                className="h-4 w-4 rounded border-slate-300 text-blue-700"
              />
              <span>Done</span>
            </label>
          </div>
          <div className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label htmlFor="guide-railway-url" className="block text-xs font-medium text-slate-700">
                Railway Base URL
              </label>
              <input
                id="guide-railway-url"
                type="url"
                value={railwayUrl}
                onChange={(e) => onChangeRailwayUrl(e.target.value)}
                className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
              />
            </div>
            <div className="rounded-lg border border-slate-200 bg-slate-950 p-3.5 font-mono text-xs text-slate-100">
              <code>{`ApiService({this.baseUrl = '${cleanUrl}'});`}</code>
            </div>
          </div>
        </article>

        {/* Step 5 */}
        <article className="rounded-xl border border-slate-200 bg-white p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h2 className="font-display text-lg font-semibold text-slate-950">
                {language === 'hi'
                  ? '05. GitHub Actions से APK डाउनलोड करें'
                  : '05. Download TruthVerify-Release-APK from GitHub Actions'}
              </h2>
            </div>
            <label className="inline-flex cursor-pointer items-center gap-2 text-xs font-medium text-slate-700 whitespace-nowrap shrink-0">
              <input
                type="checkbox"
                checked={Boolean(completedSteps['step5'])}
                onChange={() => toggleStep('step5')}
                className="h-4 w-4 rounded border-slate-300 text-blue-700"
              />
              <span>Done</span>
            </label>
          </div>
          <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
            <li>
              {language === 'hi'
                ? `अपनी "${cleanRepo}" GitHub रिपॉजिटरी के ऊपर Actions टैब पर क्लिक करें।`
                : `Open the Actions tab in your "${cleanRepo}" GitHub repository.`}
            </li>
            <li>
              {language === 'hi'
                ? 'Build Android Release APK वर्कफ़्लो पर क्लिक करें (.github/workflows/build_apk.yml स्वतः Android फ़ोल्डर व कैमरा/माइक परमिशन जोड़ देगा)।'
                : 'Select the Build Android Release APK workflow run.'}
            </li>
            <li>
              {language === 'hi'
                ? 'हरा टिक आते ही नीचे Artifacts सेक्शन से TruthVerify-Release-APK डाउनलोड करें — यह सीधे आपके Railway सर्वर से जुड़ा होगा।'
                : 'Once complete, download TruthVerify-Release-APK from the Artifacts section and install on your Android device.'}
            </li>
          </ol>
        </article>
      </div>
    </section>
  );
}
