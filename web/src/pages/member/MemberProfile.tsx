import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../api/client';
import { OverviewTab } from './tabs/OverviewTab';
import { UploadTab } from './tabs/UploadTab';
import { ReviewTab } from './tabs/ReviewTab';
import { DocumentsTab } from './tabs/DocumentsTab';
import { TrendsTab } from './tabs/TrendsTab';
import { YoYTab } from './tabs/YoYTab';
import { ConsentTab } from './tabs/ConsentTab';

const TABS = ['Overview', 'Trends', 'Year-over-year', 'Upload', 'Review queue', 'Documents', 'Consent & Privacy'] as const;
type Tab = (typeof TABS)[number];

export function MemberProfile() {
  const { memberId } = useParams<{ memberId: string }>();
  const [member, setMember] = useState<any>(null);
  const [tab, setTab] = useState<Tab>('Overview');
  const [refreshKey, setRefreshKey] = useState(0);

  useEffect(() => {
    api.getFamily().then((f) => setMember(f.members.find((m) => m.id === memberId)));
  }, [memberId]);

  if (!memberId) return null;

  function bump() {
    setRefreshKey((k) => k + 1);
  }

  return (
    <div>
      <h2 style={{ marginBottom: 4 }}>{member?.name ?? '…'}</h2>
      <div className="muted" style={{ marginBottom: 16 }}>
        {member?.relationship_to_primary} {member?.blood_group ? `· ${member.blood_group}` : ''}
      </div>

      <div className="tabs">
        {TABS.map((t) => (
          <button key={t} className={tab === t ? 'active' : ''} onClick={() => setTab(t)}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Overview' && <OverviewTab memberId={memberId} key={refreshKey} />}
      {tab === 'Trends' && <TrendsTab memberId={memberId} key={refreshKey} />}
      {tab === 'Year-over-year' && <YoYTab memberId={memberId} key={refreshKey} />}
      {tab === 'Upload' && <UploadTab memberId={memberId} onUploaded={bump} />}
      {tab === 'Review queue' && <ReviewTab memberId={memberId} key={refreshKey} onChanged={bump} />}
      {tab === 'Documents' && <DocumentsTab memberId={memberId} key={refreshKey} />}
      {tab === 'Consent & Privacy' && <ConsentTab memberId={memberId} key={refreshKey} />}
    </div>
  );
}
