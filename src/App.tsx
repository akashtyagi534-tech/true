import {useEffect, useState} from 'react';
import {AdminPanelView} from './components/AdminPanelView';
import {ArchitectureView} from './components/ArchitectureView';
import {DeployGuideView} from './components/DeployGuideView';
import {LiveSignalLab} from './components/LiveSignalLab';
import {ProjectFilesStudio} from './components/ProjectFilesStudio';
import {TopBar} from './components/TopBar';
import type {AppSection, ProjectBundle, RepoFile, UiLanguage} from './types/truthVerify';

const DEFAULT_GITHUB_USER = 'akashtyagi534-tech';

export default function App() {
  const [activeSection, setActiveSection] = useState<AppSection>('admin');
  const [language, setLanguage] = useState<UiLanguage>('hi');
  const [bundle, setBundle] = useState<ProjectBundle>('mobile');
  const [repoName, setRepoName] = useState<string>(() => {
    try {
      return localStorage.getItem('truthverify_repo_name') || 'True-';
    } catch {
      return 'True-';
    }
  });
  const [githubUsername, setGithubUsername] = useState<string>(() => {
    try {
      return localStorage.getItem('truthverify_github_username') || DEFAULT_GITHUB_USER;
    } catch {
      return DEFAULT_GITHUB_USER;
    }
  });
  const [railwayUrl, setRailwayUrl] = useState<string>(() => {
    try {
      const saved = localStorage.getItem('truthverify_railway_url') || '';
      return saved === 'https://truth-verify-production.up.railway.app' ? '' : saved;
    } catch {
      return '';
    }
  });
  const [files, setFiles] = useState<RepoFile[]>([]);
  const [isLoadingFiles, setIsLoadingFiles] = useState(true);
  const [isDownloading, setIsDownloading] = useState(false);

  const effectiveZipName = bundle === 'v3' ? 'truth-lens-v3-pro' : repoName;

  useEffect(() => {
    try {
      localStorage.setItem('truthverify_railway_url', railwayUrl);
      localStorage.setItem('truthverify_repo_name', repoName);
      localStorage.setItem('truthverify_github_username', githubUsername);
    } catch {
      // ignore storage errors
    }
  }, [railwayUrl, repoName, githubUsername]);

  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();

    async function loadRepoFiles() {
      setIsLoadingFiles(true);
      try {
        const params = new URLSearchParams({
          bundle,
          baseUrl: railwayUrl,
          repoName: effectiveZipName,
        });
        const resp = await fetch(`/api/project/files?${params.toString()}`, {
          signal: controller.signal,
        });
        if (!resp.ok) throw new Error('Failed to load repository files');
        const data = (await resp.json()) as {files: RepoFile[]};
        if (!cancelled) {
          setFiles(data.files ?? []);
        }
      } catch (err) {
        if (!cancelled && !(err instanceof DOMException && err.name === 'AbortError')) {
          console.error(err);
        }
      } finally {
        if (!cancelled) {
          setIsLoadingFiles(false);
        }
      }
    }

    const timer = window.setTimeout(loadRepoFiles, 150);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [railwayUrl, effectiveZipName, bundle]);

  const handleDownloadZip = async () => {
    setIsDownloading(true);
    try {
      const cleanRepo = effectiveZipName.trim().replace(/[^a-zA-Z0-9._-]/g, '') || 'truth-lens-v3-pro';
      const params = new URLSearchParams({
        bundle,
        baseUrl: railwayUrl,
        repoName: cleanRepo,
      });
      const resp = await fetch(`/api/project/download?${params.toString()}`);
      if (!resp.ok) throw new Error('ZIP export failed');
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `${cleanRepo}.zip`;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error(err);
    } finally {
      setIsDownloading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <TopBar
        activeSection={activeSection}
        onSelectSection={setActiveSection}
        onDownloadZip={handleDownloadZip}
        isDownloading={isDownloading}
      />

      <main>
        {activeSection === 'admin' && (
          <AdminPanelView
            railwayUrl={railwayUrl}
            onChangeRailwayUrl={setRailwayUrl}
            onOpenFiles={() => setActiveSection('files')}
            onOpenGuide={() => setActiveSection('guide')}
            language={language}
            onChangeLanguage={setLanguage}
          />
        )}

        {activeSection === 'lab' && (
          <LiveSignalLab
            railwayUrl={railwayUrl}
            language={language}
            onChangeLanguage={setLanguage}
          />
        )}

        {activeSection === 'files' && (
          <ProjectFilesStudio
            files={files}
            isLoading={isLoadingFiles}
            bundle={bundle}
            onChangeBundle={setBundle}
            repoName={effectiveZipName}
            railwayUrl={railwayUrl}
            onChangeRailwayUrl={setRailwayUrl}
            onDownloadZip={handleDownloadZip}
            isDownloading={isDownloading}
            language={language}
            onChangeLanguage={setLanguage}
          />
        )}

        {activeSection === 'guide' && (
          <DeployGuideView
            bundle={bundle}
            onChangeBundle={setBundle}
            repoName={repoName}
            onChangeRepoName={setRepoName}
            githubUsername={githubUsername}
            onChangeGithubUsername={setGithubUsername}
            railwayUrl={railwayUrl}
            onChangeRailwayUrl={setRailwayUrl}
            onDownloadZip={handleDownloadZip}
            onOpenFiles={() => setActiveSection('files')}
            language={language}
            onChangeLanguage={setLanguage}
          />
        )}

        {activeSection === 'architecture' && (
          <ArchitectureView
            railwayUrl={railwayUrl}
            language={language}
            onChangeLanguage={setLanguage}
          />
        )}
      </main>
    </div>
  );
}
