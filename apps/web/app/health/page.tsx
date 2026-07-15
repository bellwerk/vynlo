import { defaultLocale, messages } from "../../i18n/messages";

export const metadata = { title: "System health" };

export default function HealthPage() {
  const copy = messages[defaultLocale];

  return (
    <main className="health-page">
      <a className="brand" href="/" aria-label={copy.brandHome}>
        <span className="brand-mark" aria-hidden="true">
          V
        </span>
        <span>Vynlo</span>
      </a>
      <section aria-labelledby="health-title" className="health-panel">
        <p className="eyebrow">
          <span>{copy.operational}</span> {copy.stage}
        </p>
        <h1 id="health-title">{copy.healthTitle}</h1>
        <dl>
          <div>
            <dt>{copy.webShell}</dt>
            <dd>
              <span className="health-dot" aria-hidden="true" /> {copy.healthy}
            </dd>
          </div>
          <div>
            <dt>{copy.readiness}</dt>
            <dd>
              <a href="/api/v1/health/ready">{copy.jsonEndpoint}</a>
            </dd>
          </div>
          <div>
            <dt>{copy.liveness}</dt>
            <dd>
              <a href="/api/v1/health/live">{copy.jsonEndpoint}</a>
            </dd>
          </div>
        </dl>
      </section>
    </main>
  );
}
