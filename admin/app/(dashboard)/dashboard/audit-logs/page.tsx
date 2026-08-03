export default function AuditLogsPage() {
  return (
    <>
      <header className="topbar">
        <div>
          <h1>Audit Logs</h1>
          <p>A record of sensitive admin actions across LC Connect</p>
        </div>
      </header>
      <div className="content">
        <div className="coming-soon">
          <span className="coming-soon-badge">Recording active</span>
          <h2>Searchable audit viewer coming soon</h2>
          <p>
            Admin actions are already being recorded securely. A searchable viewer will appear here
            when the list API is ready.
          </p>
        </div>
      </div>
    </>
  );
}
