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
        <div className="panel empty">
          Administrator actions are being securely recorded. A searchable log viewer is coming in
          a future release.
        </div>
      </div>
    </>
  );
}
