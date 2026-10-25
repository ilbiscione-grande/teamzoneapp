// Whether something is published, and for whom: a globe for the whole
// community, people for one club. Named for screen readers and on hover.
export function PublishedIcon({ clubName }: { clubName: string | null }) {
  const label = clubName ? `Publicerad för ${clubName}` : "Publicerad för hela communityn";
  return (
    <span className="tb-published-icon" role="img" aria-label={label} title={label}>
      {clubName ? (
        <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
          <circle cx="9" cy="8" r="3.2" fill="none" stroke="currentColor" strokeWidth="1.8" />
          <path d="M3 19c.6-3.2 3-5 6-5s5.4 1.8 6 5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
          <circle cx="17" cy="9" r="2.6" fill="none" stroke="currentColor" strokeWidth="1.6" />
          <path d="M16 14.2c2.6 0 4.6 1.6 5 4.3" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
        </svg>
      ) : (
        <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">
          <circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" strokeWidth="1.8" />
          <path d="M3.5 12h17M12 3.5c2.6 2.4 3.8 5.2 3.8 8.5s-1.2 6.1-3.8 8.5c-2.6-2.4-3.8-5.2-3.8-8.5S9.4 5.9 12 3.5z"
            fill="none" stroke="currentColor" strokeWidth="1.6" />
        </svg>
      )}
    </span>
  );
}
