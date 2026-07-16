import { Button } from "@vynlo/ui-web/components/button";
import { ArrowUpRight, CircleDot, ShieldCheck } from "lucide-react";
import { defaultLocale, messages } from "../i18n/messages";

export default function HomePage() {
  const copy = messages[defaultLocale];

  return (
    <div className="app-frame">
      <header className="topbar">
        <a className="brand" href="#main" aria-label={copy.brandHome}>
          <span className="brand-mark" aria-hidden="true">
            V
          </span>
          <span>Vynlo</span>
        </a>
        <nav aria-label={copy.navigationLabel}>
          <ul className="nav-list">
            {copy.navigation.map((item, index) => (
              <li key={item}>
                <a href="#main" aria-current={index === 0 ? "page" : undefined}>
                  {item}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        <div className="environment-badge">
          <CircleDot aria-hidden="true" size={14} /> {copy.environment}
        </div>
      </header>

      <main id="main" tabIndex={-1}>
        <section className="hero" aria-labelledby="foundation-title">
          <div className="eyebrow">
            <span>{copy.stage}</span> {copy.foundation}
          </div>
          <h1 id="foundation-title">{copy.heading}</h1>
          <p className="hero-copy">{copy.introduction}</p>
          <div className="hero-actions">
            <Button asChild>
              <a href="/health">
                {copy.healthAction}{" "}
                <ArrowUpRight aria-hidden="true" size={18} />
              </a>
            </Button>
            <a className="text-link" href="/api/v1/health/ready">
              {copy.readinessAction}
            </a>
          </div>
        </section>

        <section className="status-grid" aria-label={copy.statusLabel}>
          {copy.cards.map(([title, description], index) => (
            <article
              className={`status-card ${index === 0 ? "status-card--primary" : ""}`}
              key={title}
            >
              <span className="card-index">
                {String(index + 1).padStart(2, "0")}
              </span>
              <h2>{title}</h2>
              <p>
                {index === 2 && <ShieldCheck aria-hidden="true" size={18} />}
                {description}
              </p>
            </article>
          ))}
        </section>
      </main>

      <footer>
        <span>{copy.footer[0]}</span>
        <span>{copy.footer[1]}</span>
      </footer>
    </div>
  );
}
