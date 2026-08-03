export default function SettingsPage() {
  return (
    <>
      <header className="ops-top">
        <div>
          <h1>Settings</h1>
          <p>Platform-wide configuration for LC Connect.</p>
        </div>
      </header>
      <div className="content" style={{ paddingTop: 8 }}>
        <div className="coming-soon">
          <span className="coming-soon-badge">Planned</span>
          <h2>Platform configuration is coming soon</h2>
          <p>
            Settings will live here once configuration endpoints are available. Nothing is invented
            on this screen yet.
          </p>
        </div>
      </div>
    </>
  );
}
