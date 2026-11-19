import {Download} from 'lucide-react';
import type {AppSection} from '../types/truthVerify';

interface TopBarProps {
  activeSection: AppSection;
  onSelectSection: (section: AppSection) => void;
  onDownloadZip: () => void;
  isDownloading: boolean;
}

const NAV_ITEMS: Array<{id: AppSection; label: string}> = [
  {id: 'admin', label: 'Admin Panel'},
  {id: 'files', label: 'Project Files'},
  {id: 'guide', label: 'Deploy Guide'},
  {id: 'lab', label: 'Live Lab'},
  {id: 'architecture', label: 'Architecture'},
];

export function TopBar({
  activeSection,
  onSelectSection,
  onDownloadZip,
  isDownloading,
}: TopBarProps) {
  return (
    <header className="sticky top-0 z-30 border-b border-slate-200 bg-white/95 backdrop-blur-sm">
      <div className="mx-auto flex max-w-[1360px] items-center justify-between gap-8 px-6 py-3.5">
        <button
          type="button"
          onClick={() => onSelectSection('lab')}
          className="font-display text-lg font-bold tracking-tight text-slate-900 whitespace-nowrap shrink-0 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-blue-700"
        >
          TruthVerify
        </button>

        <nav aria-label="Primary navigation" className="flex items-center gap-6 overflow-x-auto">
          {NAV_ITEMS.map((item) => {
            const isActive = activeSection === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => onSelectSection(item.id)}
                className={`relative py-1.5 text-sm font-medium transition-colors whitespace-nowrap shrink-0 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-blue-700 ${
                  isActive
                    ? 'text-slate-950'
                    : 'text-slate-500 hover:text-slate-900'
                }`}
              >
                {item.label}
                {isActive && (
                  <span
                    aria-hidden="true"
                    className="absolute inset-x-0 -bottom-[15px] h-0.5 bg-blue-700"
                  />
                )}
              </button>
            );
          })}
        </nav>

        <div className="shrink-0">
          <button
            type="button"
            onClick={onDownloadZip}
            disabled={isDownloading}
            className="inline-flex items-center gap-2 rounded-lg bg-slate-900 px-4 py-2 text-xs font-medium text-white transition-colors hover:bg-slate-800 disabled:opacity-60 whitespace-nowrap shrink-0 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-700"
          >
            <Download className="h-3.5 w-3.5" aria-hidden="true" />
            <span>{isDownloading ? 'Packaging...' : 'Download ZIP'}</span>
          </button>
        </div>
      </div>
    </header>
  );
}
