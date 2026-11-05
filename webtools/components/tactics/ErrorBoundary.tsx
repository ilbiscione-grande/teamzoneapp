"use client";

// A failure in one part of the editor stays there: the part shows what
// went wrong (so it can be told on), and can be tried again, while the rest
// keeps working. Nothing of the project is lost; it is saved as it goes.
import { Component, type ReactNode } from "react";
import { useT } from "../language";

type Props = { label: string; children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: { componentStack?: string | null }) {
    console.error(`Tacticsboard: ${this.props.label}`, error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <div className="tb-error" role="alert">
        <Failed label={this.props.label} />
        <code>{error.name}: {error.message}</code>
        <code className="tb-error-stack">{(error.stack ?? "").split("\n").slice(1, 4).join("\n")}</code>
        <div className="tb-actions">
          <Buttons onRetry={() => this.setState({ error: null })} />
        </div>
      </div>
    );
  }
}

function Failed({ label }: { label: string }) {
  const t = useT();
  return <strong>{t("{what} kunde inte visas.", { what: t(label) })}</strong>;
}

function Buttons({ onRetry }: { onRetry: () => void }) {
  const t = useT();
  return (
    <>
      <button type="button" className="wt-button small" onClick={onRetry}>{t("Försök igen")}</button>
      <button type="button" className="wt-button secondary small" onClick={() => window.location.reload()}>{t("Ladda om sidan")}</button>
    </>
  );
}
