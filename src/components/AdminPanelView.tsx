import {useCallback, useEffect, useState} from 'react';
import {
  Activity,
  AlertTriangle,
  Ban,
  Check,
  CheckCircle2,
  CloudUpload,
  ExternalLink,
  IndianRupee,
  LogOut,
  Minus,
  Plus,
  RefreshCw,
  Search,
  Shield,
  SlidersHorizontal,
  Users,
  Video,
  XCircle,
} from 'lucide-react';
import type {UiLanguage} from '../types/truthVerify';

interface AdminPanelViewProps {
  railwayUrl: string;
  onChangeRailwayUrl: (url: string) => void;
  onOpenFiles: () => void;
  onOpenGuide: () => void;
  language: UiLanguage;
  onChangeLanguage: (lang: UiLanguage) => void;
}

interface AdminSettings {
  price_per_question: number;
  min_recharge: number;
  free_questions: number;
  upi_id: string;
}

interface AdminStats {
  total_users: number;
  total_revenue: number;
  total_questions: number;
  total_scans?: number;
  active_wallet_balances?: number;
  pending_recharges: number;
  flagged_alerts: number;
}

interface AdminUser {
  id: string;
  email: string;
  name: string;
  google_connected?: boolean;
  wallet_balance: number;
  free_questions_used: number;
  total_questions_asked: number;
  is_admin: boolean;
  is_banned: boolean;
}

interface AdminRecharge {
  id: string;
  user_id: string;
  user_email: string;
  amount: number;
  utr: string;
  status: string;
  created_at: string;
}

interface AdminAlert {
  id: string;
  user_email: string;
  session_id: string;
  question_text: string;
  matched_keywords: string[];
  video_url: string;
  reviewed: boolean;
  created_at: string;
}

interface AdminScan {
  id: string;
  user_email: string;
  title: string;
  question: string;
  consistency_score: number;
  verdict: string;
  created_at: string;
}

interface AdminOtaConfig {
  app_version?: string;
  maintenance_message?: string;
  baseline_questions?: string[];
}

interface AdminOverview {
  settings: AdminSettings;
  stats: AdminStats;
  users: AdminUser[];
  recharges: AdminRecharge[];
  alerts: AdminAlert[];
  recent_scans?: AdminScan[];
  ota_config?: AdminOtaConfig;
}

const TOKEN_STORAGE_KEY = 'truthlens_admin_jwt';
const EMAIL_STORAGE_KEY = 'truthlens_admin_email';

type AdminSubTab = 'overview' | 'recharges' | 'users' | 'scans' | 'alerts';

