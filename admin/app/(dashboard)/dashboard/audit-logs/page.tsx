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
          Coming soon — admin actions are already recorded internally (`AdminAuditLog`), but there
          is no browsable log viewer yet.
        </div>
      </div>
    </>
  );
}