export function AdminPanelView({
  railwayUrl,
  onChangeRailwayUrl,
  onOpenFiles,
  onOpenGuide,
  language,
  onChangeLanguage,
}: AdminPanelViewProps) {
  const [adminEmail, setAdminEmail] = useState<string>(() => {
    try {
      return localStorage.getItem(EMAIL_STORAGE_KEY) || 'akashtyagi534@gmail.com';
    } catch {
      return 'akashtyagi534@gmail.com';
    }
  });
  const [adminPassword, setAdminPassword] = useState('AkashAdmin@2026');
  const [token, setToken] = useState<string>(() => {
    try {
      return localStorage.getItem(TOKEN_STORAGE_KEY) || '';
    } catch {
      return '';
    }
  });
  const [overview, setOverview] = useState<AdminOverview | null>(null);
  const [activeTab, setActiveTab] = useState<AdminSubTab>('overview');
  const [loading, setLoading] = useState(false);
  const [savingSettings, setSavingSettings] = useState(false);
  const [actionBusyId, setActionBusyId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  // Editable pricing & OTA form state
  const [pricePerQ, setPricePerQ] = useState('10');
  const [minRecharge, setMinRecharge] = useState('50');
  const [freeQuestions, setFreeQuestions] = useState('3');
  const [upiId, setUpiId] = useState('akashtyagi534@oksbi');
  const [otaVersion, setOtaVersion] = useState('4.0.0');
  const [otaMaint, setOtaMaint] = useState('');
  const [otaQuestions, setOtaQuestions] = useState('');
  const [savingOta, setSavingOta] = useState(false);
  const [userSearch, setUserSearch] = useState('');
  const [customWalletDelta, setCustomWalletDelta] = useState('50');

  const cleanBaseUrl = railwayUrl.trim().replace(/\/+$/, '');

  const showToast = (msg: string) => {
    setToastMsg(msg);
    window.setTimeout(() => setToastMsg(null), 3200);
  };

  const callProxy = useCallback(
    async <T,>(
      endpoint: string,
      options: {method?: 'GET' | 'POST'; body?: unknown; authToken?: string} = {},
    ): Promise<T> => {
      const resp = await fetch('/api/admin/proxy', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          baseUrl: cleanBaseUrl,
          endpoint,
          method: options.method ?? 'GET',
          token: options.authToken ?? token,
          body: options.body,
        }),
      });
      const data = (await resp.json()) as Record<string, unknown>;
      if (!resp.ok) {
        const msg =
          (typeof data.detail === 'string' && data.detail) ||
          (typeof data.error === 'string' && data.error) ||
          `Request failed (HTTP ${resp.status})`;
        throw new Error(msg);
      }
      return data as T;
    },
    [cleanBaseUrl, token],
  );

  const loadOverview = useCallback(
    async (overrideToken?: string) => {
      const activeToken = overrideToken ?? token;
      if (!cleanBaseUrl || !activeToken) return;
      setLoading(true);
      setErrorMsg(null);
      try {
        const data = await callProxy<AdminOverview>('/api/admin/overview', {
          method: 'GET',
          authToken: activeToken,
        });
        setOverview(data);
        setPricePerQ(String(data.settings.price_per_question));
        setMinRecharge(String(data.settings.min_recharge));
        setFreeQuestions(String(data.settings.free_questions));
        setUpiId(data.settings.upi_id);
        setOtaVersion(data.ota_config?.app_version || '4.0.0');
        setOtaMaint(data.ota_config?.maintenance_message || '');
        setOtaQuestions((data.ota_config?.baseline_questions || []).join('\n'));
      } catch (err) {
        setErrorMsg(err instanceof Error ? err.message : 'Failed to load admin overview.');
      } finally {
        setLoading(false);
      }
    },
    [callProxy, cleanBaseUrl, token],
  );

  useEffect(() => {
    if (cleanBaseUrl && token && !overview) {
      void loadOverview();
    }
  }, [cleanBaseUrl, token, overview, loadOverview]);

  const handleAdminLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!cleanBaseUrl) {
      setErrorMsg(
        language === 'hi'
          ? 'Pehle apna Railway public URL (https://....up.railway.app) upar dalein.'
          : 'Enter your public Railway backend URL (https://....up.railway.app) first.',
      );
      return;
    }
    setLoading(true);
    setErrorMsg(null);
    try {
      const res = await callProxy<{token: string; user: {is_admin: boolean; email: string}}>(
        '/api/auth/dev-login',
        {
          method: 'POST',
          authToken: '',
          body: {
            email: adminEmail.trim(),
            name: 'Admin',
            password: adminPassword,
          },
        },
      );
      if (!res.user?.is_admin) {
        throw new Error(
          language === 'hi'
            ? 'Yeh account Admin nahi hai. Railway Variables mein ADMIN_EMAILS aur ADMIN_PASSWORD check karein.'
            : 'This account does not have admin privileges. Check ADMIN_EMAILS and ADMIN_PASSWORD in Railway Variables.',
        );
      }
      setToken(res.token);
      try {
        localStorage.setItem(TOKEN_STORAGE_KEY, res.token);
        localStorage.setItem(EMAIL_STORAGE_KEY, adminEmail.trim());
      } catch {
        // ignore storage errors
      }
      await loadOverview(res.token);
      showToast(language === 'hi' ? 'Admin Panel Live Connected!' : 'Connected to live Admin Panel!');
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Admin login failed.');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = () => {
    setToken('');
    setOverview(null);
    setErrorMsg(null);
    try {
      localStorage.removeItem(TOKEN_STORAGE_KEY);
    } catch {
      // ignore
    }
  };

  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    setSavingSettings(true);
    setErrorMsg(null);
    try {
      await callProxy('/api/admin/settings', {
        method: 'POST',
        body: {
          price_per_question: Math.max(0, Number(pricePerQ) || 0),
          min_recharge: Math.max(1, Number(minRecharge) || 50),
          free_questions: Math.max(0, Number(freeQuestions) || 0),
          upi_id: upiId.trim(),
        },
      });
      await loadOverview();
      showToast(language === 'hi' ? 'Pricing aur UPI ID live update ho gaya!' : 'Pricing & UPI settings updated live!');
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to save settings.');
    } finally {
      setSavingSettings(false);
    }
  };

  const handleSaveOta = async (e: React.FormEvent) => {
    e.preventDefault();
    setSavingOta(true);
    setErrorMsg(null);
    try {
      const qs = otaQuestions
        .split('\n')
        .map((s) => s.trim())
        .filter(Boolean);
      await callProxy('/api/admin/ota-config', {
        method: 'POST',
        body: {
          app_version: otaVersion.trim() || '4.0.0',
          maintenance_message: otaMaint.trim(),
          baseline_questions: qs,
        },
      });
      await loadOverview();
      showToast(
        language === 'hi'
          ? 'OTA Config live push ho gaya — bina APK rebuild kiye sabhi phones update honge!'
          : 'OTA configuration pushed live to all installed APKs!',
      );
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to update OTA config.');
    } finally {
      setSavingOta(false);
    }
  };

  const handleRechargeAction = async (rechargeId: string, action: 'approve' | 'reject') => {
    setActionBusyId(rechargeId);
    setErrorMsg(null);
    try {
      await callProxy(`/api/admin/recharges/${rechargeId}/${action}`, {method: 'POST'});
      await loadOverview();
      showToast(
        action === 'approve'
          ? language === 'hi'
            ? 'Recharge Approve hua — user wallet update ho gaya!'
            : 'Recharge approved and wallet credited!'
          : language === 'hi'
            ? 'Recharge Reject kar diya gaya.'
            : 'Recharge rejected.',
      );
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Recharge action failed.');
    } finally {
      setActionBusyId(null);
    }
  };

  const handleAdjustWallet = async (userId: string, delta: number) => {
    setActionBusyId(`${userId}:${delta}`);
    setErrorMsg(null);
    try {
      await callProxy(`/api/admin/users/${userId}/wallet`, {
        method: 'POST',
        body: {delta},
      });
      await loadOverview();
      showToast(delta > 0 ? `+₹${delta} wallet mein add ho gaya!` : `₹${Math.abs(delta)} wallet se deduct hua.`);
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Wallet update failed.');
    } finally {
      setActionBusyId(null);
    }
  };

  const handleToggleBan = async (userId: string) => {
    setActionBusyId(`ban:${userId}`);
    setErrorMsg(null);
    try {
      await callProxy(`/api/admin/users/${userId}/toggle-ban`, {method: 'POST'});
      await loadOverview();
      showToast(language === 'hi' ? 'User status update ho gaya.' : 'User ban status updated.');
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Status update failed.');
    } finally {
      setActionBusyId(null);
    }
  };

  const isConnected = Boolean(overview && token);

  return (
    <section className="mx-auto max-w-[1360px] px-6 py-8">
      {/* Header */}
      <div className="mb-6 flex flex-wrap items-end justify-between gap-4 border-b border-slate-200 pb-6">
        <div className="max-w-2xl">
          <div className="flex items-center gap-2 font-mono text-xs text-slate-500">
            <Shield className="h-3.5 w-3.5 text-blue-700" aria-hidden="true" />
            <span>
              Truth Lens Pro · Admin Control Center {isConnected ? '· LIVE SQL' : '· Ready to Connect'}
            </span>
          </div>
          <h1 className="mt-1.5 font-display text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">
            {language === 'hi' ? 'Admin Panel — Pricing, Wallet, Users & Flagged Videos' : 'Admin Control Center'}
          </h1>
          <p className="mt-1.5 text-sm text-slate-600">
            {language === 'hi'
              ? 'Yahan se aap apne live Railway backend ka Per-Question Price, Free Questions, UPI ID, Recharge Approvals, Users aur Flagged Unsafe Videos seedha control kar sakte hain.'
              : 'Manage live Railway pricing, UPI ID, recharge approvals, user wallets, bans, and flagged safety videos.'}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          {isConnected && (
            <>
              <button
                type="button"
                onClick={() => void loadOverview()}
                disabled={loading}
                className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-60"
              >
                <RefreshCw className={`h-3.5 w-3.5 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" />
                <span>Refresh</span>
              </button>
              <a
                href={`${cleanBaseUrl}/admin`}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3.5 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50"
              >
                <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
                <span>Open /admin</span>
              </a>
              <button
                type="button"
                onClick={handleLogout}
                className="inline-flex items-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50 px-3.5 py-2 text-xs font-medium text-rose-700 hover:bg-rose-100"
              >
                <LogOut className="h-3.5 w-3.5" aria-hidden="true" />
                <span>Logout</span>
              </button>
            </>
          )}

          <div className="inline-flex items-center rounded-lg border border-slate-200 bg-slate-100 p-1">
            <button
              type="button"
              onClick={() => onChangeLanguage('hi')}
              className={`rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                language === 'hi' ? 'bg-white text-slate-900 shadow-xs' : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              हिन्दी
            </button>
            <button
              type="button"
              onClick={() => onChangeLanguage('en')}
              className={`rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
                language === 'en' ? 'bg-white text-slate-900 shadow-xs' : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              English
            </button>
          </div>
        </div>
      </div>

      {/* Feedback Banner */}
      {toastMsg && (
        <div className="mb-6 flex items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm font-medium text-emerald-900">
          <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-700" aria-hidden="true" />
          <span>{toastMsg}</span>
        </div>
      )}

      {errorMsg && (
        <div className="mb-6 flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-900">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-rose-700" aria-hidden="true" />
          <span>{errorMsg}</span>
        </div>
      )}

      {/* Connection / Login Gate */}
      {!overview || !token ? (
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-12">
          <form
            onSubmit={handleAdminLogin}
            className="rounded-xl border border-slate-200 bg-white p-6 lg:col-span-7"
          >
            <h2 className="font-display text-lg font-semibold text-slate-950">
              {language === 'hi' ? 'Apne Railway Live Admin Panel se Connect Karein' : 'Connect to Your Live Railway Admin'}
            </h2>
            <p className="mt-1 text-sm text-slate-600">
              {language === 'hi'
                ? 'Railway Backend Service → Settings → Networking → Generate Domain se mila apna public URL aur Admin credentials dalein:'
                : 'Enter your public Railway domain and Admin credentials from Railway Variables:'}
            </p>

            <div className="mt-5 space-y-4">
              <div>
                <label htmlFor="admin-railway-url" className="block text-xs font-medium text-slate-700">
                  Public Railway Backend URL
                </label>
                <input
                  id="admin-railway-url"
                  type="url"
                  value={railwayUrl}
                  onChange={(e) => onChangeRailwayUrl(e.target.value)}
                  placeholder="https://your-backend.up.railway.app"
                  required
                  className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2.5 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                />
                <p className="mt-1 text-[11px] text-slate-500">
                  {language === 'hi'
                    ? 'Note: railway.com/project/... dashboard link nahi, balki https://....up.railway.app public domain dalein.'
                    : 'Use the public https://....up.railway.app domain, not the railway.com/project dashboard URL.'}
                </p>
              </div>

              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div>
                  <label htmlFor="admin-email" className="block text-xs font-medium text-slate-700">
                    Admin Email (ADMIN_EMAILS)
                  </label>
                  <input
                    id="admin-email"
                    type="email"
                    value={adminEmail}
                    onChange={(e) => setAdminEmail(e.target.value)}
                    required
                    className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2.5 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                  />
                </div>
                <div>
                  <label htmlFor="admin-pass" className="block text-xs font-medium text-slate-700">
                    Admin Password (ADMIN_PASSWORD)
                  </label>
                  <input
                    id="admin-pass"
                    type="password"
                    value={adminPassword}
                    onChange={(e) => setAdminPassword(e.target.value)}
                    required
                    className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2.5 font-mono text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                  />
                </div>
              </div>

              <div className="pt-2 flex flex-wrap items-center gap-3">
                <button
                  type="submit"
                  disabled={loading}
                  className="inline-flex items-center gap-2 rounded-lg bg-slate-900 px-5 py-2.5 text-xs font-medium text-white hover:bg-slate-800 disabled:opacity-60"
                >
                  <Shield className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{loading ? 'Connecting...' : language === 'hi' ? 'Admin Login & Connect' : 'Login & Connect'}</span>
                </button>
                <button
                  type="button"
                  onClick={onOpenGuide}
                  className="rounded-lg border border-slate-300 bg-white px-4 py-2.5 text-xs font-medium text-slate-700 hover:bg-slate-50"
                >
                  {language === 'hi' ? 'Railway Domain Kaise Banayein?' : 'How to get Railway URL'}
                </button>
              </div>
            </div>
          </form>

          {/* 3 Ways to Access Admin Panel */}
          <aside className="rounded-xl border border-slate-200 bg-white p-6 lg:col-span-5">
            <h2 className="font-display text-base font-semibold text-slate-950">
              {language === 'hi' ? 'Aapke Paas 3 Jagah Admin Panel Hai' : '3 Ways to Open Your Admin Panel'}
            </h2>
            <div className="mt-4 space-y-4 text-sm text-slate-600">
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3.5">
                <p className="font-medium text-slate-900">1. Yahan Studio Admin Tab (Web)</p>
                <p className="mt-1 text-xs leading-relaxed">
                  {language === 'hi'
                    ? 'Upar apna https://....up.railway.app URL aur Admin Password daalkar yahin se live control karein.'
                    : 'Enter your public Railway URL and Admin Password on the left to manage everything right here.'}
                </p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3.5">
                <p className="font-medium text-slate-900">2. Direct Railway Web URL (/admin)</p>
                <p className="mt-1 text-xs leading-relaxed">
                  {language === 'hi'
                    ? 'Backend deploy hote hi browser mein seedha https://<aapka-domain>/admin kholein (files: backend/static/admin.html + admin.js).'
                    : 'Visit https://<your-domain>/admin directly once your Railway backend is deployed.'}
                </p>
              </div>
              <div className="rounded-lg border border-slate-200 bg-slate-50 p-3.5">
                <p className="font-medium text-slate-900">3. Android APK ke Andar Native Admin</p>
                <p className="mt-1 text-xs leading-relaxed">
                  {language === 'hi'
                    ? 'Naye Truth Lens Pro APK mein akashtyagi534@gmail.com + Admin Password se login karte hi upar golden Shield icon dikhega — tap karke seedha phone app mein Admin Panel khol sakte hain.'
                    : 'Log in inside the Android APK with your Admin email & password to unlock the native Admin Shield button in the app bar.'}
                </p>
              </div>
            </div>
            <button
              type="button"
              onClick={onOpenFiles}
              className="mt-4 w-full rounded-lg border border-slate-300 bg-white px-4 py-2 text-xs font-medium text-slate-700 hover:bg-slate-50"
            >
              {language === 'hi' ? 'Admin Panel Code Files Dekhein (Project Files)' : 'Inspect Admin Code Files'}
            </button>
          </aside>
        </div>
      ) : (
        /* Live Connected Admin Dashboard */
        <div className="space-y-6">
          {/* 6 KPI Cards */}
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-6">
            <div className="rounded-xl border border-slate-200 bg-white p-4">
              <p className="text-xs font-medium text-slate-500">Total Users</p>
              <p className="mt-1.5 font-display text-2xl font-semibold text-slate-950 tabular-nums">
                {overview.stats.total_users}
              </p>
            </div>
            <div className="rounded-xl border border-slate-200 bg-white p-4">
              <p className="text-xs font-medium text-slate-500">Total Scans</p>
              <p className="mt-1.5 font-display text-2xl font-semibold text-indigo-700 tabular-nums">
                {overview.stats.total_scans ?? overview.stats.total_questions}
              </p>
            </div>
            <div className="rounded-xl border border-slate-200 bg-white p-4">
              <p className="text-xs font-medium text-slate-500">Total Revenue</p>
              <p className="mt-1.5 font-display text-2xl font-semibold text-emerald-700 tabular-nums">
                ₹{overview.stats.total_revenue.toLocaleString('en-IN')}
              </p>
            </div>
            <div className="rounded-xl border border-slate-200 bg-white p-4">
              <p className="text-xs font-medium text-slate-500">Active Wallets</p>
              <p className="mt-1.5 font-display text-2xl font-semibold text-cyan-700 tabular-nums">
                ₹{(overview.stats.active_wallet_balances ?? 0).toLocaleString('en-IN')}
              </p>
            </div>
            <div className="rounded-xl border border-slate-200 bg-white p-4">
              <p className="text-xs font-medium text-slate-500">Pending Recharges</p>
              <p className="mt-1.5 font-display text-2xl font-semibold text-amber-600 tabular-nums">
                {overview.stats.pending_recharges}
              </p>
            </div>
            <div className="rounded-xl border border-slate-200 bg-white p-4">
              <p className="text-xs font-medium text-slate-500">Flagged Alerts</p>
              <p className="mt-1.5 font-display text-2xl font-semibold text-rose-600 tabular-nums">
                {overview.stats.flagged_alerts}
              </p>
            </div>
          </div>

          {/* Sub-navigation */}
          <div className="flex flex-wrap items-center gap-2 border-b border-slate-200 pb-3">
            {[
              {id: 'overview' as const, label: 'Pricing, UPI & OTA', icon: SlidersHorizontal},
              {
                id: 'recharges' as const,
                label: `UPI Recharges (${overview.stats.pending_recharges})`,
                icon: IndianRupee,
              },
              {id: 'users' as const, label: `Users (${overview.users.length})`, icon: Users},
              {
                id: 'scans' as const,
                label: `Recent Scans (${(overview.recent_scans ?? []).length})`,
                icon: Activity,
              },
              {id: 'alerts' as const, label: `Flagged Videos (${overview.alerts.length})`, icon: Video},
            ].map((tab) => {
              const Icon = tab.icon;
              const active = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => setActiveTab(tab.id)}
                  className={`inline-flex items-center gap-2 rounded-lg px-3.5 py-2 text-xs font-medium transition-colors ${
                    active
                      ? 'bg-slate-900 text-white'
                      : 'border border-slate-200 bg-white text-slate-700 hover:bg-slate-50'
                  }`}
                >
                  <Icon className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{tab.label}</span>
                </button>
              );
            })}
          </div>

          {/* Tab 1: Live Pricing, UPI & OTA */}
          {activeTab === 'overview' && (
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              <form onSubmit={handleSaveSettings} className="rounded-xl border border-slate-200 bg-white p-6">
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  Live Pricing & UPI Controls
                </h2>
                <p className="mt-1 text-xs text-slate-600">
                  Changes apply immediately to both the Web app and Android APK.
                </p>
                <div className="mt-5 grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <div>
                    <label htmlFor="cfg-price" className="block text-xs font-medium text-slate-700">
                      Price Per Question (₹)
                    </label>
                    <input
                      id="cfg-price"
                      type="number"
                      min={0}
                      value={pricePerQ}
                      onChange={(e) => setPricePerQ(e.target.value)}
                      className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-sm text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                    />
                  </div>
                  <div>
                    <label htmlFor="cfg-min" className="block text-xs font-medium text-slate-700">
                      Minimum Recharge (₹)
                    </label>
                    <input
                      id="cfg-min"
                      type="number"
                      min={1}
                      value={minRecharge}
                      onChange={(e) => setMinRecharge(e.target.value)}
                      className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-sm text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                    />
                  </div>
                  <div>
                    <label htmlFor="cfg-free" className="block text-xs font-medium text-slate-700">
                      Free Questions Per New User
                    </label>
                    <input
                      id="cfg-free"
                      type="number"
                      min={0}
                      value={freeQuestions}
                      onChange={(e) => setFreeQuestions(e.target.value)}
                      className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-sm text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                    />
                  </div>
                  <div>
                    <label htmlFor="cfg-upi" className="block text-xs font-medium text-slate-700">
                      Your UPI ID
                    </label>
                    <input
                      id="cfg-upi"
                      type="text"
                      value={upiId}
                      onChange={(e) => setUpiId(e.target.value)}
                      placeholder="yourname@oksbi"
                      className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-sm text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                    />
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={savingSettings}
                  className="mt-5 inline-flex items-center gap-2 rounded-lg bg-slate-900 px-5 py-2.5 text-xs font-medium text-white hover:bg-slate-800 disabled:opacity-60"
                >
                  <Check className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{savingSettings ? 'Saving...' : 'Save Live Settings'}</span>
                </button>
              </form>

              <form onSubmit={handleSaveOta} className="rounded-xl border border-slate-200 bg-white p-6">
                <h2 className="font-display text-lg font-semibold text-slate-950">
                  Over-The-Air (OTA) App Config
                </h2>
                <p className="mt-1 text-xs text-slate-600">
                  Pushes instantly to all installed Android APKs via <code>GET /app-config</code> — no APK rebuild required.
                </p>
                <div className="mt-5 space-y-4">
                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <div>
                      <label htmlFor="ota-ver" className="block text-xs font-medium text-slate-700">
                        Live App Version
                      </label>
                      <input
                        id="ota-ver"
                        type="text"
                        value={otaVersion}
                        onChange={(e) => setOtaVersion(e.target.value)}
                        className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 font-mono text-sm text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                      />
                    </div>
                    <div>
                      <label htmlFor="ota-maint" className="block text-xs font-medium text-slate-700">
                        Notice / Maintenance Banner
                      </label>
                      <input
                        id="ota-maint"
                        type="text"
                        value={otaMaint}
                        onChange={(e) => setOtaMaint(e.target.value)}
                        placeholder="Optional announcement"
                        className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                      />
                    </div>
                  </div>
                  <div>
                    <label htmlFor="ota-qs" className="block text-xs font-medium text-slate-700">
                      Stage-1 Baseline Calibration Questions (one per line)
                    </label>
                    <textarea
                      id="ota-qs"
                      rows={3}
                      value={otaQuestions}
                      onChange={(e) => setOtaQuestions(e.target.value)}
                      className="mt-1.5 w-full rounded-lg border border-slate-300 bg-slate-50 px-3.5 py-2 text-xs text-slate-900 focus:border-blue-700 focus:bg-white focus:outline-none"
                    />
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={savingOta}
                  className="mt-5 inline-flex items-center gap-2 rounded-lg bg-indigo-700 px-5 py-2.5 text-xs font-medium text-white hover:bg-indigo-800 disabled:opacity-60"
                >
                  <CloudUpload className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{savingOta ? 'Pushing...' : 'Push OTA Config Live'}</span>
                </button>
              </form>
            </div>
          )}

          {/* Tab 2: Recharges */}
          {activeTab === 'recharges' && (
            <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase text-slate-500">
                    <tr>
                      <th className="px-4 py-3">User</th>
                      <th className="px-4 py-3">Amount</th>
                      <th className="px-4 py-3">UTR / Ref</th>
                      <th className="px-4 py-3">Status</th>
                      <th className="px-4 py-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200">
                    {overview.recharges.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="px-4 py-8 text-center text-xs text-slate-500">
                          Abhi koi UPI recharge request nahi aayi hai.
                        </td>
                      </tr>
                    ) : (
                      overview.recharges.map((r) => (
                        <tr key={r.id}>
                          <td className="px-4 py-3 font-medium text-slate-900">{r.user_email}</td>
                          <td className="px-4 py-3 font-mono tabular-nums text-emerald-700">₹{r.amount}</td>
                          <td className="px-4 py-3 font-mono text-xs text-slate-600">{r.utr || '—'}</td>
                          <td className="px-4 py-3">
                            <span
                              className={`inline-flex rounded px-2 py-0.5 text-xs font-medium ${
                                r.status === 'approved'
                                  ? 'bg-emerald-50 text-emerald-700'
                                  : r.status === 'rejected'
                                    ? 'bg-rose-50 text-rose-700'
                                    : 'bg-amber-50 text-amber-700'
                              }`}
                            >
                              {r.status}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-right">
                            {r.status === 'pending' ? (
                              <div className="inline-flex items-center gap-2">
                                <button
                                  type="button"
                                  disabled={actionBusyId === r.id}
                                  onClick={() => void handleRechargeAction(r.id, 'approve')}
                                  className="inline-flex items-center gap-1 rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-700 disabled:opacity-50"
                                >
                                  <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                                  <span>Approve</span>
                                </button>
                                <button
                                  type="button"
                                  disabled={actionBusyId === r.id}
                                  onClick={() => void handleRechargeAction(r.id, 'reject')}
                                  className="inline-flex items-center gap-1 rounded-md border border-rose-200 bg-rose-50 px-3 py-1.5 text-xs font-medium text-rose-700 hover:bg-rose-100 disabled:opacity-50"
                                >
                                  <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
                                  <span>Reject</span>
                                </button>
                              </div>
                            ) : (
                              <span className="text-xs text-slate-400">Processed</span>
                            )}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Tab 3: Users */}
          {activeTab === 'users' && (
            <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
              <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-slate-50 px-4 py-3">
                <div className="relative w-full max-w-xs">
                  <Search className="pointer-events-none absolute left-3 top-2.5 h-3.5 w-3.5 text-slate-400" />
                  <input
                    type="search"
                    value={userSearch}
                    onChange={(e) => setUserSearch(e.target.value)}
                    placeholder="Search user email or name..."
                    className="w-full rounded-lg border border-slate-300 bg-white py-1.5 pl-8 pr-3 text-xs text-slate-900 focus:border-blue-700 focus:outline-none"
                  />
                </div>
                <div className="flex items-center gap-2 text-xs text-slate-600">
                  <span>Manual Amount (₹):</span>
                  <input
                    type="number"
                    min={1}
                    value={customWalletDelta}
                    onChange={(e) => setCustomWalletDelta(e.target.value)}
                    className="w-20 rounded-lg border border-slate-300 bg-white px-2.5 py-1.5 font-mono text-xs text-slate-900 focus:border-blue-700 focus:outline-none"
                  />
                </div>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase text-slate-500">
                    <tr>
                      <th className="px-4 py-3">User</th>
                      <th className="px-4 py-3">Wallet</th>
                      <th className="px-4 py-3">Questions</th>
                      <th className="px-4 py-3">Status</th>
                      <th className="px-4 py-3 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200">
                    {overview.users
                      .filter((u) => {
                        const q = userSearch.trim().toLowerCase();
                        return (
                          !q ||
                          u.email.toLowerCase().includes(q) ||
                          (u.name || '').toLowerCase().includes(q)
                        );
                      })
                      .map((u) => {
                        const deltaAmt = Math.max(1, Number(customWalletDelta) || 50);
                        return (
                          <tr key={u.id}>
                            <td className="px-4 py-3">
                              <div className="flex items-center gap-2">
                                <p className="font-medium text-slate-900">{u.name || u.email}</p>
                                {u.google_connected && (
                                  <span className="rounded bg-cyan-50 px-1.5 py-0.5 text-[10px] font-semibold text-cyan-700">
                                    Google
                                  </span>
                                )}
                              </div>
                              <p className="font-mono text-xs text-slate-500">{u.email}</p>
                            </td>
                            <td className="px-4 py-3 font-mono font-medium text-emerald-700 tabular-nums">
                              ₹{u.wallet_balance.toFixed(0)}
                            </td>
                            <td className="px-4 py-3 font-mono text-xs text-slate-600 tabular-nums">
                              {u.total_questions_asked} (Free used: {u.free_questions_used})
                            </td>
                            <td className="px-4 py-3">
                              {u.is_banned ? (
                                <span className="rounded bg-rose-50 px-2 py-0.5 text-xs font-medium text-rose-700">
                                  Blocked
                                </span>
                              ) : u.is_admin ? (
                                <span className="rounded bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700">
                                  Admin
                                </span>
                              ) : (
                                <span className="rounded bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">
                                  Active
                                </span>
                              )}
                            </td>
                            <td className="px-4 py-3 text-right">
                              <div className="inline-flex items-center gap-1.5">
                                <button
                                  type="button"
                                  disabled={actionBusyId === `${u.id}:${deltaAmt}`}
                                  onClick={() => void handleAdjustWallet(u.id, deltaAmt)}
                                  className="inline-flex items-center gap-1 rounded-md border border-emerald-200 bg-emerald-50 px-2.5 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-100 disabled:opacity-50"
                                >
                                  <Plus className="h-3 w-3" aria-hidden="true" />
                                  <span>₹{deltaAmt}</span>
                                </button>
                                <button
                                  type="button"
                                  disabled={actionBusyId === `${u.id}:${-deltaAmt}`}
                                  onClick={() => void handleAdjustWallet(u.id, -deltaAmt)}
                                  className="inline-flex items-center gap-1 rounded-md border border-slate-300 bg-white px-2.5 py-1.5 text-xs font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                                >
                                  <Minus className="h-3 w-3" aria-hidden="true" />
                                  <span>₹{deltaAmt}</span>
                                </button>
                                <button
                                  type="button"
                                  disabled={actionBusyId === `ban:${u.id}`}
                                  onClick={() => void handleToggleBan(u.id)}
                                  className="inline-flex items-center gap-1 rounded-md border border-rose-200 bg-rose-50 px-2.5 py-1.5 text-xs font-medium text-rose-700 hover:bg-rose-100 disabled:opacity-50"
                                >
                                  <Ban className="h-3 w-3" aria-hidden="true" />
                                  <span>{u.is_banned ? 'Unblock' : 'Block'}</span>
                                </button>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Tab 4: Recent Scans */}
          {activeTab === 'scans' && (
            <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                  <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase text-slate-500">
                    <tr>
                      <th className="px-4 py-3">User</th>
                      <th className="px-4 py-3">Question</th>
                      <th className="px-4 py-3">Score</th>
                      <th className="px-4 py-3">Verdict</th>
                      <th className="px-4 py-3 text-right">Time</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200">
                    {(overview.recent_scans ?? []).length === 0 ? (
                      <tr>
                        <td colSpan={5} className="px-4 py-8 text-center text-xs text-slate-500">
                          Abhi koi recent scan record nahi hua hai.
                        </td>
                      </tr>
                    ) : (
                      (overview.recent_scans ?? []).map((s) => (
                        <tr key={s.id}>
                          <td className="px-4 py-3 font-mono text-xs text-slate-600">{s.user_email}</td>
                          <td className="px-4 py-3 font-medium text-slate-900">{s.question || s.title}</td>
                          <td className="px-4 py-3">
                            <span
                              className={`inline-flex rounded px-2 py-0.5 font-mono text-xs font-semibold ${
                                s.consistency_score >= 70
                                  ? 'bg-emerald-50 text-emerald-700'
                                  : s.consistency_score >= 45
                                    ? 'bg-amber-50 text-amber-700'
                                    : 'bg-rose-50 text-rose-700'
                              }`}
                            >
                              {s.consistency_score}%
                            </span>
                          </td>
                          <td className="px-4 py-3 text-xs text-slate-600 max-w-md">{s.verdict}</td>
                          <td className="px-4 py-3 text-right font-mono text-[11px] text-slate-400">
                            {new Date(s.created_at).toLocaleString()}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Tab 4: Flagged Unsafe Videos */}
          {activeTab === 'alerts' && (
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              {overview.alerts.length === 0 ? (
                <div className="col-span-full rounded-xl border border-slate-200 bg-white p-8 text-center text-sm text-slate-500">
                  Abhi koi unsafe/flagged video alert record nahi hua hai.
                </div>
              ) : (
                overview.alerts.map((a) => (
                  <article key={a.id} className="rounded-xl border border-rose-200 bg-white p-5">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="text-xs font-semibold text-rose-700">{a.user_email}</p>
                        <p className="mt-1 text-sm font-medium text-slate-900">{a.question_text}</p>
                      </div>
                      <span className="font-mono text-[11px] text-slate-400">
                        {new Date(a.created_at).toLocaleString()}
                      </span>
                    </div>
                    {a.matched_keywords.length > 0 && (
                      <div className="mt-3 flex flex-wrap gap-1.5">
                        {a.matched_keywords.map((kw) => (
                          <span
                            key={kw}
                            className="rounded bg-rose-50 px-2 py-0.5 font-mono text-[11px] font-medium text-rose-700"
                          >
                            {kw}
                          </span>
                        ))}
                      </div>
                    )}
                    {a.video_url ? (
                      <video
                        controls
                        className="mt-4 w-full rounded-lg border border-slate-200 bg-black"
                        src={`/api/admin/video-proxy?baseUrl=${encodeURIComponent(cleanBaseUrl)}&path=${encodeURIComponent(a.video_url)}`}
                      />
                    ) : (
                      <p className="mt-3 text-xs text-slate-500">No video clip attached.</p>
                    )}
                  </article>
                ))
              )}
            </div>
          )}
        </div>
      )}
    </section>
  );
}
